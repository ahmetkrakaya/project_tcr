-- =====================================================
-- 078: Foundations - Bağış vakıfları
-- =====================================================
-- Vakıf listesi tablosu. Bağış eklerken dropdown'dan seçilir.
-- Adminler vakıf ekleyebilir, düzenleyebilir, silebilir.

-- =====================================================
-- 1) foundations tablosu
-- =====================================================
CREATE TABLE IF NOT EXISTS public.foundations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_foundations_name UNIQUE (name)
);

COMMENT ON TABLE public.foundations IS 'Bağış vakıfları listesi';

-- Varsayılan vakıflar (boş liste olmasın)
INSERT INTO public.foundations (name) VALUES ('LÖSEV'), ('TEGV')
ON CONFLICT (name) DO NOTHING;

-- =====================================================
-- 2) updated_at trigger
-- =====================================================
CREATE OR REPLACE FUNCTION public.update_foundations_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_foundations_updated_at
    BEFORE UPDATE ON public.foundations
    FOR EACH ROW
    EXECUTE FUNCTION public.update_foundations_updated_at();

-- =====================================================
-- 3) RLS - foundations
-- =====================================================
ALTER TABLE public.foundations ENABLE ROW LEVEL SECURITY;

-- Tüm authenticated kullanıcılar vakıfları görebilir (dropdown için)
CREATE POLICY "Authenticated users can view foundations"
    ON public.foundations FOR SELECT
    TO authenticated
    USING (true);

-- Sadece admin vakıf ekleyebilir
CREATE POLICY "Admins can insert foundations"
    ON public.foundations FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- Sadece admin vakıf güncelleyebilir
CREATE POLICY "Admins can update foundations"
    ON public.foundations FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- Sadece admin vakıf silebilir
CREATE POLICY "Admins can delete foundations"
    ON public.foundations FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );
