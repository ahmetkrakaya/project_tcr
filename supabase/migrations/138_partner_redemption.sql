-- ============================================================
-- 138: Partner QR doğrulama + dinamik kullanım kuralları
-- ============================================================

ALTER TABLE public.partner_campaigns
    ADD COLUMN IF NOT EXISTS qr_redemption_enabled BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS usage_limit_type TEXT NOT NULL DEFAULT 'once_per_day'
        CHECK (usage_limit_type IN (
            'unlimited',
            'once_lifetime',
            'once_per_day',
            'once_per_week',
            'max_total',
            'max_per_day'
        )),
    ADD COLUMN IF NOT EXISTS usage_limit_count INTEGER,
    ADD COLUMN IF NOT EXISTS success_message TEXT;

COMMENT ON COLUMN public.partner_campaigns.qr_redemption_enabled IS 'QR ile kasada doğrulama aktif mi';
COMMENT ON COLUMN public.partner_campaigns.usage_limit_type IS 'Kullanım limiti tipi';
COMMENT ON COLUMN public.partner_campaigns.usage_limit_count IS 'max_total / max_per_day için limit sayısı';
COMMENT ON COLUMN public.partner_campaigns.success_message IS 'Web onay sayfası özel mesajı';

-- ============================================================
-- Tablolar
-- ============================================================

