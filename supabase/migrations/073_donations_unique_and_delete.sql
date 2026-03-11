-- =====================================================
-- 073: Donations - Unique constraint + Delete RLS
-- =====================================================
-- 1) Kullanıcı aynı yarış (event veya manuel) için birden fazla bağış oluşturamaz
-- 2) Kullanıcı kendi bağışını silebilir, admin tümünü silebilir

-- Etkinlik bazlı bağışlarda: bir kullanıcı, bir event için tek bağış
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_donations_unique_event
    ON public.user_donations(user_id, event_id)
    WHERE event_id IS NOT NULL;

-- Manuel girişlerde: bir kullanıcı, aynı yarış adı + tarih için tek bağış
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_donations_unique_manual
    ON public.user_donations(user_id, race_name, race_date)
    WHERE event_id IS NULL;

-- Kullanıcı kendi bağışını silebilir
CREATE POLICY "Users can delete own donations"
    ON public.user_donations FOR DELETE
    TO authenticated
    USING (user_id = auth.uid());

-- Admin tüm bağışları silebilir
CREATE POLICY "Admins can delete any donation"
    ON public.user_donations FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role = 'super_admin'
        )
    );
