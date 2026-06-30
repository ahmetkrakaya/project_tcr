-- Rapor: tarih filtresi + genişletilmiş özet
DROP FUNCTION IF EXISTS public.get_partner_redemption_report(UUID, INT);

CREATE OR REPLACE FUNCTION public.get_partner_redemption_report(
    p_campaign_id UUID DEFAULT NULL,
    p_limit INT DEFAULT 100,
    p_from TIMESTAMPTZ DEFAULT NULL,
    p_to TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT public.is_admin_or_coach() THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    SELECT jsonb_build_object(
        'summary', (
            SELECT jsonb_build_object(
                'total_success', COUNT(*) FILTER (WHERE r.status = 'success'),
                'unique_users', COUNT(DISTINCT r.user_id) FILTER (WHERE r.status = 'success'),
                'total_attempts', COUNT(*),
                'rejected_count', COUNT(*) FILTER (WHERE r.status <> 'success')
            )
            FROM public.partner_redemptions r
            WHERE (p_campaign_id IS NULL OR r.campaign_id = p_campaign_id)
              AND (p_from IS NULL OR r.redeemed_at >= p_from)
              AND (p_to IS NULL OR r.redeemed_at <= p_to)
        ),
        'items', COALESCE((
            SELECT jsonb_agg(row ORDER BY row->>'redeemed_at' DESC)
            FROM (
                SELECT jsonb_build_object(
                    'id', r.id,
                    'redeemed_at', r.redeemed_at,
                    'status', r.status,
                    'campaign_id', r.campaign_id,
                    'partner_name', c.partner_name,
                    'discount_label', c.discount_label,
                    'user_id', r.user_id,
                    'user_name', trim(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, ''))
                ) AS row
                FROM public.partner_redemptions r
                JOIN public.partner_campaigns c ON c.id = r.campaign_id
                JOIN public.users u ON u.id = r.user_id
                WHERE (p_campaign_id IS NULL OR r.campaign_id = p_campaign_id)
                  AND (p_from IS NULL OR r.redeemed_at >= p_from)
                  AND (p_to IS NULL OR r.redeemed_at <= p_to)
                ORDER BY r.redeemed_at DESC
                LIMIT p_limit
            ) sub
        ), '[]'::jsonb)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- Dashboard özeti
CREATE OR REPLACE FUNCTION public.get_partner_redemption_dashboard(
    p_campaign_id UUID DEFAULT NULL,
    p_from TIMESTAMPTZ DEFAULT NULL,
    p_to TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT public.is_admin_or_coach() THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    SELECT jsonb_build_object(
        'usage', (
            SELECT jsonb_build_object(
                'total_success', COUNT(*) FILTER (WHERE r.status = 'success'),
                'total_attempts', COUNT(*),
                'unique_users', COUNT(DISTINCT r.user_id) FILTER (WHERE r.status = 'success'),
                'rejected_already_used',
                    COUNT(*) FILTER (WHERE r.status = 'rejected_already_used'),
                'rejected_expired',
                    COUNT(*) FILTER (WHERE r.status = 'rejected_expired'),
                'rejected_limit',
                    COUNT(*) FILTER (WHERE r.status = 'rejected_limit'),
                'rejected_inactive',
                    COUNT(*) FILTER (WHERE r.status = 'rejected_inactive')
            )
            FROM public.partner_redemptions r
            WHERE (p_campaign_id IS NULL OR r.campaign_id = p_campaign_id)
              AND (p_from IS NULL OR r.redeemed_at >= p_from)
              AND (p_to IS NULL OR r.redeemed_at <= p_to)
        ),
        'by_campaign', COALESCE((
            SELECT jsonb_agg(row ORDER BY (row->>'success_count')::INT DESC)
            FROM (
                SELECT jsonb_build_object(
                    'campaign_id', c.id,
                    'partner_name', c.partner_name,
                    'is_active', c.is_active,
                    'success_count', COUNT(*) FILTER (WHERE r.status = 'success'),
                    'total_count', COUNT(*)
                ) AS row
                FROM public.partner_campaigns c
                LEFT JOIN public.partner_redemptions r
                    ON r.campaign_id = c.id
                    AND (p_from IS NULL OR r.redeemed_at >= p_from)
                    AND (p_to IS NULL OR r.redeemed_at <= p_to)
                WHERE (p_campaign_id IS NULL OR c.id = p_campaign_id)
                GROUP BY c.id, c.partner_name, c.is_active
                HAVING COUNT(r.id) > 0 OR p_campaign_id IS NOT NULL
                ORDER BY COUNT(*) FILTER (WHERE r.status = 'success') DESC
                LIMIT 10
            ) sub
        ), '[]'::jsonb)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_partner_redemption_report(UUID, INT, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_partner_redemption_dashboard(UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
