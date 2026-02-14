-- Rota oluştururken haritadan seçilen konum (lat/lng)
ALTER TABLE public.routes
ADD COLUMN IF NOT EXISTS location_lat DECIMAL(10, 8),
ADD COLUMN IF NOT EXISTS location_lng DECIMAL(11, 8),
ADD COLUMN IF NOT EXISTS location_name TEXT;

COMMENT ON COLUMN public.routes.location_lat IS 'Haritadan seçilen rota konumu - enlem';
COMMENT ON COLUMN public.routes.location_lng IS 'Haritadan seçilen rota konumu - boylam';
COMMENT ON COLUMN public.routes.location_name IS 'Opsiyonel: mahalle/sokak adı (reverse geocode)';
