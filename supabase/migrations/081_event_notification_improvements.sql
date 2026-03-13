-- ============================================================
-- 081: Etkinlik Bildirim Sistemi İyileştirmeleri
--
-- 1. Saat sorunu: AT TIME ZONE kaldırıldı (start_time zaten yerel saat)
-- 2. UPDATE bildirimi kapatıldı (düzenleme artık bildirim göndermez)
-- 3. Kademeli katılım hatırlatmaları (48h, 24h, 12h önce)
-- 4. Admin manuel bildirim RPC fonksiyonu
-- ============================================================

-- ============================================================
-- 1 & 2: notify_on_event_change güncellemesi
--    - to_char'dan AT TIME ZONE kaldırıldı
--    - UPDATE bloğu tamamen devre dışı
-- ============================================================
CREATE OR REPLACE FUNCTION public.notify_on_event_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recipient_ids UUID[];
    v_title TEXT;
    v_body TEXT;
    v_data JSONB;
BEGIN
    IF NEW.status != 'published' THEN
        RETURN NEW;
    END IF;

    -- UPDATE: artık bildirim gönderme
    IF TG_OP = 'UPDATE' THEN
        RETURN NEW;
    END IF;

    -- INSERT: event_created mantığı (mevcut ile aynı)
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
END;
$$;

-- ============================================================
-- 1: send_event_reminder saat düzeltmesi
--    AT TIME ZONE 'Europe/Istanbul' kaldırıldı
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
    v_body := to_char(v_event.start_time, 'DD.MM.YYYY HH24:MI') || ' · Katılımını bekliyoruz.';

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
-- 3: Kademeli katılım hatırlatmaları (48h, 24h, 12h)
-- ============================================================

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS rsvp_reminder_48h_sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rsvp_reminder_24h_sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rsvp_reminder_12h_sent_at TIMESTAMPTZ;

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
    v_going_users UUID[];
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
    IF v_all_recipients IS NULL OR array_length(v_all_recipients, 1) IS NULL THEN
        RETURN;
    END IF;

    SELECT ARRAY_AGG(ep.user_id)
    INTO v_going_users
    FROM public.event_participants ep
    WHERE ep.event_id = p_event_id
      AND ep.status = 'going';

    IF v_going_users IS NOT NULL THEN
        SELECT ARRAY_AGG(uid)
        INTO v_pending_users
        FROM unnest(v_all_recipients) AS uid
        WHERE uid != ALL(v_going_users);
    ELSE
        v_pending_users := v_all_recipients;
    END IF;

    IF v_pending_users IS NULL OR array_length(v_pending_users, 1) IS NULL THEN
        RETURN;
    END IF;

    v_data := jsonb_build_object('event_id', v_event.id);
    v_title := trim(v_event.title);
    v_body := to_char(v_event.start_time, 'DD.MM.YYYY HH24:MI') || ' · Katılımını henüz bildirmedin.';

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

CREATE OR REPLACE FUNCTION public.send_scheduled_event_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
BEGIN
    -- event_created hatırlatması (1 gün önce)
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

    -- RSVP hatırlatması: 48 saat önce
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND start_time > NOW()
          AND (start_time - INTERVAL '48 hours') <= NOW()
          AND rsvp_reminder_48h_sent_at IS NULL
    LOOP
        PERFORM public.send_rsvp_reminder(v_event.id, 48, 'rsvp_reminder_48h_sent_at');
    END LOOP;

    -- RSVP hatırlatması: 24 saat önce
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND start_time > NOW()
          AND (start_time - INTERVAL '24 hours') <= NOW()
          AND rsvp_reminder_24h_sent_at IS NULL
    LOOP
        PERFORM public.send_rsvp_reminder(v_event.id, 24, 'rsvp_reminder_24h_sent_at');
    END LOOP;

    -- RSVP hatırlatması: 12 saat önce
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND start_time > NOW()
          AND (start_time - INTERVAL '12 hours') <= NOW()
          AND rsvp_reminder_12h_sent_at IS NULL
    LOOP
        PERFORM public.send_rsvp_reminder(v_event.id, 12, 'rsvp_reminder_12h_sent_at');
    END LOOP;
END;
$$;

-- ============================================================
-- 4: Admin manuel bildirim RPC
-- ============================================================
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
    v_body := to_char(v_event.start_time, 'DD.MM.YYYY HH24:MI') || ' · Hadi, seni de bekliyoruz!';

    PERFORM public.insert_notifications(
        'event_manual_notification',
        v_title,
        v_body,
        v_data,
        v_recipient_ids
    );
END;
$$;

-- ============================================================
-- Bildirim ayarları varsayılanlarını güncelle
-- ============================================================
ALTER TABLE public.user_notification_settings
  ALTER COLUMN settings SET DEFAULT '{
      "event_created": true,
      "event_updated": true,
      "event_rsvp_reminder": true,
      "event_manual_notification": true,
      "carpool_application": true,
      "carpool_application_response": true,
      "event_chat_message": true,
      "post_created": true,
      "post_updated": true,
      "listing_created": true,
      "order_created": true,
      "order_status_changed": true
  }'::jsonb;
