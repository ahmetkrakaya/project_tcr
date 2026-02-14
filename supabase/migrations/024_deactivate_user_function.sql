-- TCR Migration 024: Deactivate User Function
-- Admin kullanıcıların kullanıcıları pasif yapabilmesi için fonksiyon

-- ==========================================
-- ADMIN KULLANICI PASİFLEŞTİRME FONKSİYONU
-- ==========================================

-- Admin kullanıcıları pasif yapabilir
CREATE OR REPLACE FUNCTION public.deactivate_user(user_id_to_deactivate UUID, deactivated_by UUID)
RETURNS BOOLEAN AS $$
DECLARE
    is_admin BOOLEAN;
BEGIN
    -- Pasifleştiren kişinin admin olduğunu kontrol et
    SELECT EXISTS(
        SELECT 1 FROM public.user_roles
        WHERE user_id = deactivated_by AND role = 'super_admin'
    ) INTO is_admin;
    
    IF NOT is_admin THEN
        RAISE EXCEPTION 'Sadece admin kullanıcıları pasifleştirebilir';
    END IF;
    
    -- Kendini pasifleştiremez
    IF user_id_to_deactivate = deactivated_by THEN
        RAISE EXCEPTION 'Kendinizi pasifleştiremezsiniz';
    END IF;
    
    -- Kullanıcıyı pasif yap
    UPDATE public.users
    SET is_active = false, updated_at = NOW()
    WHERE id = user_id_to_deactivate;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
