-- =====================================================
-- 098: event-banners bucket HEIC/HEIF mime types
-- =====================================================
-- iOS ImagePicker çoğu zaman HEIC/HEIF döndürür. Bucket allowed_mime_types
-- kısıtlıysa upload başarısız olur.

BEGIN;

UPDATE storage.buckets
SET allowed_mime_types = ARRAY[
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/heic',
  'image/heif'
]
WHERE id = 'event-banners';

COMMIT;

