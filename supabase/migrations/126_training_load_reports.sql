-- ============================================================
-- 126: Training Load Reports - ortak snapshot + etkinlik bazli rapor
-- ============================================================
-- 125'teki overview mantigi tek bir yardimci fonksiyona (athlete_load_snapshot)
-- tasinir; hem koc paneli hem etkinlik yaris-formu raporu bunu kullanir.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Tek sporcunun guncel yuk anlik goruntusu
-- ------------------------------------------------------------
-- Doner: { ctl, atl, tsb, acute_7d, chronic_28d, acwr, ramp_pct, distance_7d_km, status }
CREATE OR REPLACE FUNCTION public.athlete_load_snapshot(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_warmup  INTEGER := 90;
    v_start   DATE := CURRENT_DATE - v_warmup;
    v_thr     INTEGER;
    v_birth   DATE;
    rec       RECORD;
    v_ctl     NUMERIC := 0;
    v_atl     NUMERIC := 0;
    v_acute   NUMERIC;
    v_prev    NUMERIC;
    v_chronic NUMERIC;
    v_acwr    NUMERIC;
    v_ramp    NUMERIC;
    v_status  TEXT;
    v_km7     NUMERIC;
BEGIN
    SELECT threshold_pace_seconds, birth_date
    INTO v_thr, v_birth
    FROM public.users WHERE id = p_user_id;

    -- Gunluk EWMA (CTL/ATL) son 90 gun
    FOR rec IN
        SELECT
            gs::date AS d,
            COALESCE(t.tss, 0)::NUMERIC AS day_tss
        FROM generate_series(v_start, CURRENT_DATE, INTERVAL '1 day') gs
        LEFT JOIN (
            SELECT
                (a.start_time AT TIME ZONE 'UTC')::date AS d,
                SUM(public.run_tss(
                    a.duration_seconds,
                    a.average_pace_seconds,
                    v_thr,
                    a.average_heart_rate,
                    v_birth
                )) AS tss
            FROM public.activities a
            WHERE a.user_id = p_user_id
              AND a.activity_type = 'running'
              AND (a.start_time AT TIME ZONE 'UTC')::date >= v_start
            GROUP BY 1
        ) t ON t.d = gs::date
        ORDER BY gs
    LOOP
        v_ctl := v_ctl + (rec.day_tss - v_ctl) / 42.0;
        v_atl := v_atl + (rec.day_tss - v_atl) / 7.0;
    END LOOP;

    -- Akut / kronik yukler ve mesafe
    SELECT
        COALESCE(SUM(public.run_tss(a.duration_seconds, a.average_pace_seconds,
                    v_thr, a.average_heart_rate, v_birth))
                 FILTER (WHERE (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 7), 0),
        COALESCE(SUM(public.run_tss(a.duration_seconds, a.average_pace_seconds,
                    v_thr, a.average_heart_rate, v_birth))
                 FILTER (WHERE (a.start_time AT TIME ZONE 'UTC')::date <= CURRENT_DATE - 7
                         AND (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 14), 0),
        COALESCE(SUM(public.run_tss(a.duration_seconds, a.average_pace_seconds,
                    v_thr, a.average_heart_rate, v_birth))
                 FILTER (WHERE (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 28), 0),
        COALESCE(SUM(a.distance_meters)
                 FILTER (WHERE (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 7), 0) / 1000.0
    INTO v_acute, v_prev, v_chronic, v_km7
    FROM public.activities a
    WHERE a.user_id = p_user_id
      AND a.activity_type = 'running'
      AND (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 28;

    IF v_chronic > 0 THEN
        v_acwr := round(v_acute / (v_chronic / 4.0), 2);
    ELSE
        v_acwr := NULL;
    END IF;

    IF v_prev > 0 THEN
        v_ramp := round((v_acute - v_prev) / v_prev * 100.0, 0);
    ELSE
        v_ramp := NULL;
    END IF;

    IF v_acwr IS NULL THEN
        v_status := 'unknown';
    ELSIF v_acwr > 1.5 OR v_acwr < 0.5 THEN
        v_status := 'risk';
    ELSIF v_acwr > 1.3 OR v_acwr < 0.8 THEN
        v_status := 'warning';
    ELSE
        v_status := 'ok';
    END IF;

    RETURN jsonb_build_object(
        'ctl',            round(v_ctl, 1),
        'atl',            round(v_atl, 1),
        'tsb',            round(v_ctl - v_atl, 1),
        'acute_7d',       round(v_acute, 0),
        'chronic_28d',    round(v_chronic, 0),
        'acwr',           v_acwr,
        'ramp_pct',       v_ramp,
        'distance_7d_km', round(v_km7, 1),
        'status',         v_status
    );
END;
$$;

-- Yardimci yalnizca dahili RPC'lerden cagrilir; dogrudan client erisimini kapat.
REVOKE EXECUTE ON FUNCTION public.athlete_load_snapshot(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.athlete_load_snapshot(UUID) FROM authenticated;

-- ------------------------------------------------------------
-- 2) Koc paneli ozet (yardimciyi kullanacak sekilde sadelestirildi)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_coach_training_load_overview(
    p_group_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_start  DATE := CURRENT_DATE - 90;
    v_result JSONB := '[]'::jsonb;
    u        RECORD;
BEGIN
    PERFORM public.assert_admin_or_coach();

    FOR u IN
        SELECT
            usr.id,
            TRIM(CONCAT(COALESCE(usr.first_name, ''), ' ', COALESCE(usr.last_name, ''))) AS full_name,
            usr.avatar_url
        FROM public.users usr
        WHERE usr.user_status = 'active'
          AND (
              p_group_id IS NULL
              OR EXISTS (
                  SELECT 1 FROM public.group_members gm
                  WHERE gm.user_id = usr.id AND gm.group_id = p_group_id
              )
          )
          AND EXISTS (
              SELECT 1 FROM public.activities a
              WHERE a.user_id = usr.id
                AND a.activity_type = 'running'
                AND (a.start_time AT TIME ZONE 'UTC')::date >= v_start
          )
    LOOP
        v_result := v_result || (
            jsonb_build_object(
                'user_id',   u.id,
                'full_name', CASE WHEN length(u.full_name) > 0 THEN u.full_name ELSE 'Isimsiz' END,
                'avatar_url', u.avatar_url
            ) || public.athlete_load_snapshot(u.id)
        );
    END LOOP;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_coach_training_load_overview(UUID) TO authenticated;

-- ------------------------------------------------------------
-- 3) Etkinlik bazli yaris-formu raporu
-- ------------------------------------------------------------
-- Etkinlige "going" diyen katilimcilarin guncel form/yuk durumu.
CREATE OR REPLACE FUNCTION public.get_event_training_load(p_event_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_start  DATE := CURRENT_DATE - 90;
    v_result JSONB := '[]'::jsonb;
    u        RECORD;
BEGIN
    PERFORM public.assert_admin_or_coach();

    FOR u IN
        SELECT
            usr.id,
            TRIM(CONCAT(COALESCE(usr.first_name, ''), ' ', COALESCE(usr.last_name, ''))) AS full_name,
            usr.avatar_url
        FROM public.event_participants ep
        INNER JOIN public.users usr ON usr.id = ep.user_id
        WHERE ep.event_id = p_event_id
          AND ep.status = 'going'
          AND usr.user_status = 'active'
          AND EXISTS (
              SELECT 1 FROM public.activities a
              WHERE a.user_id = usr.id
                AND a.activity_type = 'running'
                AND (a.start_time AT TIME ZONE 'UTC')::date >= v_start
          )
    LOOP
        v_result := v_result || (
            jsonb_build_object(
                'user_id',   u.id,
                'full_name', CASE WHEN length(u.full_name) > 0 THEN u.full_name ELSE 'Isimsiz' END,
                'avatar_url', u.avatar_url
            ) || public.athlete_load_snapshot(u.id)
        );
    END LOOP;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_event_training_load(UUID) TO authenticated;
