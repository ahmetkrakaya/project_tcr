-- TCR Migration 152: Üretim partileri ve maliyet takibi
-- Amaç:
-- - Her ürün için "kaç adet ürettik, birim maliyeti ne" bilgisini tutmak
-- - Beden bazında farklı adetler, parti başına tek birim maliyet
-- - Kar-zarar raporlaması için toplam üretim maliyeti ve kalan adet hesabı

-- Foreign key'ler marketplace_listings ve users üzerinde kilit aldığı için,
-- canlı trafikte beklemek yerine hızlı hata verip tekrar denenebilsin.
SET LOCAL lock_timeout = '15s';

CREATE TABLE IF NOT EXISTS public.production_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id UUID NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
    unit_cost DECIMAL(10,2) NOT NULL CHECK (unit_cost >= 0),
    currency TEXT NOT NULL DEFAULT 'TRY',
    produced_at DATE NOT NULL DEFAULT CURRENT_DATE,
    note TEXT,
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.production_batch_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id UUID NOT NULL REFERENCES public.production_batches(id) ON DELETE CASCADE,
    size TEXT NOT NULL,
    gender public.listing_gender NOT NULL DEFAULT 'unisex',
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT production_batch_items_batch_size_gender_key UNIQUE (batch_id, size, gender)
);

CREATE INDEX IF NOT EXISTS idx_production_batches_listing
    ON public.production_batches (listing_id);
CREATE INDEX IF NOT EXISTS idx_production_batch_items_batch
    ON public.production_batch_items (batch_id);

COMMENT ON TABLE public.production_batches IS
    'Ürün üretim partileri. Parti başına tek birim maliyet, beden kırılımı production_batch_items içinde.';
COMMENT ON COLUMN public.production_batches.unit_cost IS
    'Bu partideki her bir adetin üretim maliyeti. Beden fark etmeksizin aynıdır.';
COMMENT ON TABLE public.production_batch_items IS
    'Üretim partisinin beden ve cinsiyet bazlı adet kırılımı. Tek bedenli üründe size = Standart.';

DROP TRIGGER IF EXISTS update_production_batches_updated_at ON public.production_batches;
CREATE TRIGGER update_production_batches_updated_at
    BEFORE UPDATE ON public.production_batches
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- RLS: maliyet gizli veri, sadece admin/koç erişebilir
-- ============================================================
ALTER TABLE public.production_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.production_batch_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can manage production batches" ON public.production_batches;
CREATE POLICY "Admins can manage production batches"
    ON public.production_batches FOR ALL
    USING (public.is_admin_or_coach())
    WITH CHECK (public.is_admin_or_coach());

DROP POLICY IF EXISTS "Admins can manage production batch items" ON public.production_batch_items;
CREATE POLICY "Admins can manage production batch items"
    ON public.production_batch_items FOR ALL
    USING (public.is_admin_or_coach())
    WITH CHECK (public.is_admin_or_coach());

-- ============================================================
-- Yardımcı fonksiyonlar
-- ============================================================
-- Ürünün ağırlıklı ortalama birim maliyeti.
-- Manuel satış eklenirken unit_cost snapshot'ı bu değerden doldurulur.
CREATE OR REPLACE FUNCTION public.get_listing_avg_unit_cost(p_listing_id UUID)
RETURNS DECIMAL
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE
        WHEN COALESCE(SUM(i.quantity), 0) = 0 THEN NULL
        ELSE ROUND(SUM(i.quantity * b.unit_cost) / SUM(i.quantity), 2)
    END
    FROM public.production_batches b
    JOIN public.production_batch_items i ON i.batch_id = b.id
    WHERE b.listing_id = p_listing_id;
$$;

COMMENT ON FUNCTION public.get_listing_avg_unit_cost(UUID) IS
    'Ürünün tüm üretim partileri üzerinden ağırlıklı ortalama birim maliyetini döner. Parti yoksa NULL.';

-- Ürün bazında üretim özeti (toplam adet ve toplam maliyet)
CREATE OR REPLACE FUNCTION public.get_listing_production_summary(p_listing_id UUID)
RETURNS TABLE (
    total_quantity INTEGER,
    total_cost DECIMAL,
    avg_unit_cost DECIMAL
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        COALESCE(SUM(i.quantity), 0)::INTEGER,
        COALESCE(SUM(i.quantity * b.unit_cost), 0)::DECIMAL,
        CASE
            WHEN COALESCE(SUM(i.quantity), 0) = 0 THEN NULL
            ELSE ROUND(SUM(i.quantity * b.unit_cost) / SUM(i.quantity), 2)
        END
    FROM public.production_batches b
    JOIN public.production_batch_items i ON i.batch_id = b.id
    WHERE b.listing_id = p_listing_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_listing_avg_unit_cost(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_listing_production_summary(UUID) TO authenticated;
