-- =====================================================
-- 123: Monthly program track lane (pist kulvarı)
-- Koçun hazırladığı referans kulvar; sporcu uygulamada değiştirebilir.
-- =====================================================

ALTER TABLE public.monthly_program_entries
ADD COLUMN IF NOT EXISTS track_lane INTEGER DEFAULT NULL;

ALTER TABLE public.monthly_program_entries
DROP CONSTRAINT IF EXISTS monthly_program_entries_track_lane_chk;

ALTER TABLE public.monthly_program_entries
ADD CONSTRAINT monthly_program_entries_track_lane_chk
  CHECK (track_lane IS NULL OR (track_lane >= 1 AND track_lane <= 8));

COMMENT ON COLUMN public.monthly_program_entries.track_lane IS
  'Pist antrenmanı referans kulvarı (1-8). NULL = pist dışı. Sporcu görünümünde kulvar değişince pace/süre dönüşümü bu kulvara göre yapılır.';
