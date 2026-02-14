-- TCR Migration 023: Update Activity Feed Function
-- Feed fonksiyonunu güncelle - yeni detayları (kalori, kalp atışı, best pace vb.) dahil et

-- Önce eski fonksiyonu sil (return type değiştiği için)
DROP FUNCTION IF EXISTS public.get_activity_feed(integer, integer);

-- Function to get TCR Feed (güncellenmiş versiyon)
CREATE FUNCTION public.get_activity_feed(
    page_size INTEGER DEFAULT 20,
    page_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    activity_id UUID,
    user_id UUID,
    user_name TEXT,
    avatar_url TEXT,
    activity_type activity_type,
    source activity_source,
    title TEXT,
    distance_meters DECIMAL,
    duration_seconds INTEGER,
    pace_seconds INTEGER,
    best_pace_seconds INTEGER,
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    calories_burned INTEGER,
    average_heart_rate INTEGER,
    max_heart_rate INTEGER,
    elevation_gain DECIMAL,
    average_cadence INTEGER,
    feeling_rating INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.id,
        u.id,
        CONCAT(u.first_name, ' ', u.last_name),
        u.avatar_url,
        a.activity_type,
        a.source,
        a.title,
        a.distance_meters,
        a.duration_seconds,
        a.average_pace_seconds,
        a.best_pace_seconds,
        a.start_time,
        a.end_time,
        a.calories_burned,
        a.average_heart_rate,
        a.max_heart_rate,
        a.elevation_gain,
        a.average_cadence,
        a.feeling_rating
    FROM public.activities a
    JOIN public.users u ON u.id = a.user_id
    WHERE a.is_public = true
    ORDER BY a.start_time DESC
    LIMIT page_size
    OFFSET page_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
