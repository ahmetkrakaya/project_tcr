-- TCR Migration 048: Beden bazlı stok yönetimi
-- Her beden için ayrı stok miktarı tutmak için yeni tablo

-- Beden bazlı stok tablosu
CREATE TABLE IF NOT EXISTS public.listing_stock_by_size (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
    size TEXT NOT NULL, -- Beden (XS, S, M, L, XL, XXL vb.)
    quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(listing_id, size)
);

-- Index'ler
CREATE INDEX IF NOT EXISTS idx_listing_stock_by_size_listing_id ON public.listing_stock_by_size(listing_id);
CREATE INDEX IF NOT EXISTS idx_listing_stock_by_size_size ON public.listing_stock_by_size(size);

-- Updated_at trigger
CREATE TRIGGER update_listing_stock_by_size_updated_at
    BEFORE UPDATE ON public.listing_stock_by_size
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- RLS Policies
ALTER TABLE public.listing_stock_by_size ENABLE ROW LEVEL SECURITY;

-- Admin ve ürün sahibi görebilir
CREATE POLICY "Users can view stock by size for their listings or as admin"
    ON public.listing_stock_by_size
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.marketplace_listings ml
            WHERE ml.id = listing_stock_by_size.listing_id
            AND (
                ml.seller_id = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM public.user_roles ur
                    WHERE ur.user_id = auth.uid()
                    AND ur.role = 'super_admin'
                )
            )
        )
    );

-- Sadece admin ve ürün sahibi ekleyebilir/güncelleyebilir
CREATE POLICY "Users can manage stock by size for their listings or as admin"
    ON public.listing_stock_by_size
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.marketplace_listings ml
            WHERE ml.id = listing_stock_by_size.listing_id
            AND (
                ml.seller_id = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM public.user_roles ur
                    WHERE ur.user_id = auth.uid()
                    AND ur.role = 'super_admin'
                )
            )
        )
    );

-- Comment
COMMENT ON TABLE public.listing_stock_by_size IS 'Beden bazlı stok miktarları. Her beden için ayrı stok tutulur.';
