-- =====================================================
-- 072: Fix user_donations FK - auth.users -> public.users
-- =====================================================
-- PostgREST auth şemasındaki FK'leri takip edemez.
-- user_id FK'sini public.users'a yönlendiriyoruz.

ALTER TABLE public.user_donations
    DROP CONSTRAINT IF EXISTS user_donations_user_id_fkey;

ALTER TABLE public.user_donations
    ADD CONSTRAINT user_donations_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
