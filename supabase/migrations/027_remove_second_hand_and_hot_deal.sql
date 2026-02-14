-- TCR Migration 027: Remove second_hand and hot_deal listing types
-- Sadece TCR ürünleri kalacak

-- Önce listing_type kolonunu kullanan policy'leri kaldır
DROP POLICY IF EXISTS "Only admins can create TCR products" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Only admins can update TCR products" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Only admins can delete TCR products" ON public.marketplace_listings;

-- Mevcut verileri tcr_product'e çevir
UPDATE public.marketplace_listings 
SET listing_type = 'tcr_product'::listing_type
WHERE listing_type != 'tcr_product'::listing_type;

-- Default değeri kaldır
ALTER TABLE public.marketplace_listings 
    ALTER COLUMN listing_type DROP DEFAULT;

-- Yeni enum oluştur
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'listing_type_new') THEN
        CREATE TYPE listing_type_new AS ENUM ('tcr_product');
    END IF;
END $$;

-- Kolonu yeni enum tipine çevir
ALTER TABLE public.marketplace_listings 
    ALTER COLUMN listing_type TYPE listing_type_new 
    USING listing_type::text::listing_type_new;

-- Default değeri yeni enum ile ekle
ALTER TABLE public.marketplace_listings 
    ALTER COLUMN listing_type SET DEFAULT 'tcr_product'::listing_type_new;

-- Eski enum'u sil (CASCADE ile bağımlılıkları da siler)
DROP TYPE IF EXISTS listing_type CASCADE;

-- Yeni enum'u eski isimle değiştir
ALTER TYPE listing_type_new RENAME TO listing_type;

-- Policy'leri yeniden oluştur (artık sadece tcr_product var, her zaman admin kontrolü)
CREATE POLICY "Only admins can create listings"
    ON public.marketplace_listings FOR INSERT
    WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Only admins can update listings"
    ON public.marketplace_listings FOR UPDATE
    USING (public.has_role(auth.uid(), 'super_admin'))
    WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Only admins can delete listings"
    ON public.marketplace_listings FOR DELETE
    USING (public.has_role(auth.uid(), 'super_admin'));

-- Eski policy'leri kaldır (007_rls_policies.sql'den gelenler)
DROP POLICY IF EXISTS "Users can create listings" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Sellers can manage own listings" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Sellers can delete own listings" ON public.marketplace_listings;

-- Condition field'ını kaldırmak yerine, sadece kullanılmamasını sağlayalım
-- (Mevcut verileri korumak için field'ı kaldırmıyoruz, sadece yeni kayıtlarda null olacak)

COMMENT ON COLUMN public.marketplace_listings.listing_type IS 'Sadece tcr_product kullanılıyor - TCR Kulübü resmi ürünleri';
COMMENT ON COLUMN public.marketplace_listings.condition IS 'Artık kullanılmıyor - TCR ürünleri her zaman yeni';
