-- =====================================================
-- 069: Club Races - TCR Kulübü Yarış Takvimi
-- =====================================================
-- TCR tarafından düzenlenen yarışların basit listesi.
-- Sadece admin ekleme/düzenleme/silme yapabilir, herkes görebilir.

-- =====================================================
-- 1) club_races tablosu
-- =====================================================
CREATE TABLE IF NOT EXISTS public.club_races (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    date DATE NOT NULL,
    location TEXT NOT NULL,
    distance TEXT,
    description TEXT,
    url TEXT,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.club_races IS 'TCR kulübü tarafından düzenlenen yarışların listesi';

-- =====================================================
-- 2) İndeksler
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_club_races_date
    ON public.club_races(date ASC);

-- =====================================================
-- 3) updated_at trigger
-- =====================================================
CREATE OR REPLACE FUNCTION public.update_club_races_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_club_races_updated_at
    BEFORE UPDATE ON public.club_races
    FOR EACH ROW
    EXECUTE FUNCTION public.update_club_races_updated_at();

-- =====================================================
-- 4) RLS
-- =====================================================
ALTER TABLE public.club_races ENABLE ROW LEVEL SECURITY;

-- Tüm authenticated kullanıcılar listeyi görebilir
CREATE POLICY "Authenticated users can view club races"
    ON public.club_races FOR SELECT
    TO authenticated
    USING (true);

-- Sadece super_admin insert yapabilir
CREATE POLICY "Admins can insert club races"
    ON public.club_races FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role = 'super_admin'
        )
    );

-- Sadece super_admin update yapabilir
CREATE POLICY "Admins can update club races"
    ON public.club_races FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role = 'super_admin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role = 'super_admin'
        )
    );

-- Sadece super_admin delete yapabilir
CREATE POLICY "Admins can delete club races"
    ON public.club_races FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role = 'super_admin'
        )
    );
