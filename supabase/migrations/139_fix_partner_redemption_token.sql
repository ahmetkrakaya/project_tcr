-- Fix: create_partner_redemption_token içinde nested auth.uid() kaybı + pgcrypto search_path

CREATE OR REPLACE FUNCTION public.create_partner_redemption_token(p_campaign_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_campaign public.partner_campaigns%ROWTYPE;
    v_entitlement JSONB;
    v_token TEXT;
    v_token_id UUID;
    v_expires TIMESTAMPTZ;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT * INTO v_campaign
    FROM public.partner_campaigns
    WHERE id = p_campaign_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Campaign not found';
    END IF;

    IF NOT v_campaign.qr_redemption_enabled THEN
        RAISE EXCEPTION 'QR redemption is not enabled for this campaign';
    END IF;

    v_entitlement := public._get_partner_perk_entitlement_for_user(
        p_campaign_id, v_user_id
    );

    IF NOT (v_entitlement->>'can_redeem')::boolean THEN
        RAISE EXCEPTION 'Cannot redeem: %', v_entitlement->>'reason';
    END IF;

    v_token := translate(encode(gen_random_bytes(24), 'base64'), '+/', '-_');
    v_expires := NOW() + INTERVAL '60 seconds';

    INSERT INTO public.partner_redemption_tokens (campaign_id, user_id, token, expires_at)
    VALUES (p_campaign_id, v_user_id, v_token, v_expires)
    RETURNING id INTO v_token_id;

    RETURN jsonb_build_object(
        'token_id', v_token_id,
        'token', v_token,
        'expires_at', to_jsonb(v_expires),
        'redeem_url', 'https://www.rivlus.com/p/r/' || v_token
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_partner_redemption_token(UUID) TO authenticated;
