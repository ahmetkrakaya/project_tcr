-- ============================================================
-- 082: RSVP hatırlatmalarında "not_going" hariç tutulsun
--
-- Problem:
-- - RSVP hatırlatmaları (48h/24h/12h) şu an sadece "going" olanları hariç tutuyor.
-- - Kullanıcı "Katılmıyorum" (status = 'not_going') dediyse hatırlatma almamalı.
--
-- Çözüm:
-- - send_rsvp_reminder fonksiyonunda, event_participants'ta
--   status IN ('going', 'not_going') olan kullanıcıları dışarıda bırak.
-- ============================================================

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

    -- Kullanıcı yanıtladıysa (going / not_going) artık hatırlatma gönderme.
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

