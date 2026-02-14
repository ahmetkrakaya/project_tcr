-- =====================================================
-- 053: Bildirim her zaman yazılsın; push sadece ayar açıksa
-- =====================================================
-- Önceki davranış: Ayar kapalıysa insert_notifications hiç satır yazmıyordu.
-- Yeni davranış: Tüm alıcılara notifications satırı yazılır (uygulama içi sekmede görünür).
-- Push bildirimi (FCM) Edge Function tarafında user_notification_settings kontrol edilerek
-- sadece ilgili tür açıksa gönderilir; kapalıysa push gitmez, bildirim yine uygulama içinde listelenir.

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
BEGIN
    FOREACH rec IN ARRAY p_recipient_ids
    LOOP
        INSERT INTO public.notifications (user_id, type, title, body, data)
        VALUES (rec, p_type, p_title, p_body, p_data);
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.insert_notifications(TEXT, TEXT, TEXT, JSONB, UUID[]) IS
  'Tüm alıcılara bildirim satırı ekler. Push (FCM) gönderimi Edge Function içinde user_notification_settings ile kontrol edilir.';
