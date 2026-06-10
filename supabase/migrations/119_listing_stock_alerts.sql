-- =====================================================
-- 119: Listing stock alerts (Gelince Haber Ver)
-- =====================================================

CREATE TABLE IF NOT EXISTS public.listing_stock_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id UUID NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    size TEXT,
    gender TEXT,
    notified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT listing_stock_alerts_unique_subscription
        UNIQUE NULLS NOT DISTINCT (listing_id, user_id, size, gender)
);

CREATE INDEX IF NOT EXISTS idx_listing_stock_alerts_listing_pending
    ON public.listing_stock_alerts(listing_id)
    WHERE notified_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_listing_stock_alerts_user
    ON public.listing_stock_alerts(user_id);

COMMENT ON TABLE public.listing_stock_alerts IS
    'Kullanıcıların stokta olmayan ürünler için gelince haber ver abonelikleri';

ALTER TABLE public.listing_stock_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own stock alerts"
    ON public.listing_stock_alerts FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all stock alerts"
    ON public.listing_stock_alerts FOR SELECT
    USING (public.is_admin_or_coach());

CREATE POLICY "Users can create own stock alerts"
    ON public.listing_stock_alerts FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own stock alerts"
    ON public.listing_stock_alerts FOR DELETE
    USING (auth.uid() = user_id);

-- Ürünün herhangi bir stoku var mı?
CREATE OR REPLACE FUNCTION public.listing_has_any_stock(p_listing_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE
        WHEN EXISTS (
            SELECT 1
            FROM public.listing_stock_by_size s
            WHERE s.listing_id = p_listing_id
              AND s.quantity > 0
        ) THEN true
        WHEN EXISTS (
            SELECT 1
            FROM public.marketplace_listings l
            WHERE l.id = p_listing_id
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.listing_stock_by_size s
                  WHERE s.listing_id = p_listing_id
              )
              AND (l.stock_quantity IS NULL OR l.stock_quantity > 0)
        ) THEN true
        ELSE false
    END;
$$;

