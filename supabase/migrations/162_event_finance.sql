-- TCR Migration 162: Ücretli etkinlik ve genel kasa raporu
-- Amaç:
-- - Etkinlikleri ücretli olarak açabilmek (katılım ücreti + ortak/mekan payı)
-- - "Katılıyorum" diyen üyeleri otomatik satış kaydına çevirmek
-- - Manuel katılımcı (üye veya ad-soyad) ekleyebilmek
-- - Market ve etkinlik gelirlerini tek kasa raporunda birleştirmek
--
-- Finansal veriler yalnızca super_admin rolüne açıktır (koçlar göremez).

-- ============================================================
-- 0) Yardımcı: super admin kontrolü
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.has_role(auth.uid(), 'super_admin');
$$;

COMMENT ON FUNCTION public.is_super_admin() IS
    'Oturumdaki kullanıcı super_admin mi? Finans tabloları ve raporları bu kontrolü kullanır.';

-- ============================================================
-- 1) events.ticket_price (üyelere gösterilen katılım ücreti)
-- ============================================================
ALTER TABLE public.events
    ADD COLUMN IF NOT EXISTS ticket_price DECIMAL(10,2);

ALTER TABLE public.events
    DROP CONSTRAINT IF EXISTS events_ticket_price_check;
ALTER TABLE public.events
    ADD CONSTRAINT events_ticket_price_check
    CHECK (ticket_price IS NULL OR ticket_price >= 0);

COMMENT ON COLUMN public.events.ticket_price IS
    'Ücretli etkinlik katılım ücreti. NULL ise etkinlik ücretsizdir. set_event_finance ile yönetilir.';

-- ============================================================
-- 2) event_finance_settings (yalnızca admin)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.event_finance_settings (
    event_id UUID PRIMARY KEY REFERENCES public.events(id) ON DELETE CASCADE,
    is_paid BOOLEAN NOT NULL DEFAULT true,
    partner_name TEXT,
    partner_share_type TEXT NOT NULL DEFAULT 'fixed',
    partner_share_value DECIMAL(10,2) NOT NULL DEFAULT 0,
    notes TEXT,
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT event_finance_settings_share_type_check
        CHECK (partner_share_type IN ('fixed', 'percent')),
    CONSTRAINT event_finance_settings_share_value_check
        CHECK (
            partner_share_value >= 0
            AND (partner_share_type <> 'percent' OR partner_share_value <= 100)
        )
);

COMMENT ON TABLE public.event_finance_settings IS
    'Ücretli etkinlik ayarları: ortak (mekan) adı ve kişi başı ortak payı.';
COMMENT ON COLUMN public.event_finance_settings.partner_share_type IS
    'fixed: kişi başı sabit tutar, percent: katılım ücretinin yüzdesi.';

ALTER TABLE public.event_finance_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Super admins manage event finance settings" ON public.event_finance_settings;
CREATE POLICY "Super admins manage event finance settings"
    ON public.event_finance_settings FOR ALL
    USING (public.is_super_admin())
    WITH CHECK (public.is_super_admin());

-- ============================================================
-- 3) event_sales (yalnızca admin)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.event_sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    buyer_name TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'manual',
    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price DECIMAL(10,2) NOT NULL DEFAULT 0,
    partner_share_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    total_price DECIMAL(10,2) NOT NULL DEFAULT 0,
    sale_type TEXT NOT NULL DEFAULT 'regular',
    status TEXT NOT NULL DEFAULT 'pending',
    paid_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    payment_method TEXT,
    payment_date DATE,
    notes TEXT,
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT event_sales_buyer_name_check CHECK (btrim(buyer_name) <> ''),
    CONSTRAINT event_sales_source_check CHECK (source IN ('rsvp', 'manual')),
    CONSTRAINT event_sales_quantity_check CHECK (quantity > 0),
    CONSTRAINT event_sales_amounts_check CHECK (
        unit_price >= 0 AND partner_share_amount >= 0 AND total_price >= 0 AND paid_amount >= 0
    ),
    CONSTRAINT event_sales_sale_type_check CHECK (sale_type IN ('regular', 'discounted', 'gift')),
    CONSTRAINT event_sales_status_check CHECK (status IN ('pending', 'confirmed', 'cancelled')),
    CONSTRAINT event_sales_payment_method_check CHECK (
        payment_method IS NULL
        OR payment_method IN ('cash', 'transfer', 'card', 'hand', 'other')
    )
);

COMMENT ON TABLE public.event_sales IS
    'Etkinlik katılım satışları. RSVP ile otomatik veya admin tarafından manuel eklenir.';
