-- =====================================================
-- 015: VDOT System - Jack Daniels VDOT Hesaplama
-- =====================================================
-- Kullanıcı profline VDOT değeri ekleme

-- Users tablosuna VDOT alanları ekle
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS vdot DECIMAL(4,1),
ADD COLUMN IF NOT EXISTS vdot_updated_at TIMESTAMPTZ;

-- Index
CREATE INDEX IF NOT EXISTS idx_users_vdot 
    ON public.users(vdot) WHERE vdot IS NOT NULL;

-- VDOT güncelleme fonksiyonu
CREATE OR REPLACE FUNCTION update_user_vdot(
    p_user_id UUID,
    p_vdot DECIMAL(4,1)
)
RETURNS VOID AS $$
BEGIN
    UPDATE public.users
    SET 
        vdot = p_vdot,
        vdot_updated_at = NOW(),
        updated_at = NOW()
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
