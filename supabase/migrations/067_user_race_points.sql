-- ============================================================
-- User Race Points System
-- Yarış etkinliklerine katılan kullanıcılara Strava verilerine
-- göre puan veren sistem. Günlük cron job ile otomatik hesaplama.
-- ============================================================

-- pg_cron extension (zaten aktif olmalı)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ============================================================
-- 1) user_race_points tablosu
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_race_points (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    activity_id UUID REFERENCES public.activities(id) ON DELETE SET NULL,
    distance_meters DECIMAL(10, 2) NOT NULL,
    points INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, event_id)
);

CREATE INDEX IF NOT EXISTS idx_user_race_points_user_id
    ON public.user_race_points(user_id);

CREATE INDEX IF NOT EXISTS idx_user_race_points_event_id
    ON public.user_race_points(event_id);

-- ============================================================
-- 2) RLS
-- ============================================================
ALTER TABLE public.user_race_points ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view race points"
    ON public.user_race_points
    FOR SELECT
    USING (true);

CREATE POLICY "Only backend can manage race points"
    ON public.user_race_points
    FOR ALL
    USING (current_user NOT IN ('anon', 'authenticated'))
    WITH CHECK (current_user NOT IN ('anon', 'authenticated'));

-- ============================================================
-- 3) Mesafeye göre puan hesaplama fonksiyonu
--    4000-7499m  → 5000 puan (5K)
--    7500-15999m → 10000 puan (10K)
--    16000-32999m → 21000 puan (Yarı Maraton)
--    33000m+     → 42000 puan (Maraton)
--    Dışında     → 0
-- ============================================================
CREATE OR REPLACE FUNCTION public.calculate_race_points(distance_m DECIMAL)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF distance_m >= 33000 THEN
        RETURN 42000;
    ELSIF distance_m >= 16000 THEN
        RETURN 21000;
    ELSIF distance_m >= 7500 THEN
        RETURN 10000;
    ELSIF distance_m >= 4000 THEN
        RETURN 5000;
    ELSE
        RETURN 0;
    END IF;
END;
$$;

-- ============================================================
-- 4) Günlük cron fonksiyonu: dünkü yarış etkinliklerini işle
-- ============================================================
CREATE OR REPLACE FUNCTION public.process_race_points()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    race_record RECORD;
    participant RECORD;
    strava_activity RECORD;
    calculated_points INTEGER;
    race_date DATE;
BEGIN
    race_date := CURRENT_DATE - INTERVAL '1 day';

    FOR race_record IN
        SELECT id, start_time
        FROM public.events
        WHERE event_type = 'race'
          AND (start_time AT TIME ZONE 'Europe/Istanbul')::date = race_date
    LOOP
        FOR participant IN
            SELECT ep.user_id
            FROM public.event_participants ep
            WHERE ep.event_id = race_record.id
              AND ep.status = 'going'
        LOOP
            SELECT a.id, a.distance_meters
            INTO strava_activity
            FROM public.activities a
            WHERE a.user_id = participant.user_id
              AND a.source = 'strava'
              AND a.activity_type = 'running'
              AND (a.start_time AT TIME ZONE 'Europe/Istanbul')::date = race_date
            ORDER BY a.distance_meters DESC
            LIMIT 1;

            IF strava_activity.id IS NOT NULL AND strava_activity.distance_meters IS NOT NULL THEN
                calculated_points := public.calculate_race_points(strava_activity.distance_meters);

                IF calculated_points > 0 THEN
                    INSERT INTO public.user_race_points (user_id, event_id, activity_id, distance_meters, points)
                    VALUES (
                        participant.user_id,
                        race_record.id,
                        strava_activity.id,
                        strava_activity.distance_meters,
                        calculated_points
                    )
                    ON CONFLICT (user_id, event_id) DO NOTHING;
                END IF;
            END IF;
        END LOOP;
    END LOOP;
END;
$$;

-- ============================================================
-- 5) Toplam puan RPC fonksiyonu
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_user_total_points(target_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    total INTEGER;
BEGIN
    SELECT COALESCE(SUM(points), 0)
    INTO total
    FROM public.user_race_points
    WHERE user_id = target_user_id;

    RETURN total;
END;
$$;

-- ============================================================
-- 6) Cron job: Her gün 06:00 UTC (Türkiye 09:00)
-- ============================================================
SELECT cron.schedule(
    'process-race-points',
    '0 6 * * *',
    'SELECT public.process_race_points()'
);