COMMENT ON COLUMN public.event_sales.buyer_name IS
    'Alıcı adı snapshot. Üye silinse bile kayıt okunabilir kalır.';
COMMENT ON COLUMN public.event_sales.partner_share_amount IS
    'Birim başına ortağa (mekana) ödenecek tutar (satış anındaki snapshot).';
COMMENT ON COLUMN public.event_sales.status IS
    'pending: katılım bekleniyor, confirmed: katıldı / onaylandı, cancelled: iptal.';

CREATE UNIQUE INDEX IF NOT EXISTS idx_event_sales_event_user
    ON public.event_sales (event_id, user_id)
    WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_event_sales_event_status
    ON public.event_sales (event_id, status);

ALTER TABLE public.event_sales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Super admins manage event sales" ON public.event_sales;
CREATE POLICY "Super admins manage event sales"
    ON public.event_sales FOR ALL
    USING (public.is_super_admin())
    WITH CHECK (public.is_super_admin());

-- ============================================================
-- 4) Ortak payı hesaplama
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

-- ============================================================
-- 5) event_sales BEFORE trigger: varsayılanlar ve toplam
-- ============================================================
CREATE OR REPLACE FUNCTION public.event_sales_before_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ticket_price DECIMAL;
    v_share_type TEXT;
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

    SELECT s.partner_share_type INTO v_share_type
    FROM public.event_finance_settings s WHERE s.event_id = NEW.event_id;

    IF TG_OP = 'INSERT' THEN
        -- İstemci 0 gönderdiyse ve normal satışsa etkinlik ücretini kullan
        IF NEW.sale_type = 'regular' AND COALESCE(NEW.unit_price, 0) = 0 THEN
            NEW.unit_price := COALESCE(v_ticket_price, 0);
        END IF;
        IF COALESCE(NEW.partner_share_amount, 0) = 0 THEN
            -- Hediye katılımda ortak payı liste fiyatı üzerinden hesaplanır
            NEW.partner_share_amount := public.compute_event_partner_share(
                NEW.event_id,
                CASE WHEN NEW.sale_type = 'gift' THEN COALESCE(v_ticket_price, 0) ELSE NEW.unit_price END
            );
        END IF;
    ELSIF v_share_type = 'percent'
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

DROP TRIGGER IF EXISTS trg_event_sales_before_write ON public.event_sales;
CREATE TRIGGER trg_event_sales_before_write
    BEFORE INSERT OR UPDATE ON public.event_sales
    FOR EACH ROW
    EXECUTE FUNCTION public.event_sales_before_write();

-- ============================================================
-- 6) RSVP -> satış senkronizasyonu
-- ============================================================
CREATE OR REPLACE FUNCTION public.sync_event_sale_from_participant()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_paid BOOLEAN;
    v_event_id UUID;
    v_user_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_event_id := OLD.event_id;
        v_user_id := OLD.user_id;
    ELSE
        v_event_id := NEW.event_id;
        v_user_id := NEW.user_id;
    END IF;

    SELECT s.is_paid INTO v_is_paid
    FROM public.event_finance_settings s
    WHERE s.event_id = v_event_id;

    IF NOT COALESCE(v_is_paid, false) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'DELETE' AND NEW.status = 'going' THEN
        INSERT INTO public.event_sales (event_id, user_id, buyer_name, source, created_by)
        VALUES (v_event_id, v_user_id, '', 'rsvp', v_user_id)
        ON CONFLICT (event_id, user_id) WHERE user_id IS NOT NULL
        DO UPDATE SET status = 'pending'
        WHERE public.event_sales.status = 'cancelled';
    ELSE
        -- Ödeme alınmış satışlar korunur; iade kararı admin'de
        UPDATE public.event_sales
        SET status = 'cancelled'
        WHERE event_id = v_event_id
          AND user_id = v_user_id
          AND source = 'rsvp'
          AND status <> 'cancelled'
          AND paid_amount = 0;
    END IF;

    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.sync_event_sale_from_participant() IS
    'Ücretli etkinlikte going olan katılımcı için satış açar; vazgeçerse ödenmemiş satışı iptal eder.';

DROP TRIGGER IF EXISTS trg_sync_event_sale_from_participant ON public.event_participants;
CREATE TRIGGER trg_sync_event_sale_from_participant
    AFTER INSERT OR UPDATE OF status OR DELETE ON public.event_participants
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_event_sale_from_participant();

