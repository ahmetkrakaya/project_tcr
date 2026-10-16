-- TCR Migration 170: Strava detaylı aktivite verisi
-- - activities: Strava DetailedActivity alanları + senkron durumu + plan bağlantısı
-- - activity_laps, activity_best_efforts, activity_streams, activity_metrics,
--   activity_workout_compliance: kaynaktan bağımsız detay tabloları
-- - strava_enrichment_queue + strava_api_rate_state: rate-limit'e uyumlu zenginleştirme kuyruğu
-- - Detay verisini yalnızca aktivite sahibi, adminler ve sahibin grubundaki pacer'lar görür
--   (Strava API sözleşmesi: veri sahibi dışındakilere gösterim kısıtlı).

-- ============================================================
-- 1) activities: yeni kolonlar
-- ============================================================
ALTER TABLE public.activities
    ADD COLUMN IF NOT EXISTS sport_type TEXT,
    ADD COLUMN IF NOT EXISTS workout_type SMALLINT,
    ADD COLUMN IF NOT EXISTS perceived_exertion NUMERIC(3, 1),
    ADD COLUMN IF NOT EXISTS device_name TEXT,
    ADD COLUMN IF NOT EXISTS gear_id TEXT,
    ADD COLUMN IF NOT EXISTS gear_name TEXT,
    ADD COLUMN IF NOT EXISTS gear_distance_meters NUMERIC(12, 1),
    ADD COLUMN IF NOT EXISTS elapsed_seconds INTEGER,
    ADD COLUMN IF NOT EXISTS average_temp NUMERIC(4, 1),
    ADD COLUMN IF NOT EXISTS elev_high NUMERIC(7, 1),
    ADD COLUMN IF NOT EXISTS elev_low NUMERIC(7, 1),
    ADD COLUMN IF NOT EXISTS average_watts NUMERIC(6, 1),
    ADD COLUMN IF NOT EXISTS weighted_average_watts NUMERIC(6, 1),
    ADD COLUMN IF NOT EXISTS kilojoules NUMERIC(8, 1),
    ADD COLUMN IF NOT EXISTS suffer_score INTEGER,
    ADD COLUMN IF NOT EXISTS pr_count INTEGER,
    ADD COLUMN IF NOT EXISTS achievement_count INTEGER,
    ADD COLUMN IF NOT EXISTS is_trainer BOOLEAN,
    ADD COLUMN IF NOT EXISTS is_manual BOOLEAN,
    ADD COLUMN IF NOT EXISTS detail_synced_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS streams_synced_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS planned_entry_id UUID
        REFERENCES public.monthly_program_entries(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.activities.workout_type IS
    'Strava workout_type: koşuda 0=normal, 1=yarış, 2=uzun koşu, 3=antrenman.';
COMMENT ON COLUMN public.activities.perceived_exertion IS 'Strava RPE (1-10).';
COMMENT ON COLUMN public.activities.suffer_score IS 'Strava Relative Effort.';
COMMENT ON COLUMN public.activities.planned_entry_id IS
    'Plan eşleştiricinin bağladığı monthly_program_entries satırı.';

CREATE INDEX IF NOT EXISTS idx_activities_planned_entry_id
    ON public.activities(planned_entry_id) WHERE planned_entry_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_activities_device_name
    ON public.activities(device_name) WHERE device_name IS NOT NULL;

-- ============================================================
-- 2) activity_splits: ek kolonlar
-- ============================================================
ALTER TABLE public.activity_splits
    ADD COLUMN IF NOT EXISTS elapsed_seconds INTEGER,
    ADD COLUMN IF NOT EXISTS pace_zone SMALLINT,
    ADD COLUMN IF NOT EXISTS gap_pace_seconds INTEGER,
    ADD COLUMN IF NOT EXISTS average_cadence INTEGER;

