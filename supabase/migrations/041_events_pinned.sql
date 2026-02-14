-- =====================================================
-- 041: Events - Pinleme (Sabitleme) Alanları
-- =====================================================
-- Pinlenen etkinlikler ana sayfada bu haftaki etkinliklerin en başında görünür

ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_events_is_pinned ON public.events(is_pinned) WHERE is_pinned = true;
CREATE INDEX IF NOT EXISTS idx_events_pinned_at ON public.events(pinned_at DESC NULLS LAST);

COMMENT ON COLUMN public.events.is_pinned IS 'Etkinlik ana sayfada sabitlendi mi (sadece admin)';
COMMENT ON COLUMN public.events.pinned_at IS 'Sabitleme zamanı; sıralama için kullanılır';
