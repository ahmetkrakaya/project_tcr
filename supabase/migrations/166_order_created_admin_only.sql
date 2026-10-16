-- =====================================================
-- 166: Yeni sipariş bildirimi yalnızca adminlere
-- =====================================================
-- order_created bildirimi super_admin kullanıcılara gider.
-- Koçlar bu bildirimi almaz ve sipariş yönetimine yönlendirilmez.

CREATE OR REPLACE FUNCTION public.notify_on_order_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recipient_ids UUID[];
    v_data JSONB;
    v_listing_title TEXT;
BEGIN
    -- Elden satış: kaydı admin oluşturduğu için bildirim gereksiz
    IF COALESCE(NEW.is_manual, false) THEN
        RETURN NEW;
    END IF;

    v_data := jsonb_build_object('order_id', NEW.id, 'listing_id', NEW.listing_id);
    SELECT title INTO v_listing_title
    FROM public.marketplace_listings
    WHERE id = NEW.listing_id;

    SELECT ARRAY_AGG(ur.user_id)
    INTO v_recipient_ids
    FROM public.user_roles ur
    WHERE ur.role = 'super_admin';

    IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.insert_notifications(
            'order_created',
            'Yeni Sipariş Alındı',
            COALESCE(trim(v_listing_title), 'Ürün') || ' için sipariş verildi.',
            v_data,
            v_recipient_ids
        );
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_on_order_created() IS
    'Yeni uygulama siparişi gelince yalnızca super_admin kullanıcılarına order_created bildirimi yazar.';
