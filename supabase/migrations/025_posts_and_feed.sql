-- =====================================================
-- 025: Posts and Feed - Post/Makale Paylaşım Sistemi
-- =====================================================
-- Admin ve koçlar için post/makale paylaşım özelliği
-- Event info blocks yapısına benzer blok tabanlı içerik

-- Posts Tablosu
CREATE TABLE IF NOT EXISTS public.posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    cover_image_url TEXT,
    is_published BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    
    -- Index için
    CONSTRAINT posts_title_not_empty CHECK (length(trim(title)) > 0)
);

-- Post Blocks Tablosu (Event Info Blocks'a benzer)
CREATE TABLE IF NOT EXISTS public.post_blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    type TEXT NOT NULL DEFAULT 'text',
    content TEXT NOT NULL,
    sub_content TEXT,
    image_url TEXT,
    color TEXT,
    icon TEXT,
    order_index INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    
    -- Type constraint
    CONSTRAINT valid_post_block_type CHECK (type IN (
        'header',
        'subheader', 
        'schedule_item',
        'warning',
        'info',
        'tip',
        'text',
        'quote',
        'list_item',
        'checklist_item',
        'divider',
        'image'
    ))
);

-- Indexler
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON public.posts(user_id);
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON public.posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_published ON public.posts(is_published) WHERE is_published = true;
CREATE INDEX IF NOT EXISTS idx_post_blocks_post_id ON public.post_blocks(post_id);
CREATE INDEX IF NOT EXISTS idx_post_blocks_order ON public.post_blocks(post_id, order_index);

-- RLS Aktif Et
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_blocks ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- POSTS POLICIES
-- ==========================================

-- Herkes yayınlanmış postları görebilir
CREATE POLICY "Anyone can view published posts"
    ON public.posts FOR SELECT
    USING (is_published = true);

-- Admin ve Coach oluşturabilir
CREATE POLICY "Admins and coaches can create posts"
    ON public.posts FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
        AND user_id = auth.uid()
    );

-- Sadece post sahibi (ve admin/coach) güncelleyebilir
CREATE POLICY "Post owners and admins can update posts"
    ON public.posts FOR UPDATE
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Sadece post sahibi (ve admin/coach) silebilir
CREATE POLICY "Post owners and admins can delete posts"
    ON public.posts FOR DELETE
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- ==========================================
-- POST BLOCKS POLICIES
-- ==========================================

-- Herkes yayınlanmış postların bloklarını görebilir
CREATE POLICY "Anyone can view blocks of published posts"
    ON public.post_blocks FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.posts 
            WHERE posts.id = post_blocks.post_id 
            AND posts.is_published = true
        )
    );

-- Admin ve Coach blok oluşturabilir
CREATE POLICY "Admins and coaches can create post blocks"
    ON public.post_blocks FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
        AND EXISTS (
            SELECT 1 FROM public.posts
            WHERE posts.id = post_blocks.post_id
            AND (
                posts.user_id = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM public.user_roles
                    WHERE user_roles.user_id = auth.uid()
                    AND user_roles.role IN ('super_admin', 'coach')
                )
            )
        )
    );

-- Admin ve Coach blok güncelleyebilir
CREATE POLICY "Admins and coaches can update post blocks"
    ON public.post_blocks FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
        AND EXISTS (
            SELECT 1 FROM public.posts
            WHERE posts.id = post_blocks.post_id
            AND (
                posts.user_id = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM public.user_roles
                    WHERE user_roles.user_id = auth.uid()
                    AND user_roles.role IN ('super_admin', 'coach')
                )
            )
        )
    );

-- Admin ve Coach blok silebilir
CREATE POLICY "Admins and coaches can delete post blocks"
    ON public.post_blocks FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
        AND EXISTS (
            SELECT 1 FROM public.posts
            WHERE posts.id = post_blocks.post_id
            AND (
                posts.user_id = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM public.user_roles
                    WHERE user_roles.user_id = auth.uid()
                    AND user_roles.role IN ('super_admin', 'coach')
                )
            )
        )
    );

-- ==========================================
-- TRIGGERS
-- ==========================================

-- Updated_at trigger for posts
CREATE OR REPLACE FUNCTION update_post_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER post_updated_at
    BEFORE UPDATE ON public.posts
    FOR EACH ROW EXECUTE FUNCTION update_post_updated_at();

