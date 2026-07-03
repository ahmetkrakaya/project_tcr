-- ============================================================
-- 145: Etkinlik bildirimlerinde saat dilimi düzeltmesi
--
-- start_time DB'de Türkiye duvar saati olarak UTC bileşenlerine yazılır
-- (ör. 20:00 → 20:00+00). Gerçek UTC NOW() ile doğrudan karşılaştırma
-- hatırlatmayı 3 saat geciktirir; AT TIME ZONE 'Europe/Istanbul' ile
-- formatlama ise metinde +3 saat kayma yapar (20:00 → 23:00).
--
-- Çözüm: Zamanlama ve metin için ortak duvar saati yardımcıları.
-- ============================================================

-- Etkinlik başlangıcını duvar saati (timestamp, tz yok) olarak döndürür
CREATE OR REPLACE FUNCTION public.event_start_wall_time(p_start_time TIMESTAMPTZ)
RETURNS TIMESTAMP
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_start_time AT TIME ZONE 'UTC';
$$;

COMMENT ON FUNCTION public.event_start_wall_time(TIMESTAMPTZ) IS
  'Etkinlik start_time değerini uygulamadaki duvar saati olarak döndürür (TR yerel saat bileşenleri).';

-- Şu anki Türkiye duvar saati
CREATE OR REPLACE FUNCTION public.ist_wall_now()
RETURNS TIMESTAMP
LANGUAGE sql
STABLE
AS $$
  SELECT NOW() AT TIME ZONE 'Europe/Istanbul';
$$;

COMMENT ON FUNCTION public.ist_wall_now() IS
  'Şu anki Türkiye yerel duvar saati (timestamp, tz yok).';

-- Bildirim metni için etkinlik saati formatı
CREATE OR REPLACE FUNCTION public.format_event_start_for_notification(p_start_time TIMESTAMPTZ)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT to_char(p_start_time AT TIME ZONE 'UTC', 'DD.MM.YYYY HH24:MI');
$$;

COMMENT ON FUNCTION public.format_event_start_for_notification(TIMESTAMPTZ) IS
  'Etkinlik start_time değerini bildirim gövdesi için duvar saati olarak formatlar.';