-- ============================================================
-- 3) Detay tabloları
-- ============================================================
CREATE TABLE IF NOT EXISTS public.activity_laps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    activity_id UUID NOT NULL REFERENCES public.activities(id) ON DELETE CASCADE,
    lap_index INTEGER NOT NULL,
    name TEXT,
    start_offset_seconds INTEGER,
    elapsed_seconds INTEGER,
    moving_seconds INTEGER,
    distance_meters NUMERIC(10, 2),
    average_pace_seconds INTEGER,
    average_speed NUMERIC(6, 3),
    max_speed NUMERIC(6, 3),
    average_heart_rate INTEGER,
    max_heart_rate INTEGER,
    average_cadence INTEGER,
    average_watts NUMERIC(6, 1),
    elevation_gain NUMERIC(7, 1),
    start_index INTEGER,
    end_index INTEGER,
    kind TEXT CHECK (kind IN ('warmup', 'work', 'rest', 'cooldown', 'auto')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (activity_id, lap_index)
);

CREATE TABLE IF NOT EXISTS public.activity_best_efforts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    activity_id UUID NOT NULL REFERENCES public.activities(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    distance_meters NUMERIC(10, 2),
    elapsed_seconds INTEGER,
    moving_seconds INTEGER,
    pr_rank SMALLINT,
    start_index INTEGER,
    end_index INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (activity_id, name)
);

