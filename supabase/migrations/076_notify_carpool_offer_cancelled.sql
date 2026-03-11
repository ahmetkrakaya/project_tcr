-- =====================================================
-- 076: Carpool offer silindiğinde onaylı yolculara bildirim
-- =====================================================
-- carpool_offers DELETE trigger: silinen ilanın onaylı (accepted)
-- yolcularına "yolculuk iptal oldu" bildirimi gönderir.

CREATE OR REPLACE FUNCTION public.notify_on_carpool_offer_delete()
RETURNS TRIGGER AS $$
DECLARE
    v_recipient_ids UUID[];
    v_event_title TEXT;
    v_driver_name TEXT;
    v_data JSONB;
BEGIN
    SELECT ARRAY_AGG(cr.passenger_id) INTO v_recipient_ids
    FROM public.carpool_requests cr
    WHERE cr.offer_id = OLD.id
      AND cr.status = 'accepted';

    IF v_recipient_ids IS NULL OR array_length(v_recipient_ids, 1) IS NULL THEN
        RETURN OLD;
    END IF;

    SELECT e.title INTO v_event_title
    FROM public.events e
    WHERE e.id = OLD.event_id;

    SELECT trim(COALESCE(u.first_name || ' ', '') || COALESCE(u.last_name, ''))
    INTO v_driver_name
    FROM public.users u
    WHERE u.id = OLD.driver_id;

    v_driver_name := COALESCE(nullif(trim(v_driver_name), ''), 'Sürücü');
    v_data := jsonb_build_object('event_id', OLD.event_id);

    PERFORM public.insert_notifications(
        'carpool_cancelled',
        COALESCE(trim(v_event_title), 'Etkinlik'),
        v_driver_name || ' ortak yolculuk ilanını iptal etti.',
        v_data,
        v_recipient_ids
    );

    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_carpool_offer_delete_notify ON public.carpool_offers;

CREATE TRIGGER trigger_carpool_offer_delete_notify
    BEFORE DELETE ON public.carpool_offers
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_on_carpool_offer_delete();
