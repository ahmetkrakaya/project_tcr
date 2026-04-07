-- =====================================================
-- 095: Ignore post pin/unpin updates for notifications
-- =====================================================
-- Post pinleme işlemi gerçek içerik güncellemesi değildir; "Duyuru güncellendi" bildirimi gönderilmemeli.

CREATE OR REPLACE FUNCTION public.notify_on_post_change()
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
    IF NOT COALESCE(NEW.is_published, true) THEN
        RETURN NEW;
    END IF;

    -- Pinleme/pin kaldırma: sadece is_pinned ve/veya pinned_at değişmişse bildirim yok
    IF TG_OP = 'UPDATE' THEN
        IF (
            (NEW.is_pinned IS DISTINCT FROM OLD.is_pinned OR NEW.pinned_at IS DISTINCT FROM OLD.pinned_at)
            AND NEW.user_id IS NOT DISTINCT FROM OLD.user_id
            AND NEW.title IS NOT DISTINCT FROM OLD.title
            AND NEW.cover_image_url IS NOT DISTINCT FROM OLD.cover_image_url
            AND NEW.is_published IS NOT DISTINCT FROM OLD.is_published
            AND NEW.event_id IS NOT DISTINCT FROM OLD.event_id
        ) THEN
            RETURN NEW;
        END IF;
    END IF;

    v_data := jsonb_build_object('post_id', NEW.id);
    v_title := trim(NEW.title);

    IF TG_OP = 'INSERT' THEN
        v_notification_type := 'post_created';
        v_body := 'Yeni post yayınlandı.';
    ELSE
        -- Oluşturmadan kısa süre sonraki UPDATE (örn. kapak yüklemesi) için "Duyuru güncellendi" gönderme
        IF (NEW.updated_at - NEW.created_at) < interval '1 minute' THEN
            RETURN NEW;
        END IF;
        v_notification_type := 'post_updated';
        v_body := 'Duyuru güncellendi.';
    END IF;

    SELECT ARRAY_AGG(id) INTO v_recipient_ids
    FROM public.users
    WHERE is_active = true;

    IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.insert_notifications(
            v_notification_type,
            v_title,
            v_body,
            v_data,
            v_recipient_ids
        );
    END IF;
    RETURN NEW;
END;
$$;

