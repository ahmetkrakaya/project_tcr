-- =====================================================
-- 070: Club Races - URL kaldır, konum koordinatları ekle
-- =====================================================
-- url kolonu kaldırılır, location_lat ve location_lng eklenir.
-- location TEXT kolonu konum adı olarak kalır.

ALTER TABLE public.club_races DROP COLUMN IF EXISTS url;

ALTER TABLE public.club_races
    ADD COLUMN IF NOT EXISTS location_lat DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS location_lng DOUBLE PRECISION;
