-- TCR Migration 005: Activities (Antrenman Verileri)
-- Health Connect / HealthKit entegrasyonu ve aktivite takibi

-- Enum for activity types
CREATE TYPE activity_type AS ENUM ('running', 'walking', 'cycling', 'swimming', 'strength', 'yoga', 'other');

-- Enum for activity source
CREATE TYPE activity_source AS ENUM ('manual', 'health_connect', 'healthkit', 'strava', 'garmin', 'apple_watch', 'other');

-- Activities (Koşu/Antrenman kayıtları)
CREATE TABLE public.activities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    activity_type activity_type NOT NULL DEFAULT 'running',
    source activity_source NOT NULL DEFAULT 'manual',
    external_id TEXT, -- Dış kaynak ID'si (Strava activity ID vb.)
    title TEXT,
    description TEXT,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    duration_seconds INTEGER, -- Saniye cinsinden süre
    distance_meters DECIMAL(10, 2), -- Metre cinsinden mesafe
    elevation_gain DECIMAL(10, 2), -- Metre
    calories_burned INTEGER,
    average_pace_seconds INTEGER, -- Ortalama pace (saniye/km)
    best_pace_seconds INTEGER, -- En iyi pace
    average_heart_rate INTEGER,
    max_heart_rate INTEGER,
    average_cadence INTEGER, -- Adım/dakika
    route_polyline TEXT, -- Encoded polyline for map display
    weather_conditions JSONB, -- {temp: 20, humidity: 60, wind: 10}
    feeling_rating INTEGER CHECK (feeling_rating BETWEEN 1 AND 5), -- Nasıl hissettin
    notes TEXT,
    is_public BOOLEAN DEFAULT true, -- TCR Feed'de görünsün mü
    event_id UUID REFERENCES public.events(id), -- Etkinlik bağlantısı
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Activity splits (Kilometre bazlı bölümler)
CREATE TABLE public.activity_splits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    activity_id UUID NOT NULL REFERENCES public.activities(id) ON DELETE CASCADE,
    split_number INTEGER NOT NULL,
    distance_meters DECIMAL(10, 2),
    duration_seconds INTEGER,
    pace_seconds INTEGER, -- saniye/km
    elevation_change DECIMAL(10, 2),
    average_heart_rate INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User statistics (Kullanıcı istatistikleri - Cache)
CREATE TABLE public.user_statistics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
    total_distance_meters DECIMAL(12, 2) DEFAULT 0,
    total_duration_seconds BIGINT DEFAULT 0,
    total_activities INTEGER DEFAULT 0,
    total_elevation_gain DECIMAL(10, 2) DEFAULT 0,
    longest_run_meters DECIMAL(10, 2) DEFAULT 0,
    best_5k_seconds INTEGER,
    best_10k_seconds INTEGER,
    best_half_marathon_seconds INTEGER,
    best_marathon_seconds INTEGER,
    current_streak_days INTEGER DEFAULT 0,
    longest_streak_days INTEGER DEFAULT 0,
    last_activity_at TIMESTAMPTZ,
    this_week_distance DECIMAL(10, 2) DEFAULT 0,
    this_month_distance DECIMAL(10, 2) DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Leaderboard entries (Haftalık/Aylık lider tablosu)
CREATE TABLE public.leaderboard_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    period_type TEXT NOT NULL, -- 'weekly' veya 'monthly'
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    total_distance_meters DECIMAL(10, 2) DEFAULT 0,
    total_duration_seconds INTEGER DEFAULT 0,
    activity_count INTEGER DEFAULT 0,
    rank INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, period_type, period_start)
);

-- Function to update user statistics after new activity
CREATE OR REPLACE FUNCTION public.update_user_statistics()
RETURNS TRIGGER AS $$
BEGIN
    -- Kullanıcı istatistiklerini güncelle veya oluştur
    INSERT INTO public.user_statistics (user_id, total_distance_meters, total_duration_seconds, total_activities, total_elevation_gain, last_activity_at)
    VALUES (
        NEW.user_id,
        COALESCE(NEW.distance_meters, 0),
        COALESCE(NEW.duration_seconds, 0),
        1,
        COALESCE(NEW.elevation_gain, 0),
        NEW.start_time
    )
    ON CONFLICT (user_id) DO UPDATE SET
        total_distance_meters = user_statistics.total_distance_meters + COALESCE(NEW.distance_meters, 0),
        total_duration_seconds = user_statistics.total_duration_seconds + COALESCE(NEW.duration_seconds, 0),
        total_activities = user_statistics.total_activities + 1,
        total_elevation_gain = user_statistics.total_elevation_gain + COALESCE(NEW.elevation_gain, 0),
        last_activity_at = GREATEST(user_statistics.last_activity_at, NEW.start_time),
        longest_run_meters = GREATEST(user_statistics.longest_run_meters, COALESCE(NEW.distance_meters, 0)),
        updated_at = NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_activity_created
    AFTER INSERT ON public.activities
    FOR EACH ROW EXECUTE FUNCTION public.update_user_statistics();

-- Function to get weekly leaderboard
CREATE OR REPLACE FUNCTION public.get_weekly_leaderboard(week_start DATE DEFAULT date_trunc('week', CURRENT_DATE)::DATE)
RETURNS TABLE (
    rank BIGINT,
    user_id UUID,
    user_name TEXT,
    avatar_url TEXT,
    total_distance DECIMAL,
    activity_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ROW_NUMBER() OVER (ORDER BY SUM(a.distance_meters) DESC),
        u.id,
        CONCAT(u.first_name, ' ', u.last_name),
        u.avatar_url,
        SUM(a.distance_meters),
        COUNT(a.id)
    FROM public.users u
    JOIN public.activities a ON a.user_id = u.id
    WHERE a.start_time >= week_start
      AND a.start_time < week_start + INTERVAL '7 days'
      AND a.is_public = true
      AND a.activity_type = 'running'
    GROUP BY u.id, u.first_name, u.last_name, u.avatar_url
    ORDER BY SUM(a.distance_meters) DESC
    LIMIT 50;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get TCR Feed
CREATE OR REPLACE FUNCTION public.get_activity_feed(
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

-- Triggers
CREATE TRIGGER update_activities_updated_at
    BEFORE UPDATE ON public.activities
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Indexes
CREATE INDEX idx_activities_user_id ON public.activities(user_id);
CREATE INDEX idx_activities_start_time ON public.activities(start_time DESC);
CREATE INDEX idx_activities_activity_type ON public.activities(activity_type);
CREATE INDEX idx_activities_is_public ON public.activities(is_public);
CREATE INDEX idx_activities_event_id ON public.activities(event_id);
CREATE INDEX idx_activity_splits_activity_id ON public.activity_splits(activity_id);
CREATE INDEX idx_user_statistics_user_id ON public.user_statistics(user_id);
CREATE INDEX idx_leaderboard_period ON public.leaderboard_entries(period_type, period_start);
