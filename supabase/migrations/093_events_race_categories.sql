-- 093: Race categories per event & participant
-- - events.race_variant_labels: JSONB/text[] (ör. ["5K","10K","21K","42K"])
-- - event_participants.race_variant_label: kullanıcının seçtiği kategori etiketi
-- - event_results.race_variant_label: sonucun ait olduğu kategori etiketi
-- - get_event_results: kategori bilgisini de döndürür

-- 1) Yeni kolonlar

ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS race_variant_labels JSONB;

ALTER TABLE public.event_participants
ADD COLUMN IF NOT EXISTS race_variant_label TEXT;

ALTER TABLE public.event_results
ADD COLUMN IF NOT EXISTS race_variant_label TEXT;

CREATE INDEX IF NOT EXISTS idx_event_results_event_id_race_variant
  ON public.event_results(event_id, race_variant_label);

-- 2) get_event_results fonksiyonunu kategori alanı ile güncelle
-- Not: 046_add_guest_results_support.sql içindeki sürümün üzerine yazıyoruz.
--
-- Postgres notu:
-- RETURNS TABLE şeması değiştiği için CREATE OR REPLACE tek başına yetmez.
-- Önce fonksiyonu drop edip yeniden oluşturuyoruz.

DROP FUNCTION IF EXISTS public.get_event_results(UUID);

CREATE OR REPLACE FUNCTION public.get_event_results(event_uuid UUID)
RETURNS TABLE (
    result_id UUID,
    event_id UUID,
    user_id UUID,
    full_name TEXT,
    avatar_url TEXT,
    gender TEXT,
    finish_time_seconds INTEGER,
    rank_overall INTEGER,
    rank_gender INTEGER,
    notes TEXT,
    race_variant_label TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        er.id AS result_id,
        er.event_id,
        er.user_id,
        -- Guest kaydıysa guest_name'i göster, değilse kullanıcı adını
        COALESCE(er.guest_name, COALESCE(u.first_name || ' ' || u.last_name, u.email)) AS full_name,
        -- Guest kaydıysa avatar yok
        CASE WHEN er.guest_name IS NOT NULL THEN NULL ELSE u.avatar_url END AS avatar_url,
        -- Guest kaydıysa guest_gender'i göster, değilse er.gender veya u.gender
        COALESCE(er.guest_gender, er.gender, u.gender) AS gender,
        er.finish_time_seconds,
        er.rank_overall,
        er.rank_gender,
        er.notes,
        er.race_variant_label
    FROM public.event_results er
    LEFT JOIN public.users u ON u.id = er.user_id
    WHERE er.event_id = event_uuid
    ORDER BY 
        er.finish_time_seconds NULLS LAST,
        er.rank_overall NULLS LAST;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

