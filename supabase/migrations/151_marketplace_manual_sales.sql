-- TCR Migration 151: Manuel (elden / uygulama dışı) satış desteği
-- Amaç:
-- - marketplace_orders üzerinde kayıtlı kullanıcı olmadan da satış kaydı tutabilmek
-- - Satış tipi (normal / indirimli / hediye), tarihler, ödeme şekli ve kısmi ödeme takibi
-- - Maliyet snapshot'ı ile kar-zarar raporlaması
-- - Stok trigger'larının INSERT ve DELETE durumlarını da kapsaması
-- - Puan trigger'ının buyer_id NULL olduğunda patlamaması
--
-- Kilit notu: Bu migration YALNIZCA marketplace_orders tablosunu kilitler.
-- listing_stock_by_size policy güncellemesi 154 numaralı migration'a ayrıldı;
-- iki tabloyu aynı transaction'da kilitlemek canlı trafikte deadlock üretiyordu.

-- ============================================================
-- 0) Kilit stratejisi
-- ============================================================
-- Tabloyu daha ilk adımda tek seferde kilitle: uzun süren bir DDL zinciri
-- boyunca kilidi parça parça almak, eşzamanlı okumalarla deadlock'a yol açıyor.
-- Kilit alınamazsa deadlock beklemek yerine hızlıca hata ver ve tekrar denenebilsin.
SET LOCAL lock_timeout = '15s';
LOCK TABLE public.marketplace_orders IN ACCESS EXCLUSIVE MODE;

-- ============================================================
-- 1) Yeni kolonlar
-- ============================================================
ALTER TABLE public.marketplace_orders
    ALTER COLUMN buyer_id DROP NOT NULL;

ALTER TABLE public.marketplace_orders
    ADD COLUMN IF NOT EXISTS manual_buyer_name TEXT,
    ADD COLUMN IF NOT EXISTS is_manual BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS sale_type TEXT NOT NULL DEFAULT 'regular',
    ADD COLUMN IF NOT EXISTS unit_price DECIMAL(10,2),
    ADD COLUMN IF NOT EXISTS unit_cost DECIMAL(10,2),
    ADD COLUMN IF NOT EXISTS order_date DATE,
    ADD COLUMN IF NOT EXISTS delivery_date DATE,
    ADD COLUMN IF NOT EXISTS payment_date DATE,
    ADD COLUMN IF NOT EXISTS payment_method TEXT,
    ADD COLUMN IF NOT EXISTS paid_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS affects_stock BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN public.marketplace_orders.manual_buyer_name IS
    'Kayıtlı kullanıcı seçilmediğinde serbest girilen alıcı ad-soyadı.';
COMMENT ON COLUMN public.marketplace_orders.is_manual IS
    'Satış uygulama dışında (elden) yapıldıysa true.';
COMMENT ON COLUMN public.marketplace_orders.sale_type IS
    'Satış tipi: regular (normal), discounted (indirimli), gift (hediye).';
COMMENT ON COLUMN public.marketplace_orders.unit_cost IS
    'Satış anındaki birim üretim maliyeti (snapshot). Kar-zarar raporu bu değeri kullanır.';
COMMENT ON COLUMN public.marketplace_orders.paid_amount IS
    'Tahsil edilen tutar. total_price - paid_amount kalan borcu verir.';
COMMENT ON COLUMN public.marketplace_orders.affects_stock IS
    'false ise bu satış stok hareketine yol açmaz (geçmişe dönük kayıtlar için).';

-- ============================================================
-- 2) Constraint'ler
-- ============================================================
ALTER TABLE public.marketplace_orders
    DROP CONSTRAINT IF EXISTS marketplace_orders_buyer_identity_check;
ALTER TABLE public.marketplace_orders
    ADD CONSTRAINT marketplace_orders_buyer_identity_check
    CHECK (
        buyer_id IS NOT NULL
        OR (manual_buyer_name IS NOT NULL AND btrim(manual_buyer_name) <> '')
    );

ALTER TABLE public.marketplace_orders
    DROP CONSTRAINT IF EXISTS marketplace_orders_sale_type_check;
ALTER TABLE public.marketplace_orders
    ADD CONSTRAINT marketplace_orders_sale_type_check
    CHECK (sale_type IN ('regular', 'discounted', 'gift'));

ALTER TABLE public.marketplace_orders
    DROP CONSTRAINT IF EXISTS marketplace_orders_payment_method_check;
