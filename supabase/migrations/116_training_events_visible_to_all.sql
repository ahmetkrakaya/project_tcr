-- ============================================================
-- 116: Ekip antrenmanı etkinlik bildirimleri — herkese
--
-- Antrenman programları haftalık editörden yönetildiği için
-- event_group_programs ataması etkinlik görünürlüğünü belirlemez.
-- event_created alıcıları ekip antrenmanında da tüm aktif kullanıcılar.
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

    -- Ekip antrenmanı: program atamasından bağımsız, tüm aktif kullanıcılar
    IF v_event.event_type = 'training' AND v_event.participation_type = 'team' THEN
        SELECT ARRAY_AGG(id)
        INTO v_recipient_ids
        FROM public.users
        WHERE is_active = true;
        RETURN v_recipient_ids;
    END IF;

    -- Diğer etkinlik türleri
    SELECT ARRAY_AGG(id) INTO v_recipient_ids
    FROM public.users
    WHERE is_active = true;
    RETURN v_recipient_ids;
END;
$$;
