-- ============================================================
-- Integration OAuth config: Strava (ve ileride Garmin vb.) client_id / client_secret
-- Sadece backend (service_role) okuyabilir; uygulama içinde secret tutulmaz.
-- Değerleri Dashboard > SQL ile bir kez ekleyin:
--   INSERT INTO public.integration_oauth_config (provider, client_id, client_secret)
--   VALUES ('strava', 'STRAVA_CLIENT_ID', 'STRAVA_CLIENT_SECRET')
--   ON CONFLICT (provider) DO UPDATE SET client_id = EXCLUDED.client_id, client_secret = EXCLUDED.client_secret;
-- ============================================================

CREATE TABLE IF NOT EXISTS public.integration_oauth_config (
    provider TEXT PRIMARY KEY,
    client_id TEXT NOT NULL DEFAULT '',
    client_secret TEXT NOT NULL DEFAULT ''
);

ALTER TABLE public.integration_oauth_config ENABLE ROW LEVEL SECURITY;

-- Sadece backend (postgres, service_role) okuyabilsin; anon/authenticated göremesin
CREATE POLICY "Only backend can read integration_oauth_config"
    ON public.integration_oauth_config FOR SELECT
    USING (current_user NOT IN ('anon', 'authenticated'));

CREATE POLICY "Only backend can manage integration_oauth_config"
    ON public.integration_oauth_config FOR ALL
    USING (current_user NOT IN ('anon', 'authenticated'));

COMMENT ON TABLE public.integration_oauth_config IS 'OAuth client_id/client_secret per provider (strava, garmin). Read only by service_role.';
