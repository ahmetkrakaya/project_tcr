-- Personel web sayfası genel mesaj görür; özel başarı mesajı uygulamada gösterilir.

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

CREATE OR REPLACE FUNCTION public.redeem_partner_token(
    p_token TEXT,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row public.partner_redemption_tokens%ROWTYPE;
    v_campaign public.partner_campaigns%ROWTYPE;
    v_entitlement JSONB;
    v_message TEXT;
    v_status TEXT;
    v_success BOOLEAN := false;
    v_user_name TEXT;
BEGIN
    SELECT * INTO v_row
    FROM public.partner_redemption_tokens
    WHERE token = p_token
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'status', 'rejected_expired',
            'message', 'Doğrulama başarısız'
        );
    END IF;

    SELECT * INTO v_campaign
    FROM public.partner_campaigns
    WHERE id = v_row.campaign_id;

    SELECT COALESCE(NULLIF(trim(u.first_name || ' ' || u.last_name), ''), 'TCR Üyesi')
    INTO v_user_name
    FROM public.users u
    WHERE u.id = v_row.user_id;

    IF v_row.used_at IS NOT NULL THEN
        v_status := 'rejected_already_used';
        v_message := 'Doğrulama başarısız';
        INSERT INTO public.partner_redemptions (campaign_id, user_id, token_id, status, metadata)
        VALUES (v_row.campaign_id, v_row.user_id, v_row.id, v_status, p_metadata);
    ELSIF v_row.expires_at < NOW() THEN
        v_status := 'rejected_expired';
        v_message := 'Doğrulama başarısız';
        INSERT INTO public.partner_redemptions (campaign_id, user_id, token_id, status, metadata)
        VALUES (v_row.campaign_id, v_row.user_id, v_row.id, v_status, p_metadata);
    ELSIF NOT public._partner_campaign_is_live(
        v_campaign.is_active, v_campaign.starts_at, v_campaign.ends_at
    ) THEN
        v_status := 'rejected_inactive';
        v_message := 'Doğrulama başarısız';
        INSERT INTO public.partner_redemptions (campaign_id, user_id, token_id, status, metadata)
        VALUES (v_row.campaign_id, v_row.user_id, v_row.id, v_status, p_metadata);
    ELSE
        v_entitlement := public._get_partner_perk_entitlement_for_user(
            v_row.campaign_id, v_row.user_id
        );

        IF NOT (v_entitlement->>'can_redeem')::boolean THEN
            v_status := 'rejected_limit';
            v_message := 'Doğrulama başarısız';
            INSERT INTO public.partner_redemptions (campaign_id, user_id, token_id, status, metadata)
            VALUES (v_row.campaign_id, v_row.user_id, v_row.id, v_status, p_metadata);
        ELSE
            UPDATE public.partner_redemption_tokens
            SET used_at = NOW()
            WHERE id = v_row.id;

            v_status := 'success';
            v_success := true;
            v_message := 'Doğrulama başarılı';

            INSERT INTO public.partner_redemptions (campaign_id, user_id, token_id, status, metadata)
            VALUES (v_row.campaign_id, v_row.user_id, v_row.id, v_status, p_metadata);
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', v_success,
        'status', v_status,
        'message', v_message,
        'partner_name', v_campaign.partner_name,
        'logo_url', v_campaign.logo_url,
        'brand_color', v_campaign.brand_color,
        'discount_label', v_campaign.discount_label,
        'discount_percent', v_campaign.discount_percent,
        'member_name', v_user_name
    );
END;
$$;

COMMENT ON COLUMN public.partner_campaigns.success_message IS 'Başarılı QR sonrası üye uygulamasında gösterilen mesaj';
