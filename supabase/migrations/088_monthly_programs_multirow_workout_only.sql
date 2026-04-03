-- =====================================================
-- 088: Monthly programs revision
-- - Çoklu satır/gün desteği
-- - Sadece antrenman odaklı veri modeli
-- =====================================================

-- 087'deki tek-gün unique kuralını kaldır
ALTER TABLE public.monthly_program_entries
DROP CONSTRAINT IF EXISTS monthly_program_entries_one_row_per_day_uk;

-- scope_type tutarlılık kuralını revize et:
-- group  -> training_group_id zorunlu, user_id boş
-- member -> training_group_id + user_id zorunlu
ALTER TABLE public.monthly_program_entries
DROP CONSTRAINT IF EXISTS monthly_program_entries_scope_consistency_chk;

ALTER TABLE public.monthly_program_entries
ADD CONSTRAINT monthly_program_entries_scope_consistency_chk
CHECK (
  (scope_type = 'group' AND training_group_id IS NOT NULL AND user_id IS NULL)
  OR
  (scope_type = 'member' AND training_group_id IS NOT NULL AND user_id IS NOT NULL)
);

-- Etkinlik meta alanları bu tabloda kullanılmayacak (sadece antrenman yapısı saklanacak)
ALTER TABLE public.monthly_program_entries
DROP COLUMN IF EXISTS route_id,
DROP COLUMN IF EXISTS start_time,
DROP COLUMN IF EXISTS location_name,
DROP COLUMN IF EXISTS location_address,
DROP COLUMN IF EXISTS coach_notes;

-- duration_minutes artık segment içinde (workout_definition) temsil ediliyor.
ALTER TABLE public.monthly_program_entries
DROP COLUMN IF EXISTS duration_minutes;

-- workout_definition zorunlu, text ise özet amaçlı opsiyonel kalsın
ALTER TABLE public.monthly_program_entries
ALTER COLUMN workout_definition SET NOT NULL;

-- Aynı gün + aynı hedef kombinasyonu tekil olsun
DROP INDEX IF EXISTS idx_monthly_program_entries_unique_target_per_day;
CREATE UNIQUE INDEX idx_monthly_program_entries_unique_target_per_day
  ON public.monthly_program_entries (
    plan_date,
    scope_type,
    COALESCE(training_group_id, '00000000-0000-0000-0000-000000000000'::uuid),
    COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );
