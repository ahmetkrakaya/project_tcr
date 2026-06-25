-- =====================================================
-- 131: Etkinlik sohbeti push — katılımcılara, mesaj başına bildirim
-- =====================================================
-- Önceki davranış chat_room_members üzerinden gidiyordu; odaya hiç
-- girmemiş katılımcılar push alamıyordu. Gruplama/collapse ile birlikte
-- bazı cihazlarda bildirim hiç görünmeyebiliyordu.
-- Yeni davranış: status = 'going' olan her katılımcıya her mesaj için
-- ayrı notifications satırı (insert_notifications).

CREATE OR REPLACE FUNCTION public.notify_on_event_chat_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_room_type chat_room_type;
    v_event_id UUID;
    v_event_title TEXT;
    v_recipient_ids UUID[];
    v_sender_name TEXT;
    v_data JSONB;
BEGIN
    SELECT cr.room_type, cr.event_id INTO v_room_type, v_event_id
    FROM public.chat_rooms cr
    WHERE cr.id = NEW.room_id;

    IF v_room_type != 'event' OR v_event_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.is_deleted IS TRUE THEN
        RETURN NEW;
    END IF;

    SELECT title INTO v_event_title FROM public.events WHERE id = v_event_id;

    -- Gönderen hariç, etkinliğe katılan (going) tüm katılımcılar
    SELECT ARRAY_AGG(DISTINCT ep.user_id) INTO v_recipient_ids
    FROM public.event_participants ep
    WHERE ep.event_id = v_event_id
      AND ep.status = 'going'
      AND ep.user_id IS NOT NULL
      AND (NEW.sender_id IS NULL OR ep.user_id != NEW.sender_id);

    IF v_recipient_ids IS NULL OR array_length(v_recipient_ids, 1) IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT trim(COALESCE(u.first_name || ' ', '') || COALESCE(u.last_name, ''))
    INTO v_sender_name
    FROM public.users u
    WHERE u.id = NEW.sender_id;

    v_data := jsonb_build_object(
        'room_id', NEW.room_id,
        'event_id', v_event_id,
        'message_id', NEW.id
    );

    PERFORM public.insert_notifications(
        'event_chat_message',
        COALESCE(trim(v_event_title), 'Etkinlik sohbeti'),
        COALESCE(nullif(trim(v_sender_name), ''), 'Bir katılımcı')
            || ': ' || left(trim(NEW.content), 80),
        v_data,
        v_recipient_ids
    );

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_on_event_chat_message() IS
  'Etkinlik sohbetinde yeni mesajda going katılımcılara (gönderen hariç) push bildirimi satırı ekler.';
