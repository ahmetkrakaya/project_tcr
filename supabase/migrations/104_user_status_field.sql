-- Migration 104: users tablosuna user_status alanı ekle
-- 'pending' | 'active' | 'rejected' | 'banned'
-- is_active alanı geriye uyumluluk için korunuyor

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS user_status TEXT
    CHECK (user_status IN ('pending', 'active', 'rejected', 'banned'))
    NOT NULL DEFAULT 'pending';

-- Mevcut kayıtları güncelle
UPDATE public.users SET user_status = 'active'  WHERE is_active = true;
UPDATE public.users SET user_status = 'pending' WHERE is_active = false;

-- approve_user: is_active + user_status birlikte güncelle
CREATE OR REPLACE FUNCTION public.approve_user(user_id_to_approve UUID, approved_by UUID)
RETURNS BOOLEAN AS $$
DECLARE
  is_approver_admin BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = approved_by AND role = 'super_admin'
  ) INTO is_approver_admin;

  IF NOT is_approver_admin THEN
    RAISE EXCEPTION 'Sadece adminler kullanıcı onaylayabilir';
  END IF;

  UPDATE public.users
  SET is_active = true, user_status = 'active', updated_at = NOW()
  WHERE id = user_id_to_approve;

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- deactivate_user → ban (is_active=false, user_status='banned')
CREATE OR REPLACE FUNCTION public.deactivate_user(user_id_to_deactivate UUID, deactivated_by UUID)
RETURNS BOOLEAN AS $$
DECLARE
  is_approver_admin BOOLEAN;
  target_is_super_admin BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = deactivated_by AND role = 'super_admin'
  ) INTO is_approver_admin;

  IF NOT is_approver_admin THEN
    RAISE EXCEPTION 'Sadece adminler kullanıcı banlayabilir';
  END IF;

  IF user_id_to_deactivate = deactivated_by THEN
    RAISE EXCEPTION 'Kendinizi banlayamazsınız';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = user_id_to_deactivate AND role = 'super_admin'
  ) INTO target_is_super_admin;

  IF target_is_super_admin THEN
    RAISE EXCEPTION 'Admin kullanıcı banlanamaz';
  END IF;

  UPDATE public.users
  SET is_active = false, user_status = 'banned', updated_at = NOW()
  WHERE id = user_id_to_deactivate;

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- reject_user: onay bekleyen bir kullanıcıyı reddet
CREATE OR REPLACE FUNCTION public.reject_user(user_id_to_reject UUID, rejected_by UUID)
RETURNS BOOLEAN AS $$
DECLARE
  is_approver_admin BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = rejected_by AND role = 'super_admin'
  ) INTO is_approver_admin;

  IF NOT is_approver_admin THEN
    RAISE EXCEPTION 'Sadece adminler kullanıcı reddedebilir';
  END IF;

  UPDATE public.users
  SET is_active = false, user_status = 'rejected', updated_at = NOW()
  WHERE id = user_id_to_reject;

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- reactivate_user: banlanan/reddedilen kullanıcıyı tekrar aktif yap
CREATE OR REPLACE FUNCTION public.reactivate_user(user_id_to_reactivate UUID, reactivated_by UUID)
RETURNS BOOLEAN AS $$
DECLARE
  is_approver_admin BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = reactivated_by AND role = 'super_admin'
  ) INTO is_approver_admin;

  IF NOT is_approver_admin THEN
    RAISE EXCEPTION 'Sadece adminler kullanıcı yeniden aktif yapabilir';
  END IF;

  UPDATE public.users
  SET is_active = true, user_status = 'active', updated_at = NOW()
  WHERE id = user_id_to_reactivate;

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