ALTER TABLE public.marketplace_orders
    ADD CONSTRAINT marketplace_orders_payment_method_check
    CHECK (
        payment_method IS NULL
        OR payment_method IN ('cash', 'transfer', 'card', 'hand', 'other')
    );

ALTER TABLE public.marketplace_orders
    DROP CONSTRAINT IF EXISTS marketplace_orders_paid_amount_check;
ALTER TABLE public.marketplace_orders
    ADD CONSTRAINT marketplace_orders_paid_amount_check
    CHECK (paid_amount >= 0);

-- ============================================================
-- 3) Mevcut kayıtların doldurulması (backfill)
-- ============================================================
UPDATE public.marketplace_orders
SET order_date = created_at::date
WHERE order_date IS NULL;

UPDATE public.marketplace_orders
SET unit_price = ROUND(total_price / GREATEST(quantity, 1), 2)
WHERE unit_price IS NULL;

UPDATE public.marketplace_orders
SET payment_date = completed_at::date
WHERE payment_date IS NULL
  AND completed_at IS NOT NULL;

UPDATE public.marketplace_orders
SET paid_amount = total_price
WHERE paid_amount = 0
  AND status = 'completed';

UPDATE public.marketplace_orders
SET sale_type = 'gift'
WHERE total_price = 0
  AND sale_type = 'regular';

-- Raporlama için index'ler
CREATE INDEX IF NOT EXISTS idx_marketplace_orders_listing_status
    ON public.marketplace_orders (listing_id, status);
CREATE INDEX IF NOT EXISTS idx_marketplace_orders_order_date
    ON public.marketplace_orders (order_date);