CREATE TABLE IF NOT EXISTS public.partner_redemption_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.partner_campaigns(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    token TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_partner_redemption_tokens_campaign_user
    ON public.partner_redemption_tokens (campaign_id, user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_partner_redemption_tokens_expires
    ON public.partner_redemption_tokens (expires_at)
    WHERE used_at IS NULL;

CREATE TABLE IF NOT EXISTS public.partner_redemptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.partner_campaigns(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    token_id UUID REFERENCES public.partner_redemption_tokens(id) ON DELETE SET NULL,
    status TEXT NOT NULL CHECK (status IN (
        'success',
        'rejected_expired',
        'rejected_limit',
        'rejected_inactive',
        'rejected_already_used'
    )),
    redeemed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_partner_redemptions_campaign_date
    ON public.partner_redemptions (campaign_id, redeemed_at DESC);

CREATE INDEX IF NOT EXISTS idx_partner_redemptions_user_campaign
    ON public.partner_redemptions (user_id, campaign_id, redeemed_at DESC);

CREATE INDEX IF NOT EXISTS idx_partner_redemptions_success
    ON public.partner_redemptions (campaign_id, user_id, redeemed_at DESC)
    WHERE status = 'success';

ALTER TABLE public.partner_redemption_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_redemptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own redemption tokens" ON public.partner_redemption_tokens;
CREATE POLICY "Users can view own redemption tokens"
    ON public.partner_redemption_tokens FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can view own redemptions" ON public.partner_redemptions;
CREATE POLICY "Users can view own redemptions"
    ON public.partner_redemptions FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Admins can view all redemptions" ON public.partner_redemptions;
CREATE POLICY "Admins can view all redemptions"
    ON public.partner_redemptions FOR SELECT
    TO authenticated
    USING (public.is_admin_or_coach());

-- ============================================================
-- Yardımcı: kampanya aktif mi
-- ============================================================

CREATE OR REPLACE FUNCTION public._partner_campaign_is_live(
    p_is_active BOOLEAN,
    p_starts_at TIMESTAMPTZ,
    p_ends_at TIMESTAMPTZ,
    p_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_is_active
        AND p_at >= p_starts_at
        AND (p_ends_at IS NULL OR p_at <= p_ends_at);
$$;

-- ============================================================
-- Yardımcı: kullanım sayıları
-- ============================================================

CREATE OR REPLACE FUNCTION public._partner_redemption_usage_counts(
    p_campaign_id UUID,
    p_user_id UUID,
    p_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TABLE (
    uses_total BIGINT,
    uses_today BIGINT,
    uses_week BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        COUNT(*) FILTER (WHERE status = 'success') AS uses_total,
        COUNT(*) FILTER (
            WHERE status = 'success'
              AND redeemed_at >= date_trunc('day', p_at AT TIME ZONE 'Europe/Istanbul')
                                 AT TIME ZONE 'Europe/Istanbul'
              AND redeemed_at < (date_trunc('day', p_at AT TIME ZONE 'Europe/Istanbul') + INTERVAL '1 day')
                                 AT TIME ZONE 'Europe/Istanbul'
        ) AS uses_today,
        COUNT(*) FILTER (
            WHERE status = 'success'
              AND redeemed_at >= p_at - INTERVAL '7 days'
        ) AS uses_week
    FROM public.partner_redemptions
    WHERE campaign_id = p_campaign_id
      AND user_id = p_user_id;
$$;

-- ============================================================
-- Entitlement kontrolü
-- ============================================================

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
        'usage_limit_count', v_campaign.usage_limit_count
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_partner_perk_entitlement(p_campaign_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN public._get_partner_perk_entitlement_for_user(p_campaign_id, v_user_id);
END;
$$;

-- ============================================================
-- Token oluştur
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_partner_redemption_token(p_campaign_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

    v_entitlement := public.get_partner_perk_entitlement(p_campaign_id);

    IF NOT (v_entitlement->>'can_redeem')::boolean THEN
        RAISE EXCEPTION 'Cannot redeem: %', v_entitlement->>'reason';
    END IF;

    v_token := replace(replace(encode(gen_random_bytes(24), 'base64'), '+', '-'), '/', '_');
    v_expires := NOW() + INTERVAL '60 seconds';

    INSERT INTO public.partner_redemption_tokens (campaign_id, user_id, token, expires_at)
    VALUES (p_campaign_id, v_user_id, v_token, v_expires)
    RETURNING id INTO v_token_id;

    RETURN jsonb_build_object(
        'token_id', v_token_id,
        'token', v_token,
        'expires_at', v_expires,
        'redeem_url', 'https://www.rivlus.com/p/r/' || v_token
    );
END;
$$;

-- ============================================================
-- Token kullan (edge function / service role)
-- ============================================================

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
            'message', 'Geçersiz veya süresi dolmuş kod.'
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
        v_message := 'Bu kod zaten kullanılmış.';
        INSERT INTO public.partner_redemptions (campaign_id, user_id, token_id, status, metadata)
        VALUES (v_row.campaign_id, v_row.user_id, v_row.id, v_status, p_metadata);
    ELSIF v_row.expires_at < NOW() THEN
        v_status := 'rejected_expired';
        v_message := 'Kodun süresi dolmuş. Müşteriden ekranı yenilemesini isteyin.';
        INSERT INTO public.partner_redemptions (campaign_id, user_id, token_id, status, metadata)
        VALUES (v_row.campaign_id, v_row.user_id, v_row.id, v_status, p_metadata);
    ELSIF NOT public._partner_campaign_is_live(
        v_campaign.is_active, v_campaign.starts_at, v_campaign.ends_at
    ) THEN
        v_status := 'rejected_inactive';
        v_message := 'Kampanya şu an geçerli değil.';
        INSERT INTO public.partner_redemptions (campaign_id, user_id, token_id, status, metadata)
        VALUES (v_row.campaign_id, v_row.user_id, v_row.id, v_status, p_metadata);
    ELSE
        v_entitlement := public._get_partner_perk_entitlement_for_user(
            v_row.campaign_id, v_row.user_id
        );

        IF NOT (v_entitlement->>'can_redeem')::boolean THEN
            v_status := 'rejected_limit';
            v_message := CASE v_entitlement->>'reason'
                WHEN 'daily_limit_reached' THEN 'Bugünkü kullanım hakkı dolmuş.'
                WHEN 'lifetime_limit_reached' THEN 'Bu avantaj daha önce kullanılmış.'
                WHEN 'weekly_limit_reached' THEN 'Haftalık kullanım hakkı dolmuş.'
                WHEN 'total_limit_reached' THEN 'Toplam kullanım hakkı dolmuş.'
                ELSE 'Kullanım hakkı bulunmuyor.'
            END;
            INSERT INTO public.partner_redemptions (campaign_id, user_id, token_id, status, metadata)
            VALUES (v_row.campaign_id, v_row.user_id, v_row.id, v_status, p_metadata);
        ELSE
            UPDATE public.partner_redemption_tokens
            SET used_at = NOW()
            WHERE id = v_row.id;

            v_status := 'success';
            v_success := true;
            v_message := COALESCE(
                NULLIF(trim(v_campaign.success_message), ''),
                'İşlem başarılı. İndirim uygulanabilir.'
            );

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

-- ============================================================
-- Admin raporlama özeti
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_partner_redemption_report(
    p_campaign_id UUID DEFAULT NULL,
    p_limit INT DEFAULT 100
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
                'unique_users', COUNT(DISTINCT r.user_id) FILTER (WHERE r.status = 'success')
            )
            FROM public.partner_redemptions r
            WHERE (p_campaign_id IS NULL OR r.campaign_id = p_campaign_id)
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
                ORDER BY r.redeemed_at DESC
                LIMIT p_limit
            ) sub
        ), '[]'::jsonb)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_partner_perk_entitlement(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_partner_redemption_token(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_partner_token(TEXT, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_partner_redemption_report(UUID, INT) TO authenticated;
