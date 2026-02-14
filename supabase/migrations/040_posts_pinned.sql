-- =====================================================
-- 040: Posts - Pinleme (Sabitleme) Alanları
-- =====================================================
-- Pinlenen postlar ana sayfada her zaman en üstte görünür

ALTER TABLE public.posts
ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_posts_is_pinned ON public.posts(is_pinned) WHERE is_pinned = true;
CREATE INDEX IF NOT EXISTS idx_posts_pinned_at ON public.posts(pinned_at DESC NULLS LAST);

COMMENT ON COLUMN public.posts.is_pinned IS 'Post ana sayfada sabitlendi mi (sadece admin)';
COMMENT ON COLUMN public.posts.pinned_at IS 'Sabitleme zamanı; sıralama için kullanılır';
