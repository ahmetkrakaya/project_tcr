-- =====================================================
-- 042: Posts event_id - Etkinlik programından üretilen post bağlantısı
-- =====================================================

ALTER TABLE public.posts
ADD COLUMN IF NOT EXISTS event_id UUID NULL REFERENCES public.events(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_posts_event_id_unique
ON public.posts(event_id) WHERE event_id IS NOT NULL;

COMMENT ON COLUMN public.posts.event_id IS 'Etkinlik programından üretilen postlarda kaynak etkinlik';
