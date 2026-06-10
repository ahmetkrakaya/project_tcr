-- =====================================================
-- 101: Donations - Admin update + delete politikaları
-- =====================================================
-- Admin (super_admin veya coach): zaman kısıtı olmadan
--   tüm bağışları güncelleyebilir ve silebilir.
-- Normal kullanıcı: yalnızca kendi bağışı, yarıştan
--   sonraki 5 gün içinde.

-- Sadece super_admin'i kapsayan eski silme politikasını kaldır
DROP POLICY IF EXISTS "Admins can delete any donation" ON public.user_donations;

-- Tüm admin ve coach'lar herhangi bir bağışı silebilir
CREATE POLICY "Admins can delete any donation"
    ON public.user_donations FOR DELETE
    TO authenticated
    USING (public.is_admin_or_coach());

-- Tüm admin ve coach'lar zaman kısıtı olmadan herhangi bir bağışı güncelleyebilir
CREATE POLICY "Admins can update any donation"
    ON public.user_donations FOR UPDATE
    TO authenticated
    USING (public.is_admin_or_coach())
    WITH CHECK (public.is_admin_or_coach() AND amount > 0);
