-- =====================================================
-- 160: Satış adet/düzenleme stok deltasını düzelt
-- =====================================================
-- Sorun:
-- - Adet 5→3 düzenlenince rapor "Kalan" 7 oluyor ama stok 5'te kalıyordu
-- - "Stoktan düş" tekrar açılınca eski iade olmadan new_qty düşülüp stok 2 oluyordu
--
-- Kök neden:
-- - apply_order_stock_delta SECURITY DEFINER değil, UPSERT yok, size normalize yok,
--   stock_quantity senkronu yok → delta güvenilir uygulanmıyordu
--
-- Çözüm:
-- - Sipariş stok deltası üretim yoluyla aynı (DEFINER + UPSERT + Standart + sync)
-- - Rezervasyon: affects_stock AND status <> cancelled (kalan ile aynı mantık)
-- - Bildirim YOK (157: stok bildirimi yalnızca üretimden)
-- - Tek seferlik backfill: stok = üretim − (iptal dışı ∧ stoktan düşen satışlar)

-- =====================
-- 1) Sipariş stok deltası (üretimle hizalı, bildirim yok)
-- =====================
CREATE OR REPLACE FUNCTION public.apply_order_stock_delta(
    p_listing_id UUID,
    p_size TEXT,
    p_gender public.listing_gender,
    p_delta INTEGER
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_gender public.listing_gender;
    v_size TEXT;
BEGIN
    IF p_delta = 0 THEN
        RETURN;
    END IF;

    v_gender := COALESCE(p_gender, 'unisex'::public.listing_gender);
    v_size := COALESCE(NULLIF(btrim(p_size), ''), 'Standart');

    INSERT INTO public.listing_stock_by_size (listing_id, size, gender, quantity)
    VALUES (p_listing_id, v_size, v_gender, GREATEST(0, p_delta))
    ON CONFLICT (listing_id, size, gender)
    DO UPDATE SET
        quantity = GREATEST(0, public.listing_stock_by_size.quantity + p_delta),
        updated_at = NOW();

    UPDATE public.marketplace_listings
    SET stock_quantity = (
        SELECT COALESCE(SUM(s.quantity), 0)
        FROM public.listing_stock_by_size s
        WHERE s.listing_id = p_listing_id
    )
    WHERE id = p_listing_id;
END;
$$;

COMMENT ON FUNCTION public.apply_order_stock_delta(UUID, TEXT, public.listing_gender, INTEGER) IS
    'Satış stok deltası. UPSERT + stock_quantity sync. Bildirim göndermez.';

GRANT EXECUTE ON FUNCTION public.apply_order_stock_delta(UUID, TEXT, public.listing_gender, INTEGER)
    TO authenticated;

-- =====================
-- 2) Rezervasyon = kalan mantığı (iptal dışı + stoktan düş)
-- =====================
CREATE OR REPLACE FUNCTION public.order_reserved_quantity(
    p_status public.order_status,
    p_affects_stock BOOLEAN,
    p_quantity INTEGER
)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN COALESCE(p_affects_stock, true)
             AND p_status IS DISTINCT FROM 'cancelled'::public.order_status
        THEN COALESCE(p_quantity, 0)
        ELSE 0
    END;
$$;

COMMENT ON FUNCTION public.order_reserved_quantity(public.order_status, BOOLEAN, INTEGER) IS
    'Stoka yazılan adet: affects_stock true ve status <> cancelled ise quantity, aksi halde 0.';

-- =====================
-- 3) Trigger fonksiyonu (adet değişince delta = old - new)
-- =====================
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
BEGIN
    IF TG_OP = 'INSERT' THEN
        new_reserved := public.order_reserved_quantity(
            NEW.status, NEW.affects_stock, NEW.quantity
        );
        IF new_reserved <> 0 THEN
            PERFORM public.apply_order_stock_delta(
                NEW.listing_id, NEW.selected_size, NEW.selected_gender, -new_reserved
            );
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        old_reserved := public.order_reserved_quantity(
            OLD.status, OLD.affects_stock, OLD.quantity
        );
        IF old_reserved <> 0 THEN
            PERFORM public.apply_order_stock_delta(
                OLD.listing_id, OLD.selected_size, OLD.selected_gender, old_reserved
            );
        END IF;
        RETURN OLD;
    END IF;

    old_reserved := public.order_reserved_quantity(
        OLD.status, OLD.affects_stock, OLD.quantity
    );
    new_reserved := public.order_reserved_quantity(
        NEW.status, NEW.affects_stock, NEW.quantity
    );
    old_gender := COALESCE(OLD.selected_gender, 'unisex'::public.listing_gender);
    new_gender := COALESCE(NEW.selected_gender, 'unisex'::public.listing_gender);
    old_size := COALESCE(NULLIF(btrim(OLD.selected_size), ''), 'Standart');
    new_size := COALESCE(NULLIF(btrim(NEW.selected_size), ''), 'Standart');

    same_bucket := OLD.listing_id = NEW.listing_id
        AND old_size = new_size
        AND old_gender = new_gender;

    IF same_bucket THEN
        IF old_reserved <> new_reserved THEN
            -- Örn. 5→3 ve stoktan düş açık: delta = +2 (stok artar)
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
    'Adet azalınca stok artar (ör. 5→3 ⇒ +2). Bildirim göndermez.';

