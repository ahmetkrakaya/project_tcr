-- =====================================================
-- 165: Market paket (bundle) ürünleri
-- =====================================================
-- Amaç:
-- - Birden fazla ürünü (ör. TCR Forma + TCR Buff) tek paket olarak satmak
-- - Paketin kendi fiziksel stoğu yoktur; satılabilir adet bileşenlerden hesaplanır:
--     paket stoğu = MIN( Σ_kova floor(bileşen_kova_stoğu / paketteki_adet) )
-- - Paket satışı her bileşenin seçilen beden/cinsiyet kovasından stok düşer
-- - Bileşen tek başına satıldığında paket stoğu otomatik güncellenir
--
-- Sipariş tarafı: marketplace_orders.bundle_selections satış anındaki bileşen
-- seçimlerinin kopyasıdır. Paket tanımı sonradan değişse bile iade/iptal doğru
-- kovaya yapılır.
--   [{"listing_id": "..", "title": "TCR Forma", "size": "M", "gender": "male", "qty": 1}, ...]

-- =====================
-- 1) Şema
-- =====================
ALTER TABLE public.marketplace_listings
    ADD COLUMN IF NOT EXISTS is_bundle BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.marketplace_listings.is_bundle IS
    'true ise ürün bir pakettir; stoğu listing_bundle_items bileşenlerinden hesaplanır.';

CREATE TABLE IF NOT EXISTS public.listing_bundle_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bundle_listing_id UUID NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
    component_listing_id UUID NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT listing_bundle_items_unique UNIQUE (bundle_listing_id, component_listing_id),
    CONSTRAINT listing_bundle_items_not_self CHECK (bundle_listing_id <> component_listing_id)
);

CREATE INDEX IF NOT EXISTS idx_listing_bundle_items_component
    ON public.listing_bundle_items (component_listing_id);

COMMENT ON TABLE public.listing_bundle_items IS
    'Paket ürünün bileşenleri ve paket başına adetleri.';

ALTER TABLE public.marketplace_orders
    ADD COLUMN IF NOT EXISTS bundle_selections JSONB;

COMMENT ON COLUMN public.marketplace_orders.bundle_selections IS
    'Paket satışında bileşen seçimlerinin kopyası: [{listing_id, title, size, gender, qty}]. '
    'Paket olmayan siparişlerde NULL.';

-- =====================
-- 2) RLS
-- =====================
ALTER TABLE public.listing_bundle_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view bundle items" ON public.listing_bundle_items;
CREATE POLICY "Anyone can view bundle items"
    ON public.listing_bundle_items FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Admins can manage bundle items" ON public.listing_bundle_items;
CREATE POLICY "Admins can manage bundle items"
    ON public.listing_bundle_items FOR ALL
    USING (public.is_admin_or_coach())
    WITH CHECK (public.is_admin_or_coach());

GRANT SELECT ON public.listing_bundle_items TO authenticated, anon;

-- Paket alıcılarının bileşen beden/stokunu görebilmesi için
-- aktif ilanların stok satırları herkese açık okunur.
DROP POLICY IF EXISTS "Anyone can view stock of active listings"
    ON public.listing_stock_by_size;
CREATE POLICY "Anyone can view stock of active listings"
    ON public.listing_stock_by_size FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.marketplace_listings ml
            WHERE ml.id = listing_stock_by_size.listing_id
              AND ml.status = 'active'
        )
    );

-- =====================
-- 3) Bileşen doğrulama: paket içine paket eklenemez
-- =====================
CREATE OR REPLACE FUNCTION public.validate_listing_bundle_item()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.marketplace_listings
        WHERE id = NEW.bundle_listing_id AND is_bundle
    ) THEN
        RAISE EXCEPTION 'Bileşen yalnızca paket ürüne eklenebilir';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.marketplace_listings
        WHERE id = NEW.component_listing_id AND is_bundle
    ) THEN
        RAISE EXCEPTION 'Bir paket başka bir paketin bileşeni olamaz';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_listing_bundle_item_validate ON public.listing_bundle_items;
CREATE TRIGGER on_listing_bundle_item_validate
    BEFORE INSERT OR UPDATE ON public.listing_bundle_items
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_listing_bundle_item();

-- =====================
-- 4) Paket stoğu hesaplama ve senkron
-- =====================
CREATE OR REPLACE FUNCTION public.compute_bundle_stock(p_bundle_id UUID)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(MIN(per_component), 0)::INTEGER
    FROM (
        SELECT COALESCE((
            SELECT SUM(s.quantity / bi.quantity)
            FROM public.listing_stock_by_size s
            WHERE s.listing_id = bi.component_listing_id
        ), 0) AS per_component
        FROM public.listing_bundle_items bi
        WHERE bi.bundle_listing_id = p_bundle_id
    ) t;
$$;

COMMENT ON FUNCTION public.compute_bundle_stock(UUID) IS
    'Paketin satılabilir adedi: bileşenler arasında MIN(Σ kova floor(stok / paket adedi)).';

