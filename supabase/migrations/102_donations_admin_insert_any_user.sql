-- =====================================================
-- 102: Donations - Admin başkası adına bağış ekleyebilsin
-- =====================================================
-- Sadece super_admin, herhangi bir user_id ile bağış kaydı oluşturabilir.
-- Normal kullanıcılar yalnızca kendi user_id'leriyle ekleyebilir (değişiklik yok).

-- Admin INSERT politikası ekle
CREATE POLICY "Admins can insert donation for any user"
    ON public.user_donations FOR INSERT
    TO authenticated
    WITH CHECK (public.has_role(auth.uid(), 'super_admin'));
