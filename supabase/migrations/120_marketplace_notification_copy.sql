-- =====================================================
-- 120: Market bildirim metinleri ve yeni türler
-- =====================================================
-- - Yeni ürün: 5 rastgele metin, herkese
-- - Stok güncelleme: herkese (abone olanlar hariç)
-- - Gelince haber ver: yalnızca abonelere (stok güncelleme ile çakışmaz)
-- - İndirim: 5 rastgele metin, herkese
-- - Sipariş bildirimleri kapatıldı

CREATE OR REPLACE FUNCTION public.pick_random_variant(p_count INTEGER)
RETURNS INTEGER
LANGUAGE sql
VOLATILE
AS $$
    SELECT 1 + floor(random() * GREATEST(p_count, 1))::INTEGER;
$$;

-- =====================
-- YENİ ÜRÜN (5 varyant)
-- =====================
CREATE OR REPLACE FUNCTION public.notify_on_listing_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recipient_ids UUID[];
    v_data JSONB;
    v_title TEXT;
    v_body TEXT;
    v_product TEXT;
    v_variant INTEGER;
BEGIN
    IF NEW.status != 'active' THEN
        RETURN NEW;
    END IF;

    v_product := trim(NEW.title);
    v_data := jsonb_build_object('listing_id', NEW.id);
    v_variant := public.pick_random_variant(5);

    CASE v_variant
        WHEN 1 THEN
            v_title := 'Yeni Ürün: ' || v_product;
            v_body := 'TCR Market''e yeni bir parça eklendi. İlk sen incele, stoklar sınırlı olabilir.';
        WHEN 2 THEN
            v_title := 'Market''e Düşen Yeni Ürün';
            v_body := v_product || ' şimdi rafta. Detaylara göz at, beğenirsen hemen kap.';
        WHEN 3 THEN
            v_title := 'Taze Gelen: ' || v_product;
            v_body := 'Yeni ürün yayında. Koşu rutinine yakışan bir parça olabilir — hemen bak.';
        WHEN 4 THEN
            v_title := v_product || ' — Yeni!';
            v_body := 'Market listemiz güncellendi. Bu ürünü kaçırma, erken alan kazanır.';
        ELSE
            v_title := 'Rafta Yeni Ürün Var';
            v_body := v_product || ' eklendi. Favorilerine ekle, fırsatı yakala.';
    END CASE;

    SELECT ARRAY_AGG(id)
    INTO v_recipient_ids
    FROM public.users
    WHERE is_active = true;

    IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.insert_notifications(
            'listing_created',
            v_title,
            v_body,
            v_data,
            v_recipient_ids
        );
    END IF;

    RETURN NEW;
END;
$$;