GRANT EXECUTE ON FUNCTION public.compute_bundle_stock(UUID) TO authenticated;

-- Paket satırının stock_quantity alanı her zaman hesaplanan değerdir;
-- istemci yanlışlıkla stok yazsa bile ezilir.
CREATE OR REPLACE FUNCTION public.enforce_bundle_stock_quantity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.is_bundle THEN
        NEW.stock_quantity := public.compute_bundle_stock(NEW.id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_listing_bundle_stock_enforce ON public.marketplace_listings;
CREATE TRIGGER on_listing_bundle_stock_enforce
    BEFORE INSERT OR UPDATE ON public.marketplace_listings
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_bundle_stock_quantity();

CREATE OR REPLACE FUNCTION public.refresh_bundle_stock(p_component_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.marketplace_listings ml
    SET stock_quantity = public.compute_bundle_stock(ml.id)
    WHERE ml.is_bundle
      AND ml.id IN (
          SELECT bi.bundle_listing_id
          FROM public.listing_bundle_items bi
          WHERE bi.component_listing_id = p_component_id
      )
      AND ml.stock_quantity IS DISTINCT FROM public.compute_bundle_stock(ml.id);
END;
$$;

COMMENT ON FUNCTION public.refresh_bundle_stock(UUID) IS
    'Bileşeni içeren paketlerin stock_quantity alanını yeniden hesaplar.';

CREATE OR REPLACE FUNCTION public.on_component_stock_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        PERFORM public.refresh_bundle_stock(OLD.listing_id);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE')
       AND (TG_OP = 'INSERT' OR NEW.listing_id IS DISTINCT FROM OLD.listing_id) THEN
        PERFORM public.refresh_bundle_stock(NEW.listing_id);
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS on_listing_stock_by_size_bundle_sync ON public.listing_stock_by_size;
CREATE TRIGGER on_listing_stock_by_size_bundle_sync
    AFTER INSERT OR UPDATE OR DELETE ON public.listing_stock_by_size
    FOR EACH ROW
    EXECUTE FUNCTION public.on_component_stock_change();

CREATE OR REPLACE FUNCTION public.on_bundle_items_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_bundle_id UUID;
BEGIN
    v_bundle_id := COALESCE(NEW.bundle_listing_id, OLD.bundle_listing_id);
    UPDATE public.marketplace_listings
    SET stock_quantity = public.compute_bundle_stock(v_bundle_id)
    WHERE id = v_bundle_id;

    IF TG_OP = 'UPDATE' AND OLD.bundle_listing_id <> NEW.bundle_listing_id THEN
        UPDATE public.marketplace_listings
        SET stock_quantity = public.compute_bundle_stock(OLD.bundle_listing_id)
        WHERE id = OLD.bundle_listing_id;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS on_listing_bundle_items_sync ON public.listing_bundle_items;
CREATE TRIGGER on_listing_bundle_items_sync
    AFTER INSERT OR UPDATE OR DELETE ON public.listing_bundle_items
    FOR EACH ROW
    EXECUTE FUNCTION public.on_bundle_items_change();

-- =====================
-- 5) Sipariş: paket seçimlerine stok deltası
-- =====================
CREATE OR REPLACE FUNCTION public.order_has_bundle_selections(p_selections JSONB)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_selections IS NOT NULL
       AND jsonb_typeof(p_selections) = 'array'
       AND jsonb_array_length(p_selections) > 0;
$$;

-- p_units: paket adedi (pozitif = stok iade, negatif = stok düş).
-- p_check: düşerken kovada yeterli stok yoksa hata ver.
CREATE OR REPLACE FUNCTION public.apply_bundle_stock_delta(
    p_selections JSONB,
    p_units INTEGER,
    p_check BOOLEAN DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sel RECORD;
    v_size TEXT;
    v_gender public.listing_gender;
    v_need INTEGER;
    v_have INTEGER;
BEGIN
    IF p_units = 0 OR NOT public.order_has_bundle_selections(p_selections) THEN
        RETURN;
    END IF;

    FOR v_sel IN
        SELECT *
        FROM jsonb_to_recordset(p_selections)
            AS x(listing_id UUID, title TEXT, size TEXT, gender TEXT, qty INTEGER)
    LOOP
        v_size := COALESCE(NULLIF(btrim(v_sel.size), ''), 'Standart');
        v_gender := COALESCE(NULLIF(v_sel.gender, ''), 'unisex')::public.listing_gender;
        v_need := p_units * GREATEST(COALESCE(v_sel.qty, 1), 1);

        IF p_check AND v_need < 0 THEN
            SELECT COALESCE(SUM(quantity), 0)
            INTO v_have
            FROM public.listing_stock_by_size
            WHERE listing_id = v_sel.listing_id
              AND size = v_size
              AND gender = v_gender;

            IF v_have < -v_need THEN
                RAISE EXCEPTION 'Yetersiz stok: % % (mevcut %, gereken %)',
                    COALESCE(v_sel.title, 'Bileşen'), v_size, v_have, -v_need
                    USING ERRCODE = 'P0001';
            END IF;
        END IF;

        PERFORM public.apply_order_stock_delta(
            v_sel.listing_id, v_size, v_gender, v_need
        );
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.apply_bundle_stock_delta(JSONB, INTEGER, BOOLEAN) IS
    'Paket siparişinin bileşen kovalarına stok deltası uygular (p_units × qty).';

-- Paket siparişinde seçim zorunlu; paket olmayan üründe seçim yasak.
CREATE OR REPLACE FUNCTION public.validate_order_bundle_selections()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_bundle BOOLEAN;
BEGIN
    SELECT is_bundle INTO v_is_bundle
    FROM public.marketplace_listings
    WHERE id = NEW.listing_id;

    IF COALESCE(v_is_bundle, false) THEN
        IF NOT public.order_has_bundle_selections(NEW.bundle_selections) THEN
            RAISE EXCEPTION 'Paket siparişi için bileşen seçimleri zorunludur';
        END IF;
    ELSIF NEW.bundle_selections IS NOT NULL THEN
        NEW.bundle_selections := NULL;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_order_bundle_validate ON public.marketplace_orders;
CREATE TRIGGER on_order_bundle_validate
    BEFORE INSERT OR UPDATE OF listing_id, bundle_selections
    ON public.marketplace_orders
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_order_bundle_selections();

-- 160'taki trigger + paket dalı
CREATE OR REPLACE FUNCTION public.manage_stock_on_order_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    old_reserved INTEGER := 0;
    new_reserved INTEGER := 0;
    old_gender public.listing_gender;
    new_gender public.listing_gender;
    old_size TEXT;
    new_size TEXT;
    same_bucket BOOLEAN;
    old_is_bundle BOOLEAN := false;
    new_is_bundle BOOLEAN := false;
BEGIN
    IF TG_OP = 'INSERT' THEN
        new_reserved := public.order_reserved_quantity(
            NEW.status, NEW.affects_stock, NEW.quantity
        );
        IF new_reserved <> 0 THEN
            IF public.order_has_bundle_selections(NEW.bundle_selections) THEN
                PERFORM public.apply_bundle_stock_delta(
                    NEW.bundle_selections, -new_reserved, true
                );
            ELSE
                PERFORM public.apply_order_stock_delta(
                    NEW.listing_id, NEW.selected_size, NEW.selected_gender, -new_reserved
                );
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        old_reserved := public.order_reserved_quantity(
            OLD.status, OLD.affects_stock, OLD.quantity
        );
        IF old_reserved <> 0 THEN
            IF public.order_has_bundle_selections(OLD.bundle_selections) THEN
                PERFORM public.apply_bundle_stock_delta(
                    OLD.bundle_selections, old_reserved, false
                );
            ELSE
                PERFORM public.apply_order_stock_delta(
                    OLD.listing_id, OLD.selected_size, OLD.selected_gender, old_reserved
                );
            END IF;
        END IF;
        RETURN OLD;
    END IF;

    old_reserved := public.order_reserved_quantity(
        OLD.status, OLD.affects_stock, OLD.quantity
    );
    new_reserved := public.order_reserved_quantity(
        NEW.status, NEW.affects_stock, NEW.quantity
    );
    old_is_bundle := public.order_has_bundle_selections(OLD.bundle_selections);
    new_is_bundle := public.order_has_bundle_selections(NEW.bundle_selections);

    IF old_is_bundle OR new_is_bundle THEN
        IF old_reserved = new_reserved
           AND OLD.listing_id = NEW.listing_id
           AND OLD.bundle_selections IS NOT DISTINCT FROM NEW.bundle_selections THEN
            RETURN NEW;
        END IF;

        -- Önce eski rezervasyonu iade et, sonra yenisini (kontrollü) düş
        IF old_reserved <> 0 THEN
            IF old_is_bundle THEN
                PERFORM public.apply_bundle_stock_delta(
                    OLD.bundle_selections, old_reserved, false
                );
            ELSE
                PERFORM public.apply_order_stock_delta(
                    OLD.listing_id, OLD.selected_size, OLD.selected_gender, old_reserved
                );
            END IF;
        END IF;

        IF new_reserved <> 0 THEN
            IF new_is_bundle THEN
                PERFORM public.apply_bundle_stock_delta(
                    NEW.bundle_selections, -new_reserved, true
                );
            ELSE
                PERFORM public.apply_order_stock_delta(
                    NEW.listing_id, NEW.selected_size, NEW.selected_gender, -new_reserved
                );
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    old_gender := COALESCE(OLD.selected_gender, 'unisex'::public.listing_gender);
    new_gender := COALESCE(NEW.selected_gender, 'unisex'::public.listing_gender);
    old_size := COALESCE(NULLIF(btrim(OLD.selected_size), ''), 'Standart');
    new_size := COALESCE(NULLIF(btrim(NEW.selected_size), ''), 'Standart');

    same_bucket := OLD.listing_id = NEW.listing_id
        AND old_size = new_size
        AND old_gender = new_gender;

    IF same_bucket THEN
        IF old_reserved <> new_reserved THEN
            PERFORM public.apply_order_stock_delta(
                NEW.listing_id, NEW.selected_size, NEW.selected_gender,
                old_reserved - new_reserved
            );
        END IF;
    ELSE
        IF old_reserved <> 0 THEN
            PERFORM public.apply_order_stock_delta(
                OLD.listing_id, OLD.selected_size, OLD.selected_gender, old_reserved
            );
        END IF;
        IF new_reserved <> 0 THEN
            PERFORM public.apply_order_stock_delta(
                NEW.listing_id, NEW.selected_size, NEW.selected_gender, -new_reserved
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.manage_stock_on_order_status_change() IS
    'Sipariş INSERT/UPDATE/DELETE sonrası stok rezervasyonunu senkronize eder. '
    'Paket siparişlerinde bileşen kovalarından düşer (yetersiz stokta hata). Bildirim göndermez.';

DROP TRIGGER IF EXISTS on_order_stock_update ON public.marketplace_orders;
CREATE TRIGGER on_order_stock_update
    AFTER UPDATE OF status, quantity, selected_size, selected_gender, affects_stock, listing_id, bundle_selections
    ON public.marketplace_orders
    FOR EACH ROW
    EXECUTE FUNCTION public.manage_stock_on_order_status_change();

-- =====================
-- 6) Ortalama birim maliyet: paket = Σ bileşen ort. maliyeti × adet
-- =====================
CREATE OR REPLACE FUNCTION public.get_listing_avg_unit_cost(p_listing_id UUID)
RETURNS DECIMAL
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_bundle BOOLEAN;
    v_cost DECIMAL;
BEGIN
    SELECT is_bundle INTO v_is_bundle
    FROM public.marketplace_listings
    WHERE id = p_listing_id;

    IF COALESCE(v_is_bundle, false) THEN
        SELECT CASE
            WHEN COUNT(c.cost) = 0 THEN NULL
            ELSE ROUND(SUM(COALESCE(c.cost, 0) * c.qty), 2)
        END
        INTO v_cost
        FROM (
            SELECT
                bi.quantity AS qty,
                (
                    SELECT CASE
                        WHEN COALESCE(SUM(i.quantity), 0) = 0 THEN NULL
                        ELSE SUM(i.quantity * b.unit_cost) / SUM(i.quantity)
                    END
                    FROM public.production_batches b
                    JOIN public.production_batch_items i ON i.batch_id = b.id
                    WHERE b.listing_id = bi.component_listing_id
                ) AS cost
            FROM public.listing_bundle_items bi
            WHERE bi.bundle_listing_id = p_listing_id
        ) c;
        RETURN v_cost;
    END IF;

    SELECT CASE
        WHEN COALESCE(SUM(i.quantity), 0) = 0 THEN NULL
        ELSE ROUND(SUM(i.quantity * b.unit_cost) / SUM(i.quantity), 2)
    END
    INTO v_cost
    FROM public.production_batches b
    JOIN public.production_batch_items i ON i.batch_id = b.id
    WHERE b.listing_id = p_listing_id;

    RETURN v_cost;
END;
$$;

COMMENT ON FUNCTION public.get_listing_avg_unit_cost(UUID) IS
    'Ağırlıklı ortalama birim maliyet. Pakette bileşen maliyetleri × paket adedi toplamı.';

GRANT EXECUTE ON FUNCTION public.get_listing_avg_unit_cost(UUID) TO authenticated;

-- =====================
-- 7) Paketle satılan bileşen adetleri (rapor yardımcı view'ı)
-- =====================
CREATE OR REPLACE VIEW public.marketplace_bundle_component_sales AS
SELECT
    o.id AS order_id,
    o.listing_id AS bundle_listing_id,
    x.listing_id AS component_listing_id,
    COALESCE(NULLIF(btrim(x.size), ''), 'Standart') AS size,
    COALESCE(NULLIF(x.gender, ''), 'unisex')::public.listing_gender AS gender,
    (o.quantity * GREATEST(COALESCE(x.qty, 1), 1))::INTEGER AS quantity,
    o.status,
    o.affects_stock,
    COALESCE(o.order_date, o.created_at::date) AS eff_date
FROM public.marketplace_orders o
CROSS JOIN LATERAL jsonb_to_recordset(o.bundle_selections)
    AS x(listing_id UUID, title TEXT, size TEXT, gender TEXT, qty INTEGER)
WHERE public.order_has_bundle_selections(o.bundle_selections);

COMMENT ON VIEW public.marketplace_bundle_component_sales IS
    'Paket siparişlerinin bileşen bazlı açılımı (satır = sipariş × bileşen).';

REVOKE ALL ON public.marketplace_bundle_component_sales FROM anon, authenticated;

-- =====================
-- 8) Market özeti: paket maliyeti + bileşenlerde paketle satılan
-- =====================
DROP FUNCTION IF EXISTS public.get_market_overview(DATE, DATE);
CREATE OR REPLACE FUNCTION public.get_market_overview(
    p_from DATE DEFAULT NULL,
    p_to DATE DEFAULT NULL
)
RETURNS TABLE (
    listing_id UUID,
    title TEXT,
    image_url TEXT,
    currency TEXT,
    price DECIMAL,
    produced_quantity INTEGER,
    avg_unit_cost DECIMAL,
    total_production_cost DECIMAL,
    sold_quantity INTEGER,
    regular_quantity INTEGER,
    discounted_quantity INTEGER,
    gift_quantity INTEGER,
    total_sales DECIMAL,
    total_paid DECIMAL,
    outstanding DECIMAL,
    total_cogs DECIMAL,
    profit_vs_cogs DECIMAL,
    profit_vs_production DECIMAL,
    remaining_quantity INTEGER,
    current_stock INTEGER,
    is_bundle BOOLEAN,
    bundle_sold_quantity INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_admin_or_coach() THEN
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
    unit AS (
        SELECT l.id AS lid, public.get_listing_avg_unit_cost(l.id) AS cost
        FROM public.marketplace_listings l
        WHERE l.status <> 'deleted'
    ),
    ord AS (
        SELECT
            o.listing_id AS lid,
            o.quantity,
            o.sale_type,
            o.total_price,
            o.paid_amount,
            o.affects_stock,
            COALESCE(u.cost, 0) AS eff_unit_cost,
            COALESCE(o.order_date, o.created_at::date) AS eff_date
        FROM public.marketplace_orders o
        LEFT JOIN unit u ON u.lid = o.listing_id
        WHERE o.status <> 'cancelled'
    ),
    sales AS (
        SELECT
            ord.lid,
            COALESCE(SUM(ord.quantity), 0)::INTEGER AS total_qty,
            COALESCE(SUM(ord.quantity) FILTER (WHERE ord.sale_type = 'regular'), 0)::INTEGER AS regular_qty,
            COALESCE(SUM(ord.quantity) FILTER (WHERE ord.sale_type = 'discounted'), 0)::INTEGER AS discounted_qty,
            COALESCE(SUM(ord.quantity) FILTER (WHERE ord.sale_type = 'gift'), 0)::INTEGER AS gift_qty,
            COALESCE(SUM(ord.total_price), 0)::DECIMAL AS sales_total,
            COALESCE(SUM(ord.paid_amount), 0)::DECIMAL AS paid_total,
            COALESCE(SUM(ord.quantity * ord.eff_unit_cost), 0)::DECIMAL AS cogs_total
        FROM ord
        WHERE (p_from IS NULL OR ord.eff_date >= p_from)
          AND (p_to IS NULL OR ord.eff_date <= p_to)
        GROUP BY ord.lid
    ),
    sales_stock AS (
        SELECT
            ord.lid,
            COALESCE(
                SUM(ord.quantity) FILTER (WHERE COALESCE(ord.affects_stock, true)),
                0
            )::INTEGER AS total_qty
        FROM ord
        GROUP BY ord.lid
    ),
    bundle_period AS (
        SELECT
            bcs.component_listing_id AS lid,
            SUM(bcs.quantity)::INTEGER AS qty
        FROM public.marketplace_bundle_component_sales bcs
        WHERE bcs.status <> 'cancelled'
          AND (p_from IS NULL OR bcs.eff_date >= p_from)
          AND (p_to IS NULL OR bcs.eff_date <= p_to)
        GROUP BY bcs.component_listing_id
    ),
    bundle_stock AS (
        SELECT
            bcs.component_listing_id AS lid,
            SUM(bcs.quantity)::INTEGER AS qty
        FROM public.marketplace_bundle_component_sales bcs
        WHERE bcs.status <> 'cancelled'
          AND COALESCE(bcs.affects_stock, true)
        GROUP BY bcs.component_listing_id
    )
    SELECT
        ml.id,
        ml.title,
        (
            SELECT li.image_url
            FROM public.listing_images li
            WHERE li.listing_id = ml.id
            ORDER BY li.sort_order ASC
            LIMIT 1
        ),
        ml.currency,
        ml.price,
        COALESCE(prod.qty, 0),
        unit.cost,
        COALESCE(prod.cost, 0)::DECIMAL,
        (COALESCE(sales.regular_qty, 0) + COALESCE(sales.discounted_qty, 0)),
        COALESCE(sales.regular_qty, 0),
        COALESCE(sales.discounted_qty, 0),
        COALESCE(sales.gift_qty, 0),
        COALESCE(sales.sales_total, 0)::DECIMAL,
        COALESCE(sales.paid_total, 0)::DECIMAL,
        (COALESCE(sales.sales_total, 0) - COALESCE(sales.paid_total, 0))::DECIMAL,
        COALESCE(sales.cogs_total, 0)::DECIMAL,
        (COALESCE(sales.sales_total, 0) - COALESCE(sales.cogs_total, 0))::DECIMAL,
        (COALESCE(sales.sales_total, 0) - COALESCE(prod.cost, 0))::DECIMAL,
        CASE
            WHEN ml.is_bundle THEN COALESCE(ml.stock_quantity, 0)
            ELSE COALESCE(prod.qty, 0)
                - COALESCE(sales_stock.total_qty, 0)
                - COALESCE(bundle_stock.qty, 0)
        END,
        CASE
            WHEN ml.is_bundle THEN COALESCE(ml.stock_quantity, 0)
            ELSE COALESCE(
                (SELECT SUM(s.quantity)::INTEGER FROM public.listing_stock_by_size s WHERE s.listing_id = ml.id),
                ml.stock_quantity,
                0
            )
        END,
        ml.is_bundle,
        COALESCE(bundle_period.qty, 0)
    FROM public.marketplace_listings ml
    LEFT JOIN prod ON prod.lid = ml.id
    LEFT JOIN unit ON unit.lid = ml.id
    LEFT JOIN sales ON sales.lid = ml.id
    LEFT JOIN sales_stock ON sales_stock.lid = ml.id
    LEFT JOIN bundle_period ON bundle_period.lid = ml.id
    LEFT JOIN bundle_stock ON bundle_stock.lid = ml.id
    WHERE ml.status <> 'deleted'
    ORDER BY ml.created_at DESC;
END;
$$;

COMMENT ON FUNCTION public.get_market_overview(DATE, DATE) IS
    'Market özeti. Bileşenlerde Kalan = üretim − (tekil + paketle satış); paket satırında Kalan = paket stoğu.';

-- =====================
-- 9) Ürün raporu
-- =====================
DROP FUNCTION IF EXISTS public.get_market_product_report(UUID);
CREATE OR REPLACE FUNCTION public.get_market_product_report(p_listing_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_listing JSONB;
    v_production JSONB;
    v_sales JSONB;
    v_sizes JSONB;
    v_bundle_items JSONB := '[]'::jsonb;
    v_bundle_breakdown JSONB := '[]'::jsonb;
    v_is_bundle BOOLEAN := false;
    v_prod_qty INTEGER := 0;
    v_prod_cost DECIMAL := 0;
    v_avg_cost DECIMAL;
    v_sold_qty INTEGER := 0;
    v_stock_sold_qty INTEGER := 0;
    v_bundle_qty INTEGER := 0;
    v_bundle_stock_qty INTEGER := 0;
    v_current_stock INTEGER := 0;
    v_remaining INTEGER := 0;
BEGIN
    IF NOT public.is_admin_or_coach() THEN
        RAISE EXCEPTION 'Bu rapora erişim yetkiniz yok';
    END IF;

    SELECT
        COALESCE(SUM(i.quantity), 0),
        COALESCE(SUM(i.quantity * b.unit_cost), 0)
    INTO v_prod_qty, v_prod_cost
    FROM public.production_batches b
    JOIN public.production_batch_items i ON i.batch_id = b.id
    WHERE b.listing_id = p_listing_id;

    v_avg_cost := public.get_listing_avg_unit_cost(p_listing_id);

    SELECT
        jsonb_build_object(
            'id', ml.id,
            'title', ml.title,
            'price', ml.price,
            'currency', ml.currency,
            'stock_gender_mode', ml.stock_gender_mode,
            'is_bundle', ml.is_bundle,
            'image_url', (
                SELECT li.image_url FROM public.listing_images li
                WHERE li.listing_id = ml.id ORDER BY li.sort_order ASC LIMIT 1
            )
        ),
        ml.is_bundle
    INTO v_listing, v_is_bundle
    FROM public.marketplace_listings ml
    WHERE ml.id = p_listing_id;

    IF v_listing IS NULL THEN
        RAISE EXCEPTION 'Ürün bulunamadı';
    END IF;

    SELECT CASE
        WHEN ml.is_bundle THEN COALESCE(ml.stock_quantity, 0)
        ELSE COALESCE(
            (SELECT SUM(s.quantity)::INTEGER FROM public.listing_stock_by_size s WHERE s.listing_id = ml.id),
            ml.stock_quantity,
            0
        )
    END
    INTO v_current_stock
    FROM public.marketplace_listings ml
    WHERE ml.id = p_listing_id;

    v_production := jsonb_build_object(
        'total_quantity', v_prod_qty,
        'total_cost', v_prod_cost,
        'avg_unit_cost', v_avg_cost
    );

    WITH ord AS (
        SELECT
            o.quantity,
            o.sale_type,
            o.total_price,
            o.paid_amount,
            o.affects_stock,
            COALESCE(v_avg_cost, 0) AS eff_unit_cost
        FROM public.marketplace_orders o
        WHERE o.listing_id = p_listing_id
          AND o.status <> 'cancelled'
    )
    SELECT
        jsonb_build_object(
            'total_quantity', COALESCE(SUM(quantity), 0),
            'regular_quantity', COALESCE(SUM(quantity) FILTER (WHERE sale_type = 'regular'), 0),
            'discounted_quantity', COALESCE(SUM(quantity) FILTER (WHERE sale_type = 'discounted'), 0),
            'gift_quantity', COALESCE(SUM(quantity) FILTER (WHERE sale_type = 'gift'), 0),
            'regular_total', COALESCE(SUM(total_price) FILTER (WHERE sale_type = 'regular'), 0),
            'discounted_total', COALESCE(SUM(total_price) FILTER (WHERE sale_type = 'discounted'), 0),
            'total_sales', COALESCE(SUM(total_price), 0),
            'total_paid', COALESCE(SUM(paid_amount), 0),
            'outstanding', COALESCE(SUM(total_price), 0) - COALESCE(SUM(paid_amount), 0),
            'total_cogs', COALESCE(SUM(quantity * eff_unit_cost), 0)
        ),
        COALESCE(SUM(quantity), 0),
        COALESCE(SUM(quantity) FILTER (WHERE COALESCE(affects_stock, true)), 0)
    INTO v_sales, v_sold_qty, v_stock_sold_qty
    FROM ord;

    SELECT
        COALESCE(SUM(bcs.quantity), 0),
        COALESCE(SUM(bcs.quantity) FILTER (WHERE COALESCE(bcs.affects_stock, true)), 0)
    INTO v_bundle_qty, v_bundle_stock_qty
    FROM public.marketplace_bundle_component_sales bcs
    WHERE bcs.component_listing_id = p_listing_id
      AND bcs.status <> 'cancelled';

    v_sales := v_sales
        || jsonb_build_object(
            'bundle_quantity', v_bundle_qty,
            'profit_vs_cogs', (v_sales->>'total_sales')::DECIMAL - (v_sales->>'total_cogs')::DECIMAL,
            'profit_vs_production', (v_sales->>'total_sales')::DECIMAL - v_prod_cost
        );

    IF v_is_bundle THEN
        v_remaining := v_current_stock;

        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'listing_id', bi.component_listing_id,
                'title', c.title,
                'quantity', bi.quantity,
                'stock', COALESCE((
                    SELECT SUM(s.quantity)::INTEGER
                    FROM public.listing_stock_by_size s
                    WHERE s.listing_id = bi.component_listing_id
                ), 0)
            )
            ORDER BY bi.sort_order, c.title
        ), '[]'::jsonb)
        INTO v_bundle_items
        FROM public.listing_bundle_items bi
        JOIN public.marketplace_listings c ON c.id = bi.component_listing_id
        WHERE bi.bundle_listing_id = p_listing_id;

        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'listing_id', t.component_listing_id,
                'title', t.title,
                'size', t.size,
                'gender', t.gender,
                'quantity', t.qty
            )
            ORDER BY t.title, t.gender, t.size
        ), '[]'::jsonb)
        INTO v_bundle_breakdown
        FROM (
            SELECT
                bcs.component_listing_id,
                COALESCE(c.title, '') AS title,
                bcs.size,
                bcs.gender,
                SUM(bcs.quantity)::INTEGER AS qty
            FROM public.marketplace_bundle_component_sales bcs
            LEFT JOIN public.marketplace_listings c ON c.id = bcs.component_listing_id
            WHERE bcs.bundle_listing_id = p_listing_id
              AND bcs.status <> 'cancelled'
            GROUP BY bcs.component_listing_id, c.title, bcs.size, bcs.gender
        ) t;

        v_sizes := '[]'::jsonb;
    ELSE
        v_remaining := v_prod_qty - v_stock_sold_qty - v_bundle_stock_qty;

        WITH produced AS (
            SELECT i.size, i.gender, SUM(i.quantity)::INTEGER AS qty
            FROM public.production_batches b
            JOIN public.production_batch_items i ON i.batch_id = b.id
            WHERE b.listing_id = p_listing_id
            GROUP BY i.size, i.gender
        ),
        sold_raw AS (
            SELECT
                COALESCE(NULLIF(btrim(o.selected_size), ''), 'Standart') AS size,
                COALESCE(o.selected_gender, 'unisex'::public.listing_gender) AS gender,
                o.quantity AS qty,
                0 AS bundle_qty
            FROM public.marketplace_orders o
            WHERE o.listing_id = p_listing_id
              AND o.status <> 'cancelled'
              AND COALESCE(o.affects_stock, true)
            UNION ALL
            SELECT bcs.size, bcs.gender, bcs.quantity, bcs.quantity
            FROM public.marketplace_bundle_component_sales bcs
            WHERE bcs.component_listing_id = p_listing_id
              AND bcs.status <> 'cancelled'
              AND COALESCE(bcs.affects_stock, true)
        ),
        sold AS (
            SELECT size, gender, SUM(qty)::INTEGER AS qty, SUM(bundle_qty)::INTEGER AS bundle_qty
            FROM sold_raw
            GROUP BY size, gender
        ),
        stock AS (
            SELECT s.size, s.gender, SUM(s.quantity)::INTEGER AS qty
            FROM public.listing_stock_by_size s
            WHERE s.listing_id = p_listing_id
            GROUP BY s.size, s.gender
        ),
        keys AS (
            SELECT size, gender FROM produced
            UNION
            SELECT size, gender FROM sold
            UNION
            SELECT size, gender FROM stock
        )
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'size', k.size,
                'gender', k.gender,
                'produced', COALESCE(p.qty, 0),
                'sold', COALESCE(sd.qty, 0),
                'bundle_sold', COALESCE(sd.bundle_qty, 0),
                'remaining', COALESCE(p.qty, 0) - COALESCE(sd.qty, 0),
                'stock', COALESCE(st.qty, 0)
            )
            ORDER BY k.gender, k.size
        ), '[]'::jsonb)
        INTO v_sizes
        FROM keys k
        LEFT JOIN produced p ON p.size = k.size AND p.gender = k.gender
        LEFT JOIN sold sd ON sd.size = k.size AND sd.gender = k.gender
        LEFT JOIN stock st ON st.size = k.size AND st.gender = k.gender;
    END IF;

    RETURN jsonb_build_object(
        'listing', v_listing,
        'production', v_production,
        'sales', v_sales,
        'remaining_quantity', v_remaining,
        'current_stock', v_current_stock,
        'size_breakdown', v_sizes,
        'bundle_items', v_bundle_items,
        'bundle_breakdown', v_bundle_breakdown
    );
