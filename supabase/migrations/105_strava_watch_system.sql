-- =====================================================
-- 105: Strava Watch System
-- =====================================================
-- Ahmet ve Ayça'nın koşularını Ömer'e bildiren sistem.
-- strava_watch_config: kimin kimi izlediği
-- strava_watch_notifications: her koşu için bildirim durumu (görüldü mü?)

-- strava_watch_config: izleme konfigürasyonu
CREATE TABLE IF NOT EXISTS public.strava_watch_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    watcher_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    watched_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(watcher_user_id, watched_user_id)
);

CREATE INDEX IF NOT EXISTS idx_strava_watch_config_watcher ON public.strava_watch_config(watcher_user_id);
CREATE INDEX IF NOT EXISTS idx_strava_watch_config_watched ON public.strava_watch_config(watched_user_id);

-- strava_watch_notifications: her yeni koşu için bildirim takibi
CREATE TABLE IF NOT EXISTS public.strava_watch_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activity_id UUID NOT NULL REFERENCES public.activities(id) ON DELETE CASCADE,
    watcher_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    watched_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    first_notified_at TIMESTAMPTZ DEFAULT NOW(),
    last_notified_at TIMESTAMPTZ DEFAULT NOW(),
    viewed_at TIMESTAMPTZ,
    notification_count INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(activity_id, watcher_user_id)
);

CREATE INDEX IF NOT EXISTS idx_strava_watch_notif_watcher ON public.strava_watch_notifications(watcher_user_id);
CREATE INDEX IF NOT EXISTS idx_strava_watch_notif_activity ON public.strava_watch_notifications(activity_id);
CREATE INDEX IF NOT EXISTS idx_strava_watch_notif_unviewed ON public.strava_watch_notifications(watcher_user_id, viewed_at) WHERE viewed_at IS NULL;

-- RLS
ALTER TABLE public.strava_watch_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.strava_watch_notifications ENABLE ROW LEVEL SECURITY;

-- İzleyici kendi config kayıtlarını okuyabilir
CREATE POLICY "Watcher can view own watch config"
    ON public.strava_watch_config FOR SELECT
    USING (auth.uid() = watcher_user_id OR auth.uid() = watched_user_id);

-- İzleyici kendi bildirim durumlarını okuyabilir ve viewed_at'i güncelleyebilir
CREATE POLICY "Watcher can view own watch notifications"
    ON public.strava_watch_notifications FOR SELECT
    USING (auth.uid() = watcher_user_id OR auth.uid() = watched_user_id);

CREATE POLICY "Watcher can update own watch notifications"
    ON public.strava_watch_notifications FOR UPDATE
    USING (auth.uid() = watcher_user_id)
    WITH CHECK (auth.uid() = watcher_user_id);

COMMENT ON TABLE public.strava_watch_config IS 'Strava koşu takip sistemi - kimin kimi izlediği';
COMMENT ON TABLE public.strava_watch_notifications IS 'Her yeni koşu için bildirim durumu (görüldü mü, kaç kez gönderildi)';

-- Başlangıç verileri: Ömer -> Ahmet ve Ayça'yı izliyor
INSERT INTO public.strava_watch_config (watcher_user_id, watched_user_id, is_active)
VALUES
    ('376cd156-abdd-4c2e-85a8-35dc88043cc1', 'b30a2dbf-6c44-4cc9-b740-12ed0ed08e37', true),
    ('376cd156-abdd-4c2e-85a8-35dc88043cc1', 'a9cb8485-af1e-4299-a744-088bdadacbc9', true)
ON CONFLICT (watcher_user_id, watched_user_id) DO NOTHING;