-- =====================
-- GELİNCE HABER VER (yalnızca aboneler)
-- =====================
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
    v_title TEXT;
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

    v_title := 'İstediğin Ürün Geldi';

    IF v_size_label IS NOT NULL AND v_gender_label IS NOT NULL THEN
        v_body := v_listing_title || ' (' || v_gender_label || ' ' || v_size_label
            || ') bekleme listenden çıktı. Tam istediğin kombinasyon stokta — kaçırma.';
    ELSIF v_size_label IS NOT NULL THEN
        v_body := v_listing_title || ' (' || v_size_label
            || ' beden) yeniden stokta. Beklediğin için haber veriyoruz, hemen incele.';
    ELSE
        v_body := v_listing_title
            || ' yeniden stokta. Bekleme listendeki ürünün geldi — şimdi sipariş verebilirsin.';
    END IF;

    v_data := jsonb_build_object(
        'listing_id', p_listing_id,
        'size', p_size,
        'gender', p_gender
    );

    PERFORM public.insert_notifications(
        'listing_back_in_stock',
        v_title,
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

-- =====================
-- STOK GÜNCELLEME (herkese, aboneler hariç)
-- =====================
CREATE OR REPLACE FUNCTION public.dispatch_listing_stock_updated_broadcast(
    p_listing_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_listing_title TEXT;
    v_recipient_ids UUID[];
    v_data JSONB;
BEGIN
    IF NOT public.listing_has_any_stock(p_listing_id) THEN
        RETURN;
    END IF;

    SELECT trim(title)
    INTO v_listing_title
    FROM public.marketplace_listings
    WHERE id = p_listing_id;

    IF v_listing_title IS NULL THEN
        RETURN;
    END IF;

    SELECT ARRAY_AGG(u.id)
    INTO v_recipient_ids
    FROM public.users u
    WHERE u.is_active = true
      AND NOT EXISTS (
          SELECT 1
          FROM public.listing_stock_alerts a
          WHERE a.listing_id = p_listing_id
            AND a.user_id = u.id
            AND a.notified_at IS NULL
      );

    IF v_recipient_ids IS NULL OR array_length(v_recipient_ids, 1) IS NULL THEN
        RETURN;
    END IF;

    v_data := jsonb_build_object('listing_id', p_listing_id);

    PERFORM public.insert_notifications(
        'listing_stock_updated',
        'Stok Güncellendi',
        v_listing_title || ' tekrar siparişe açıldı. Rafta seni bekliyor — şimdi göz at.',
        v_data,
        v_recipient_ids
    );
END;
$$;

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
        -- Önce genel stok bildirimi (bekleyen aboneler hariç), sonra abonelere özel bildirim
        PERFORM public.dispatch_listing_stock_updated_broadcast(NEW.listing_id);
        PERFORM public.dispatch_listing_stock_alerts(
            NEW.listing_id,
            NEW.size,
            NEW.gender,
            true
        );
    END IF;

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
    IF TG_OP = 'UPDATE'
       AND COALESCE(OLD.stock_quantity, 0) <= 0
       AND NEW.stock_quantity IS NOT NULL
       AND NEW.stock_quantity > 0
       AND NOT EXISTS (
           SELECT 1
           FROM public.listing_stock_by_size s
           WHERE s.listing_id = NEW.id
       ) THEN
        PERFORM public.dispatch_listing_stock_updated_broadcast(NEW.id);
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

-- =====================
-- İNDİRİM (5 varyant, herkese)
-- =====================
CREATE OR REPLACE FUNCTION public.is_listing_discount_active(
    p_percent INTEGER,
    p_starts_at TIMESTAMPTZ,
    p_ends_at TIMESTAMPTZ,
    p_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT p_percent IS NOT NULL
       AND p_percent > 0
       AND (p_starts_at IS NULL OR p_starts_at <= p_at)
       AND (p_ends_at IS NULL OR p_ends_at > p_at);
$$;

CREATE OR REPLACE FUNCTION public.notify_on_listing_discount_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recipient_ids UUID[];
    v_data JSONB;
    v_title TEXT;
    v_body TEXT;
    v_product TEXT;
    v_percent INTEGER;
    v_variant INTEGER;
    v_was_active BOOLEAN;
    v_is_active BOOLEAN;
BEGIN
    v_was_active := public.is_listing_discount_active(
        OLD.discount_percent,
        OLD.discount_starts_at,
        OLD.discount_ends_at
    );
    v_is_active := public.is_listing_discount_active(
        NEW.discount_percent,
        NEW.discount_starts_at,
        NEW.discount_ends_at
    );

    IF NEW.status != 'active' THEN
        RETURN NEW;
    END IF;

    IF NOT v_is_active THEN
        RETURN NEW;
    END IF;

    IF v_was_active
       AND OLD.discount_percent IS NOT DISTINCT FROM NEW.discount_percent
       AND OLD.discount_starts_at IS NOT DISTINCT FROM NEW.discount_starts_at
       AND OLD.discount_ends_at IS NOT DISTINCT FROM NEW.discount_ends_at THEN
        RETURN NEW;
    END IF;

    v_product := trim(NEW.title);
    v_percent := NEW.discount_percent;
    v_data := jsonb_build_object(
        'listing_id', NEW.id,
        'discount_percent', v_percent
    );
    v_variant := public.pick_random_variant(5);

    CASE v_variant
        WHEN 1 THEN
            v_title := 'İndirim Başladı: ' || v_product;
            v_body := '%' || v_percent || ' indirimle şimdi senin. Süreli fırsatı kaçırma.';
        WHEN 2 THEN
            v_title := v_product || ' — %' || v_percent || ' İndirim';
            v_body := 'Market''te özel fiyat yayında. Ne kadar erken o kadar iyi.';
        WHEN 3 THEN
            v_title := 'Fırsat Alarmı';
            v_body := v_product || ' ürününde %' || v_percent || ' indirim başladı. Hemen incele.';
        WHEN 4 THEN
            v_title := 'Kaçırma: ' || v_product;
            v_body := '%' || v_percent || ' indirim yalnızca sınırlı süre. Detaylar markette.';
        ELSE
            v_title := 'Özel Fiyat: ' || v_product;
            v_body := 'Seçili üründe %' || v_percent || ' indirim. Koşu ekipmanını şimdi yakala.';
    END CASE;

    SELECT ARRAY_AGG(id)
    INTO v_recipient_ids
    FROM public.users
    WHERE is_active = true;

    IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.insert_notifications(
            'listing_discount',
            v_title,
            v_body,
            v_data,
            v_recipient_ids
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_listing_discount_notify ON public.marketplace_listings;
CREATE TRIGGER on_listing_discount_notify
    AFTER INSERT OR UPDATE OF discount_percent, discount_starts_at, discount_ends_at
    ON public.marketplace_listings
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_on_listing_discount_change();

-- =====================
-- SİPARİŞ BİLDİRİMLERİNİ KAPAT
-- =====================
DROP TRIGGER IF EXISTS on_order_created_notify ON public.marketplace_orders;
DROP TRIGGER IF EXISTS on_order_status_notify ON public.marketplace_orders;

-- =====================
-- YENİ BİLDİRİM TİPLERİ — varsayılan ayarlar
-- =====================
UPDATE public.user_notification_settings
SET settings = settings || '{"listing_stock_updated": true}'::jsonb
WHERE NOT (settings ? 'listing_stock_updated');

UPDATE public.user_notification_settings
SET settings = settings || '{"listing_discount": true}'::jsonb
WHERE NOT (settings ? 'listing_discount');

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
        "listing_stock_updated": true,
        "listing_discount": true,
        "order_created": true,
        "order_status_changed": true
    }'::jsonb;
