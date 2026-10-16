-- TCR Migration 164: Etkinlik maliyet kalemleri (mekan, DJ, diğer)
-- Kişi başı giderler satış snapshot'ına (partner_share_amount) yazılır.
-- Etkinlik geneli giderler (ör. DJ'e tek seferlik ödeme) raporlarda kârdan düşülür.

CREATE TABLE IF NOT EXISTS public.event_finance_costs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    scope TEXT NOT NULL DEFAULT 'per_person',
    share_type TEXT NOT NULL DEFAULT 'fixed',
    share_value DECIMAL(10,2) NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT event_finance_costs_name_check CHECK (btrim(name) <> ''),
    CONSTRAINT event_finance_costs_scope_check CHECK (scope IN ('per_person', 'event')),
    CONSTRAINT event_finance_costs_share_type_check CHECK (share_type IN ('fixed', 'percent')),
    CONSTRAINT event_finance_costs_share_value_check CHECK (
        share_value >= 0
        AND (share_type <> 'percent' OR share_value <= 100)
        AND (scope <> 'event' OR share_type = 'fixed')
    )
);

COMMENT ON TABLE public.event_finance_costs IS
    'Ücretli etkinliğin gider kalemleri. per_person: bilet başına, event: etkinlik geneli tek tutar.';

CREATE INDEX IF NOT EXISTS idx_event_finance_costs_event
    ON public.event_finance_costs (event_id, sort_order);

ALTER TABLE public.event_finance_costs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Super admins manage event finance costs" ON public.event_finance_costs;
CREATE POLICY "Super admins manage event finance costs"
    ON public.event_finance_costs FOR ALL
    USING (public.is_super_admin())
    WITH CHECK (public.is_super_admin());

-- Mevcut tek ortak payını bir kaleme taşı
INSERT INTO public.event_finance_costs (event_id, name, scope, share_type, share_value, sort_order)
SELECT
    s.event_id,
    COALESCE(NULLIF(btrim(s.partner_name), ''), 'Mekan'),
    'per_person',
    s.partner_share_type,
    s.partner_share_value,
    0
FROM public.event_finance_settings s
WHERE s.is_paid
  AND NOT EXISTS (
      SELECT 1 FROM public.event_finance_costs c WHERE c.event_id = s.event_id
  );

-- ============================================================
-- Kişi başı maliyet (satış snapshot)
-- ============================================================
CREATE OR REPLACE FUNCTION public.compute_event_partner_share(
    p_event_id UUID,
    p_unit_price DECIMAL
)
RETURNS DECIMAL
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (
            SELECT SUM(
                CASE
                    WHEN c.share_type = 'percent'
                        THEN ROUND(COALESCE(p_unit_price, 0) * c.share_value / 100, 2)
                    ELSE c.share_value
                END
            )
            FROM public.event_finance_costs c
            WHERE c.event_id = p_event_id
              AND c.scope = 'per_person'
        ),
        (
            SELECT CASE
                WHEN s.partner_share_type = 'percent'
                    THEN ROUND(COALESCE(p_unit_price, 0) * s.partner_share_value / 100, 2)
                ELSE s.partner_share_value
            END
            FROM public.event_finance_settings s
            WHERE s.event_id = p_event_id
        ),
        0
    )::DECIMAL;
$$;

CREATE OR REPLACE FUNCTION public.compute_event_fixed_costs(p_event_id UUID)
RETURNS DECIMAL
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (
            SELECT SUM(c.share_value)
            FROM public.event_finance_costs c
            WHERE c.event_id = p_event_id
              AND c.scope = 'event'
        ),
        0
    )::DECIMAL;
$$;

