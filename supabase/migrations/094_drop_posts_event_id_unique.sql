-- =====================================================
-- 094: Drop unique index on posts.event_id
-- =====================================================
-- Aynı etkinliğe birden fazla post bağlanabilsin diye tekillik kaldırılır.

DROP INDEX IF EXISTS public.idx_posts_event_id_unique;

