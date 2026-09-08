-- TCR Migration 154: Beden bazlı stok için koç erişimi
-- Amaç: listing_stock_by_size policy'lerini is_admin_or_coach()'a genişletmek.
--       Önceden yalnızca super_admin stok yönetebiliyordu, koçlar göremiyordu.
--
-- Kilit notu: 151 numaralı migration'dan ayrıldı. Bu iki tabloyu (marketplace_orders
-- ve listing_stock_by_size) aynı transaction'da AccessExclusiveLock ile kilitlemek,
-- ikisini ters sırada okuyan canlı sorgularla deadlock üretiyordu.

SET LOCAL lock_timeout = '15s';
LOCK TABLE public.listing_stock_by_size IN ACCESS EXCLUSIVE MODE;

DROP POLICY IF EXISTS "Users can view stock by size for their listings or as admin"
    ON public.listing_stock_by_size;
CREATE POLICY "Users can view stock by size for their listings or as admin"
    ON public.listing_stock_by_size FOR SELECT
    USING (
        public.is_admin_or_coach()
        OR EXISTS (
            SELECT 1 FROM public.marketplace_listings ml
            WHERE ml.id = listing_stock_by_size.listing_id
              AND ml.seller_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can manage stock by size for their listings or as admin"
    ON public.listing_stock_by_size;
CREATE POLICY "Users can manage stock by size for their listings or as admin"
    ON public.listing_stock_by_size FOR ALL
    USING (
        public.is_admin_or_coach()
        OR EXISTS (
            SELECT 1 FROM public.marketplace_listings ml
            WHERE ml.id = listing_stock_by_size.listing_id
              AND ml.seller_id = auth.uid()
        )
    )
    WITH CHECK (
        public.is_admin_or_coach()
        OR EXISTS (
            SELECT 1 FROM public.marketplace_listings ml
            WHERE ml.id = listing_stock_by_size.listing_id
              AND ml.seller_id = auth.uid()
        )
    );