-- Kanal başına tam çözünürlüklü dizi + ekranda çizim için indirgenmiş preview.
-- GPS (latlng) bilinçli olarak saklanmaz; harita için activities.route_polyline yeterli.
CREATE TABLE IF NOT EXISTS public.activity_streams (
    activity_id UUID PRIMARY KEY REFERENCES public.activities(id) ON DELETE CASCADE,
    point_count INTEGER NOT NULL DEFAULT 0,
    time_seconds INTEGER[],
    distance_meters REAL[],
    altitude REAL[],
    velocity REAL[],
    heartrate SMALLINT[],
    cadence SMALLINT[],
    watts SMALLINT[],
    temp SMALLINT[],
    moving BOOLEAN[],
    grade REAL[],
    preview JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON COLUMN public.activity_streams.cadence IS 'Adım/dakika (Strava RPM x2).';
COMMENT ON COLUMN public.activity_streams.preview IS
    '~500 noktalık indirgenmiş seri: {t, d, pace, hr, alt, cad, w, grade}.';

CREATE TABLE IF NOT EXISTS public.activity_metrics (
    activity_id UUID PRIMARY KEY REFERENCES public.activities(id) ON DELETE CASCADE,
    hr_zones JSONB,
    pace_zones JSONB,
    gap_pace_seconds INTEGER,
    decoupling_pct NUMERIC(5, 1),
    hr_drift_pct NUMERIC(5, 1),
    trimp NUMERIC(6, 1),
    tss NUMERIC(6, 1),
    stopped_seconds INTEGER,
    stop_count INTEGER,
    pace_cv NUMERIC(5, 3),
    split_type TEXT CHECK (split_type IN ('negative', 'positive', 'even')),
    first_half_pace_seconds INTEGER,
    second_half_pace_seconds INTEGER,
    fastest_split INTEGER,
    slowest_split INTEGER,
    average_stride_meters NUMERIC(4, 2),
    hr_recovery JSONB,
    intervals JSONB,
    assumptions JSONB,
    computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON COLUMN public.activity_metrics.intervals IS
    'Turlar antrenmana göre bölünmemişse hız serisinden tespit edilen çalışma/dinlenme bölümleri.';
COMMENT ON COLUMN public.activity_metrics.assumptions IS
    'Hesaplamada kullanılan maks/dinlenik nabız, eşik pace gibi varsayımlar.';

CREATE TABLE IF NOT EXISTS public.activity_workout_compliance (
    activity_id UUID PRIMARY KEY REFERENCES public.activities(id) ON DELETE CASCADE,
    planned_entry_id UUID REFERENCES public.monthly_program_entries(id) ON DELETE CASCADE,
    match_method TEXT CHECK (match_method IN ('laps', 'intervals', 'stream')),
    steps JSONB NOT NULL DEFAULT '[]'::jsonb,
    score NUMERIC(5, 1),
    completed_reps INTEGER,
    planned_reps INTEGER,
    computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_activity_laps_activity_id ON public.activity_laps(activity_id);
CREATE INDEX IF NOT EXISTS idx_activity_best_efforts_activity_id ON public.activity_best_efforts(activity_id);
CREATE INDEX IF NOT EXISTS idx_activity_workout_compliance_entry
    ON public.activity_workout_compliance(planned_entry_id);

-- Sporcunun Strava kalp atışı zon sınırları (GET /athlete/zones)
ALTER TABLE public.user_integrations
    ADD COLUMN IF NOT EXISTS athlete_zones JSONB,
    ADD COLUMN IF NOT EXISTS athlete_zones_fetched_at TIMESTAMPTZ;

-- ============================================================
-- 4) Kuyruk + rate limit durumu (sadece service role)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.strava_enrichment_queue (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    strava_activity_id BIGINT NOT NULL UNIQUE,
    mode TEXT NOT NULL DEFAULT 'full' CHECK (mode IN ('full', 'refresh')),
    priority SMALLINT NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'done', 'failed', 'skipped')),
    attempts INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    locked_at TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON COLUMN public.strava_enrichment_queue.mode IS
    'full: eksik olanı (detail/streams) çek; refresh: detail ve streams yeniden çekilir.';

CREATE INDEX IF NOT EXISTS idx_strava_enrichment_queue_pick
    ON public.strava_enrichment_queue(status, priority, next_attempt_at);

DROP TRIGGER IF EXISTS update_strava_enrichment_queue_updated_at ON public.strava_enrichment_queue;
CREATE TRIGGER update_strava_enrichment_queue_updated_at
    BEFORE UPDATE ON public.strava_enrichment_queue
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.strava_api_rate_state (
    id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    limit_15m INTEGER,
    usage_15m INTEGER,
    limit_daily INTEGER,
    usage_daily INTEGER,
    read_limit_15m INTEGER,
    read_usage_15m INTEGER,
    read_limit_daily INTEGER,
    read_usage_daily INTEGER,
    blocked_until TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.strava_api_rate_state (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.strava_enrichment_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.strava_api_rate_state ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 5) Görüntüleme yetkisi
-- ============================================================
CREATE OR REPLACE FUNCTION public.can_view_activity_details(p_activity_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.activities a
        WHERE a.id = p_activity_id
          AND (
              a.user_id = auth.uid()
              OR public.is_super_admin()
              OR EXISTS (
                  SELECT 1
                  FROM public.group_pacers gp
                  JOIN public.group_members gm ON gm.group_id = gp.group_id
                  WHERE gp.user_id = auth.uid()
                    AND gm.user_id = a.user_id
              )
          )
    );
$$;

GRANT EXECUTE ON FUNCTION public.can_view_activity_details(UUID) TO authenticated;

ALTER TABLE public.activity_laps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_best_efforts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_streams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_workout_compliance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Activity laps viewable by owner, admin, pacer" ON public.activity_laps;
CREATE POLICY "Activity laps viewable by owner, admin, pacer"
    ON public.activity_laps FOR SELECT TO authenticated
    USING (public.can_view_activity_details(activity_id));

DROP POLICY IF EXISTS "Activity best efforts viewable by owner, admin, pacer" ON public.activity_best_efforts;
CREATE POLICY "Activity best efforts viewable by owner, admin, pacer"
    ON public.activity_best_efforts FOR SELECT TO authenticated
    USING (public.can_view_activity_details(activity_id));

DROP POLICY IF EXISTS "Activity streams viewable by owner, admin, pacer" ON public.activity_streams;
CREATE POLICY "Activity streams viewable by owner, admin, pacer"
    ON public.activity_streams FOR SELECT TO authenticated
    USING (public.can_view_activity_details(activity_id));

DROP POLICY IF EXISTS "Activity metrics viewable by owner, admin, pacer" ON public.activity_metrics;
CREATE POLICY "Activity metrics viewable by owner, admin, pacer"
    ON public.activity_metrics FOR SELECT TO authenticated
    USING (public.can_view_activity_details(activity_id));

DROP POLICY IF EXISTS "Activity compliance viewable by owner, admin, pacer" ON public.activity_workout_compliance;
CREATE POLICY "Activity compliance viewable by owner, admin, pacer"
    ON public.activity_workout_compliance FOR SELECT TO authenticated
    USING (public.can_view_activity_details(activity_id));

-- Split'ler de artık sadece sahip / admin / pacer tarafından görülebilir
DROP POLICY IF EXISTS "Activity splits viewable with activity" ON public.activity_splits;
CREATE POLICY "Activity splits viewable with activity"
    ON public.activity_splits FOR SELECT TO authenticated
    USING (public.can_view_activity_details(activity_id));

-- ============================================================
-- 6) Kuyruk fonksiyonları
-- ============================================================
CREATE OR REPLACE FUNCTION public.enqueue_strava_enrichment(
    p_user_id UUID,
    p_strava_activity_id BIGINT,
    p_mode TEXT DEFAULT 'full',
    p_priority SMALLINT DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.strava_enrichment_queue (user_id, strava_activity_id, mode, priority)
    VALUES (p_user_id, p_strava_activity_id, COALESCE(p_mode, 'full'), COALESCE(p_priority, 0))
    ON CONFLICT (strava_activity_id) DO UPDATE SET
        user_id = EXCLUDED.user_id,
        mode = CASE
            WHEN strava_enrichment_queue.status IN ('pending', 'processing')
                 AND strava_enrichment_queue.mode = 'refresh' THEN 'refresh'
            ELSE EXCLUDED.mode
        END,
        priority = CASE
            WHEN strava_enrichment_queue.status = 'pending'
                THEN LEAST(strava_enrichment_queue.priority, EXCLUDED.priority)
            ELSE EXCLUDED.priority
        END,
        status = CASE
            WHEN strava_enrichment_queue.status = 'processing' THEN 'processing'
            ELSE 'pending'
        END,
        attempts = CASE
            WHEN strava_enrichment_queue.status IN ('pending', 'processing')
                THEN strava_enrichment_queue.attempts
            ELSE 0
        END,
        next_attempt_at = CASE
            WHEN strava_enrichment_queue.status = 'pending'
                THEN strava_enrichment_queue.next_attempt_at
            ELSE NOW()
        END,
        last_error = NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enqueue_strava_enrichment(UUID, BIGINT, TEXT, SMALLINT)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_strava_enrichment(UUID, BIGINT, TEXT, SMALLINT) TO service_role;

-- Worker için atomik iş alma; 10 dakikadır "processing" kalan işler yeniden alınır.
CREATE OR REPLACE FUNCTION public.claim_strava_enrichment_jobs(p_limit INTEGER DEFAULT 5)
RETURNS SETOF public.strava_enrichment_queue
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    UPDATE public.strava_enrichment_queue q
    SET status = 'processing',
        locked_at = NOW(),
        attempts = q.attempts + 1
    WHERE q.id IN (
        SELECT id
        FROM public.strava_enrichment_queue
        WHERE (status = 'pending' AND next_attempt_at <= NOW())
           OR (status = 'processing' AND locked_at < NOW() - INTERVAL '10 minutes')
        ORDER BY priority, next_attempt_at
        LIMIT GREATEST(p_limit, 1)
        FOR UPDATE SKIP LOCKED
    )
    RETURNING q.*;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_strava_enrichment_jobs(INTEGER)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_strava_enrichment_jobs(INTEGER) TO service_role;

-- Yeni Strava koşusu (webhook, backfill veya uygulama senkronu) kuyruğa girer.
-- Rate limit bütçesi için sadece koşular zenginleştirilir.
CREATE OR REPLACE FUNCTION public.enqueue_strava_activity_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.source = 'strava'
       AND NEW.activity_type = 'running'
       AND NEW.external_id ~ '^[0-9]+$' THEN
        PERFORM public.enqueue_strava_enrichment(NEW.user_id, NEW.external_id::BIGINT, 'full', 0::SMALLINT);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_activities_enqueue_strava_enrichment ON public.activities;
CREATE TRIGGER trg_activities_enqueue_strava_enrichment
    AFTER INSERT ON public.activities
    FOR EACH ROW EXECUTE FUNCTION public.enqueue_strava_activity_on_insert();

-- Sahip veya admin bir aktivitenin detayını yeniden çektirebilir
CREATE OR REPLACE FUNCTION public.request_activity_enrichment(p_activity_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_activity RECORD;
BEGIN
    SELECT id, user_id, source, external_id
    INTO v_activity
    FROM public.activities
    WHERE id = p_activity_id;

    IF v_activity.id IS NULL THEN
        RAISE EXCEPTION 'Aktivite bulunamadi';
    END IF;

    IF v_activity.user_id <> auth.uid() AND NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Bu islem icin yetkiniz yok';
    END IF;

    IF v_activity.source <> 'strava' OR v_activity.external_id !~ '^[0-9]+$' THEN
        RETURN 'unsupported';
    END IF;

    PERFORM public.enqueue_strava_enrichment(
        v_activity.user_id, v_activity.external_id::BIGINT, 'refresh', 0::SMALLINT
    );
    RETURN 'queued';
END;
$$;

GRANT EXECUTE ON FUNCTION public.request_activity_enrichment(UUID) TO authenticated;

-- Geçmiş aktiviteleri düşük öncelikle kuyruğa ekler (admin veya service role)
CREATE OR REPLACE FUNCTION public.enqueue_strava_backfill(
    p_days INTEGER DEFAULT 60,
    p_limit INTEGER DEFAULT 2000
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER := 0;
    rec RECORD;
BEGIN
    IF auth.uid() IS NOT NULL AND NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Bu islem sadece adminler icindir';
    END IF;

    FOR rec IN
        SELECT a.user_id, a.external_id
        FROM public.activities a
        WHERE a.source = 'strava'
          AND a.activity_type = 'running'
          AND a.external_id ~ '^[0-9]+$'
          AND a.start_time >= NOW() - make_interval(days => GREATEST(p_days, 1))
          AND (a.detail_synced_at IS NULL OR a.streams_synced_at IS NULL)
          AND NOT EXISTS (
              SELECT 1 FROM public.strava_enrichment_queue q
              WHERE q.strava_activity_id = a.external_id::BIGINT
                AND q.status IN ('pending', 'processing', 'skipped')
          )
        ORDER BY a.start_time DESC
        LIMIT GREATEST(p_limit, 1)
    LOOP
        PERFORM public.enqueue_strava_enrichment(rec.user_id, rec.external_id::BIGINT, 'full', 10::SMALLINT);
        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enqueue_strava_backfill(INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enqueue_strava_backfill(INTEGER, INTEGER) TO authenticated, service_role;

-- ============================================================
-- 7) Uygulama için tek çağrıda analiz verisi
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_activity_analysis(p_activity_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_activity RECORD;
    v_queue_status TEXT;
    v_queue_attempts INTEGER;
    v_queue_error TEXT;
    v_queue_next TIMESTAMPTZ;
BEGIN
    IF NOT public.can_view_activity_details(p_activity_id) THEN
        RETURN jsonb_build_object('can_view', false);
    END IF;

    SELECT id, user_id, source, external_id, planned_entry_id, detail_synced_at, streams_synced_at
    INTO v_activity
    FROM public.activities
    WHERE id = p_activity_id;

    IF v_activity.source = 'strava' AND v_activity.external_id ~ '^[0-9]+$' THEN
        SELECT status, attempts, last_error, next_attempt_at
        INTO v_queue_status, v_queue_attempts, v_queue_error, v_queue_next
        FROM public.strava_enrichment_queue
        WHERE strava_activity_id = v_activity.external_id::BIGINT;
    END IF;

    RETURN jsonb_build_object(
        'can_view', true,
        'can_refresh', (v_activity.user_id = auth.uid() OR public.is_super_admin()),
        'sync', jsonb_build_object(
            'detail_synced_at', v_activity.detail_synced_at,
            'streams_synced_at', v_activity.streams_synced_at,
            'queue_status', v_queue_status,
            'queue_attempts', v_queue_attempts,
            'queue_error', v_queue_error,
            'queue_next_attempt_at', v_queue_next
        ),
        'laps', COALESCE((
            SELECT jsonb_agg(to_jsonb(l) - 'activity_id' - 'created_at' ORDER BY l.lap_index)
            FROM public.activity_laps l
            WHERE l.activity_id = p_activity_id
        ), '[]'::jsonb),
        'splits', COALESCE((
            SELECT jsonb_agg(to_jsonb(s) - 'activity_id' - 'created_at' ORDER BY s.split_number)
            FROM public.activity_splits s
            WHERE s.activity_id = p_activity_id
        ), '[]'::jsonb),
        'best_efforts', COALESCE((
            SELECT jsonb_agg(to_jsonb(b) - 'activity_id' - 'created_at' ORDER BY b.distance_meters)
            FROM public.activity_best_efforts b
            WHERE b.activity_id = p_activity_id
        ), '[]'::jsonb),
        'metrics', (
            SELECT to_jsonb(m) - 'activity_id'
            FROM public.activity_metrics m
            WHERE m.activity_id = p_activity_id
        ),
        'compliance', (
            SELECT to_jsonb(c) - 'activity_id'
            FROM public.activity_workout_compliance c
            WHERE c.activity_id = p_activity_id
        ),
        'streams_preview', (
            SELECT st.preview
            FROM public.activity_streams st
            WHERE st.activity_id = p_activity_id
        ),
        'planned', (
            SELECT jsonb_build_object(
                'id', e.id,
                'plan_date', e.plan_date,
                'program_content', e.program_content,
                'coach_notes', e.coach_notes,
                'training_type', tt.display_name
            )
            FROM public.monthly_program_entries e
            LEFT JOIN public.training_types tt ON tt.id = e.training_type_id
            WHERE e.id = v_activity.planned_entry_id
        )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_activity_analysis(UUID) TO authenticated;

-- ============================================================
-- 8) Admin: saat modeli dağılımı
-- ============================================================
CREATE OR REPLACE FUNCTION public.device_brand(p_device_name TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_device_name IS NULL OR btrim(p_device_name) = '' THEN 'unknown'
        WHEN p_device_name ILIKE 'garmin%' THEN 'garmin'
        WHEN p_device_name ILIKE 'apple watch%' THEN 'apple_watch'
        WHEN p_device_name ILIKE 'coros%' THEN 'coros'
        WHEN p_device_name ILIKE 'polar%' THEN 'polar'
        WHEN p_device_name ILIKE 'suunto%' THEN 'suunto'
        WHEN p_device_name ILIKE 'samsung%' OR p_device_name ILIKE 'galaxy%' THEN 'samsung'
        WHEN p_device_name ILIKE 'amazfit%' OR p_device_name ILIKE 'zepp%' THEN 'amazfit'
        WHEN p_device_name ILIKE 'huawei%' THEN 'huawei'
        WHEN p_device_name ILIKE 'fitbit%' OR p_device_name ILIKE 'pixel watch%' THEN 'google'
        WHEN p_device_name ILIKE 'wahoo%' THEN 'wahoo'
        WHEN p_device_name ILIKE 'strava%' OR p_device_name ILIKE '%iphone%' OR p_device_name ILIKE '%android%' THEN 'phone'
        ELSE 'other'
    END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_device_distribution(p_days INTEGER DEFAULT 90)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_since TIMESTAMPTZ := NOW() - make_interval(days => GREATEST(COALESCE(p_days, 90), 1));
    v_result JSONB;
BEGIN
    PERFORM public.assert_super_admin();

    WITH acts AS (
        SELECT a.user_id, a.device_name, public.device_brand(a.device_name) AS brand
        FROM public.activities a
        WHERE a.source = 'strava'
          AND a.activity_type = 'running'
          AND a.start_time >= v_since
          AND a.detail_synced_at IS NOT NULL
    ),
    -- Kullanıcının en çok kullandığı marka = birincil cihazı
    primary_brand AS (
        SELECT DISTINCT ON (user_id) user_id, brand
        FROM (
            SELECT user_id, brand, COUNT(*) AS cnt
            FROM acts
            GROUP BY user_id, brand
        ) x
        ORDER BY user_id, cnt DESC
    )
    SELECT jsonb_build_object(
        'days', p_days,
        'total_activities', (SELECT COUNT(*) FROM acts),
        'total_users', (SELECT COUNT(DISTINCT user_id) FROM acts),
        'brands', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'brand', b.brand,
                'activities', b.activities,
                'users', b.users,
                'primary_users', COALESCE(p.primary_users, 0)
            ) ORDER BY b.activities DESC)
            FROM (
                SELECT brand, COUNT(*) AS activities, COUNT(DISTINCT user_id) AS users
                FROM acts
                GROUP BY brand
            ) b
            LEFT JOIN (
                SELECT brand, COUNT(*) AS primary_users
                FROM primary_brand
                GROUP BY brand
            ) p ON p.brand = b.brand
        ), '[]'::jsonb),
        'models', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'device_name', m.device_name,
                'brand', public.device_brand(m.device_name),
                'activities', m.activities,
                'users', m.users
            ) ORDER BY m.activities DESC)
            FROM (
                SELECT device_name, COUNT(*) AS activities, COUNT(DISTINCT user_id) AS users
                FROM acts
                WHERE device_name IS NOT NULL
                GROUP BY device_name
                ORDER BY COUNT(*) DESC
                LIMIT 30
            ) m
        ), '[]'::jsonb)
    )
    INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_device_distribution(INTEGER) TO authenticated;