-- Updated_at trigger for post_blocks
CREATE OR REPLACE FUNCTION update_post_block_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER post_block_updated_at
    BEFORE UPDATE ON public.post_blocks
    FOR EACH ROW EXECUTE FUNCTION update_post_block_updated_at();

-- ==========================================
-- FEED FUNCTION
-- ==========================================
-- Hem aktiviteler hem postları birleştiren feed fonksiyonu

CREATE OR REPLACE FUNCTION get_unified_feed(
    page_size INTEGER DEFAULT 20,
    page_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    item_type TEXT,
    item_id UUID,
    user_id UUID,
    user_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ,
    -- Activity fields
    activity_type TEXT,
    activity_source TEXT,
    activity_title TEXT,
    distance_meters NUMERIC,
    duration_seconds INTEGER,
    pace_seconds INTEGER,
    -- Post fields
    post_title TEXT,
    post_cover_image_url TEXT
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH activities AS (
        SELECT 
            'activity'::TEXT as item_type,
            a.id::UUID as item_id,
            a.user_id::UUID,
            COALESCE(u.first_name || ' ' || u.last_name, u.email)::TEXT as user_name,
            u.avatar_url::TEXT,
            a.start_time as created_at,
            a.activity_type::TEXT,
            a.source::TEXT,
            a.title::TEXT as activity_title,
            a.distance_meters,
            a.duration_seconds,
            a.pace_seconds,
            NULL::TEXT as post_title,
            NULL::TEXT as post_cover_image_url
        FROM public.activities a
        INNER JOIN public.users u ON u.id = a.user_id
        WHERE a.is_public = true
    ),
    posts AS (
        SELECT 
            'post'::TEXT as item_type,
            p.id::UUID as item_id,
            p.user_id::UUID,
            COALESCE(u.first_name || ' ' || u.last_name, u.email)::TEXT as user_name,
            u.avatar_url::TEXT,
            p.created_at,
            NULL::TEXT as activity_type,
            NULL::TEXT as activity_source,
            NULL::TEXT as activity_title,
            NULL::NUMERIC as distance_meters,
            NULL::INTEGER as duration_seconds,
            NULL::INTEGER as pace_seconds,
            p.title::TEXT as post_title,
            p.cover_image_url::TEXT as post_cover_image_url
        FROM public.posts p
        INNER JOIN public.users u ON u.id = p.user_id
        WHERE p.is_published = true
    ),
    unified AS (
        SELECT * FROM activities
        UNION ALL
        SELECT * FROM posts
    )
    SELECT 
        unified.item_type,
        unified.item_id,
        unified.user_id,
        unified.user_name,
        unified.avatar_url,
        unified.created_at,
        unified.activity_type,
        unified.activity_source,
        unified.activity_title,
        unified.distance_meters,
        unified.duration_seconds,
        unified.pace_seconds,
        unified.post_title,
        unified.post_cover_image_url
    FROM unified
    ORDER BY unified.created_at DESC
    LIMIT page_size
    OFFSET page_offset;
END;
$$;

-- ==========================================
-- STORAGE BUCKET FOR POST IMAGES
-- ==========================================

-- Create storage bucket for post images (if not exists)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'post-images',
  'post-images',
  true,
  10485760, -- 10MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users (admin/coach) to upload post images
CREATE POLICY "Admins and coaches can upload post images"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'post-images'
  AND (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = auth.uid()
      AND (role = 'super_admin' OR role = 'coach')
    )
  )
);

-- Allow public read access to post images
CREATE POLICY "Public can view post images"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'post-images');

-- Allow admins/coaches to delete post images
CREATE POLICY "Admins and coaches can delete post images"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'post-images'
  AND (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = auth.uid()
      AND (role = 'super_admin' OR role = 'coach')
    )
  )
);

-- Comments
COMMENT ON TABLE public.posts IS 'Admin ve koçlar tarafından oluşturulan post/makale içerikleri';
COMMENT ON TABLE public.post_blocks IS 'Post içeriklerinin blok tabanlı yapısı (event_info_blocks benzeri)';
COMMENT ON FUNCTION get_unified_feed IS 'Hem aktiviteler hem postları birleştiren feed fonksiyonu';
