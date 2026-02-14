-- Add banner_image_url column to events table
ALTER TABLE public.events 
ADD COLUMN IF NOT EXISTS banner_image_url text;

-- Create storage bucket for event banners (if not exists)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'event-banners',
  'event-banners',
  true,
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload event banners
CREATE POLICY "Authenticated users can upload event banners"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'event-banners'
  AND (
    -- Only admins and coaches can upload
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = auth.uid()
      AND (role = 'super_admin' OR role = 'coach')
    )
  )
);

-- Allow public read access to event banners
CREATE POLICY "Public can view event banners"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'event-banners');

-- Allow admins/coaches to delete event banners
CREATE POLICY "Admins and coaches can delete event banners"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'event-banners'
  AND (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = auth.uid()
      AND (role = 'super_admin' OR role = 'coach')
    )
  )
);

-- Index for faster queries
CREATE INDEX IF NOT EXISTS idx_events_banner_image_url ON public.events (banner_image_url) WHERE banner_image_url IS NOT NULL;

COMMENT ON COLUMN public.events.banner_image_url IS 'URL to the event banner image stored in Supabase Storage';
