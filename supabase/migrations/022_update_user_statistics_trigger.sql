-- TCR Migration 022: Update User Statistics Trigger
-- İstatistik trigger'ını güncelle ve yeniden hesaplama fonksiyonu ekle

-- Güncellenmiş trigger fonksiyonu (this_week_distance ve this_month_distance dahil)
CREATE OR REPLACE FUNCTION public.update_user_statistics()
RETURNS TRIGGER AS $$
DECLARE
    week_start DATE;
    month_start DATE;
BEGIN
    -- Hafta ve ay başlangıçlarını hesapla
    week_start := date_trunc('week', CURRENT_DATE)::DATE;
    month_start := date_trunc('month', CURRENT_DATE)::DATE;
    
    -- Kullanıcı istatistiklerini güncelle veya oluştur
    INSERT INTO public.user_statistics (
        user_id, 
        total_distance_meters, 
        total_duration_seconds, 
        total_activities, 
        total_elevation_gain, 
        last_activity_at,
        this_week_distance,
        this_month_distance
    )
    VALUES (
        NEW.user_id,
        COALESCE(NEW.distance_meters, 0),
        COALESCE(NEW.duration_seconds, 0),
        1,
        COALESCE(NEW.elevation_gain, 0),
        NEW.start_time,
        CASE WHEN NEW.start_time >= week_start THEN COALESCE(NEW.distance_meters, 0) ELSE 0 END,
        CASE WHEN NEW.start_time >= month_start THEN COALESCE(NEW.distance_meters, 0) ELSE 0 END
    )
    ON CONFLICT (user_id) DO UPDATE SET
        total_distance_meters = user_statistics.total_distance_meters + COALESCE(NEW.distance_meters, 0),
        total_duration_seconds = user_statistics.total_duration_seconds + COALESCE(NEW.duration_seconds, 0),
        total_activities = user_statistics.total_activities + 1,
        total_elevation_gain = user_statistics.total_elevation_gain + COALESCE(NEW.elevation_gain, 0),
        last_activity_at = GREATEST(user_statistics.last_activity_at, NEW.start_time),
        longest_run_meters = GREATEST(
            user_statistics.longest_run_meters, 
            CASE WHEN NEW.activity_type = 'running' THEN COALESCE(NEW.distance_meters, 0) ELSE user_statistics.longest_run_meters END
        ),
        this_week_distance = user_statistics.this_week_distance + 
            CASE WHEN NEW.start_time >= week_start THEN COALESCE(NEW.distance_meters, 0) ELSE 0 END,
        this_month_distance = user_statistics.this_month_distance + 
            CASE WHEN NEW.start_time >= month_start THEN COALESCE(NEW.distance_meters, 0) ELSE 0 END,
        updated_at = NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Tüm aktivitelerden istatistikleri yeniden hesaplayan fonksiyon
CREATE OR REPLACE FUNCTION public.recalculate_user_statistics(check_user_id UUID)
RETURNS VOID AS $$
DECLARE
    week_start DATE;
    month_start DATE;
    stats RECORD;
BEGIN
    week_start := date_trunc('week', CURRENT_DATE)::DATE;
    month_start := date_trunc('month', CURRENT_DATE)::DATE;
    
    -- Tüm aktivitelerden istatistikleri hesapla
    SELECT 
        COALESCE(SUM(COALESCE(distance_meters, 0)), 0) as total_distance,
        COALESCE(SUM(COALESCE(duration_seconds, 0)), 0) as total_duration,
        COUNT(*) as total_count,
        COALESCE(SUM(COALESCE(elevation_gain, 0)), 0) as total_elevation,
        COALESCE(MAX(CASE WHEN activity_type = 'running' THEN distance_meters ELSE 0 END), 0) as longest_run,
        MAX(start_time) as last_activity,
        COALESCE(SUM(CASE WHEN start_time >= week_start THEN COALESCE(distance_meters, 0) ELSE 0 END), 0) as week_distance,
        COALESCE(SUM(CASE WHEN start_time >= month_start THEN COALESCE(distance_meters, 0) ELSE 0 END), 0) as month_distance
    INTO stats
    FROM public.activities
    WHERE user_id = check_user_id;
    
    -- İstatistikleri güncelle veya oluştur
    INSERT INTO public.user_statistics (
        user_id,
        total_distance_meters,
        total_duration_seconds,
        total_activities,
        total_elevation_gain,
        longest_run_meters,
        last_activity_at,
        this_week_distance,
        this_month_distance,
        updated_at
    )
    VALUES (
        check_user_id,
        stats.total_distance,
        stats.total_duration,
        stats.total_count,
        stats.total_elevation,
        stats.longest_run,
        stats.last_activity,
        stats.week_distance,
        stats.month_distance,
        NOW()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        total_distance_meters = stats.total_distance,
        total_duration_seconds = stats.total_duration,
        total_activities = stats.total_count,
        total_elevation_gain = stats.total_elevation,
        longest_run_meters = stats.longest_run,
        last_activity_at = stats.last_activity,
        this_week_distance = stats.week_distance,
        this_month_distance = stats.month_distance,
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Mevcut tüm kullanıcılar için istatistikleri yeniden hesapla
DO $$
DECLARE
    user_record RECORD;
BEGIN
    FOR user_record IN SELECT id FROM public.users LOOP
        PERFORM public.recalculate_user_statistics(user_record.id);
    END LOOP;
END $$;
