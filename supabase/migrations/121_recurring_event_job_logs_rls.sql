-- ============================================================
-- recurring_event_job_logs: RLS etkinleştir
-- İç operasyon log tablosu; create_next_recurring_events() (SECURITY DEFINER)
-- ve pg_cron tarafından yazılır. Uygulama istemcilerinden erişilmez.
-- ============================================================

ALTER TABLE public.recurring_event_job_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Only backend can read recurring_event_job_logs"
    ON public.recurring_event_job_logs;
CREATE POLICY "Only backend can read recurring_event_job_logs"
    ON public.recurring_event_job_logs FOR SELECT
    USING (current_user NOT IN ('anon', 'authenticated'));

DROP POLICY IF EXISTS "Only backend can manage recurring_event_job_logs"
    ON public.recurring_event_job_logs;
CREATE POLICY "Only backend can manage recurring_event_job_logs"
    ON public.recurring_event_job_logs FOR ALL
    USING (current_user NOT IN ('anon', 'authenticated'));
