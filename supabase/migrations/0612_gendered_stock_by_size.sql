-- TCR Migration 061: Gendered stock by size and orders
-- Amaç:
-- - listing_stock_by_size tablosuna gender dimension'ı eklemek
-- - marketplace_orders tablosuna selected_gender eklemek
-- - marketplace_listings için stok cinsiyet modu eklemek
-- - manage_stock_on_order_status_change fonksiyonunu gender+size kombinasyonuna göre güncellemek

-- 1) Gender enum tipi (marketplace stokları için)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type typ
        JOIN pg_namespace nsp ON nsp.oid = typ.typnamespace
        WHERE nsp.nspname = 'public'
          AND typ.typname = 'listing_gender'
    ) THEN
        CREATE TYPE public.listing_gender AS ENUM ('male', 'female', 'unisex');
    END IF;
END
$$;

-- 2) Stok gender modu enum'u (ürün seviyesinde)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type typ
        JOIN pg_namespace nsp ON nsp.oid = typ.typnamespace
        WHERE nsp.nspname = 'public'
          AND typ.typname = 'listing_stock_gender_mode'
    ) THEN
        CREATE TYPE public.listing_stock_gender_mode AS ENUM ('unisex', 'gendered');
    END IF;
END
$$;

-- 3) marketplace_listings: stok gender modu kolonu
ALTER TABLE public.marketplace_listings
    ADD COLUMN IF NOT EXISTS stock_gender_mode public.listing_stock_gender_mode NOT NULL DEFAULT 'unisex';

COMMENT ON COLUMN public.marketplace_listings.stock_gender_mode IS
    'Stokların cinsiyet boyutuna göre tutulup tutulmadığını belirtir: unisex (tek stok), gendered (erkek/kadın ayrı stok).';

-- 4) listing_stock_by_size: gender kolonu ve unique constraint güncellemesi
ALTER TABLE public.listing_stock_by_size
    ADD COLUMN IF NOT EXISTS gender public.listing_gender;

-- Mevcut kayıtlar için default gender = unisex
UPDATE public.listing_stock_by_size
SET gender = 'unisex'
WHERE gender IS NULL;

ALTER TABLE public.listing_stock_by_size
    ALTER COLUMN gender SET NOT NULL;

-- Eski UNIQUE(listing_id, size) constraint'ini kaldır
ALTER TABLE public.listing_stock_by_size
    DROP CONSTRAINT IF EXISTS listing_stock_by_size_listing_id_size_key;

-- Yeni unique: listing_id + size + gender
ALTER TABLE public.listing_stock_by_size
    ADD CONSTRAINT listing_stock_by_size_listing_id_size_gender_key
    UNIQUE (listing_id, size, gender);

COMMENT ON COLUMN public.listing_stock_by_size.gender IS
    'Stok kaydının ait olduğu cinsiyet: male, female veya unisex.';

-- 5) marketplace_orders: selected_gender kolonu
ALTER TABLE public.marketplace_orders
    ADD COLUMN IF NOT EXISTS selected_gender public.listing_gender;

COMMENT ON COLUMN public.marketplace_orders.selected_gender IS
    'Sipariş sırasında seçilen cinsiyet (male, female, unisex). Eski siparişlerde NULL kalabilir.';

-- 6) manage_stock_on_order_status_change fonksiyonunu gender+size ile güncelle
CREATE OR REPLACE FUNCTION public.manage_stock_on_order_status_change()
RETURNS TRIGGER AS $$
DECLARE
    order_size TEXT;
    order_gender public.listing_gender;
    has_stock_by_size BOOLEAN;
BEGIN
    -- Siparişin seçilen bedenini ve cinsiyetini al
    order_size := NEW.selected_size;
    -- NULL ise geriye dönük uyumluluk için unisex kabul et
    order_gender := COALESCE(NEW.selected_gender, 'unisex'::public.listing_gender);

    -- Beden + cinsiyet bazlı stok var mı kontrol et
    IF order_size IS NOT NULL AND order_size <> '' THEN
        SELECT EXISTS (
            SELECT 1
            FROM public.listing_stock_by_size
            WHERE listing_id = NEW.listing_id
              AND size = order_size
              AND gender = order_gender
        ) INTO has_stock_by_size;
    ELSE
        has_stock_by_size := FALSE;
    END IF;

    -- Onaylandı durumuna geçildiğinde stok düşür (sadece beklemede ise)
    IF NEW.status = 'confirmed' AND OLD.status = 'pending' THEN
        -- Beden + cinsiyet bazlı stok varsa
        IF has_stock_by_size THEN
            UPDATE public.listing_stock_by_size
            SET quantity = GREATEST(0, quantity - NEW.quantity)
            WHERE listing_id = NEW.listing_id
              AND size = order_size
              AND gender = order_gender
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
            -- Beden + cinsiyet bazlı stok varsa
            IF has_stock_by_size THEN
                UPDATE public.listing_stock_by_size
                SET quantity = GREATEST(0, quantity - NEW.quantity)
                WHERE listing_id = NEW.listing_id
                  AND size = order_size
                  AND gender = order_gender
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
        
        -- Beden + cinsiyet bazlı stok varsa
        IF has_stock_by_size THEN
            UPDATE public.listing_stock_by_size
            SET quantity = quantity + NEW.quantity
            WHERE listing_id = NEW.listing_id
              AND size = order_size
              AND gender = order_gender;
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

COMMENT ON FUNCTION public.manage_stock_on_order_status_change() IS 
'Sipariş durumu değiştiğinde stok yönetimi yapar. Beklemede durumunda stok düşmez. Onaylandı veya Tamamlandı durumunda stok düşer. İptal edildiğinde (önceden onaylandı/tamamlandı ise) stok geri gelir. Beden + cinsiyet bazlı stok desteği vardır.';

