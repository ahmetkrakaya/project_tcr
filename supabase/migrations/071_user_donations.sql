-- =====================================================
-- 071: User Donations - Kullanıcı Bağışları
-- =====================================================
-- Üyelerin yarışlarda topladıkları bağışları kaydetmeleri için tablo.
-- Etkinlikten seçilebilir veya manuel yarış girişi yapılabilir.
-- Güncelleme: yarış tarihinden sonraki 5. güne kadar izinli.

-- =====================================================
-- 1) user_donations tablosu
-- =====================================================
CREATE TABLE IF NOT EXISTS public.user_donations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_id UUID REFERENCES public.events(id) ON DELETE SET NULL,
    race_name TEXT,
    race_date DATE,
    foundation_name TEXT NOT NULL,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT chk_event_or_manual CHECK (
        (event_id IS NOT NULL AND race_name IS NULL AND race_date IS NULL)
        OR
        (event_id IS NULL AND race_name IS NOT NULL AND race_date IS NOT NULL)
    )
);

COMMENT ON TABLE public.user_donations IS 'Üyelerin yarışlarda topladıkları bağış kayıtları';

-- =====================================================
-- 2) İndeksler
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_user_donations_user_id
    ON public.user_donations(user_id);

CREATE INDEX IF NOT EXISTS idx_user_donations_amount_desc
    ON public.user_donations(amount DESC);

CREATE INDEX IF NOT EXISTS idx_user_donations_event_id
    ON public.user_donations(event_id)
    WHERE event_id IS NOT NULL;

-- =====================================================
-- 3) updated_at trigger
-- =====================================================
CREATE OR REPLACE FUNCTION public.update_user_donations_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_user_donations_updated_at
    BEFORE UPDATE ON public.user_donations
    FOR EACH ROW
    EXECUTE FUNCTION public.update_user_donations_updated_at();

-- =====================================================
-- 4) RLS
-- =====================================================
ALTER TABLE public.user_donations ENABLE ROW LEVEL SECURITY;

-- Tüm authenticated kullanıcılar bağışları görebilir
CREATE POLICY "Authenticated users can view donations"
    ON public.user_donations FOR SELECT
    TO authenticated
    USING (true);

-- Kullanıcılar sadece kendi bağışlarını ekleyebilir
CREATE POLICY "Users can insert own donations"
    ON public.user_donations FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- Kullanıcılar kendi bağışlarını, yarış tarihinden sonraki 5 gün içinde güncelleyebilir
CREATE POLICY "Users can update own donations within 5 days after race"
    ON public.user_donations FOR UPDATE
    TO authenticated
    USING (
        user_id = auth.uid()
        AND (
            CASE
                WHEN event_id IS NOT NULL THEN
                    (SELECT (e.start_time::date + INTERVAL '5 days') >= CURRENT_DATE
                     FROM public.events e WHERE e.id = event_id)
                ELSE
                    (race_date + INTERVAL '5 days') >= CURRENT_DATE
            END
        )
    )
    WITH CHECK (user_id = auth.uid());
