-- ============================================================
-- 136: Üye avantajları / partner kampanyaları
-- ============================================================

CREATE TABLE IF NOT EXISTS public.partner_campaigns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug TEXT NOT NULL UNIQUE,
    partner_name TEXT NOT NULL,
    tagline TEXT,
    logo_url TEXT,
    brand_color TEXT NOT NULL DEFAULT '#1B4332',
    discount_percent INTEGER NOT NULL CHECK (discount_percent > 0 AND discount_percent <= 100),
    discount_label TEXT NOT NULL,
    terms TEXT,
    redemption_hint TEXT NOT NULL DEFAULT 'Bu ekranı kasada gösterin',
    location_name TEXT,
    location_address TEXT,
    starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ends_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT true,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_partner_campaigns_active
    ON public.partner_campaigns (is_active, sort_order, starts_at DESC);

CREATE OR REPLACE FUNCTION public.update_partner_campaigns_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS partner_campaigns_updated_at ON public.partner_campaigns;
CREATE TRIGGER partner_campaigns_updated_at
    BEFORE UPDATE ON public.partner_campaigns
    FOR EACH ROW
    EXECUTE FUNCTION public.update_partner_campaigns_updated_at();

ALTER TABLE public.partner_campaigns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read partner campaigns" ON public.partner_campaigns;
CREATE POLICY "Authenticated users can read partner campaigns"
    ON public.partner_campaigns FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Admins and coaches can manage partner campaigns" ON public.partner_campaigns;
CREATE POLICY "Admins and coaches can manage partner campaigns"
    ON public.partner_campaigns FOR ALL
    TO authenticated
    USING (public.is_admin_or_coach())
    WITH CHECK (public.is_admin_or_coach());

COMMENT ON TABLE public.partner_campaigns IS 'Üye avantajları: partner işletmelerde indirim kampanyaları';

-- Storage bucket for partner logos
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'partner-logos',
    'partner-logos',
    true,
    5242880,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'image/heif']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Admins and coaches can upload partner logos" ON storage.objects;
CREATE POLICY "Admins and coaches can upload partner logos"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'partner-logos'
    AND EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role IN ('super_admin', 'coach')
    )
);

DROP POLICY IF EXISTS "Public can view partner logos" ON storage.objects;
CREATE POLICY "Public can view partner logos"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'partner-logos');

DROP POLICY IF EXISTS "Admins and coaches can update partner logos" ON storage.objects;
CREATE POLICY "Admins and coaches can update partner logos"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
    bucket_id = 'partner-logos'
    AND EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role IN ('super_admin', 'coach')
    )
);

DROP POLICY IF EXISTS "Admins and coaches can delete partner logos" ON storage.objects;
CREATE POLICY "Admins and coaches can delete partner logos"
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id = 'partner-logos'
    AND EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role IN ('super_admin', 'coach')
    )
);