-- Satış yazarken yüzde kalem varsa kişi başı maliyeti yenile
CREATE OR REPLACE FUNCTION public.event_sales_before_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ticket_price DECIMAL;
    v_has_percent BOOLEAN;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.buyer_name IS NULL OR btrim(NEW.buyer_name) = '' THEN
            SELECT NULLIF(btrim(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')), '')
            INTO NEW.buyer_name
            FROM public.users u
            WHERE u.id = NEW.user_id;
            NEW.buyer_name := COALESCE(NEW.buyer_name, 'Bilinmiyor');
        END IF;

        IF NEW.created_by IS NULL THEN
            NEW.created_by := auth.uid();
        END IF;
    END IF;

    IF NEW.sale_type = 'gift' THEN
        NEW.unit_price := 0;
    END IF;

    SELECT e.ticket_price INTO v_ticket_price
    FROM public.events e WHERE e.id = NEW.event_id;

    SELECT EXISTS (
        SELECT 1
        FROM public.event_finance_costs c
        WHERE c.event_id = NEW.event_id
          AND c.scope = 'per_person'
          AND c.share_type = 'percent'
    ) OR EXISTS (
        SELECT 1
        FROM public.event_finance_settings s
        WHERE s.event_id = NEW.event_id
          AND s.partner_share_type = 'percent'
          AND NOT EXISTS (
              SELECT 1 FROM public.event_finance_costs c WHERE c.event_id = NEW.event_id
          )
    )
    INTO v_has_percent;

    IF TG_OP = 'INSERT' THEN
        IF NEW.sale_type = 'regular' AND COALESCE(NEW.unit_price, 0) = 0 THEN
            NEW.unit_price := COALESCE(v_ticket_price, 0);
        END IF;
        IF COALESCE(NEW.partner_share_amount, 0) = 0 THEN
            NEW.partner_share_amount := public.compute_event_partner_share(
                NEW.event_id,
                CASE WHEN NEW.sale_type = 'gift' THEN COALESCE(v_ticket_price, 0) ELSE NEW.unit_price END
            );
        END IF;
    ELSIF v_has_percent
          AND NEW.unit_price IS DISTINCT FROM OLD.unit_price
          AND NEW.partner_share_amount IS NOT DISTINCT FROM OLD.partner_share_amount
          AND NEW.sale_type <> 'gift' THEN
        NEW.partner_share_amount := public.compute_event_partner_share(NEW.event_id, NEW.unit_price);
    END IF;

    NEW.total_price := ROUND(NEW.quantity * NEW.unit_price, 2);
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

-- ============================================================
-- set_event_finance: maliyet kalemleri
-- ============================================================
DROP FUNCTION IF EXISTS public.set_event_finance(UUID, BOOLEAN, DECIMAL, TEXT, TEXT, DECIMAL, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION public.set_event_finance(
    p_event_id UUID,
    p_is_paid BOOLEAN,
    p_ticket_price DECIMAL DEFAULT NULL,
    p_partner_name TEXT DEFAULT NULL,
    p_partner_share_type TEXT DEFAULT 'fixed',
    p_partner_share_value DECIMAL DEFAULT 0,
    p_notes TEXT DEFAULT NULL,
    p_apply_to_unpaid BOOLEAN DEFAULT false,
    p_costs JSONB DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_item JSONB;
    v_first_name TEXT;
    v_first_type TEXT := 'fixed';
    v_first_value DECIMAL := 0;
    v_sort INTEGER := 0;
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Bu işlem için yetkiniz yok';
    END IF;

    IF p_is_paid AND (p_ticket_price IS NULL OR p_ticket_price < 0) THEN
        RAISE EXCEPTION 'Ücretli etkinlik için geçerli bir katılım ücreti girin';
    END IF;

    IF p_costs IS NOT NULL THEN
        DELETE FROM public.event_finance_costs WHERE event_id = p_event_id;

        IF jsonb_typeof(p_costs) = 'array' THEN
            FOR v_item IN SELECT value FROM jsonb_array_elements(p_costs)
            LOOP
                INSERT INTO public.event_finance_costs (
                    event_id, name, scope, share_type, share_value, sort_order
                )
                VALUES (
                    p_event_id,
                    COALESCE(NULLIF(btrim(v_item->>'name'), ''), 'Gider'),
                    COALESCE(NULLIF(v_item->>'scope', ''), 'per_person'),
                    COALESCE(NULLIF(v_item->>'share_type', ''), 'fixed'),
                    COALESCE((v_item->>'share_value')::DECIMAL, 0),
                    v_sort
                );
                IF v_sort = 0 THEN
                    v_first_name := COALESCE(NULLIF(btrim(v_item->>'name'), ''), 'Gider');
                    v_first_type := COALESCE(NULLIF(v_item->>'share_type', ''), 'fixed');
                    v_first_value := COALESCE((v_item->>'share_value')::DECIMAL, 0);
                END IF;
                v_sort := v_sort + 1;
            END LOOP;
        END IF;
    ELSIF p_is_paid THEN
        v_first_name := NULLIF(btrim(COALESCE(p_partner_name, '')), '');
        v_first_type := COALESCE(p_partner_share_type, 'fixed');
        v_first_value := COALESCE(p_partner_share_value, 0);

        IF NOT EXISTS (
            SELECT 1 FROM public.event_finance_costs WHERE event_id = p_event_id
        ) AND COALESCE(v_first_value, 0) > 0 THEN
            INSERT INTO public.event_finance_costs (
                event_id, name, scope, share_type, share_value, sort_order
            )
            VALUES (
                p_event_id,
                COALESCE(v_first_name, 'Mekan'),
                'per_person',
                v_first_type,
                v_first_value,
                0
            );
        END IF;
    END IF;

    IF v_first_name IS NULL THEN
        SELECT c.name, c.share_type, c.share_value
        INTO v_first_name, v_first_type, v_first_value
        FROM public.event_finance_costs c
        WHERE c.event_id = p_event_id
        ORDER BY c.sort_order
        LIMIT 1;
    END IF;

    INSERT INTO public.event_finance_settings (
        event_id, is_paid, partner_name, partner_share_type, partner_share_value, notes, created_by
    )
    VALUES (
        p_event_id,
        p_is_paid,
        v_first_name,
        COALESCE(v_first_type, 'fixed'),
        COALESCE(v_first_value, 0),
        NULLIF(btrim(COALESCE(p_notes, '')), ''),
        auth.uid()
    )
    ON CONFLICT (event_id) DO UPDATE SET
        is_paid = EXCLUDED.is_paid,
        partner_name = EXCLUDED.partner_name,
        partner_share_type = EXCLUDED.partner_share_type,
        partner_share_value = EXCLUDED.partner_share_value,
        notes = EXCLUDED.notes,
        updated_at = NOW();

    UPDATE public.events
    SET ticket_price = CASE WHEN p_is_paid THEN p_ticket_price ELSE NULL END
    WHERE id = p_event_id;

    IF p_is_paid THEN
        INSERT INTO public.event_sales (event_id, user_id, buyer_name, source, created_by)
        SELECT ep.event_id, ep.user_id, '', 'rsvp', auth.uid()
        FROM public.event_participants ep
        WHERE ep.event_id = p_event_id
          AND ep.status = 'going'
        ON CONFLICT (event_id, user_id) WHERE user_id IS NOT NULL
        DO UPDATE SET status = 'pending'
        WHERE public.event_sales.status = 'cancelled'
          AND public.event_sales.source = 'rsvp';

        IF p_apply_to_unpaid THEN
            UPDATE public.event_sales es
            SET unit_price = p_ticket_price,
                partner_share_amount = public.compute_event_partner_share(p_event_id, p_ticket_price)
            WHERE es.event_id = p_event_id
              AND es.status <> 'cancelled'
              AND es.sale_type = 'regular'
              AND es.paid_amount = 0;
        END IF;
    ELSE
        DELETE FROM public.event_finance_costs WHERE event_id = p_event_id;
        UPDATE public.event_sales
        SET status = 'cancelled'
        WHERE event_id = p_event_id
          AND source = 'rsvp'
          AND status <> 'cancelled'
          AND paid_amount = 0;
    END IF;
END;
$$;

-- ============================================================
-- Raporlar: etkinlik geneli gideri de kârdan düş
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_event_finance_overview(
    p_from DATE DEFAULT NULL,
    p_to DATE DEFAULT NULL
)
RETURNS TABLE (
    event_id UUID,
    title TEXT,
    start_time TIMESTAMPTZ,
    event_status TEXT,
    is_paid BOOLEAN,
    ticket_price DECIMAL,
    partner_name TEXT,
    participant_count INTEGER,
    paid_count INTEGER,
    gift_count INTEGER,
    total_sales DECIMAL,
    total_partner_share DECIMAL,
    net_profit DECIMAL,
    total_paid DECIMAL,
    outstanding DECIMAL
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Bu rapora erişim yetkiniz yok';
    END IF;

    RETURN QUERY
    WITH agg AS (
        SELECT
            es.event_id AS eid,
            COALESCE(SUM(es.quantity), 0)::INTEGER AS qty,
            COUNT(*) FILTER (WHERE es.paid_amount >= es.total_price AND es.sale_type <> 'gift')::INTEGER AS paid_cnt,
            COALESCE(SUM(es.quantity) FILTER (WHERE es.sale_type = 'gift'), 0)::INTEGER AS gift_qty,
            COALESCE(SUM(es.total_price), 0)::DECIMAL AS sales_total,
            COALESCE(SUM(es.quantity * es.partner_share_amount), 0)::DECIMAL AS share_total,
            COALESCE(SUM(es.paid_amount), 0)::DECIMAL AS paid_total
        FROM public.event_sales es
        WHERE es.status <> 'cancelled'
        GROUP BY es.event_id
    ),
    fixed AS (
        SELECT c.event_id AS eid, COALESCE(SUM(c.share_value), 0)::DECIMAL AS event_cost
        FROM public.event_finance_costs c
        WHERE c.scope = 'event'
        GROUP BY c.event_id
    )
    SELECT
        e.id,
        e.title,
        e.start_time,
        e.status::TEXT,
        COALESCE(s.is_paid, false),
        e.ticket_price,
        s.partner_name,
        COALESCE(agg.qty, 0),
        COALESCE(agg.paid_cnt, 0),
        COALESCE(agg.gift_qty, 0),
        COALESCE(agg.sales_total, 0)::DECIMAL,
        (COALESCE(agg.share_total, 0) + COALESCE(fixed.event_cost, 0))::DECIMAL,
        (COALESCE(agg.sales_total, 0) - COALESCE(agg.share_total, 0) - COALESCE(fixed.event_cost, 0))::DECIMAL,
        COALESCE(agg.paid_total, 0)::DECIMAL,
        (COALESCE(agg.sales_total, 0) - COALESCE(agg.paid_total, 0))::DECIMAL
    FROM public.events e
    LEFT JOIN public.event_finance_settings s ON s.event_id = e.id
    LEFT JOIN agg ON agg.eid = e.id
    LEFT JOIN fixed ON fixed.eid = e.id
    WHERE (s.event_id IS NOT NULL OR agg.eid IS NOT NULL)
      AND (p_from IS NULL OR (e.start_time AT TIME ZONE 'Europe/Istanbul')::date >= p_from)
      AND (p_to IS NULL OR (e.start_time AT TIME ZONE 'Europe/Istanbul')::date <= p_to)
    ORDER BY e.start_time DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_event_finance_detail(p_event_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event JSONB;
    v_settings JSONB;
    v_costs JSONB;
    v_summary JSONB;
    v_sales JSONB;
    v_event_fixed DECIMAL := 0;
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Bu rapora erişim yetkiniz yok';
    END IF;

    SELECT jsonb_build_object(
        'id', e.id,
        'title', e.title,
        'start_time', e.start_time,
        'status', e.status,
        'ticket_price', e.ticket_price,
        'location_name', e.location_name
    )
    INTO v_event
    FROM public.events e
    WHERE e.id = p_event_id;

    IF v_event IS NULL THEN
        RAISE EXCEPTION 'Etkinlik bulunamadı';
    END IF;

    SELECT to_jsonb(s) - 'created_by' - 'created_at'
    INTO v_settings
    FROM public.event_finance_settings s
    WHERE s.event_id = p_event_id;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', c.id,
            'event_id', c.event_id,
            'name', c.name,
            'scope', c.scope,
            'share_type', c.share_type,
            'share_value', c.share_value,
            'sort_order', c.sort_order
        )
        ORDER BY c.sort_order, c.created_at
    ), '[]'::jsonb)
    INTO v_costs
    FROM public.event_finance_costs c
    WHERE c.event_id = p_event_id;

    IF v_settings IS NOT NULL THEN
        v_settings := v_settings || jsonb_build_object('costs', v_costs);
    END IF;

    v_event_fixed := public.compute_event_fixed_costs(p_event_id);

    SELECT jsonb_build_object(
        'participant_count', COALESCE(SUM(es.quantity), 0),
        'regular_count', COALESCE(SUM(es.quantity) FILTER (WHERE es.sale_type = 'regular'), 0),
        'discounted_count', COALESCE(SUM(es.quantity) FILTER (WHERE es.sale_type = 'discounted'), 0),
        'gift_count', COALESCE(SUM(es.quantity) FILTER (WHERE es.sale_type = 'gift'), 0),
        'total_sales', COALESCE(SUM(es.total_price), 0),
        'total_partner_share', COALESCE(SUM(es.quantity * es.partner_share_amount), 0) + v_event_fixed,
        'per_person_cost', COALESCE(SUM(es.quantity * es.partner_share_amount), 0),
        'event_fixed_cost', v_event_fixed,
        'net_profit', COALESCE(SUM(es.total_price), 0)
            - COALESCE(SUM(es.quantity * es.partner_share_amount), 0)
            - v_event_fixed,
        'total_paid', COALESCE(SUM(es.paid_amount), 0),
        'outstanding', COALESCE(SUM(es.total_price), 0) - COALESCE(SUM(es.paid_amount), 0)
    )
    INTO v_summary
    FROM public.event_sales es
    WHERE es.event_id = p_event_id
      AND es.status <> 'cancelled';

    IF v_summary IS NULL THEN
        v_summary := jsonb_build_object(
            'participant_count', 0,
            'regular_count', 0,
            'discounted_count', 0,
            'gift_count', 0,
            'total_sales', 0,
            'total_partner_share', v_event_fixed,
            'per_person_cost', 0,
            'event_fixed_cost', v_event_fixed,
            'net_profit', -v_event_fixed,
            'total_paid', 0,
            'outstanding', 0
        );
    END IF;

    SELECT COALESCE(jsonb_agg(row_data ORDER BY sort_cancelled, sort_name), '[]'::jsonb)
    INTO v_sales
    FROM (
        SELECT
            (es.status = 'cancelled') AS sort_cancelled,
            lower(COALESCE(
                NULLIF(btrim(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')), ''),
                es.buyer_name
            )) AS sort_name,
            jsonb_build_object(
                'id', es.id,
                'event_id', es.event_id,
                'user_id', es.user_id,
                'buyer_name', COALESCE(
                    NULLIF(btrim(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')), ''),
                    es.buyer_name
                ),
                'avatar_url', u.avatar_url,
                'source', es.source,
                'quantity', es.quantity,
                'unit_price', es.unit_price,
                'partner_share_amount', es.partner_share_amount,
                'total_price', es.total_price,
                'total_partner_share', es.quantity * es.partner_share_amount,
                'net', es.total_price - es.quantity * es.partner_share_amount,
                'sale_type', es.sale_type,
                'status', es.status,
                'paid_amount', es.paid_amount,
                'outstanding', es.total_price - es.paid_amount,
                'payment_method', es.payment_method,
                'payment_date', es.payment_date,
                'notes', es.notes,
                'created_at', es.created_at,
                'rsvp_status', ep.status,
                'checked_in', COALESCE(ep.checked_in, false)
            ) AS row_data
        FROM public.event_sales es
        LEFT JOIN public.users u ON u.id = es.user_id
        LEFT JOIN public.event_participants ep
            ON ep.event_id = es.event_id AND ep.user_id = es.user_id
        WHERE es.event_id = p_event_id
    ) t;

    RETURN jsonb_build_object(
        'event', v_event,
        'settings', v_settings,
        'costs', v_costs,
        'summary', v_summary,
        'sales', v_sales
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_finance_overview(
    p_from DATE DEFAULT NULL,
    p_to DATE DEFAULT NULL
)
RETURNS TABLE (
    source TEXT,
    ref_id UUID,
    title TEXT,
    ref_date DATE,
    quantity INTEGER,
    gross DECIMAL,
    cost DECIMAL,
    net DECIMAL,
    collected DECIMAL,
    outstanding DECIMAL
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Bu rapora erişim yetkiniz yok';
    END IF;

    RETURN QUERY
    WITH prod AS (
        SELECT
            b.listing_id AS lid,
            SUM(i.quantity)::INTEGER AS qty,
            SUM(i.quantity * b.unit_cost)::DECIMAL AS cost
        FROM public.production_batches b
        JOIN public.production_batch_items i ON i.batch_id = b.id
        GROUP BY b.listing_id
    ),
    ord AS (
        SELECT
            o.listing_id AS lid,
            o.quantity,
            o.total_price,
            o.paid_amount,
            CASE WHEN p.qty > 0 THEN ROUND(p.cost / p.qty, 2) ELSE 0 END AS eff_unit_cost,
            COALESCE(o.order_date, o.created_at::date) AS eff_date
        FROM public.marketplace_orders o
        LEFT JOIN prod p ON p.lid = o.listing_id
        WHERE o.status <> 'cancelled'
    ),
    market AS (
        SELECT
            'market'::TEXT AS src,
            ml.id AS rid,
            ml.title AS ttl,
            MAX(ord.eff_date) AS dt,
            COALESCE(SUM(ord.quantity), 0)::INTEGER AS qty,
            COALESCE(SUM(ord.total_price), 0)::DECIMAL AS gross_total,
            COALESCE(SUM(ord.quantity * ord.eff_unit_cost), 0)::DECIMAL AS cost_total,
            COALESCE(SUM(ord.paid_amount), 0)::DECIMAL AS paid_total
        FROM ord
        JOIN public.marketplace_listings ml ON ml.id = ord.lid
        WHERE (p_from IS NULL OR ord.eff_date >= p_from)
          AND (p_to IS NULL OR ord.eff_date <= p_to)
        GROUP BY ml.id, ml.title
    ),
    ev AS (
        SELECT
            'event'::TEXT AS src,
            e.id AS rid,
            e.title AS ttl,
            (e.start_time AT TIME ZONE 'Europe/Istanbul')::date AS dt,
            COALESCE(SUM(es.quantity), 0)::INTEGER AS qty,
            COALESCE(SUM(es.total_price), 0)::DECIMAL AS gross_total,
            (
                COALESCE(SUM(es.quantity * es.partner_share_amount), 0)
                + public.compute_event_fixed_costs(e.id)
            )::DECIMAL AS cost_total,
            COALESCE(SUM(es.paid_amount), 0)::DECIMAL AS paid_total
        FROM public.event_sales es
        JOIN public.events e ON e.id = es.event_id
        WHERE es.status <> 'cancelled'
          AND (p_from IS NULL OR (e.start_time AT TIME ZONE 'Europe/Istanbul')::date >= p_from)
          AND (p_to IS NULL OR (e.start_time AT TIME ZONE 'Europe/Istanbul')::date <= p_to)
        GROUP BY e.id, e.title, e.start_time
    ),
    combined AS (
        SELECT * FROM market
        UNION ALL
        SELECT * FROM ev
    )
    SELECT
        c.src,
        c.rid,
        c.ttl,
        c.dt,
        c.qty,
        c.gross_total,
        c.cost_total,
        (c.gross_total - c.cost_total)::DECIMAL,
        c.paid_total,
        (c.gross_total - c.paid_total)::DECIMAL
    FROM combined c
    ORDER BY c.dt DESC NULLS LAST, c.ttl ASC;
END;
$$;

COMMENT ON FUNCTION public.get_finance_overview(DATE, DATE) IS
    'Genel kasa raporu. Etkinlik maliyeti = kişi başı giderler + etkinlik geneli giderler.';

GRANT EXECUTE ON FUNCTION public.set_event_finance(UUID, BOOLEAN, DECIMAL, TEXT, TEXT, DECIMAL, TEXT, BOOLEAN, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compute_event_fixed_costs(UUID) TO authenticated;
