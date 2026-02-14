-- =====================================================
-- 039: Events lane_config (Pist kulvar ataması - pace bazlı)
-- =====================================================
-- Rota pist (track) ise event seviyesinde pace bazlı kulvar tanımı.
-- Yapı: { "track_length_km": 0.4, "lanes": [ { "lane_number": 1, "pace_min_sec_per_km": 240, "pace_max_sec_per_km": 270, "label": "4:00-4:30" }, ... ] }

ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS lane_config JSONB DEFAULT NULL;

COMMENT ON COLUMN public.events.lane_config IS
  'Pist rotada pace bazlı kulvar: track_length_km (opsiyonel), lanes: [{ lane_number, pace_min_sec_per_km, pace_max_sec_per_km, label? }]. Yoksa routes.total_distance kullanılır.';

-- Şablondan etkinlik oluşturulurken lane_config kopyalanabilsin
ALTER TABLE public.event_templates
ADD COLUMN IF NOT EXISTS lane_config JSONB DEFAULT NULL;

COMMENT ON COLUMN public.event_templates.lane_config IS
  'Pist kulvar ayarı; şablondan etkinlik oluşturulurken kopyalanır.';
