-- TCR Migration 100: Marketplace politikalarını tüm adminler için düzelt
-- 1) marketplace_listings: tüm admin/coach'lar düzenleyebilsin
-- 2) listing_images: adminler de görselleri yönetebilsin

-- ==========================================
-- marketplace_listings politikaları
-- ==========================================

-- Mevcut kısıtlayıcı politikaları kaldır (027 ve 026'dan gelenler)
DROP POLICY IF EXISTS "Only admins can create listings" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Only admins can update listings" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Only admins can delete listings" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Only admins can create TCR products" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Only admins can update TCR products" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Only admins can delete TCR products" ON public.marketplace_listings;

-- Tüm admin ve coach'lar oluşturabilir
CREATE POLICY "Admins can create listings"
    ON public.marketplace_listings FOR INSERT
    WITH CHECK (public.is_admin_or_coach());

-- Tüm admin ve coach'lar güncelleyebilir
CREATE POLICY "Admins can update listings"
    ON public.marketplace_listings FOR UPDATE
    USING (public.is_admin_or_coach())
    WITH CHECK (public.is_admin_or_coach());

-- Tüm admin ve coach'lar silebilir
CREATE POLICY "Admins can delete listings"
    ON public.marketplace_listings FOR DELETE
    USING (public.is_admin_or_coach());

-- ==========================================
-- listing_images politikaları
-- ==========================================

-- Mevcut politikayı kaldır
DROP POLICY IF EXISTS "Sellers can manage listing images" ON public.listing_images;

-- Adminler veya ilgili satıcı yönetebilir
CREATE POLICY "Admins can manage listing images"
    ON public.listing_images FOR ALL
    USING (
        public.is_admin_or_coach()
        OR listing_id IN (
            SELECT id FROM public.marketplace_listings WHERE seller_id = auth.uid()
        )
    )
    WITH CHECK (
        public.is_admin_or_coach()
        OR listing_id IN (
            SELECT id FROM public.marketplace_listings WHERE seller_id = auth.uid()
        )
    );
