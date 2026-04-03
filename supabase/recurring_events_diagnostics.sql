-- Recurring events diagnostics / manual checks
-- Run these in Supabase SQL Editor (production or staging).

-- 1) pg_cron extension enabled?
SELECT extname
FROM pg_extension
WHERE extname = 'pg_cron';

-- 2) recurring job exists?
SELECT jobid, jobname, schedule, command, active
FROM cron.job
WHERE jobname = 'create-next-recurring-events';

-- 3) last runs / errors
SELECT jobid, job_pid, status, return_message, start_time, end_time
FROM cron.job_run_details
WHERE jobid IN (
  SELECT jobid FROM cron.job WHERE jobname = 'create-next-recurring-events'
)
ORDER BY start_time DESC
LIMIT 20;

-- 4) trigger function manually
SELECT public.create_next_recurring_events();

-- 5) verify latest recurring series tails (Istanbul date)
SELECT
  COALESCE(parent_event_id, id) AS series_root_id,
  id,
  title,
  start_time AT TIME ZONE 'Europe/Istanbul' AS start_time_ist,
  recurrence_rule
FROM public.events
WHERE is_recurring = true
ORDER BY series_root_id, start_time DESC;

-- 6) observe scheduler logs (added in migration 083)
SELECT *
FROM public.recurring_event_job_logs
ORDER BY started_at DESC
LIMIT 50;
