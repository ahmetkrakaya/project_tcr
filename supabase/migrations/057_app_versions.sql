-- =====================================================
-- 057: App Versions - Zorunlu Güncelleme Sistemi
-- =====================================================
-- Uygulama versiyonlarını ve zorunlu güncelleme bilgilerini yönetmek için tablo

CREATE TABLE public.app_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  minimum_version TEXT NOT NULL,
  current_version TEXT NOT NULL,
  is_force_update BOOLEAN NOT NULL DEFAULT false,
  message TEXT,
  app_store_url TEXT,
  play_store_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(platform)
);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_app_versions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER app_versions_updated_at
  BEFORE UPDATE ON public.app_versions
  FOR EACH ROW
  EXECUTE FUNCTION update_app_versions_updated_at();

-- Enable RLS
ALTER TABLE public.app_versions ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Herkes versiyon bilgilerini okuyabilir (anon kullanıcılar dahil)
CREATE POLICY "Anyone can read app versions"
  ON public.app_versions FOR SELECT
  USING (true);

-- Sadece admin/coach versiyon bilgilerini ekleyebilir/güncelleyebilir
CREATE POLICY "Only admins can insert/update app versions"
  ON public.app_versions FOR ALL
  USING (public.is_admin_or_coach());

-- Index for faster platform lookups
CREATE INDEX idx_app_versions_platform ON public.app_versions(platform);

-- Insert initial version data for iOS and Android
INSERT INTO public.app_versions (platform, minimum_version, current_version, is_force_update, app_store_url, play_store_url)
VALUES 
  (
    'ios',
    '1.2026.2',
    '1.2026.2',
    false,
    'https://apps.apple.com/app/id123456789', -- TODO: Gerçek App Store ID ile değiştirin
    NULL
  ),
  (
    'android',
    '1.2026.2',
    '1.2026.2',
    false,
    NULL,
    'https://play.google.com/store/apps/details?id=com.rivlus.project_tcr'
  )
ON CONFLICT (platform) DO NOTHING;
