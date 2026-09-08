-- TCR Migration 157: Stok bildirimi yalnızca üretim partisinden
-- Sorun: listing_stock_by_size / stock_quantity trigger'ları her 0→pozitif
-- geçişinde (satış iptali, stok geri yazımı vb.) herkese "Stok Güncellendi"
-- bildirimi gönderiyordu.
-- Çözüm: tablo trigger'larından bildirimi kaldır; yalnızca
-- apply_production_stock_delta içinde (üretim partisi stok artırınca) gönder.

-- 1) Trigger'lar artık bildirim göndermez (satış / iptal sessiz kalır)
CREATE OR REPLACE FUNCTION public.notify_on_listing_stock_by_size_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Bildirimler apply_production_stock_delta üzerinden gider.
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_on_listing_stock_quantity_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Bildirimler apply_production_stock_delta üzerinden gider.
    RETURN NEW;
END;
$$;

-- 2) Üretim stok deltası: pozitif girişte ve kova 0→>0 olduysa bildir
CREATE OR REPLACE FUNCTION public.apply_production_stock_delta(
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
    v_old_qty INTEGER := 0;
    v_new_qty INTEGER := 0;
BEGIN
    IF p_delta = 0 THEN
        RETURN;
    END IF;

    v_gender := COALESCE(p_gender, 'unisex'::public.listing_gender);
    v_size := COALESCE(NULLIF(btrim(p_size), ''), 'Standart');

    SELECT quantity
    INTO v_old_qty
    FROM public.listing_stock_by_size
    WHERE listing_id = p_listing_id
      AND size = v_size
      AND gender = v_gender;

    v_old_qty := COALESCE(v_old_qty, 0);

    INSERT INTO public.listing_stock_by_size (listing_id, size, gender, quantity)
    VALUES (p_listing_id, v_size, v_gender, GREATEST(0, p_delta))
    ON CONFLICT (listing_id, size, gender)
    DO UPDATE SET
        quantity = GREATEST(0, public.listing_stock_by_size.quantity + p_delta),
        updated_at = NOW();

    SELECT quantity
    INTO v_new_qty
    FROM public.listing_stock_by_size
    WHERE listing_id = p_listing_id
      AND size = v_size
      AND gender = v_gender;

    v_new_qty := COALESCE(v_new_qty, 0);

    -- Genel stok alanını beden stoklarının toplamına senkronla
    UPDATE public.marketplace_listings
    SET stock_quantity = (
        SELECT COALESCE(SUM(s.quantity), 0)
        FROM public.listing_stock_by_size s
        WHERE s.listing_id = p_listing_id
    )
    WHERE id = p_listing_id;

    -- Yalnızca üretimle stok geri geldiğinde (0 → pozitif) bildir
    IF p_delta > 0 AND v_old_qty <= 0 AND v_new_qty > 0 THEN
        PERFORM public.dispatch_listing_stock_updated_broadcast(p_listing_id);
        PERFORM public.dispatch_listing_stock_alerts(
            p_listing_id,
            v_size,
            v_gender::TEXT,
            true
        );
    END IF;
END;
$$;

COMMENT ON FUNCTION public.apply_production_stock_delta(UUID, TEXT, public.listing_gender, INTEGER) IS
    'Üretim partisi stok deltası. Bildirim yalnızca üretimle 0→pozitif stok artışında gönderilir.';
