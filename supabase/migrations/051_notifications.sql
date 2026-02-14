-- =====================================================
-- 051: Notifications - Bildirim Sistemi
-- =====================================================
-- notifications tablosu, user_notification_settings, users.fcm_token
-- Bildirim tetikleyicileri ayrı migration'da (052)

-- Notifications tablosu
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT,
    data JSONB,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_read ON public.notifications(user_id, read_at) WHERE read_at IS NULL;

-- User notification settings (bildirim türüne göre aç/kapa)
CREATE TABLE IF NOT EXISTS public.user_notification_settings (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    settings JSONB NOT NULL DEFAULT '{
        "event_created": true,
        "event_updated": true,
        "carpool_application": true,
        "carpool_application_response": true,
        "event_chat_message": true,
        "post_created": true,
        "post_updated": true,
        "listing_created": true,
        "order_created": true,
        "order_status_changed": true
    }'::jsonb,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_notification_settings_user_id ON public.user_notification_settings(user_id);

-- FCM token (push bildirimler için, ileride kullanılacak)
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_notification_settings ENABLE ROW LEVEL SECURITY;

-- Kullanıcı sadece kendi bildirimlerini okuyabilir / güncelleyebilir (read_at)
CREATE POLICY "Users can view own notifications"
    ON public.notifications FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update own notifications"
    ON public.notifications FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Insert sadece trigger/fonksiyon ile (SECURITY DEFINER). Client insert yapmasın.
-- Service role veya backend fonksiyon insert yapacak; bu yüzden INSERT policy yok.
-- Trigger fonksiyonları SECURITY DEFINER kullanacak.

-- Kullanıcı kendi ayarlarını okuyup güncelleyebilir
CREATE POLICY "Users can view own notification settings"
    ON public.user_notification_settings FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own notification settings"
    ON public.user_notification_settings FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own notification settings"
    ON public.user_notification_settings FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- updated_at trigger for user_notification_settings
CREATE OR REPLACE FUNCTION update_user_notification_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS user_notification_settings_updated_at ON public.user_notification_settings;
CREATE TRIGGER user_notification_settings_updated_at
    BEFORE UPDATE ON public.user_notification_settings
    FOR EACH ROW EXECUTE FUNCTION update_user_notification_settings_updated_at();

COMMENT ON TABLE public.notifications IS 'Kullanıcı bildirimleri';
COMMENT ON TABLE public.user_notification_settings IS 'Bildirim türüne göre kullanıcı tercihleri';
