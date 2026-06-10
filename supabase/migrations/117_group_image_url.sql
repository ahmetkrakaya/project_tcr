-- Grup fotoğrafı desteği
ALTER TABLE public.training_groups
    ADD COLUMN IF NOT EXISTS image_url TEXT;

COMMENT ON COLUMN public.training_groups.image_url IS 'Grup fotoğrafı URL (Supabase Storage). Boşsa ikon kullanılır.';

CREATE INDEX IF NOT EXISTS idx_training_groups_image_url
    ON public.training_groups (image_url)
    WHERE image_url IS NOT NULL;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'group-images',
    'group-images',
    true,
    5242880,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'image/heif']
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Admins and coaches can upload group images"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'group-images'
    AND EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role IN ('super_admin', 'coach')
    )
);

CREATE POLICY "Public can view group images"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'group-images');

CREATE POLICY "Admins and coaches can update group images"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
    bucket_id = 'group-images'
    AND EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role IN ('super_admin', 'coach')
    )
);

CREATE POLICY "Admins and coaches can delete group images"
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id = 'group-images'
    AND EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role IN ('super_admin', 'coach')
    )
);