-- ============================================================
-- 7) set_event_finance: ayarları kaydet + geriye dönük satış
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_event_finance(
    p_event_id UUID,
    p_is_paid BOOLEAN,
    p_ticket_price DECIMAL DEFAULT NULL,
    p_partner_name TEXT DEFAULT NULL,
    p_partner_share_type TEXT DEFAULT 'fixed',
    p_partner_share_value DECIMAL DEFAULT 0,
    p_notes TEXT DEFAULT NULL,
    p_apply_to_unpaid BOOLEAN DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Bu işlem için yetkiniz yok';
    END IF;

    IF p_is_paid AND (p_ticket_price IS NULL OR p_ticket_price < 0) THEN
        RAISE EXCEPTION 'Ücretli etkinlik için geçerli bir katılım ücreti girin';
    END IF;

    INSERT INTO public.event_finance_settings (
        event_id, is_paid, partner_name, partner_share_type, partner_share_value, notes, created_by
    )
    VALUES (
        p_event_id,
        p_is_paid,
        NULLIF(btrim(COALESCE(p_partner_name, '')), ''),
        COALESCE(p_partner_share_type, 'fixed'),
        COALESCE(p_partner_share_value, 0),
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
        UPDATE public.event_sales
        SET status = 'cancelled'
        WHERE event_id = p_event_id
          AND source = 'rsvp'
          AND status <> 'cancelled'
          AND paid_amount = 0;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.set_event_finance(UUID, BOOLEAN, DECIMAL, TEXT, TEXT, DECIMAL, TEXT, BOOLEAN) IS
    'Etkinlik ücret ayarlarını kaydeder. Ücretli yapılırsa mevcut katılımcılar için satış açar; '
    'p_apply_to_unpaid true ise ödenmemiş normal satışların fiyatını günceller.';

-- ============================================================
-- 8) Etkinlik finans özeti
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
        COALESCE(agg.share_total, 0)::DECIMAL,
        (COALESCE(agg.sales_total, 0) - COALESCE(agg.share_total, 0))::DECIMAL,
        COALESCE(agg.paid_total, 0)::DECIMAL,
        (COALESCE(agg.sales_total, 0) - COALESCE(agg.paid_total, 0))::DECIMAL
    FROM public.events e
    LEFT JOIN public.event_finance_settings s ON s.event_id = e.id
    LEFT JOIN agg ON agg.eid = e.id
    WHERE (s.event_id IS NOT NULL OR agg.eid IS NOT NULL)
      AND (p_from IS NULL OR (e.start_time AT TIME ZONE 'Europe/Istanbul')::date >= p_from)
      AND (p_to IS NULL OR (e.start_time AT TIME ZONE 'Europe/Istanbul')::date <= p_to)
    ORDER BY e.start_time DESC;
END;
$$;

-- ============================================================
-- 9) Etkinlik finans detayı
-- ============================================================
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
    v_summary JSONB;
    v_sales JSONB;
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

    SELECT jsonb_build_object(
        'participant_count', COALESCE(SUM(es.quantity), 0),
        'regular_count', COALESCE(SUM(es.quantity) FILTER (WHERE es.sale_type = 'regular'), 0),
        'discounted_count', COALESCE(SUM(es.quantity) FILTER (WHERE es.sale_type = 'discounted'), 0),
        'gift_count', COALESCE(SUM(es.quantity) FILTER (WHERE es.sale_type = 'gift'), 0),
        'total_sales', COALESCE(SUM(es.total_price), 0),
        'total_partner_share', COALESCE(SUM(es.quantity * es.partner_share_amount), 0),
        'net_profit', COALESCE(SUM(es.total_price), 0) - COALESCE(SUM(es.quantity * es.partner_share_amount), 0),
        'total_paid', COALESCE(SUM(es.paid_amount), 0),
        'outstanding', COALESCE(SUM(es.total_price), 0) - COALESCE(SUM(es.paid_amount), 0)
    )
    INTO v_summary
    FROM public.event_sales es
    WHERE es.event_id = p_event_id
      AND es.status <> 'cancelled';

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
        'summary', v_summary,
        'sales', v_sales
    );
END;
$$;

-- ============================================================
-- 10) Genel kasa özeti: market + etkinlik
-- ============================================================
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
            COALESCE(SUM(es.quantity * es.partner_share_amount), 0)::DECIMAL AS cost_total,
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
    'Genel kasa raporu. Market satırlarında maliyet = satılan malın maliyeti (COGS), '
    'etkinlik satırlarında maliyet = ortak (mekan) payı.';

GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_event_finance(UUID, BOOLEAN, DECIMAL, TEXT, TEXT, DECIMAL, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_event_finance_overview(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_event_finance_detail(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_finance_overview(DATE, DATE) TO authenticated;
