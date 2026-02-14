-- TCR Migration 018: Remove Referral System
-- Referans kodu sistemini tamamen kaldır

-- ==========================================
-- 1. REFERRAL CODE KOLONLARINI KALDIR
-- ==========================================

-- Önce referral_code index'ini kaldır
DROP INDEX IF EXISTS idx_users_referral_code;

-- referral_code ve referred_by kolonlarını kaldır
ALTER TABLE public.users 
    DROP COLUMN IF EXISTS referral_code,
    DROP COLUMN IF EXISTS referred_by;

-- ==========================================
-- 2. REFERRAL CODE FONKSİYONUNU KALDIR
-- ==========================================

DROP FUNCTION IF EXISTS generate_referral_code() CASCADE;

-- ==========================================
-- 3. TRIGGER FONKSİYONUNU GÜNCELLE
-- ==========================================

-- handle_new_user fonksiyonunu referral_code olmadan güncelle
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Email doğrulanmış kullanıcılar için profil oluştur
    -- Email doğrulanmamışsa profil oluşturma (email confirmation sonrası oluşturulacak)
    IF NEW.email_confirmed_at IS NOT NULL THEN
        INSERT INTO public.users (id, email, first_name, last_name, is_active)
        VALUES (
            NEW.id,
            NEW.email,
            COALESCE((NEW.raw_user_meta_data->>'first_name')::TEXT, NULL),
            COALESCE((NEW.raw_user_meta_data->>'last_name')::TEXT, NULL),
            false  -- Varsayılan olarak onay bekliyor
        )
        ON CONFLICT (id) DO NOTHING;
        
        -- Varsayılan member rolü atanır (sadece email doğrulanmışsa)
        INSERT INTO public.user_roles (user_id, role)
        VALUES (NEW.id, 'member')
        ON CONFLICT (user_id, role) DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ==========================================
-- 4. EMAIL DOĞRULAMA SONRASI TRIGGER
-- ==========================================

-- Email doğrulandığında kullanıcı profilini oluştur
CREATE OR REPLACE FUNCTION public.handle_email_confirmed()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Email doğrulandıysa ve profil yoksa oluştur
    IF NEW.email_confirmed_at IS NOT NULL AND OLD.email_confirmed_at IS NULL THEN
        INSERT INTO public.users (id, email, first_name, last_name, is_active)
        VALUES (
            NEW.id,
            NEW.email,
            COALESCE((NEW.raw_user_meta_data->>'first_name')::TEXT, NULL),
            COALESCE((NEW.raw_user_meta_data->>'last_name')::TEXT, NULL),
            false  -- Varsayılan olarak onay bekliyor
        )
        ON CONFLICT (id) DO UPDATE SET
            email = NEW.email,
            first_name = COALESCE((NEW.raw_user_meta_data->>'first_name')::TEXT, public.users.first_name),
            last_name = COALESCE((NEW.raw_user_meta_data->>'last_name')::TEXT, public.users.last_name);
        
        -- Varsayılan member rolü atanır
        INSERT INTO public.user_roles (user_id, role)
        VALUES (NEW.id, 'member')
        ON CONFLICT (user_id, role) DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Email doğrulama trigger'ı
DROP TRIGGER IF EXISTS on_email_confirmed ON auth.users;
CREATE TRIGGER on_email_confirmed
    AFTER UPDATE OF email_confirmed_at ON auth.users
    FOR EACH ROW 
    WHEN (NEW.email_confirmed_at IS NOT NULL AND OLD.email_confirmed_at IS NULL)
    EXECUTE FUNCTION public.handle_email_confirmed();
