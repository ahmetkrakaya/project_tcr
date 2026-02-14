-- =====================================================
-- 058: Remove current_version from app_versions
-- =====================================================
-- current_version kolonu artık kullanılmıyor, sadece minimum_version üzerinden kontrol yapılıyor.

ALTER TABLE public.app_versions
  DROP COLUMN IF EXISTS current_version;

