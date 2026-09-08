-- TCR Migration 156: Tek seferlik stok backfill
-- Kaynak: üretim partileri − iptal edilmemiş satışlar (rapordaki "Kalan" ile aynı)
-- Tüm ürünlerin listing_stock_by_size ve stock_quantity alanları buna göre yeniden yazılır.
-- Partisi olmayan ürünler stok = 0 olur.
--
-- Not: Stok alert trigger'ı enum→text imza uyumsuzluğu nedeniyle bulk insert'te
-- patlıyordu; burada hem trigger düzeltilir hem backfill sırasında bildirimler
-- bastırılır (toplu stok yazımında "gelince haber ver" spam olmasın).

SET LOCAL lock_timeout = '30s';

-- Trigger: NEW.gender (listing_gender) → TEXT cast
CREATE OR REPLACE FUNCTION public.notify_on_listing_stock_by_size_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_should_notify BOOLEAN := false;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_should_notify := NEW.quantity > 0;
    ELSIF TG_OP = 'UPDATE' THEN
        v_should_notify := COALESCE(OLD.quantity, 0) <= 0 AND NEW.quantity > 0;
    END IF;

    IF v_should_notify THEN
        PERFORM public.dispatch_listing_stock_updated_broadcast(NEW.listing_id);
        PERFORM public.dispatch_listing_stock_alerts(
            NEW.listing_id,
            NEW.size,
            NEW.gender::TEXT,
            true
        );
    END IF;

    RETURN NEW;
END;
$$;

DO $$
BEGIN
    -- Bulk yazımda stok alert / quantity trigger'larını geçici kapat
    ALTER TABLE public.listing_stock_by_size
        DISABLE TRIGGER on_listing_stock_by_size_alert;
    ALTER TABLE public.marketplace_listings
        DISABLE TRIGGER on_listing_stock_quantity_alert;

    -- 1) Mevcut beden stoklarını temizle
    DELETE FROM public.listing_stock_by_size;

    -- 2) Üretilen − satılan = kalan (get_market_product_report ile aynı: status <> cancelled)
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

    -- 3) Genel stok alanını beden toplamına (partisi yoksa 0) senkronla
    UPDATE public.marketplace_listings ml
    SET stock_quantity = COALESCE((
        SELECT SUM(s.quantity)::INTEGER
        FROM public.listing_stock_by_size s
        WHERE s.listing_id = ml.id
    ), 0);

    -- Trigger'ları tekrar aç
    ALTER TABLE public.listing_stock_by_size
        ENABLE TRIGGER on_listing_stock_by_size_alert;
    ALTER TABLE public.marketplace_listings
        ENABLE TRIGGER on_listing_stock_quantity_alert;
EXCEPTION
    WHEN OTHERS THEN
        -- Hata olursa trigger'lar kapalı kalmasın
        ALTER TABLE public.listing_stock_by_size
            ENABLE TRIGGER on_listing_stock_by_size_alert;
        ALTER TABLE public.marketplace_listings
            ENABLE TRIGGER on_listing_stock_quantity_alert;
        RAISE;
END;
$$;

COMMENT ON TABLE public.listing_stock_by_size IS
    'Beden bazlı stok. Kaynak: üretim − iptal dışı satışlar (migration 156 backfill + sonraki parti delta sync).';