-- ------------------------------------------------------------
-- send_event_reminder
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_event_reminder(p_event_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
    v_all_recipients UUID[];
    v_responded_users UUID[];
    v_pending_users UUID[];
    v_title TEXT;
    v_body TEXT;
    v_data JSONB;
BEGIN
    SELECT id, title, start_time, status
    INTO v_event
    FROM public.events
    WHERE id = p_event_id;

    IF v_event.id IS NULL OR v_event.status != 'published' THEN
        RETURN;
    END IF;

    v_all_recipients := public.get_event_created_recipients(p_event_id);
    IF v_all_recipients IS NULL OR array_length(v_all_recipients, 1) IS NULL OR array_length(v_all_recipients, 1) = 0 THEN
        RETURN;
    END IF;

    SELECT ARRAY_AGG(ep.user_id)
    INTO v_responded_users
    FROM public.event_participants ep
    WHERE ep.event_id = p_event_id
      AND ep.status IN ('going', 'not_going');

    IF v_responded_users IS NOT NULL THEN
        SELECT ARRAY_AGG(uid)
        INTO v_pending_users
        FROM unnest(v_all_recipients) AS uid
        WHERE uid != ALL(v_responded_users);
    ELSE
        v_pending_users := v_all_recipients;
    END IF;

    IF v_pending_users IS NOT NULL AND array_length(v_pending_users, 1) IS NOT NULL AND array_length(v_pending_users, 1) > 0 THEN
        v_data := jsonb_build_object('event_id', v_event.id);
        v_title := trim(v_event.title);
        v_body := public.format_event_start_for_notification(v_event.start_time)
                  || ' · Katılımını bekliyoruz.';

        PERFORM public.insert_notifications(
            'event_created',
            v_title,
            v_body,
            v_data,
            v_pending_users
        );
    END IF;

    UPDATE public.events
    SET event_reminder_sent_at = NOW()
    WHERE id = p_event_id;
END;
$$;

-- ------------------------------------------------------------
-- send_rsvp_reminder
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_rsvp_reminder(
    p_event_id UUID,
    p_hours_before INT,
    p_sent_column TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
    v_all_recipients UUID[];
    v_responded_users UUID[];
    v_pending_users UUID[];
    v_start_wall TIMESTAMP;
    v_now_wall TIMESTAMP;
    v_reminder_at TIMESTAMP;
    v_title TEXT;
    v_body TEXT;
    v_data JSONB;
BEGIN
    SELECT id, title, start_time, status
    INTO v_event
    FROM public.events
    WHERE id = p_event_id;

    IF v_event.id IS NULL OR v_event.status != 'published' THEN
        RETURN;
    END IF;

    v_start_wall := public.event_start_wall_time(v_event.start_time);
    v_now_wall := public.ist_wall_now();
    v_reminder_at := v_start_wall - make_interval(hours => p_hours_before);

    -- Etkinlik başlangıcına göre pencere: [T-N saat, T-start)
    IF v_now_wall >= v_start_wall OR v_now_wall < v_reminder_at THEN
        RETURN;
    END IF;

    v_all_recipients := public.get_event_created_recipients(p_event_id);
    IF v_all_recipients IS NULL OR array_length(v_all_recipients, 1) IS NULL THEN
        RETURN;
    END IF;

    SELECT ARRAY_AGG(ep.user_id)
    INTO v_responded_users
    FROM public.event_participants ep
    WHERE ep.event_id = p_event_id
      AND ep.status IN ('going', 'not_going');

    IF v_responded_users IS NOT NULL THEN
        SELECT ARRAY_AGG(uid)
        INTO v_pending_users
        FROM unnest(v_all_recipients) AS uid
        WHERE uid != ALL(v_responded_users);
    ELSE
        v_pending_users := v_all_recipients;
    END IF;

    IF v_pending_users IS NULL OR array_length(v_pending_users, 1) IS NULL THEN
        RETURN;
    END IF;

    v_data := jsonb_build_object('event_id', v_event.id);
    v_title := trim(v_event.title);
    v_body := public.format_event_start_for_notification(v_event.start_time)
              || ' · Katılımını henüz bildirmedin.';

    PERFORM public.insert_notifications(
        'event_rsvp_reminder',
        v_title,
        v_body,
        v_data,
        v_pending_users
    );

    EXECUTE format('UPDATE public.events SET %I = NOW() WHERE id = $1', p_sent_column)
    USING p_event_id;
END;
$$;

-- ------------------------------------------------------------
-- send_scheduled_event_reminders
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_scheduled_event_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
    v_now_wall TIMESTAMP := public.ist_wall_now();
BEGIN
    -- event_created: tekrarlı seriden otomatik oluşturulan etkinlikler, T-24h penceresi
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND public.event_start_wall_time(start_time) > v_now_wall
          AND parent_event_id IS NOT NULL
          AND (public.event_start_wall_time(start_time) - INTERVAL '24 hours') <= v_now_wall
          AND event_reminder_sent_at IS NULL
    LOOP
        PERFORM public.send_event_reminder(v_event.id);
    END LOOP;

    -- RSVP hatırlatması: start_time'dan tam 2 saat önce ([T-2h, T-start) penceresi)
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND public.event_start_wall_time(start_time) > v_now_wall
          AND (public.event_start_wall_time(start_time) - INTERVAL '2 hours') <= v_now_wall
          AND (created_at AT TIME ZONE 'Europe/Istanbul')
              <= (public.event_start_wall_time(start_time) - INTERVAL '2 hours')
          AND rsvp_reminder_2h_sent_at IS NULL
    LOOP
        PERFORM public.send_rsvp_reminder(v_event.id, 2, 'rsvp_reminder_2h_sent_at');
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.send_scheduled_event_reminders() IS
  'Tekrarlı otomatik etkinlikler için event_created T-24h; RSVP hatırlatması T-2h (TR duvar saati).';

-- ------------------------------------------------------------
-- notify_on_event_change
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_on_event_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status != 'published'
       OR public.event_start_wall_time(NEW.start_time) <= public.ist_wall_now() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.parent_event_id IS NOT NULL THEN
            RETURN NEW;
        END IF;
        PERFORM public.send_event_reminder(NEW.id);
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF OLD.status IS DISTINCT FROM 'published' AND NEW.status = 'published' THEN
            IF NEW.parent_event_id IS NULL THEN
                PERFORM public.send_event_reminder(NEW.id);
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    RETURN NEW;
END;
$$;

-- ------------------------------------------------------------
-- notify_on_event_group_program_insert
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_on_event_group_program_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
    v_all_recipients UUID[];
    v_responded_users UUID[];
    v_pending_users UUID[];
    v_title TEXT;
    v_body TEXT;
    v_data JSONB;
BEGIN
    SELECT id, title, start_time, status, event_type, parent_event_id
    INTO v_event
    FROM public.events
    WHERE id = NEW.event_id;

    IF v_event.id IS NULL
       OR v_event.status != 'published'
       OR public.event_start_wall_time(v_event.start_time) <= public.ist_wall_now()
       OR v_event.event_type != 'training'
       OR v_event.parent_event_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT ARRAY_AGG(gm.user_id)
    INTO v_all_recipients
    FROM public.group_members gm
    WHERE gm.group_id = NEW.training_group_id;

    IF v_all_recipients IS NULL OR array_length(v_all_recipients, 1) IS NULL OR array_length(v_all_recipients, 1) = 0 THEN
        RETURN NEW;
    END IF;

    SELECT ARRAY_AGG(ep.user_id)
    INTO v_responded_users
    FROM public.event_participants ep
    WHERE ep.event_id = NEW.event_id
      AND ep.status IN ('going', 'not_going');

    IF v_responded_users IS NOT NULL THEN
        SELECT ARRAY_AGG(uid)
        INTO v_pending_users
        FROM unnest(v_all_recipients) AS uid
        WHERE uid != ALL(v_responded_users);
    ELSE
        v_pending_users := v_all_recipients;
    END IF;

    IF v_pending_users IS NULL OR array_length(v_pending_users, 1) IS NULL OR array_length(v_pending_users, 1) = 0 THEN
        RETURN NEW;
    END IF;

    v_data := jsonb_build_object('event_id', v_event.id);
    v_title := trim(v_event.title);
    v_body := public.format_event_start_for_notification(v_event.start_time)
              || ' · Katılımını bekliyoruz.';

    PERFORM public.insert_notifications(
        'event_created',
        v_title,
        v_body,
        v_data,
        v_pending_users
    );

    UPDATE public.events
    SET event_reminder_sent_at = NOW()
    WHERE id = v_event.id;

    RETURN NEW;
END;
$$;

-- ------------------------------------------------------------
-- send_manual_event_notification
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_manual_event_notification(p_event_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_is_admin BOOLEAN;
    v_event RECORD;
    v_recipient_ids UUID[];
    v_title TEXT;
    v_body TEXT;
    v_data JSONB;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Yetkisiz erişim';
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM public.user_roles
        WHERE user_id = v_caller_id
          AND role IN ('super_admin', 'coach')
    ) INTO v_is_admin;

    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Bu işlem için yetkiniz yok';
    END IF;

    SELECT id, title, start_time, status
    INTO v_event
    FROM public.events
    WHERE id = p_event_id;

    IF v_event.id IS NULL THEN
        RAISE EXCEPTION 'Etkinlik bulunamadı';
    END IF;

    v_recipient_ids := public.get_event_created_recipients(p_event_id);
    IF v_recipient_ids IS NULL OR array_length(v_recipient_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'Bildirim gönderilecek kullanıcı bulunamadı';
    END IF;

    v_data := jsonb_build_object('event_id', v_event.id);
    v_title := trim(v_event.title);
    v_body := public.format_event_start_for_notification(v_event.start_time)
              || ' · Hadi, seni de bekliyoruz!';

    PERFORM public.insert_notifications(
        'event_manual_notification',
        v_title,
        v_body,
        v_data,
        v_recipient_ids
    );
END;
$$;
