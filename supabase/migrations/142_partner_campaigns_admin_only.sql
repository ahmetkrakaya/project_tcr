-- Kampanya: yalnızca admin/koç görünürlüğü

ALTER TABLE public.partner_campaigns
    ADD COLUMN IF NOT EXISTS admin_only BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.partner_campaigns.admin_only IS
    'true ise kampanya yalnızca admin ve koçlar tarafından görülür/kullanılır';

DROP POLICY IF EXISTS "Authenticated users can read partner campaigns"
    ON public.partner_campaigns;

CREATE POLICY "Authenticated users can read partner campaigns"
    ON public.partner_campaigns FOR SELECT
    TO authenticated
    USING (
        NOT admin_only
        OR public.is_admin_or_coach()
    );

-- SECURITY DEFINER RPC'ler RLS bypass ettiği için entitlement'ta da kontrol
CREATE OR REPLACE FUNCTION public._get_partner_perk_entitlement_for_user(
    p_campaign_id UUID,
    p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_campaign public.partner_campaigns%ROWTYPE;
    v_uses_total BIGINT;
    v_uses_today BIGINT;
    v_uses_week BIGINT;
    v_limit INT;
    v_can BOOLEAN := true;
    v_reason TEXT := NULL;
    v_next TIMESTAMPTZ := NULL;
    v_now TIMESTAMPTZ := NOW();
BEGIN
    SELECT * INTO v_campaign
    FROM public.partner_campaigns
    WHERE id = p_campaign_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Campaign not found';
    END IF;

    IF v_campaign.admin_only AND NOT EXISTS (
        SELECT 1
        FROM public.user_roles ur
        WHERE ur.user_id = p_user_id
          AND ur.role IN ('super_admin', 'coach')
    ) THEN
        RETURN jsonb_build_object(
            'can_redeem', false,
            'reason', 'campaign_inactive',
            'uses_today', 0,
            'uses_total', 0,
            'uses_week', 0,
            'next_available_at', NULL,
            'qr_enabled', v_campaign.qr_redemption_enabled,
            'usage_limit_type', v_campaign.usage_limit_type,
            'usage_limit_count', v_campaign.usage_limit_count,
            'success_message', NULLIF(trim(v_campaign.success_message), '')
        );
    END IF;

    SELECT u.uses_total, u.uses_today, u.uses_week
    INTO v_uses_total, v_uses_today, v_uses_week
    FROM public._partner_redemption_usage_counts(p_campaign_id, p_user_id, v_now) u;

    IF NOT public._partner_campaign_is_live(
        v_campaign.is_active, v_campaign.starts_at, v_campaign.ends_at, v_now
    ) THEN
        v_can := false;
        IF NOT v_campaign.is_active THEN
            v_reason := 'campaign_inactive';
        ELSIF v_now < v_campaign.starts_at THEN
            v_reason := 'campaign_not_started';
        ELSE
            v_reason := 'campaign_ended';
        END IF;
    ELSIF v_campaign.qr_redemption_enabled THEN
        v_limit := v_campaign.usage_limit_count;

        CASE v_campaign.usage_limit_type
            WHEN 'unlimited' THEN
                NULL;
            WHEN 'once_lifetime' THEN
                IF v_uses_total >= 1 THEN
                    v_can := false;
                    v_reason := 'lifetime_limit_reached';
                END IF;
            WHEN 'once_per_day' THEN
                IF v_uses_today >= 1 THEN
                    v_can := false;
                    v_reason := 'daily_limit_reached';
                    v_next := (date_trunc('day', v_now AT TIME ZONE 'Europe/Istanbul') + INTERVAL '1 day')
                              AT TIME ZONE 'Europe/Istanbul';
                END IF;
            WHEN 'once_per_week' THEN
                IF v_uses_week >= 1 THEN
                    v_can := false;
                    v_reason := 'weekly_limit_reached';
                    v_next := v_now + INTERVAL '7 days';
                END IF;
            WHEN 'max_total' THEN
                IF v_limit IS NULL OR v_limit < 1 THEN
                    v_limit := 1;
                END IF;
                IF v_uses_total >= v_limit THEN
                    v_can := false;
                    v_reason := 'total_limit_reached';
                END IF;
            WHEN 'max_per_day' THEN
                IF v_limit IS NULL OR v_limit < 1 THEN
                    v_limit := 1;
                END IF;
                IF v_uses_today >= v_limit THEN
                    v_can := false;
                    v_reason := 'daily_limit_reached';
                    v_next := (date_trunc('day', v_now AT TIME ZONE 'Europe/Istanbul') + INTERVAL '1 day')
                              AT TIME ZONE 'Europe/Istanbul';
                END IF;
            ELSE
                NULL;
        END CASE;
    END IF;

    RETURN jsonb_build_object(
        'can_redeem', v_can,
        'reason', v_reason,
        'uses_today', COALESCE(v_uses_today, 0),
        'uses_total', COALESCE(v_uses_total, 0),
        'uses_week', COALESCE(v_uses_week, 0),
        'next_available_at', v_next,
        'qr_enabled', v_campaign.qr_redemption_enabled,
        'usage_limit_type', v_campaign.usage_limit_type,
        'usage_limit_count', v_campaign.usage_limit_count,
        'success_message', NULLIF(trim(v_campaign.success_message), '')
    );
END;
$$;
