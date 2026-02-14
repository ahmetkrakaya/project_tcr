-- TCR Migration 050: Sipariş durumuna göre stok yönetimi düzeltmesi
-- Beklemede durumunda stok düşmemeli
-- Onaylandı veya Tamamlandı durumunda stok düşmeli
-- İptal edildiğinde (önceden onaylandı/tamamlandı ise) stok geri gelmeli
-- Beden bazlı stok desteği

-- Eski trigger'ı kaldır
DROP TRIGGER IF EXISTS on_order_stock_update ON public.marketplace_orders;

-- Yeni stok yönetimi fonksiyonu
CREATE OR REPLACE FUNCTION public.manage_stock_on_order_status_change()
RETURNS TRIGGER AS $$
DECLARE
    order_size TEXT;
    has_stock_by_size BOOLEAN;
    current_stock_by_size INTEGER;
BEGIN
    -- Siparişin seçilen bedenini al
    order_size := NEW.selected_size;
    
    -- Beden bazlı stok var mı kontrol et
    SELECT EXISTS (
        SELECT 1 FROM public.listing_stock_by_size
        WHERE listing_id = NEW.listing_id
        AND size = order_size
    ) INTO has_stock_by_size;
    
    -- Onaylandı durumuna geçildiğinde stok düşür (sadece beklemede ise)
    IF NEW.status = 'confirmed' AND OLD.status = 'pending' THEN
        -- Beden bazlı stok varsa
        IF order_size IS NOT NULL AND order_size != '' AND has_stock_by_size THEN
            -- Beden bazlı stoktan düş
            UPDATE public.listing_stock_by_size
            SET quantity = GREATEST(0, quantity - NEW.quantity)
            WHERE listing_id = NEW.listing_id
              AND size = order_size
              AND quantity IS NOT NULL;
        ELSE
            -- Genel stoktan düş
            UPDATE public.marketplace_listings
            SET stock_quantity = GREATEST(0, stock_quantity - NEW.quantity)
            WHERE id = NEW.listing_id 
              AND stock_quantity IS NOT NULL;
        END IF;
    END IF;
    
    -- Tamamlandı durumuna geçildiğinde stok düşür (sadece beklemede veya onaylandı ise)
    IF NEW.status = 'completed' 
       AND (OLD.status = 'pending' OR OLD.status = 'confirmed') THEN
        
        -- Eğer önceden beklemede ise (stok henüz düşmemiş)
        IF OLD.status = 'pending' THEN
            -- Beden bazlı stok varsa
            IF order_size IS NOT NULL AND order_size != '' AND has_stock_by_size THEN
                -- Beden bazlı stoktan düş
                UPDATE public.listing_stock_by_size
                SET quantity = GREATEST(0, quantity - NEW.quantity)
                WHERE listing_id = NEW.listing_id
                  AND size = order_size
                  AND quantity IS NOT NULL;
            ELSE
                -- Genel stoktan düş
                UPDATE public.marketplace_listings
                SET stock_quantity = GREATEST(0, stock_quantity - NEW.quantity)
                WHERE id = NEW.listing_id 
                  AND stock_quantity IS NOT NULL;
            END IF;
        END IF;
        -- Eğer önceden onaylandı ise stok zaten düşmüş, tekrar düşürme
    END IF;
    
    -- İptal edildiğinde stok geri ekle (eğer önceden onaylandı veya tamamlandı ise)
    -- Not: pending'den cancelled'a geçildiğinde stok zaten düşmemişti, geri eklemeye gerek yok
    IF NEW.status = 'cancelled' 
       AND (OLD.status = 'confirmed' OR OLD.status = 'completed') THEN
        
        -- Beden bazlı stok varsa
        IF order_size IS NOT NULL AND order_size != '' AND has_stock_by_size THEN
            -- Beden bazlı stoka geri ekle
            UPDATE public.listing_stock_by_size
            SET quantity = quantity + NEW.quantity
            WHERE listing_id = NEW.listing_id
              AND size = order_size;
        ELSE
            -- Genel stoka geri ekle
            UPDATE public.marketplace_listings
            SET stock_quantity = COALESCE(stock_quantity, 0) + NEW.quantity
            WHERE id = NEW.listing_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger'ı ekle
CREATE TRIGGER on_order_stock_update
    AFTER UPDATE ON public.marketplace_orders
    FOR EACH ROW 
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION public.manage_stock_on_order_status_change();

-- Açıklama
COMMENT ON FUNCTION public.manage_stock_on_order_status_change() IS 
'Sipariş durumu değiştiğinde stok yönetimi yapar. Beklemede durumunda stok düşmez. Onaylandı veya Tamamlandı durumunda stok düşer. İptal edildiğinde (önceden onaylandı/tamamlandı ise) stok geri gelir. Beden bazlı stok desteği vardır.';
