-- =====================================================
-- 074: Donations - Allow zero amount on insert
-- =====================================================
-- amount kolonu için CHECK constraint güncellenir:
--  - 0'dan küçük olamaz (negatif yasak)
--  - 0 değeri geçerli (henüz bağış toplanmamış olabilir)

ALTER TABLE public.user_donations
    DROP CONSTRAINT IF EXISTS user_donations_amount_check;

ALTER TABLE public.user_donations
    ADD CONSTRAINT user_donations_amount_check
    CHECK (amount >= 0);