DROP TRIGGER IF EXISTS on_order_stock_update ON public.marketplace_orders;
CREATE TRIGGER on_order_stock_update
    AFTER UPDATE OF status, quantity, selected_size, selected_gender, affects_stock, listing_id
    ON public.marketplace_orders
    FOR EACH ROW
    EXECUTE FUNCTION public.manage_stock_on_order_status_change();

DROP TRIGGER IF EXISTS on_order_stock_insert ON public.marketplace_orders;
CREATE TRIGGER on_order_stock_insert
    AFTER INSERT ON public.marketplace_orders
    FOR EACH ROW
    EXECUTE FUNCTION public.manage_stock_on_order_status_change();

DROP TRIGGER IF EXISTS on_order_stock_delete ON public.marketplace_orders;
CREATE TRIGGER on_order_stock_delete
    AFTER DELETE ON public.marketplace_orders
    FOR EACH ROW
    EXECUTE FUNCTION public.manage_stock_on_order_status_change();

-- =====================
-- 4) Rapor "Kalan": stoktan düşmeyen satışları sayma
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
    current_stock INTEGER
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
    ord AS (
        SELECT
            o.listing_id AS lid,
            o.quantity,
            o.sale_type,
            o.total_price,
            o.paid_amount,
            o.affects_stock,
            COALESCE(
                o.unit_cost,
                CASE WHEN p.qty > 0 THEN ROUND(p.cost / p.qty, 2) ELSE 0 END
            ) AS eff_unit_cost,
            COALESCE(o.order_date, o.created_at::date) AS eff_date
        FROM public.marketplace_orders o
        LEFT JOIN prod p ON p.lid = o.listing_id
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
        -- Kalan: stoktan düşen satışlar (stok ile aynı)
        SELECT
            ord.lid,
            COALESCE(
                SUM(ord.quantity) FILTER (WHERE COALESCE(ord.affects_stock, true)),
                0
            )::INTEGER AS total_qty
        FROM ord
        GROUP BY ord.lid
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
        CASE WHEN COALESCE(prod.qty, 0) > 0 THEN ROUND(prod.cost / prod.qty, 2) ELSE NULL END,
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
        (COALESCE(prod.qty, 0) - COALESCE(sales_stock.total_qty, 0)),
        COALESCE(
            (SELECT SUM(s.quantity)::INTEGER FROM public.listing_stock_by_size s WHERE s.listing_id = ml.id),
            ml.stock_quantity,
            0
        )
    FROM public.marketplace_listings ml
    LEFT JOIN prod ON prod.lid = ml.id
    LEFT JOIN sales ON sales.lid = ml.id
    LEFT JOIN sales_stock ON sales_stock.lid = ml.id
    WHERE ml.status <> 'deleted'
    ORDER BY ml.created_at DESC;
END;
$$;

COMMENT ON FUNCTION public.get_market_overview(DATE, DATE) IS
    'Market özeti. Kalan = üretim − (iptal dışı ve stoktan düşen satışlar); stok ile aynı mantık.';

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
    v_prod_qty INTEGER := 0;
    v_prod_cost DECIMAL := 0;
    v_avg_cost DECIMAL;
    v_sold_qty INTEGER := 0;
    v_stock_sold_qty INTEGER := 0;
    v_current_stock INTEGER := 0;
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

    v_avg_cost := CASE WHEN v_prod_qty > 0 THEN ROUND(v_prod_cost / v_prod_qty, 2) ELSE NULL END;

    SELECT jsonb_build_object(
        'id', ml.id,
        'title', ml.title,
        'price', ml.price,
        'currency', ml.currency,
        'stock_gender_mode', ml.stock_gender_mode,
        'image_url', (
            SELECT li.image_url FROM public.listing_images li
            WHERE li.listing_id = ml.id ORDER BY li.sort_order ASC LIMIT 1
        )
    )
    INTO v_listing
    FROM public.marketplace_listings ml
    WHERE ml.id = p_listing_id;

    IF v_listing IS NULL THEN
        RAISE EXCEPTION 'Ürün bulunamadı';
    END IF;

    SELECT COALESCE(
        (SELECT SUM(s.quantity)::INTEGER FROM public.listing_stock_by_size s WHERE s.listing_id = ml.id),
        ml.stock_quantity,
        0
    )
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
            COALESCE(o.unit_cost, v_avg_cost, 0) AS eff_unit_cost
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

    v_sales := v_sales
        || jsonb_build_object(
            'profit_vs_cogs', (v_sales->>'total_sales')::DECIMAL - (v_sales->>'total_cogs')::DECIMAL,
            'profit_vs_production', (v_sales->>'total_sales')::DECIMAL - v_prod_cost
        );

    WITH produced AS (
        SELECT i.size, i.gender, SUM(i.quantity)::INTEGER AS qty
        FROM public.production_batches b
        JOIN public.production_batch_items i ON i.batch_id = b.id
        WHERE b.listing_id = p_listing_id
        GROUP BY i.size, i.gender
    ),
    sold AS (
        SELECT
            COALESCE(NULLIF(btrim(o.selected_size), ''), 'Standart') AS size,
            COALESCE(o.selected_gender, 'unisex'::public.listing_gender) AS gender,
            SUM(o.quantity)::INTEGER AS qty
        FROM public.marketplace_orders o
        WHERE o.listing_id = p_listing_id
          AND o.status <> 'cancelled'
          AND COALESCE(o.affects_stock, true)
        GROUP BY 1, 2
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

    RETURN jsonb_build_object(
        'listing', v_listing,
        'production', v_production,
        'sales', v_sales,
        'remaining_quantity', v_prod_qty - v_stock_sold_qty,
        'current_stock', v_current_stock,
        'size_breakdown', v_sizes
    );
END;
$$;

COMMENT ON FUNCTION public.get_market_product_report(UUID) IS
    'Ürün raporu. Kalan = üretim − (iptal dışı ve stoktan düşen satışlar); stok ile aynı mantık.';

-- =====================
-- 5) Mevcut stokları kalan formülüne göre onar (bildirimsiz)
-- =====================
DO $$
BEGIN
    ALTER TABLE public.listing_stock_by_size
        DISABLE TRIGGER on_listing_stock_by_size_alert;
    ALTER TABLE public.marketplace_listings
        DISABLE TRIGGER on_listing_stock_quantity_alert;

    DELETE FROM public.listing_stock_by_size;

    INSERT INTO public.listing_stock_by_size (listing_id, size, gender, quantity)
    WITH produced AS (
        SELECT
            b.listing_id,
            i.size,
            i.gender,
            SUM(i.quantity)::INTEGER AS qty
        FROM public.production_batches b
        JOIN public.production_batch_items i ON i.batch_id = b.id
        GROUP BY b.listing_id, i.size, i.gender
    ),
    sold AS (
        SELECT
            o.listing_id,
            COALESCE(NULLIF(btrim(o.selected_size), ''), 'Standart') AS size,
            COALESCE(o.selected_gender, 'unisex'::public.listing_gender) AS gender,
            SUM(o.quantity)::INTEGER AS qty
        FROM public.marketplace_orders o
        WHERE o.status <> 'cancelled'
          AND COALESCE(o.affects_stock, true)
        GROUP BY 1, 2, 3
    )
    SELECT
        p.listing_id,
        p.size,
        p.gender,
        GREATEST(0, p.qty - COALESCE(s.qty, 0))::INTEGER AS quantity
    FROM produced p
    LEFT JOIN sold s
      ON s.listing_id = p.listing_id
     AND s.size = p.size
     AND s.gender = p.gender;

    UPDATE public.marketplace_listings ml
    SET stock_quantity = COALESCE((
        SELECT SUM(s.quantity)::INTEGER
        FROM public.listing_stock_by_size s
        WHERE s.listing_id = ml.id
    ), 0);

    ALTER TABLE public.listing_stock_by_size
        ENABLE TRIGGER on_listing_stock_by_size_alert;
    ALTER TABLE public.marketplace_listings
        ENABLE TRIGGER on_listing_stock_quantity_alert;
EXCEPTION
    WHEN OTHERS THEN
        ALTER TABLE public.listing_stock_by_size
            ENABLE TRIGGER on_listing_stock_by_size_alert;
        ALTER TABLE public.marketplace_listings
            ENABLE TRIGGER on_listing_stock_quantity_alert;
        RAISE;
END;
$$;
