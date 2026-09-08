-- =====================================================
-- 158: Sipariş bildirim tetikleyicilerini geri getir
-- =====================================================
-- Migration 120 sipariş bildirimlerini kapatmıştı:
--   DROP TRIGGER on_order_created_notify / on_order_status_notify
-- Fonksiyonlar DB'de kalmış olabilir; tetikleyici olmadığı için
-- adminlere yeni sipariş ve alıcıya durum güncellemesi gitmiyordu.
--
-- Bu migration:
-- - Fonksiyonları güncel şemaya göre yeniden tanımlar
-- - Trigger'ları tekrar bağlar
-- - Manuel (elden) satışlarda admin bildirimi atlanır (admin zaten kaydı oluşturuyor)
-- - buyer_id NULL ise durum bildirimi atlanır (kayıtsız alıcı)

-- =====================
-- YENİ SİPARİŞ → admin / coach
-- =====================
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
    WHERE ur.role IN ('super_admin', 'coach');

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

DROP TRIGGER IF EXISTS on_order_created_notify ON public.marketplace_orders;
CREATE TRIGGER on_order_created_notify
    AFTER INSERT ON public.marketplace_orders
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_on_order_created();

-- =====================
-- DURUM DEĞİŞTİ → alıcı (buyer)
-- =====================
CREATE OR REPLACE FUNCTION public.notify_on_order_status_changed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_data JSONB;
    v_status_text TEXT;
    v_listing_title TEXT;
BEGIN
    IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
        RETURN NEW;
    END IF;

    -- Kayıtsız (elden) alıcıya push gidecek kullanıcı yok
    IF NEW.buyer_id IS NULL THEN
        RETURN NEW;
    END IF;

    v_status_text := CASE NEW.status
        WHEN 'pending' THEN 'beklemede'
        WHEN 'confirmed' THEN 'onaylandı'
        WHEN 'cancelled' THEN 'iptal edildi'
        WHEN 'completed' THEN 'tamamlandı'
        ELSE NEW.status::TEXT
    END;

    SELECT title INTO v_listing_title
    FROM public.marketplace_listings
    WHERE id = NEW.listing_id;

    v_data := jsonb_build_object(
        'order_id', NEW.id,
        'listing_id', NEW.listing_id,
        'status', NEW.status
    );

    PERFORM public.insert_notifications(
        'order_status_changed',
        'Siparişinizin durumu güncellendi',
        COALESCE(trim(v_listing_title), 'Ürün') || '. Siparişiniz ' || v_status_text || '.',
        v_data,
        ARRAY[NEW.buyer_id]
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_order_status_notify ON public.marketplace_orders;
CREATE TRIGGER on_order_status_notify
    AFTER UPDATE OF status ON public.marketplace_orders
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_on_order_status_changed();

COMMENT ON FUNCTION public.notify_on_order_created() IS
    'Yeni uygulama siparişi gelince super_admin ve coach kullanıcılarına order_created bildirimi yazar.';

COMMENT ON FUNCTION public.notify_on_order_status_changed() IS
    'Sipariş durumu değişince kayıtlı alıcıya (buyer_id) order_status_changed bildirimi yazar.';
