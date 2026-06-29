-- ============================================================
-- 135: Tekrarlı seriden otomatik oluşturulan etkinliklerde
-- event_created oluşturma anında gitmesin; T-24h cron ile gitsin.
-- Elle oluşturulan (parent_event_id IS NULL) etkinlikler anında gider.
-- ============================================================

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
    IF NEW.status != 'published' OR NEW.start_time <= NOW() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- Tekrarlı seriden otomatik oluşturulan: cron T-24h gönderecek
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

COMMENT ON FUNCTION public.notify_on_event_change() IS
  'event_created: elle oluşturulan etkinlikler anında; tekrarlı seriden otomatik oluşturulanlar T-24h cron ile gider.';

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
       OR v_event.start_time <= NOW()
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
  'Antrenman etkinliğine grup eklendiğinde event_created gönderir; tekrarlı seriden otomatik oluşturulanlarda atlanır (T-24h cron).';

-- ------------------------------------------------------------
-- send_scheduled_event_reminders: event_created T-24h + RSVP T-2h
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
    -- event_created: tekrarlı seriden otomatik oluşturulan etkinlikler, T-24h penceresi
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND start_time > NOW()
          AND parent_event_id IS NOT NULL
          AND (start_time - INTERVAL '24 hours') <= NOW()
          AND event_reminder_sent_at IS NULL
    LOOP
        PERFORM public.send_event_reminder(v_event.id);
    END LOOP;

    -- RSVP hatırlatması: start_time'dan tam 2 saat önce ([T-2h, T-start) penceresi)
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND start_time > NOW()
          AND (start_time - INTERVAL '2 hours') <= NOW()
          AND created_at <= (start_time - INTERVAL '2 hours')
          AND rsvp_reminder_2h_sent_at IS NULL
    LOOP
        PERFORM public.send_rsvp_reminder(v_event.id, 2, 'rsvp_reminder_2h_sent_at');
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.send_scheduled_event_reminders() IS
  'Tekrarlı otomatik etkinlikler için event_created T-24h; RSVP hatırlatması T-2h.';
