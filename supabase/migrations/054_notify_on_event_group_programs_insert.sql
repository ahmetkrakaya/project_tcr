-- =====================================================
-- 054: Ekip antrenmanı bildirimi - event_group_programs INSERT
-- =====================================================
-- Etkinlik önce oluşturuluyor, sonra grup programları ekleniyor. Bu yüzden
-- events INSERT tetikleyicisi çalıştığında event_group_programs henüz boş;
-- alıcı bulunamıyor ve bildirim gitmiyordu.
-- Çözüm: event_group_programs'a her grup eklendiğinde o grubun üyelerine
-- "event_created" bildirimi gönder. (Kullanıcı en fazla bir grupta olduğu için
-- aynı kişiye tekrar bildirim gitmez.)

CREATE OR REPLACE FUNCTION public.notify_on_event_group_program_insert()
RETURNS TRIGGER
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
    -- Etkinlik bilgisi: yayınlanmış, antrenman, ekip olmalı
    SELECT id, title, start_time, status, event_type, participation_type
    INTO v_event
    FROM public.events
    WHERE id = NEW.event_id;

    IF v_event.id IS NULL THEN
        RETURN NEW;
    END IF;
    IF v_event.status != 'published' THEN
        RETURN NEW;
    END IF;
    IF v_event.event_type != 'training' OR v_event.participation_type != 'team' THEN
        RETURN NEW;
    END IF;

    -- Bu grubun üyeleri (group_members.group_id = training_group_id)
    SELECT ARRAY_AGG(gm.user_id)
    INTO v_recipient_ids
    FROM public.group_members gm
    WHERE gm.group_id = NEW.training_group_id;

    IF v_recipient_ids IS NULL OR array_length(v_recipient_ids, 1) IS NULL OR array_length(v_recipient_ids, 1) = 0 THEN
        RETURN NEW;
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

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_event_group_program_insert_notify ON public.event_group_programs;
CREATE TRIGGER on_event_group_program_insert_notify
    AFTER INSERT ON public.event_group_programs
    FOR EACH ROW EXECUTE FUNCTION public.notify_on_event_group_program_insert();

COMMENT ON FUNCTION public.notify_on_event_group_program_insert() IS
  'Ekip antrenmanı oluşturulduktan sonra grup programı eklendiğinde o grubun üyelerine event_created bildirimi gönderir.';
