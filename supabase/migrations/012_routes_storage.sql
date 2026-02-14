-- Create storage bucket for GPX route files
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'routes',
  'routes',
  true,
  10485760, -- 10MB limit
  ARRAY['application/gpx+xml', 'application/xml', 'text/xml']
)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users (admins/coaches) to upload routes
CREATE POLICY "Admins and coaches can upload routes"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'routes'
  AND (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = auth.uid()
      AND (role = 'super_admin' OR role = 'coach')
    )
  )
);

-- Allow public read access to routes
CREATE POLICY "Public can view routes"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'routes');

-- Allow admins/coaches to delete routes
CREATE POLICY "Admins and coaches can delete routes"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'routes'
  AND (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = auth.uid()
      AND (role = 'super_admin' OR role = 'coach')
    )
  )
);

-- RLS policies for routes table (if not already set)
-- Enable RLS
ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;

-- Everyone can view routes
CREATE POLICY "Anyone can view routes"
ON public.routes
FOR SELECT
TO authenticated
USING (true);

-- Only admins/coaches can create routes
CREATE POLICY "Admins and coaches can create routes"
ON public.routes
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid()
    AND (role = 'super_admin' OR role = 'coach')
  )
);

-- Only admins/coaches can update routes
CREATE POLICY "Admins and coaches can update routes"
ON public.routes
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid()
    AND (role = 'super_admin' OR role = 'coach')
  )
);

-- Only admins/coaches can delete routes
CREATE POLICY "Admins and coaches can delete routes"
ON public.routes
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid()
    AND (role = 'super_admin' OR role = 'coach')
  )
);

COMMENT ON TABLE public.routes IS 'GPX rotaları - koşu parkurları';
