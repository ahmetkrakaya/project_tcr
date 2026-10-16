-- ============================================================
-- Garmin Training API V2 - Otomatik Antrenman Senkronizasyonu
-- Garmin Connect'e gönderilen workout'ları takip eder.
-- pg_cron + pg_net ile günlük otomatik sync tetikler.
-- ============================================================

-- pg_net extension (Edge Function'ı HTTP ile çağırmak için)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ============================================================
-- Garmin'e gönderilen antrenmanları takip tablosu
-- ============================================================
CREATE TABLE public.garmin_sent_workouts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    program_id UUID NOT NULL,
    garmin_workout_id BIGINT,
    garmin_schedule_id BIGINT,
    scheduled_date DATE,
    workout_name TEXT,
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, event_id, program_id)
);

CREATE INDEX idx_garmin_sent_workouts_user_id ON public.garmin_sent_workouts(user_id);
CREATE INDEX idx_garmin_sent_workouts_event_id ON public.garmin_sent_workouts(event_id);
CREATE INDEX idx_garmin_sent_workouts_scheduled_date ON public.garmin_sent_workouts(scheduled_date);

CREATE TRIGGER update_garmin_sent_workouts_updated_at
    BEFORE UPDATE ON public.garmin_sent_workouts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- RLS
ALTER TABLE public.garmin_sent_workouts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own garmin sent workouts"
    ON public.garmin_sent_workouts FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Service role can manage garmin sent workouts"
    ON public.garmin_sent_workouts FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================================
-- Cron config: Supabase URL ve service role key (app.settings yok)
-- Bu tabloya değerleri bir kez manuel eklemen gerekir (Dashboard > SQL):
--   INSERT INTO public.garmin_cron_config (supabase_url, service_role_key)
--   VALUES ('https://PROJE_REF.supabase.co', 'service_role_key_buraya');
-- ============================================================
CREATE TABLE public.garmin_cron_config (
    id INT PRIMARY KEY DEFAULT 1,
    supabase_url TEXT NOT NULL DEFAULT '',
    service_role_key TEXT NOT NULL DEFAULT '',
    CONSTRAINT garmin_cron_config_single_row CHECK (id = 1)
);

ALTER TABLE public.garmin_cron_config ENABLE ROW LEVEL SECURITY;

-- Sadece postgres/supabase_admin okuyabilsin; anon/authenticated göremesin
CREATE POLICY "Only backend can read garmin_cron_config"
    ON public.garmin_cron_config FOR SELECT
    USING (current_user NOT IN ('anon', 'authenticated'));

CREATE POLICY "Only backend can update garmin_cron_config"
    ON public.garmin_cron_config FOR ALL
    USING (current_user NOT IN ('anon', 'authenticated'));

-- Config yoksa no-op; varsa Edge Function'ı tetikleyen fonksiyon
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

-- pg_cron job: Her gün 05:00 UTC (Türkiye 08:00) tetikle
DO $outer$
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
$outer$;
