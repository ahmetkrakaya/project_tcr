-- ============================================================
-- 080: Etkinlik bildirimi zamanlaması
-- Etkinlik oluşturulduğunda anında bildirim gitmez.
-- Bildirim en erken etkinlikten 1 gün önce gönderilir.
-- Etkinlik 24 saatten az süre kala oluşturulduysa hemen gider.
-- ============================================================

-- Etkinlik hatırlatma bildirimi gönderildi mi takibi
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS event_reminder_sent_at TIMESTAMPTZ;

COMMENT ON COLUMN public.events.event_reminder_sent_at IS
  'event_created bildirimi gönderildiğinde set edilir; tekrar gönderimi önler';

-- ============================================================
-- Yardımcı: Etkinlik için event_created alıcı listesini döner
-- (notify_on_event_change ile aynı mantık)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_event_created_recipients(p_event_id UUID)
RETURNS UUID[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
    v_recipient_ids UUID[];
BEGIN
    SELECT id, event_type, participation_type, visibility
    INTO v_event
    FROM public.events
    WHERE id = p_event_id
      AND status = 'published';

    IF v_event.id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Bireysel antrenman: bildirim yok
    IF v_event.event_type = 'training' AND v_event.participation_type = 'individual' THEN
        RETURN NULL;
    END IF;

    -- Özel (restricted) etkinlikler
    IF v_event.visibility = 'restricted' THEN
        SELECT ARRAY_AGG(evu.user_id)
        INTO v_recipient_ids
        FROM public.event_visible_users evu
        WHERE evu.event_id = p_event_id;
        RETURN v_recipient_ids;
    END IF;

    -- Ekip antrenmanı
    IF v_event.event_type = 'training' AND v_event.participation_type = 'team' THEN
        SELECT ARRAY_AGG(DISTINCT gm.user_id)
        INTO v_recipient_ids
        FROM public.event_group_programs egp
        JOIN public.group_members gm ON gm.group_id = egp.training_group_id
        WHERE egp.event_id = p_event_id;
        RETURN v_recipient_ids;
    END IF;

    -- Diğer etkinlik türleri
    SELECT ARRAY_AGG(id) INTO v_recipient_ids
    FROM public.users
    WHERE is_active = true;
    RETURN v_recipient_ids;
END;
$$;

-- ============================================================
-- Etkinlik hatırlatma bildirimi gönder ve işaretle
-- ============================================================
CREATE OR REPLACE FUNCTION public.send_event_reminder(p_event_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
    v_recipient_ids UUID[];
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

    v_recipient_ids := public.get_event_created_recipients(p_event_id);
    IF v_recipient_ids IS NULL OR array_length(v_recipient_ids, 1) IS NULL OR array_length(v_recipient_ids, 1) = 0 THEN
        RETURN;
    END IF;

    v_data := jsonb_build_object('event_id', v_event.id);
    v_title := trim(v_event.title);
    v_body := to_char(v_event.start_time AT TIME ZONE 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') || ' · Katılımını bekliyoruz.';

    PERFORM public.insert_notifications(
        'event_created',
        v_title,
        v_body,
        v_data,
        v_recipient_ids
    );

    UPDATE public.events
    SET event_reminder_sent_at = NOW()
    WHERE id = p_event_id;
END;
$$;

-- ============================================================
-- notify_on_event_change: event_created artık anında gitmez
-- Sadece etkinlik 24 saatten az süre sonraysa (1 gün önce geçildiyse) hemen gönder
-- event_updated anında kalmaya devam eder
-- ============================================================
CREATE OR REPLACE FUNCTION public.notify_on_event_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recipient_ids UUID[];
    v_notification_type TEXT;
    v_title TEXT;
    v_body TEXT;
    v_data JSONB;
BEGIN
    -- Sadece yayınlanmış etkinlikler için
    IF NEW.status != 'published' THEN
        RETURN NEW;
    END IF;

    v_data := jsonb_build_object('event_id', NEW.id);
    v_title := trim(NEW.title);
    v_body := to_char(NEW.start_time AT TIME ZONE 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') || ' · Katılımını bekliyoruz.';

    IF TG_OP = 'INSERT' THEN
        -- event_created: En erken 1 gün önce gitmeli
        -- 24 saatten az kaldıysa hemen gönder; yoksa cron gönderecek
        IF NEW.event_type = 'training' AND NEW.participation_type = 'individual' THEN
            RETURN NEW;
        END IF;
        IF (NEW.start_time - INTERVAL '1 day') <= NOW() AND NEW.start_time > NOW() THEN
            v_recipient_ids := public.get_event_created_recipients(NEW.id);
            IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
                PERFORM public.send_event_reminder(NEW.id);
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE: event_updated anında kalsın
    v_notification_type := 'event_updated';

    -- Bireysel antrenman: bildirim yok
    IF NEW.event_type = 'training' AND NEW.participation_type = 'individual' THEN
        RETURN NEW;
    END IF;

    -- Özel (restricted) etkinlikler
    IF NEW.visibility = 'restricted' THEN
        SELECT ARRAY_AGG(evu.user_id)
        INTO v_recipient_ids
        FROM public.event_visible_users evu
        WHERE evu.event_id = NEW.id;
        IF v_recipient_ids IS NULL OR array_length(v_recipient_ids, 1) IS NULL OR array_length(v_recipient_ids, 1) = 0 THEN
            RETURN NEW;
        END IF;
        PERFORM public.insert_notifications(v_notification_type, v_title, v_body, v_data, v_recipient_ids);
        RETURN NEW;
    END IF;

    -- Ekip antrenmanı
    IF NEW.event_type = 'training' AND NEW.participation_type = 'team' THEN
        SELECT ARRAY_AGG(DISTINCT gm.user_id)
        INTO v_recipient_ids
        FROM public.event_group_programs egp
        JOIN public.group_members gm ON gm.group_id = egp.training_group_id
        WHERE egp.event_id = NEW.id;
        IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
            PERFORM public.insert_notifications(v_notification_type, v_title, v_body, v_data, v_recipient_ids);
        END IF;
        RETURN NEW;
    END IF;

    -- Diğer etkinlik türleri
    SELECT ARRAY_AGG(id) INTO v_recipient_ids
    FROM public.users
    WHERE is_active = true;
    IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.insert_notifications(v_notification_type, v_title, v_body, v_data, v_recipient_ids);
    END IF;
    RETURN NEW;
END;
$$;

-- ============================================================
-- notify_on_event_group_program_insert: Artık anında bildirim yok
-- Cron job 1 gün önce gönderecek (grup eklenince alıcı listesi dahil edilir)
-- ============================================================
CREATE OR REPLACE FUNCTION public.notify_on_event_group_program_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- event_created bildirimi artık cron ile 1 gün önce gidecek
    RETURN NEW;
END;
$$;

-- ============================================================
-- Cron: Etkinlikten 1 gün önce bildirim gönder
-- Her 15 dakikada bir çalışır
-- ============================================================
CREATE OR REPLACE FUNCTION public.send_scheduled_event_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
BEGIN
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND start_time > NOW()
          AND (start_time - INTERVAL '1 day') <= NOW()
          AND event_reminder_sent_at IS NULL
    LOOP
        PERFORM public.send_event_reminder(v_event.id);
    END LOOP;
END;
$$;

-- pg_cron job (unschedule job yoksa hata verir, bu yüzden exception ile sarmalıyoruz)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('send-event-reminders');
    EXCEPTION
      WHEN OTHERS THEN NULL;  -- Job yoksa (ilk kurulum) hata verir, yoksay
    END;
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'send-event-reminders',
      '*/15 * * * *',
      'SELECT public.send_scheduled_event_reminders()'
    );
  END IF;
END
$$;