END;
$$;

COMMENT ON FUNCTION public.get_market_product_report(UUID) IS
    'Ürün raporu. Bileşende Kalan = üretim − (tekil + paketle satış). '
    'Pakette bileşen listesi ve bileşen/beden bazlı satış dağılımı döner.';

-- =====================
-- 10) Satış satırları: paket içeriği özeti
-- =====================
DROP FUNCTION IF EXISTS public.get_market_product_sales(UUID);
CREATE OR REPLACE FUNCTION public.get_market_product_sales(p_listing_id UUID)
RETURNS TABLE (
    order_id UUID,
    row_no INTEGER,
    buyer_id UUID,
    buyer_name TEXT,
    is_manual BOOLEAN,
    sale_type TEXT,
    size TEXT,
    gender public.listing_gender,
    quantity INTEGER,
    order_date DATE,
    delivery_date DATE,
    payment_date DATE,
    unit_cost DECIMAL,
    total_cost DECIMAL,
    unit_price DECIMAL,
    total_price DECIMAL,
    paid_amount DECIMAL,
    outstanding DECIMAL,
    profit DECIMAL,
    payment_method TEXT,
    status public.order_status,
    note TEXT,
    bundle_selections JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_avg_cost DECIMAL;
BEGIN
    IF NOT public.is_admin_or_coach() THEN
        RAISE EXCEPTION 'Bu rapora erişim yetkiniz yok';
    END IF;

    SELECT public.get_listing_avg_unit_cost(p_listing_id) INTO v_avg_cost;

    RETURN QUERY
    SELECT
        o.id,
        ROW_NUMBER() OVER (
            ORDER BY COALESCE(o.order_date, o.created_at::date) ASC, o.created_at ASC
        )::INTEGER,
        o.buyer_id,
        COALESCE(
            NULLIF(btrim(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')), ''),
            o.manual_buyer_name,
            'Bilinmiyor'
        ),
        o.is_manual,
        o.sale_type,
        o.selected_size,
        o.selected_gender,
        o.quantity,
        COALESCE(o.order_date, o.created_at::date),
        o.delivery_date,
        o.payment_date,
        v_avg_cost,
        (o.quantity * COALESCE(v_avg_cost, 0))::DECIMAL,
        COALESCE(o.unit_price, ROUND(o.total_price / GREATEST(o.quantity, 1), 2)),
        o.total_price,
        o.paid_amount,
        (o.total_price - o.paid_amount)::DECIMAL,
        (o.total_price - o.quantity * COALESCE(v_avg_cost, 0))::DECIMAL,
        o.payment_method,
        o.status,
        o.seller_note,
        o.bundle_selections
    FROM public.marketplace_orders o
    LEFT JOIN public.users u ON u.id = o.buyer_id
    WHERE o.listing_id = p_listing_id
    ORDER BY COALESCE(o.order_date, o.created_at::date) ASC, o.created_at ASC;
END;
$$;

COMMENT ON FUNCTION public.get_market_product_sales(UUID) IS
    'Ürün satış geçmişi. Maliyet canlı ort. birim maliyetten; paket satışlarında bileşen seçimleri döner.';

GRANT EXECUTE ON FUNCTION public.get_market_overview(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_market_product_report(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_market_product_sales(UUID) TO authenticated;
