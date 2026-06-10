-- =====================================================
-- 106: Strava Watch Reminder - Saatlik Cron Job
-- =====================================================
-- pg_cron ile saatlik strava-watch-reminder fonksiyonu çağrılır.
-- Ömer, Ahmet/Ayça'nın koşusunu 1 saat içinde görmediyse hatırlatma bildirimi gönderilir.

-- pg_cron extension'ı etkinleştir (zaten etkinse hata vermez)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Saatlik cron job: her saat başı çalışır
SELECT cron.schedule(
  'strava-watch-reminder-hourly',
  '0 * * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.supabase_url') || '/functions/v1/strava-watch-reminder',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.service_role_key')
    ),
    body := '{}'::jsonb
  );
  $$
);

COMMENT ON EXTENSION pg_cron IS 'Strava watch reminder saatlik cron job için';
