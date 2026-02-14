-- TCR Migration 019: User Approval System
-- Kullanıcı onay sistemi - is_active kontrolü ile giriş engelleme

-- ==========================================
-- 1. IS_ACTIVE DEFAULT DEĞERİNİ GÜNCELLE
-- ==========================================

-- Yeni kayıtlar için is_active varsayılan olarak false olacak
-- (Migration 018'de zaten false yapıldı, burada sadece mevcut kayıtlar için kontrol ediyoruz)

-- Mevcut kullanıcılar için is_active kontrolü yoksa false yap
-- (Sadece test için, production'da bu satırı kaldırabilirsiniz)
-- UPDATE public.users SET is_active = false WHERE is_active IS NULL;

-- ==========================================
-- 2. GİRİŞ KONTROLÜ İÇİN HELPER FONKSİYON
-- ==========================================

-- Kullanıcının giriş yapabilmesi için hem email doğrulanmış hem de aktif olması gerekir
CREATE OR REPLACE FUNCTION public.can_user_login(user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    user_record RECORD;
BEGIN
    -- Auth tablosundan kullanıcı bilgilerini al
    SELECT 
        u.email_confirmed_at,
        p.is_active
    INTO user_record
    FROM auth.users u
    LEFT JOIN public.users p ON p.id = u.id
    WHERE u.id = user_id;
    
    -- Kullanıcı bulunamadıysa false
    IF user_record IS NULL THEN
        RETURN false;
    END IF;
    
    -- Email doğrulanmış VE aktif olmalı
    RETURN user_record.email_confirmed_at IS NOT NULL 
           AND user_record.is_active = true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 3. RLS POLICY GÜNCELLEMESİ
-- ==========================================

-- Kullanıcılar sadece aktif ve email doğrulanmış kullanıcıların verilerini görebilir
-- (Mevcut RLS policy'ler zaten var, burada sadece not olarak bırakıyoruz)

-- ==========================================
-- 4. ADMIN ONAY FONKSİYONU (Opsiyonel)
-- ==========================================

-- Admin kullanıcıları onaylayabilir
CREATE OR REPLACE FUNCTION public.approve_user(user_id_to_approve UUID, approved_by UUID)
RETURNS BOOLEAN AS $$
DECLARE
    is_admin BOOLEAN;
BEGIN
    -- Onaylayan kişinin admin olduğunu kontrol et
    SELECT EXISTS(
        SELECT 1 FROM public.user_roles
        WHERE user_id = approved_by AND role = 'super_admin'
    ) INTO is_admin;
    
    IF NOT is_admin THEN
        RAISE EXCEPTION 'Sadece admin kullanıcıları onaylayabilir';
    END IF;
    
    -- Kullanıcıyı aktif yap
    UPDATE public.users
    SET is_active = true, updated_at = NOW()
    WHERE id = user_id_to_approve;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
