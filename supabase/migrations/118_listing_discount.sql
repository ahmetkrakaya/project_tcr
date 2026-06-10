-- TCR Migration 118: Marketplace listing time-limited discounts
-- Ürünlere belirli bir süre için yüzde indirim uygulanabilir.

ALTER TABLE public.marketplace_listings
    ADD COLUMN IF NOT EXISTS discount_percent SMALLINT,
    ADD COLUMN IF NOT EXISTS discount_starts_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS discount_ends_at TIMESTAMPTZ;

ALTER TABLE public.marketplace_listings
    DROP CONSTRAINT IF EXISTS marketplace_listings_discount_percent_check;

ALTER TABLE public.marketplace_listings
    ADD CONSTRAINT marketplace_listings_discount_percent_check
    CHECK (
        discount_percent IS NULL
        OR (discount_percent >= 1 AND discount_percent <= 100)
    );

ALTER TABLE public.marketplace_listings
    DROP CONSTRAINT IF EXISTS marketplace_listings_discount_window_check;

ALTER TABLE public.marketplace_listings
    ADD CONSTRAINT marketplace_listings_discount_window_check
    CHECK (
        discount_percent IS NULL
        OR (
            discount_starts_at IS NOT NULL
            AND discount_ends_at IS NOT NULL
            AND discount_ends_at > discount_starts_at
        )
    );

COMMENT ON COLUMN public.marketplace_listings.discount_percent IS
    'Aktif indirim döneminde uygulanacak yüzde indirim (1-100).';

COMMENT ON COLUMN public.marketplace_listings.discount_starts_at IS
    'İndirimin başlayacağı tarih/saat (UTC).';

COMMENT ON COLUMN public.marketplace_listings.discount_ends_at IS
    'İndirimin biteceği tarih/saat (UTC).';

CREATE INDEX IF NOT EXISTS idx_marketplace_listings_discount_ends_at
    ON public.marketplace_listings (discount_ends_at)
    WHERE discount_percent IS NOT NULL;
