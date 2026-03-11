-- =====================================================
-- 075: Donations - Insert can be 0, update must be > 0
-- =====================================================
-- Amaç:
-- - İlk kayıt (INSERT): amount 0 olabilir, negatif olamaz
-- - Güncelleme (UPDATE): amount 0 olamaz ( > 0 olmalı )
--
-- Not: Önceki migration'larda inline CHECK yüzünden constraint adı farklı kalmış olabilir.
-- Bu yüzden amount ile ilgili CHECK constraint'lerini dinamik olarak bulup kaldırıyoruz.

DO $$
DECLARE
  c RECORD;
BEGIN
  FOR c IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.user_donations'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%amount%'
  LOOP
    EXECUTE format('ALTER TABLE public.user_donations DROP CONSTRAINT IF EXISTS %I', c.conname);
  END LOOP;
END $$;

-- INSERT için 0 kabul, negatif yasak
ALTER TABLE public.user_donations
  ADD CONSTRAINT user_donations_amount_non_negative_check
  CHECK (amount >= 0);

-- UPDATE policy: amount mutlaka > 0 olmalı (0 update edilemesin)
DROP POLICY IF EXISTS "Users can update own donations within 5 days after race" ON public.user_donations;

CREATE POLICY "Users can update own donations within 5 days after race"
    ON public.user_donations FOR UPDATE
    TO authenticated
    USING (
        user_id = auth.uid()
        AND (
            CASE
                WHEN event_id IS NOT NULL THEN
                    (SELECT (e.start_time::date + INTERVAL '5 days') >= CURRENT_DATE
                     FROM public.events e WHERE e.id = event_id)
                ELSE
                    (race_date + INTERVAL '5 days') >= CURRENT_DATE
            END
        )
    )
    WITH CHECK (
        user_id = auth.uid()
        AND amount > 0
    );

