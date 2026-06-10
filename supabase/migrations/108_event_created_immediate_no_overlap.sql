-- ============================================================
-- 108: event_created anında + üst üste bildirim engeli
--
-- 1. event_created: yayınlandığı anda gider (cron T-1 gün kaldırıldı)
-- 2. RSVP 24h/12h: aynı pencerede event_created gittiyse atlanır
-- 3. send_event_reminder: alıcı yoksa event_reminder_sent_at işaretlenmez
-- 4. Ekip antrenmanı: grup eklendiğinde o grubun üyelerine event_created
-- 5. Taslak -> yayın geçişinde de event_created tetiklenir
-- ============================================================

-- ------------------------------------------------------------
-- send_event_reminder: alıcı yoksa bayrak set etme
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
        v_body := to_char(v_event.start_time, 'DD.MM.YYYY HH24:MI') || ' · Katılımını bekliyoruz.';

        PERFORM public.insert_notifications(
            'event_created',
            v_title,
            v_body,
            v_data,
            v_pending_users
        );
    END IF;

    -- Duyuru denendi (alıcı vardı); RSVP çakışma kontrolü için işaretle
    UPDATE public.events
    SET event_reminder_sent_at = NOW()
    WHERE id = p_event_id;
END;
$$;

-- ------------------------------------------------------------
-- notify_on_event_change: event_created oluşturulur/yayınlanır yayınlanmaz
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_on_event_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status != 'published' OR NEW.start_time <= NOW() THEN
        RETURN NEW;
    END IF;

    IF NEW.event_type = 'training' AND NEW.participation_type = 'individual' THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        PERFORM public.send_event_reminder(NEW.id);
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF OLD.status IS DISTINCT FROM 'published' AND NEW.status = 'published' THEN
            PERFORM public.send_event_reminder(NEW.id);
        END IF;
        RETURN NEW;
    END IF;

    RETURN NEW;
END;
$$;

-- ------------------------------------------------------------
-- Ekip antrenmanı: grup programı eklendiğinde o gruba event_created
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
    SELECT id, title, start_time, status, event_type, participation_type
    INTO v_event
    FROM public.events
    WHERE id = NEW.event_id;

    IF v_event.id IS NULL
       OR v_event.status != 'published'
       OR v_event.start_time <= NOW()
       OR v_event.event_type != 'training'
       OR v_event.participation_type != 'team' THEN
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
    v_body := to_char(v_event.start_time, 'DD.MM.YYYY HH24:MI') || ' · Katılımını bekliyoruz.';

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

COMMENT ON FUNCTION public.notify_on_event_group_program_insert() IS
  'Ekip antrenmanında grup programı eklendiğinde o grubun üyelerine event_created gönderir; RSVP çakışma bayrağını günceller.';

-- ------------------------------------------------------------
-- Cron: yalnızca RSVP hatırlatmaları (event_created cron yok)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_scheduled_event_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
BEGIN
    -- RSVP 24h: [T-24h, T-12h), oluşturulduğunda ≥24h vardı,
    -- event_created aynı pencerede gittiyse atla
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND start_time > NOW()
          AND (start_time - INTERVAL '24 hours') <= NOW()
          AND (start_time - INTERVAL '12 hours') > NOW()
          AND created_at <= (start_time - INTERVAL '24 hours')
          AND rsvp_reminder_24h_sent_at IS NULL
          AND (
              event_reminder_sent_at IS NULL
              OR event_reminder_sent_at < (start_time - INTERVAL '24 hours')
          )
    LOOP
        PERFORM public.send_rsvp_reminder(v_event.id, 24, 'rsvp_reminder_24h_sent_at');
    END LOOP;

    -- RSVP 12h: [T-12h, T-start), oluşturulduğunda ≥12h vardı,
    -- event_created aynı pencerede gittiyse atla
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND start_time > NOW()
          AND (start_time - INTERVAL '12 hours') <= NOW()
          AND created_at <= (start_time - INTERVAL '12 hours')
          AND rsvp_reminder_12h_sent_at IS NULL
          AND (
              event_reminder_sent_at IS NULL
              OR event_reminder_sent_at < (start_time - INTERVAL '12 hours')
          )
    LOOP
        PERFORM public.send_rsvp_reminder(v_event.id, 12, 'rsvp_reminder_12h_sent_at');
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.send_scheduled_event_reminders() IS
  'RSVP hatırlatmaları (24h ve 12h). event_created artık oluşturulur yayınlanmaz anında gider.';

COMMENT ON COLUMN public.events.event_reminder_sent_at IS
  'event_created duyurusu gönderildiğinde set edilir; RSVP çakışma kontrolü ve tekrar gönderimi önler';
