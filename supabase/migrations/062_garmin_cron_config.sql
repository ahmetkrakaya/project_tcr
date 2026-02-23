-- ============================================================
-- Garmin cron fix: app.settings kullanılamadığı için config tablosu
-- Mevcut cron job'ı kaldırıp config tablosu + wrapper fonksiyon ile yeniden kurar.
-- ============================================================

-- Eski cron job'ı kaldır (unrecognized config parameter veren)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('sync-garmin-workouts');
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END
$$;

-- Config tablosu (061'de yoksa burada oluşturuldu)
CREATE TABLE IF NOT EXISTS public.garmin_cron_config (
    id INT PRIMARY KEY DEFAULT 1,
    supabase_url TEXT NOT NULL DEFAULT '',
    service_role_key TEXT NOT NULL DEFAULT '',
    CONSTRAINT garmin_cron_config_single_row CHECK (id = 1)
);

ALTER TABLE public.garmin_cron_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Only backend can read garmin_cron_config" ON public.garmin_cron_config;
CREATE POLICY "Only backend can read garmin_cron_config"
    ON public.garmin_cron_config FOR SELECT
    USING (current_user NOT IN ('anon', 'authenticated'));

DROP POLICY IF EXISTS "Only backend can update garmin_cron_config" ON public.garmin_cron_config;
CREATE POLICY "Only backend can update garmin_cron_config"
    ON public.garmin_cron_config FOR ALL
    USING (current_user NOT IN ('anon', 'authenticated'));

-- Tek satır: URL ve key boş kalabilir; doldurulunca cron çalışır
INSERT INTO public.garmin_cron_config (id, supabase_url, service_role_key)
VALUES (1, '', '')
ON CONFLICT (id) DO NOTHING;

-- Config varsa Edge Function'ı tetikleyen fonksiyon
CREATE OR REPLACE FUNCTION public.trigger_garmin_push_workout()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_url TEXT;
    v_key TEXT;
BEGIN
    SELECT supabase_url, service_role_key
    INTO v_url, v_key
    FROM public.garmin_cron_config
    WHERE id = 1;
    IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
        RETURN;
    END IF;
    PERFORM net.http_post(
        url := v_url || '/functions/v1/garmin-push-workout',
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || v_key,
            'Content-Type', 'application/json'
        ),
        body := '{"mode":"cron"}'::jsonb
    );
END;
$$;

-- Cron job: Her gün 05:00 UTC
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'sync-garmin-workouts',
      '0 5 * * *',
      'SELECT public.trigger_garmin_push_workout();'
    );
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
  WHEN OTHERS THEN NULL;
END
$$;