-- ============================================================
-- 4) Stok yönetimi: INSERT / UPDATE / DELETE
-- ============================================================
-- Belirli beden+cinsiyet kovasına stok deltası uygular.
-- Beden bazlı kayıt yoksa ürünün genel stock_quantity alanına düşer.
CREATE OR REPLACE FUNCTION public.apply_order_stock_delta(
    p_listing_id UUID,
    p_size TEXT,
    p_gender public.listing_gender,
    p_delta INTEGER
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_gender public.listing_gender;
    v_has_size_row BOOLEAN := FALSE;
BEGIN
    IF p_delta = 0 THEN
        RETURN;
    END IF;

    v_gender := COALESCE(p_gender, 'unisex'::public.listing_gender);

    IF p_size IS NOT NULL AND btrim(p_size) <> '' THEN
        SELECT EXISTS (
            SELECT 1
            FROM public.listing_stock_by_size
            WHERE listing_id = p_listing_id
              AND size = p_size
              AND gender = v_gender
        ) INTO v_has_size_row;
    END IF;

    IF v_has_size_row THEN
        UPDATE public.listing_stock_by_size
        SET quantity = GREATEST(0, quantity + p_delta)
        WHERE listing_id = p_listing_id
          AND size = p_size
          AND gender = v_gender;
    ELSE
        UPDATE public.marketplace_listings
        SET stock_quantity = GREATEST(0, COALESCE(stock_quantity, 0) + p_delta)
        WHERE id = p_listing_id
          AND stock_quantity IS NOT NULL;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.apply_order_stock_delta(UUID, TEXT, public.listing_gender, INTEGER) IS
    'Beden+cinsiyet kovasına (yoksa genel stoka) verilen stok deltasını uygular. Negatif delta stok düşer.';

-- Bir siparişin kaç adet stok rezerve ettiğini döner.
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
             AND p_status IN ('confirmed', 'completed')
        THEN COALESCE(p_quantity, 0)
        ELSE 0
    END;
$$;

CREATE OR REPLACE FUNCTION public.manage_stock_on_order_status_change()
RETURNS TRIGGER AS $$
DECLARE
    old_reserved INTEGER := 0;
    new_reserved INTEGER := 0;
    old_gender public.listing_gender;
    new_gender public.listing_gender;
    same_bucket BOOLEAN;
BEGIN
    IF TG_OP = 'INSERT' THEN
        new_reserved := public.order_reserved_quantity(NEW.status, NEW.affects_stock, NEW.quantity);
        IF new_reserved > 0 THEN
            PERFORM public.apply_order_stock_delta(
                NEW.listing_id, NEW.selected_size, NEW.selected_gender, -new_reserved
            );
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        old_reserved := public.order_reserved_quantity(OLD.status, OLD.affects_stock, OLD.quantity);
        IF old_reserved > 0 THEN
            PERFORM public.apply_order_stock_delta(
                OLD.listing_id, OLD.selected_size, OLD.selected_gender, old_reserved
            );
        END IF;
        RETURN OLD;
    END IF;

    old_reserved := public.order_reserved_quantity(OLD.status, OLD.affects_stock, OLD.quantity);
    new_reserved := public.order_reserved_quantity(NEW.status, NEW.affects_stock, NEW.quantity);
    old_gender := COALESCE(OLD.selected_gender, 'unisex'::public.listing_gender);
    new_gender := COALESCE(NEW.selected_gender, 'unisex'::public.listing_gender);

    same_bucket := OLD.listing_id = NEW.listing_id
        AND COALESCE(OLD.selected_size, '') = COALESCE(NEW.selected_size, '')
        AND old_gender = new_gender;

    IF same_bucket THEN
        IF old_reserved <> new_reserved THEN
            PERFORM public.apply_order_stock_delta(
                NEW.listing_id, NEW.selected_size, NEW.selected_gender,
                old_reserved - new_reserved
            );
        END IF;
    ELSE
        IF old_reserved > 0 THEN
            PERFORM public.apply_order_stock_delta(
                OLD.listing_id, OLD.selected_size, OLD.selected_gender, old_reserved
            );
        END IF;
        IF new_reserved > 0 THEN
            PERFORM public.apply_order_stock_delta(
                NEW.listing_id, NEW.selected_size, NEW.selected_gender, -new_reserved
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.manage_stock_on_order_status_change() IS
    'Sipariş eklendiğinde, güncellendiğinde veya silindiğinde stok rezervasyonunu senkronize eder. Onaylandı/Tamamlandı durumları stok düşürür, diğerleri düşürmez. affects_stock false ise stok hareketi yapılmaz.';

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

-- ============================================================
-- 5) Puan trigger'ı: buyer_id NULL guard
-- ============================================================
CREATE OR REPLACE FUNCTION public.upsert_order_points(
    p_order_id UUID,
    p_buyer_id UUID,
    p_total_price DECIMAL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_points INTEGER;
BEGIN
    -- Kayıtlı kullanıcıya bağlı olmayan (elden) satışlar puan üretmez
    IF p_buyer_id IS NULL THEN
        DELETE FROM public.user_points
        WHERE order_id = p_order_id
          AND source_type = 'marketplace_order';
        RETURN;
    END IF;

    v_points := public.calculate_order_points(p_total_price);

    IF v_points <= 0 THEN
        DELETE FROM public.user_points
        WHERE order_id = p_order_id
          AND source_type = 'marketplace_order';
        RETURN;
    END IF;

    UPDATE public.user_points
    SET
        user_id = p_buyer_id,
        points = v_points,
        note = format('Market siparişi: yüzde 5 (%s TL)', p_total_price),
        updated_at = NOW()
    WHERE order_id = p_order_id
      AND source_type = 'marketplace_order';

    IF NOT FOUND THEN
        INSERT INTO public.user_points (
            user_id, points, source_type, order_id, note
        )
        VALUES (
            p_buyer_id,
            v_points,
            'marketplace_order',
            p_order_id,
            format('Market siparişi: yüzde 5 (%s TL)', p_total_price)
        );
    END IF;
END;
$$;

-- ============================================================
-- 6) RLS: admin ve koçlar manuel satışları yönetebilsin
-- ============================================================
DROP POLICY IF EXISTS "Admins can view all orders" ON public.marketplace_orders;
CREATE POLICY "Admins can view all orders"
    ON public.marketplace_orders FOR SELECT
    USING (public.is_admin_or_coach());

DROP POLICY IF EXISTS "Admins can create orders" ON public.marketplace_orders;
CREATE POLICY "Admins can create orders"
    ON public.marketplace_orders FOR INSERT
    WITH CHECK (public.is_admin_or_coach());

DROP POLICY IF EXISTS "Admins can update all orders" ON public.marketplace_orders;
CREATE POLICY "Admins can update all orders"
    ON public.marketplace_orders FOR UPDATE
    USING (public.is_admin_or_coach())
    WITH CHECK (public.is_admin_or_coach());

DROP POLICY IF EXISTS "Admins can delete orders" ON public.marketplace_orders;
CREATE POLICY "Admins can delete orders"
    ON public.marketplace_orders FOR DELETE
    USING (public.is_admin_or_coach());
