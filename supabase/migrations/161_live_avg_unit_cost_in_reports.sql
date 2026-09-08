-- =====================================================
-- 161: Satış maliyetleri canlı ortalama birim maliyet
-- =====================================================
-- Önceki davranış: satış anındaki unit_cost snapshot'ı kilitleniyordu;
-- yeni parti eklenince eski satırlar eski ortalamada kalıyordu (625 vs 635).
--
-- Yeni davranış: rapor / Excel / kar hesapları her zaman
-- get_listing_avg_unit_cost (güncel ağırlıklı ortalama) kullanır.
-- Parti eklenince / değişince tüm satış satırları otomatik yeni maliyeti gösterir.

COMMENT ON COLUMN public.marketplace_orders.unit_cost IS
    'Eski snapshot alanı; raporlar artık kullanmaz. Maliyet canlı ort. birim maliyetten gelir.';

COMMENT ON FUNCTION public.get_listing_avg_unit_cost(UUID) IS
    'Ürünün tüm üretim partileri üzerinden ağırlıklı ortalama birim maliyet. '
    'Rapor ve kar hesaplarında canlı maliyet kaynağıdır.';

-- =====================
-- 1) Satış satırları (Excel / ürün satış tablosu)
-- =====================
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
    note TEXT
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
        o.seller_note
    FROM public.marketplace_orders o
    LEFT JOIN public.users u ON u.id = o.buyer_id
    WHERE o.listing_id = p_listing_id
    ORDER BY COALESCE(o.order_date, o.created_at::date) ASC, o.created_at ASC;
END;
$$;

COMMENT ON FUNCTION public.get_market_product_sales(UUID) IS
    'Ürün satış geçmişi. Maliyet ve kar, güncel ortalama birim maliyetten canlı hesaplanır.';

-- =====================
-- 2) Market özeti — COGS canlı ortalama
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
            CASE
                WHEN p.qty > 0 THEN ROUND(p.cost / p.qty, 2)
                ELSE 0
            END AS eff_unit_cost,
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
    'Market özeti. Satılan maliyet (COGS) güncel ortalama birim maliyetten canlı hesaplanır.';

-- =====================
-- 3) Ürün raporu — COGS canlı ortalama
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
    'Ürün raporu. Kalan stok mantığı korunur; satılan maliyet canlı ort. birim maliyetten hesaplanır.';