-- ============================================================
-- 9) Cron: strava-enrich worker (her 2 dakikada bir)
-- garmin_cron_config'teki supabase_url / service_role_key kullanılır.
-- ============================================================
CREATE OR REPLACE FUNCTION public.trigger_strava_enrich()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_url TEXT;
    v_key TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.strava_enrichment_queue
        WHERE (status = 'pending' AND next_attempt_at <= NOW())
           OR (status = 'processing' AND locked_at < NOW() - INTERVAL '10 minutes')
    ) THEN
        RETURN;
    END IF;

    SELECT supabase_url, service_role_key
    INTO v_url, v_key
    FROM public.garmin_cron_config
    WHERE id = 1;

    IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
        RETURN;
    END IF;

    PERFORM net.http_post(
        url := v_url || '/functions/v1/strava-enrich',
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || v_key,
            'Content-Type', 'application/json'
        ),
        body := '{}'::jsonb
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.trigger_strava_enrich() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        BEGIN
            PERFORM cron.unschedule('strava-enrich');
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        PERFORM cron.schedule(
            'strava-enrich',
            '*/2 * * * *',
            'SELECT public.trigger_strava_enrich();'
        );
    END IF;
EXCEPTION
    WHEN undefined_object THEN NULL;
    WHEN OTHERS THEN NULL;
END
$$;