-- Bekleyen aboneliklere bildirim gönder
CREATE OR REPLACE FUNCTION public.dispatch_listing_stock_alerts(
    p_listing_id UUID,
    p_size TEXT DEFAULT NULL,
    p_gender TEXT DEFAULT NULL,
    p_notify_listing_level BOOLEAN DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_listing_title TEXT;
    v_recipient_ids UUID[];
    v_body TEXT;
    v_data JSONB;
    v_size_label TEXT;
    v_gender_label TEXT;
BEGIN
    SELECT trim(title)
    INTO v_listing_title
    FROM public.marketplace_listings
    WHERE id = p_listing_id;

    IF v_listing_title IS NULL THEN
        RETURN;
    END IF;

    v_recipient_ids := ARRAY[]::UUID[];

    -- Beden / cinsiyet bazlı abonelikler
    IF p_size IS NOT NULL THEN
        SELECT COALESCE(ARRAY_AGG(DISTINCT a.user_id), ARRAY[]::UUID[])
        INTO v_recipient_ids
        FROM public.listing_stock_alerts a
        WHERE a.listing_id = p_listing_id
          AND a.notified_at IS NULL
          AND a.size = p_size
          AND (
              (p_gender IS NULL AND a.gender IS NULL)
              OR a.gender = p_gender
          );
    END IF;

    -- Tüm ürün aboneliği (size/gender null)
    IF p_notify_listing_level AND public.listing_has_any_stock(p_listing_id) THEN
        SELECT COALESCE(ARRAY_AGG(DISTINCT merged.user_id), ARRAY[]::UUID[])
        INTO v_recipient_ids
        FROM (
            SELECT UNNEST(COALESCE(v_recipient_ids, ARRAY[]::UUID[])) AS user_id
            UNION
            SELECT alert.user_id
            FROM public.listing_stock_alerts alert
            WHERE alert.listing_id = p_listing_id
              AND alert.notified_at IS NULL
              AND alert.size IS NULL
              AND alert.gender IS NULL
        ) merged;
    END IF;

    IF v_recipient_ids IS NULL OR array_length(v_recipient_ids, 1) IS NULL THEN
        RETURN;
    END IF;

    v_size_label := NULL;
    v_gender_label := NULL;
    IF p_size IS NOT NULL THEN
        v_size_label := p_size;
        IF p_gender = 'male' THEN
            v_gender_label := 'Erkek';
        ELSIF p_gender = 'female' THEN
            v_gender_label := 'Kadın';
        END IF;
    END IF;

    IF v_size_label IS NOT NULL AND v_gender_label IS NOT NULL THEN
        v_body := v_listing_title || ' (' || v_gender_label || ' ' || v_size_label || ') tekrar stokta!';
    ELSIF v_size_label IS NOT NULL THEN
        v_body := v_listing_title || ' (' || v_size_label || ' beden) tekrar stokta!';
    ELSE
        v_body := v_listing_title || ' tekrar stokta!';
    END IF;

    v_data := jsonb_build_object(
        'listing_id', p_listing_id,
        'size', p_size,
        'gender', p_gender
    );

    PERFORM public.insert_notifications(
        'listing_back_in_stock',
        'Ürün Tekrar Stokta',
        v_body,
        v_data,
        v_recipient_ids
    );

    UPDATE public.listing_stock_alerts
    SET notified_at = NOW()
    WHERE listing_id = p_listing_id
      AND notified_at IS NULL
      AND user_id = ANY(v_recipient_ids)
      AND (
          (p_size IS NOT NULL AND size = p_size AND (
              (p_gender IS NULL AND gender IS NULL) OR gender = p_gender
          ))
          OR (p_notify_listing_level AND size IS NULL AND gender IS NULL)
      );
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_on_listing_stock_by_size_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.quantity > 0 THEN
            PERFORM public.dispatch_listing_stock_alerts(
                NEW.listing_id,
                NEW.size,
                NEW.gender,
                true
            );
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF COALESCE(OLD.quantity, 0) <= 0 AND NEW.quantity > 0 THEN
            PERFORM public.dispatch_listing_stock_alerts(
                NEW.listing_id,
                NEW.size,
                NEW.gender,
                true
            );
        END IF;
        RETURN NEW;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_listing_stock_by_size_alert ON public.listing_stock_by_size;
CREATE TRIGGER on_listing_stock_by_size_alert
    AFTER INSERT OR UPDATE OF quantity ON public.listing_stock_by_size
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_on_listing_stock_by_size_change();

CREATE OR REPLACE FUNCTION public.notify_on_listing_stock_quantity_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'UPDATE'
       AND COALESCE(OLD.stock_quantity, 0) <= 0
       AND NEW.stock_quantity IS NOT NULL
       AND NEW.stock_quantity > 0
       AND NOT EXISTS (
           SELECT 1
           FROM public.listing_stock_by_size s
           WHERE s.listing_id = NEW.id
       ) THEN
        PERFORM public.dispatch_listing_stock_alerts(
            NEW.id,
            NULL,
            NULL,
            true
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_listing_stock_quantity_alert ON public.marketplace_listings;
CREATE TRIGGER on_listing_stock_quantity_alert
    AFTER UPDATE OF stock_quantity ON public.marketplace_listings
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_on_listing_stock_quantity_change();

-- Yeni bildirim tipi için varsayılan ayar
UPDATE public.user_notification_settings
SET settings = settings || '{"listing_back_in_stock": true}'::jsonb
WHERE NOT (settings ? 'listing_back_in_stock');

ALTER TABLE public.user_notification_settings
    ALTER COLUMN settings SET DEFAULT '{
        "event_created": true,
        "event_updated": true,
        "carpool_application": true,
        "carpool_application_response": true,
        "event_chat_message": true,
        "post_created": true,
        "post_updated": true,
        "listing_created": true,
        "listing_back_in_stock": true,
        "order_created": true,
        "order_status_changed": true
    }'::jsonb;
