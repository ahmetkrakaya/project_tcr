-- TCR Migration 033: Fix listing status when order is completed
-- Sipariş tamamlandığında listing durumunu tekrar active yap
-- Stok bitene kadar listing active kalmalı

-- Function: Sipariş tamamlandığında listing'i tekrar active yap
CREATE OR REPLACE FUNCTION public.handle_order_completed()
RETURNS TRIGGER AS $$
BEGIN
    -- Sipariş tamamlandığında listing durumunu tekrar active yap
    -- Stok varsa listing active kalmalı
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        UPDATE public.marketplace_listings
        SET status = 'active'
        WHERE id = NEW.listing_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Sipariş tamamlandığında
CREATE TRIGGER on_order_completed
    AFTER UPDATE ON public.marketplace_orders
    FOR EACH ROW EXECUTE FUNCTION public.handle_order_completed();

-- Function: Sipariş onaylandığında listing durumunu güncelle
-- Stoklu ürünler için: Stok bitene kadar listing active kalmalı
-- Stoksuz ürünler için: Reserved yap
CREATE OR REPLACE FUNCTION public.handle_order_confirmed()
RETURNS TRIGGER AS $$
DECLARE
    listing_stock INTEGER;
BEGIN
    -- Sipariş onaylandığında listing durumunu güncelle
    IF NEW.status = 'confirmed' AND OLD.status != 'confirmed' THEN
        -- Listing'in stok miktarını kontrol et
        SELECT stock_quantity INTO listing_stock
        FROM public.marketplace_listings
        WHERE id = NEW.listing_id;
        
        -- Stok varsa (null değilse ve > 0 ise) active kal, yoksa reserved yap
        IF listing_stock IS NOT NULL AND listing_stock > 0 THEN
            -- Stok varsa active kal (stok bitene kadar satışa devam edebilir)
            UPDATE public.marketplace_listings
            SET status = 'active'
            WHERE id = NEW.listing_id;
        ELSE
            -- Stok yoksa veya null ise reserved yap (tek ürün satıldı)
            UPDATE public.marketplace_listings
            SET status = 'reserved'
            WHERE id = NEW.listing_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
