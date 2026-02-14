-- =====================================================
-- 052: Notification Triggers - Bildirim tetikleyicileri
-- =====================================================
-- Events, posts, marketplace, carpool, chat için trigger'lar
-- Tüm fonksiyonlar SECURITY DEFINER ile notifications tablosuna yazabilir

-- Helper: Kullanıcının bu bildirim türünü alıp almadığını kontrol et (ayar açıksa true)
-- Sadece açıkça false ise kapalı sayılır; key yoksa veya true ise bildirim gider
CREATE OR REPLACE FUNCTION public.notification_type_enabled(p_user_id UUID, p_type TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_settings JSONB;
    v_val JSONB;
BEGIN
    SELECT settings INTO v_settings FROM public.user_notification_settings WHERE user_id = p_user_id;
    IF v_settings IS NULL THEN
        RETURN true;
    END IF;
    v_val := v_settings->p_type;
    -- Key yoksa (NULL) veya true ise açık; sadece JSONB false ise kapalı
    RETURN (v_val IS NULL OR v_val IS DISTINCT FROM 'false'::jsonb);
END;
$$;

-- Helper: Alıcı listesine bildirim ekle (ayarı açık olanlara)
-- Post bildirimleri: "Yeni duyuru" (post_created) kapalıysa hiç gönderme; "Duyuru güncellendi" ayrı kontrol.
CREATE OR REPLACE FUNCTION public.insert_notifications(
    p_type TEXT,
    p_title TEXT,
    p_body TEXT,
    p_data JSONB,
    p_recipient_ids UUID[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    rec UUID;
    v_send BOOLEAN;
BEGIN
    FOREACH rec IN ARRAY p_recipient_ids
    LOOP
        IF p_type IN ('post_created', 'post_updated') THEN
            -- Duyuru: "Yeni duyuru" kapalıysa hiç gönderme; post_updated için ayrıca "Duyuru güncellendi" açık olmalı
            IF NOT public.notification_type_enabled(rec, 'post_created') THEN
                v_send := false;
            ELSIF p_type = 'post_updated' AND NOT public.notification_type_enabled(rec, 'post_updated') THEN
                v_send := false;
            ELSE
                v_send := true;
            END IF;
        ELSE
            v_send := public.notification_type_enabled(rec, p_type);
        END IF;
        IF v_send THEN
            INSERT INTO public.notifications (user_id, type, title, body, data)
            VALUES (rec, p_type, p_title, p_body, p_data);
        END IF;
    END LOOP;
END;
$$;

-- =====================
-- EVENTS
-- =====================
CREATE OR REPLACE FUNCTION public.notify_on_event_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recipient_ids UUID[];
    v_notification_type TEXT;
    v_title TEXT;
    v_body TEXT;
    v_data JSONB;
BEGIN
    -- Sadece yayınlanmış etkinlikler için
    IF NEW.status != 'published' THEN
        RETURN NEW;
    END IF;

    v_data := jsonb_build_object('event_id', NEW.id);
    v_title := trim(NEW.title);
    -- İçerik: etkinlik tarihi + kısa metin (örn. "15.02.2026 09:00 · Katılımını bekliyoruz.")
    v_body := to_char(NEW.start_time AT TIME ZONE 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') || ' · Katılımını bekliyoruz.';

    IF TG_OP = 'INSERT' THEN
        v_notification_type := 'event_created';
    ELSE
        v_notification_type := 'event_updated';
    END IF;

    -- Bireysel antrenman: bildirim yok
    IF NEW.event_type = 'training' AND NEW.participation_type = 'individual' THEN
        RETURN NEW;
    END IF;

    -- Ekip antrenmanı (training + team): event_group_programs'taki grupların üyeleri
    IF NEW.event_type = 'training' AND NEW.participation_type = 'team' THEN
        SELECT ARRAY_AGG(DISTINCT gm.user_id)
        INTO v_recipient_ids
        FROM public.event_group_programs egp
        JOIN public.group_members gm ON gm.group_id = egp.training_group_id
        WHERE egp.event_id = NEW.id;
        IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
            PERFORM public.insert_notifications(
                v_notification_type,
                v_title,
                v_body,
                v_data,
                v_recipient_ids
            );
        END IF;
        RETURN NEW;
    END IF;

    -- Diğer etkinlik türleri (race, social, workshop, other): tüm aktif kullanıcılar
    SELECT ARRAY_AGG(id) INTO v_recipient_ids
    FROM public.users
    WHERE is_active = true;
    IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.insert_notifications(
            v_notification_type,
            v_title,
            v_body,
            v_data,
            v_recipient_ids
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_event_notify ON public.events;
CREATE TRIGGER on_event_notify
    AFTER INSERT OR UPDATE ON public.events
    FOR EACH ROW EXECUTE FUNCTION public.notify_on_event_change();

-- =====================
-- POSTS
-- =====================
-- Başlık: post adı. İçerik: sabit kısa mesaj (bloklardan özet çıkarmıyoruz).
CREATE OR REPLACE FUNCTION public.notify_on_post_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recipient_ids UUID[];
    v_notification_type TEXT;
    v_title TEXT;
    v_body TEXT;
    v_data JSONB;
BEGIN
    IF NOT COALESCE(NEW.is_published, true) THEN
        RETURN NEW;
    END IF;

    v_data := jsonb_build_object('post_id', NEW.id);
    v_title := trim(NEW.title);

    IF TG_OP = 'INSERT' THEN
        v_notification_type := 'post_created';
        v_body := 'Yeni post yayınlandı.';
    ELSE
        -- Oluşturmadan kısa süre sonraki UPDATE (örn. kapak yüklemesi) için "Duyuru güncellendi" gönderme
        IF (NEW.updated_at - NEW.created_at) < interval '1 minute' THEN
            RETURN NEW;
        END IF;
        v_notification_type := 'post_updated';
        v_body := 'Duyuru güncellendi.';
    END IF;

    SELECT ARRAY_AGG(id) INTO v_recipient_ids
    FROM public.users
    WHERE is_active = true;
    IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.insert_notifications(
            v_notification_type,
            v_title,
            v_body,
            v_data,
            v_recipient_ids
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_post_notify ON public.posts;
CREATE TRIGGER on_post_notify
    AFTER INSERT OR UPDATE ON public.posts
    FOR EACH ROW EXECUTE FUNCTION public.notify_on_post_change();

-- =====================
-- MARKETPLACE LISTINGS (yeni ürün)
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
BEGIN
    IF NEW.status != 'active' THEN
        RETURN NEW;
    END IF;
    v_data := jsonb_build_object('listing_id', NEW.id);
    SELECT ARRAY_AGG(id) INTO v_recipient_ids
    FROM public.users
    WHERE is_active = true;
    IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.insert_notifications(
            'listing_created',
            'Yeni Ürün: ' || trim(NEW.title),
            'Yeni ürünü kaçırma! Listede seni bekliyor.',
            v_data,
            v_recipient_ids
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_listing_created_notify ON public.marketplace_listings;
CREATE TRIGGER on_listing_created_notify
    AFTER INSERT ON public.marketplace_listings
    FOR EACH ROW EXECUTE FUNCTION public.notify_on_listing_created();

-- =====================
-- MARKETPLACE ORDERS
-- =====================
-- Sipariş oluşturuldu: adminlere (super_admin, coach)
CREATE OR REPLACE FUNCTION public.notify_on_order_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recipient_ids UUID[];
    v_data JSONB;
    v_listing_title TEXT;
BEGIN
    v_data := jsonb_build_object('order_id', NEW.id, 'listing_id', NEW.listing_id);
    SELECT title INTO v_listing_title FROM public.marketplace_listings WHERE id = NEW.listing_id;
    SELECT ARRAY_AGG(ur.user_id) INTO v_recipient_ids
    FROM public.user_roles ur
    WHERE ur.role IN ('super_admin', 'coach');
    IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.insert_notifications(
            'order_created',
            'Yeni Sipariş Alındı',
            COALESCE(trim(v_listing_title), 'Ürün') || ' için sipariş verildi.',
            v_data,
            v_recipient_ids
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_order_created_notify ON public.marketplace_orders;
CREATE TRIGGER on_order_created_notify
    AFTER INSERT ON public.marketplace_orders
    FOR EACH ROW EXECUTE FUNCTION public.notify_on_order_created();

-- Sipariş durumu değişti: siparişi veren (buyer_id)
CREATE OR REPLACE FUNCTION public.notify_on_order_status_changed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_data JSONB;
    v_status_text TEXT;
    v_listing_title TEXT;
BEGIN
    IF OLD.status = NEW.status THEN
        RETURN NEW;
    END IF;
    v_status_text := CASE NEW.status
        WHEN 'confirmed' THEN 'onaylandı'
        WHEN 'cancelled' THEN 'iptal edildi'
        WHEN 'completed' THEN 'tamamlandı'
        ELSE NEW.status::TEXT
    END;
    SELECT title INTO v_listing_title FROM public.marketplace_listings WHERE id = NEW.listing_id;
    v_data := jsonb_build_object('order_id', NEW.id, 'listing_id', NEW.listing_id, 'status', NEW.status);
    PERFORM public.insert_notifications(
        'order_status_changed',
        'Siparişinizin durumu güncellendi',
        COALESCE(trim(v_listing_title), 'Ürün') || '. Siparişiniz ' || v_status_text || '.',
        v_data,
        ARRAY[NEW.buyer_id]
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_order_status_notify ON public.marketplace_orders;
CREATE TRIGGER on_order_status_notify
    AFTER UPDATE ON public.marketplace_orders
    FOR EACH ROW EXECUTE FUNCTION public.notify_on_order_status_changed();

-- =====================
-- CARPOOL REQUESTS
-- =====================
-- Başvuru yapıldı: ilanı açan (driver_id)
CREATE OR REPLACE FUNCTION public.notify_on_carpool_request_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_driver_id UUID;
    v_data JSONB;
    v_event_title TEXT;
    v_passenger_name TEXT;
BEGIN
    SELECT co.driver_id, e.title INTO v_driver_id, v_event_title
    FROM public.carpool_offers co
    JOIN public.events e ON e.id = co.event_id
    WHERE co.id = NEW.offer_id;
    IF v_driver_id IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT trim(COALESCE(u.first_name || ' ', '') || COALESCE(u.last_name, '')) INTO v_passenger_name
    FROM public.users u WHERE u.id = NEW.passenger_id;
    v_passenger_name := COALESCE(nullif(trim(v_passenger_name), ''), 'Bir üye');
    v_data := jsonb_build_object('request_id', NEW.id, 'offer_id', NEW.offer_id, 'event_id', (SELECT event_id FROM public.carpool_offers WHERE id = NEW.offer_id));
    PERFORM public.insert_notifications(
        'carpool_application',
        COALESCE(trim(v_event_title), 'Etkinlik'),
        v_passenger_name || ' ortak yolculuk başvurusu yaptı.',
        v_data,
        ARRAY[v_driver_id]
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_carpool_request_insert_notify ON public.carpool_requests;
CREATE TRIGGER on_carpool_request_insert_notify
    AFTER INSERT ON public.carpool_requests
    FOR EACH ROW EXECUTE FUNCTION public.notify_on_carpool_request_insert();

-- Başvuru kabul/red: başvuran (passenger_id). Başlık: etkinlik adı, içerik: durum mesajı.
CREATE OR REPLACE FUNCTION public.notify_on_carpool_request_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_data JSONB;
    v_msg TEXT;
    v_event_title TEXT;
BEGIN
    IF OLD.status = NEW.status OR NEW.status NOT IN ('accepted', 'rejected') THEN
        RETURN NEW;
    END IF;
    v_msg := CASE NEW.status
        WHEN 'accepted' THEN 'Ortak yolculuk başvurunuz kabul edildi.'
        WHEN 'rejected' THEN 'Ortak yolculuk başvurunuz reddedildi.'
        ELSE ''
    END;
    SELECT e.title INTO v_event_title
    FROM public.carpool_offers co
    JOIN public.events e ON e.id = co.event_id
    WHERE co.id = NEW.offer_id;
    v_data := jsonb_build_object('request_id', NEW.id, 'offer_id', NEW.offer_id, 'event_id', (SELECT event_id FROM public.carpool_offers WHERE id = NEW.offer_id), 'status', NEW.status);
    PERFORM public.insert_notifications(
        'carpool_application_response',
        COALESCE(trim(v_event_title), 'Etkinlik'),
        v_msg,
        v_data,
        ARRAY[NEW.passenger_id]
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_carpool_request_status_notify ON public.carpool_requests;
CREATE TRIGGER on_carpool_request_status_notify
    AFTER UPDATE ON public.carpool_requests
    FOR EACH ROW EXECUTE FUNCTION public.notify_on_carpool_request_status();

-- =====================
-- CHAT MESSAGES (etkinlik sohbeti)
-- =====================
-- Başlık: etkinlik adı. İçerik: gönderen + mesaj önizlemesi (mevcut gibi).
CREATE OR REPLACE FUNCTION public.notify_on_event_chat_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_room_type chat_room_type;
    v_event_id UUID;
    v_event_title TEXT;
    v_recipient_ids UUID[];
    v_sender_name TEXT;
    v_data JSONB;
BEGIN
    SELECT cr.room_type, cr.event_id INTO v_room_type, v_event_id
    FROM public.chat_rooms cr
    WHERE cr.id = NEW.room_id;
    IF v_room_type != 'event' OR v_event_id IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT title INTO v_event_title FROM public.events WHERE id = v_event_id;
    -- Gönderen hariç odadaki tüm üyeler
    SELECT ARRAY_AGG(crm.user_id) INTO v_recipient_ids
    FROM public.chat_room_members crm
    WHERE crm.room_id = NEW.room_id
      AND crm.user_id IS NOT NULL
      AND (NEW.sender_id IS NULL OR crm.user_id != NEW.sender_id);
    IF v_recipient_ids IS NULL OR array_length(v_recipient_ids, 1) IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT trim(COALESCE(u.first_name || ' ', '') || COALESCE(u.last_name, '')) INTO v_sender_name
    FROM public.users u WHERE u.id = NEW.sender_id;
    v_data := jsonb_build_object('room_id', NEW.room_id, 'event_id', v_event_id, 'message_id', NEW.id);
    PERFORM public.insert_notifications(
        'event_chat_message',
        COALESCE(trim(v_event_title), 'Etkinlik sohbeti'),
        COALESCE(nullif(trim(v_sender_name), ''), 'Bir katılımcı') || ': ' || left(trim(NEW.content), 80),
        v_data,
        v_recipient_ids
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_event_chat_message_notify ON public.chat_messages;
CREATE TRIGGER on_event_chat_message_notify
    AFTER INSERT ON public.chat_messages
    FOR EACH ROW EXECUTE FUNCTION public.notify_on_event_chat_message();
