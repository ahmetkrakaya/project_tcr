-- TCR Migration 021: User Integrations (Strava, Garmin vb.)
-- Harici servis entegrasyonları için token ve bağlantı yönetimi

-- User integrations table
CREATE TABLE public.user_integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL, -- 'strava', 'garmin', etc.
    provider_user_id TEXT, -- Harici servisteki kullanıcı ID'si
    access_token TEXT NOT NULL,
    refresh_token TEXT,
    token_expires_at TIMESTAMPTZ,
    scopes TEXT[], -- İzin verilen scope'lar
    athlete_data JSONB, -- Profil bilgileri (isim, avatar vb.)
    connected_at TIMESTAMPTZ DEFAULT NOW(),
    last_sync_at TIMESTAMPTZ,
    sync_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, provider)
);

-- Indexes
CREATE INDEX idx_user_integrations_user_id ON public.user_integrations(user_id);
CREATE INDEX idx_user_integrations_provider ON public.user_integrations(provider);
CREATE INDEX idx_user_integrations_provider_user_id ON public.user_integrations(provider_user_id);

-- Updated at trigger
CREATE TRIGGER update_user_integrations_updated_at
    BEFORE UPDATE ON public.user_integrations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- RLS Policies
ALTER TABLE public.user_integrations ENABLE ROW LEVEL SECURITY;

-- Kullanıcılar sadece kendi entegrasyonlarını görebilir
CREATE POLICY "Users can view own integrations"
    ON public.user_integrations FOR SELECT
    USING (auth.uid() = user_id);

-- Kullanıcılar kendi entegrasyonlarını ekleyebilir
CREATE POLICY "Users can insert own integrations"
    ON public.user_integrations FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Kullanıcılar kendi entegrasyonlarını güncelleyebilir
CREATE POLICY "Users can update own integrations"
    ON public.user_integrations FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Kullanıcılar kendi entegrasyonlarını silebilir
CREATE POLICY "Users can delete own integrations"
    ON public.user_integrations FOR DELETE
    USING (auth.uid() = user_id);

-- Function to check if user has connected a specific provider
CREATE OR REPLACE FUNCTION public.has_integration(check_user_id UUID, check_provider TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS(
        SELECT 1 FROM public.user_integrations
        WHERE user_id = check_user_id 
        AND provider = check_provider
        AND sync_enabled = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get user's Strava integration
CREATE OR REPLACE FUNCTION public.get_strava_integration(check_user_id UUID)
RETURNS TABLE (
    id UUID,
    provider_user_id TEXT,
    athlete_data JSONB,
    connected_at TIMESTAMPTZ,
    last_sync_at TIMESTAMPTZ,
    sync_enabled BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ui.id,
        ui.provider_user_id,
        ui.athlete_data,
        ui.connected_at,
        ui.last_sync_at,
        ui.sync_enabled
    FROM public.user_integrations ui
    WHERE ui.user_id = check_user_id 
    AND ui.provider = 'strava';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add external_id index to activities table for faster duplicate checking
CREATE INDEX IF NOT EXISTS idx_activities_external_id ON public.activities(external_id) WHERE external_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_activities_source ON public.activities(source);

-- Unique constraint for external activities to prevent duplicates
-- Önce index oluştur
CREATE UNIQUE INDEX IF NOT EXISTS idx_activities_unique_external 
    ON public.activities(user_id, source, external_id) 
    WHERE external_id IS NOT NULL;

-- Unique constraint ekle (Supabase upsert için gerekli)
-- Not: PostgreSQL'de partial unique index constraint olarak kullanılamaz
-- Bu yüzden manuel kontrol yapıyoruz, ama index performans için var
