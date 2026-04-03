-- ============================================================
-- 089: 1 gün önce event_created hatırlatması RSVP'ye uysun
--
-- send_rsvp_reminder (48h/24h/12h) zaten going + not_going hariç tutuyor (082).
-- send_event_reminder ise tüm get_event_created_recipients'a gidiyordu;
-- "Katılmıyorum" veya "Katılıyorum" işaretleyenler yine de ~1 gün önce bildirim alıyordu.
--
-- Kural: going veya not_going yanıtı verenlere bu hatırlatma gitmesin;
-- yanıt yoksa (veya sadece maybe) gitsin. İşlem sonrası event_reminder_sent_at
-- her zaman set edilir (yanıtlayanlar kaldıysa bile tekrar cron denemesin).
-- ============================================================

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

    UPDATE public.events
    SET event_reminder_sent_at = NOW()
    WHERE id = p_event_id;
END;
$$;
