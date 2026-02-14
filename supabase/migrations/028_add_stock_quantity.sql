-- TCR Migration 028: Add stock quantity to marketplace listings
-- Stok yönetimi için stock_quantity kolonu ekle

-- Stock quantity kolonu ekle
ALTER TABLE public.marketplace_listings 
ADD COLUMN IF NOT EXISTS stock_quantity INTEGER DEFAULT NULL;

-- Mevcut kayıtlar için varsayılan değer (sınırsız stok gibi davranmak için NULL)
-- NULL = sınırsız stok, 0 = stok yok, >0 = mevcut stok

-- Stok kontrolü için comment
COMMENT ON COLUMN public.marketplace_listings.stock_quantity IS 'Stok miktarı. NULL = sınırsız, 0 = stok yok, >0 = mevcut stok';

-- Sipariş oluşturulduğunda stok azaltma trigger'ı
CREATE OR REPLACE FUNCTION public.decrease_stock_on_order()
RETURNS TRIGGER AS $$
BEGIN
    -- Sipariş onaylandığında stok azalt
    IF NEW.status = 'confirmed' AND OLD.status != 'confirmed' THEN
        UPDATE public.marketplace_listings
        SET stock_quantity = GREATEST(0, stock_quantity - NEW.quantity)
        WHERE id = NEW.listing_id 
          AND stock_quantity IS NOT NULL;
    END IF;
    
    -- Sipariş iptal edildiğinde stok geri ekle
    IF NEW.status = 'cancelled' AND OLD.status = 'confirmed' THEN
        UPDATE public.marketplace_listings
        SET stock_quantity = stock_quantity + NEW.quantity
        WHERE id = NEW.listing_id 
          AND stock_quantity IS NOT NULL;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger'ı ekle (eğer yoksa)
DROP TRIGGER IF EXISTS on_order_stock_update ON public.marketplace_orders;
CREATE TRIGGER on_order_stock_update
    AFTER UPDATE ON public.marketplace_orders
    FOR EACH ROW EXECUTE FUNCTION public.decrease_stock_on_order();
