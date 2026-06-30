-- Partner kampanyalarına harita koordinatları
ALTER TABLE public.partner_campaigns
    ADD COLUMN IF NOT EXISTS location_lat DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS location_lng DOUBLE PRECISION;

COMMENT ON COLUMN public.partner_campaigns.location_lat IS 'Partner konumu enlem (haritadan seçim)';
COMMENT ON COLUMN public.partner_campaigns.location_lng IS 'Partner konumu boylam (haritadan seçim)';
