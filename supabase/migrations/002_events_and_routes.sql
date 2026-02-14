-- TCR Migration 002: Events and Routes
-- Etkinlik yönetimi ve GPX rotaları

-- Enum for event types
CREATE TYPE event_type AS ENUM ('training', 'race', 'social', 'workshop', 'other');

-- Enum for event status
CREATE TYPE event_status AS ENUM ('draft', 'published', 'cancelled', 'completed');

-- Enum for RSVP status
CREATE TYPE rsvp_status AS ENUM ('going', 'not_going', 'maybe');

-- Training groups (Antrenman grupları)
CREATE TABLE public.training_groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    target_distance TEXT, -- Örn: "10K", "21K", "42K"
    difficulty_level INTEGER DEFAULT 1 CHECK (difficulty_level BETWEEN 1 AND 5),
    color TEXT DEFAULT '#3B82F6', -- UI rengi
    icon TEXT DEFAULT 'running',
    is_active BOOLEAN DEFAULT true,
    created_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Group members (Grup üyelikleri)
CREATE TABLE public.group_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id UUID NOT NULL REFERENCES public.training_groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(group_id, user_id)
);

-- Routes (GPX rotaları)
CREATE TABLE public.routes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    gpx_data TEXT, -- Raw GPX XML string
    gpx_file_url TEXT, -- Supabase Storage URL
    total_distance DECIMAL(10, 2), -- Kilometre cinsinden
    elevation_gain DECIMAL(10, 2), -- Metre cinsinden
    elevation_loss DECIMAL(10, 2),
    max_elevation DECIMAL(10, 2),
    min_elevation DECIMAL(10, 2),
    elevation_profile JSONB, -- [{distance: 0, elevation: 100}, ...]
    start_location JSONB, -- {lat: 41.0082, lng: 28.9784, name: "Kadıköy"}
    end_location JSONB,
    terrain_type TEXT, -- "asphalt", "trail", "mixed"
    difficulty_level INTEGER DEFAULT 1 CHECK (difficulty_level BETWEEN 1 AND 5),
    thumbnail_url TEXT,
    created_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Events (Etkinlikler)
CREATE TABLE public.events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    description TEXT,
    event_type event_type DEFAULT 'training',
    status event_status DEFAULT 'draft',
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    location_name TEXT,
    location_address TEXT,
    location_lat DECIMAL(10, 8),
    location_lng DECIMAL(11, 8),
    route_id UUID REFERENCES public.routes(id),
    training_group_id UUID REFERENCES public.training_groups(id),
    max_participants INTEGER,
    weather_api_data JSONB, -- API'den gelen ham veri
    weather_note TEXT, -- Admin override notu
    coach_notes TEXT, -- Antrenör notları
    is_recurring BOOLEAN DEFAULT false,
    recurrence_rule TEXT, -- iCal RRULE format
    parent_event_id UUID REFERENCES public.events(id), -- Recurring event parent
    created_by UUID NOT NULL REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Event participants (RSVP)
CREATE TABLE public.event_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    status rsvp_status NOT NULL DEFAULT 'going',
    note TEXT,
    responded_at TIMESTAMPTZ DEFAULT NOW(),
    checked_in BOOLEAN DEFAULT false,
    checked_in_at TIMESTAMPTZ,
    UNIQUE(event_id, user_id)
);

-- Training schedules (Haftalık antrenman programı)
CREATE TABLE public.training_schedules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    training_group_id UUID NOT NULL REFERENCES public.training_groups(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    day_of_week INTEGER CHECK (day_of_week BETWEEN 0 AND 6), -- 0 = Pazar
    start_time TIME NOT NULL,
    duration_minutes INTEGER DEFAULT 60,
    default_location_name TEXT,
    default_route_id UUID REFERENCES public.routes(id),
    is_active BOOLEAN DEFAULT true,
    created_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Pickup locations (Buluşma noktaları - Carpooling için)
CREATE TABLE public.pickup_locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL, -- "Teraspark", "Çınar", etc.
    address TEXT,
    lat DECIMAL(10, 8),
    lng DECIMAL(11, 8),
    is_active BOOLEAN DEFAULT true,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Triggers for updated_at
CREATE TRIGGER update_training_groups_updated_at
    BEFORE UPDATE ON public.training_groups
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_routes_updated_at
    BEFORE UPDATE ON public.routes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_events_updated_at
    BEFORE UPDATE ON public.events
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_training_schedules_updated_at
    BEFORE UPDATE ON public.training_schedules
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Indexes
CREATE INDEX idx_events_start_time ON public.events(start_time);
CREATE INDEX idx_events_status ON public.events(status);
CREATE INDEX idx_events_event_type ON public.events(event_type);
CREATE INDEX idx_events_training_group_id ON public.events(training_group_id);
CREATE INDEX idx_events_created_by ON public.events(created_by);
CREATE INDEX idx_event_participants_event_id ON public.event_participants(event_id);
CREATE INDEX idx_event_participants_user_id ON public.event_participants(user_id);
CREATE INDEX idx_event_participants_status ON public.event_participants(status);
CREATE INDEX idx_group_members_group_id ON public.group_members(group_id);
CREATE INDEX idx_group_members_user_id ON public.group_members(user_id);
CREATE INDEX idx_routes_created_by ON public.routes(created_by);
CREATE INDEX idx_training_schedules_group_id ON public.training_schedules(training_group_id);

-- Function to get participant count for an event
CREATE OR REPLACE FUNCTION public.get_event_participant_count(event_uuid UUID)
RETURNS INTEGER AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM public.event_participants
        WHERE event_id = event_uuid AND status = 'going'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if user is participant of an event
CREATE OR REPLACE FUNCTION public.is_event_participant(event_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS(
        SELECT 1 FROM public.event_participants
        WHERE event_id = event_uuid AND user_id = user_uuid AND status = 'going'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Insert default pickup locations
INSERT INTO public.pickup_locations (name, sort_order) VALUES
    ('Teraspark', 1),
    ('Çınar', 2),
    ('Forum Çamlık', 3),
    ('Çamlık', 4),
    ('Sümer', 5),
    ('Otogar', 6),
    ('KYK', 7),
    ('Amfipark', 8);
