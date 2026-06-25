-- ============================================================
-- 128: get_person_360 - haftalik/aylik km duzeltmesi
-- ============================================================
-- user_statistics.this_week_distance / this_month_distance cache
-- alanlari guvenilir guncellenmedigi icin (orn. "Bu Hafta" toplam
-- kadar gorunuyordu), bu degerleri activities'ten canli hesapliyoruz.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_person_360(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile     JSONB;
    v_stats       JSONB;
    v_points      INTEGER;
    v_strava      BOOLEAN;
    v_group_name  TEXT;
    v_last_open   TIMESTAMPTZ;
    v_recent      JSONB;
    v_load        JSONB;
BEGIN
    PERFORM public.assert_admin_or_coach();

    SELECT jsonb_build_object(
        'user_id', u.id,
        'full_name', TRIM(CONCAT(COALESCE(u.first_name, ''), ' ', COALESCE(u.last_name, ''))),
        'avatar_url', u.avatar_url,
        'vdot', u.vdot,
        'threshold_pace_seconds', u.threshold_pace_seconds
    ), u.last_app_open_at
    INTO v_profile, v_last_open
    FROM public.users u WHERE u.id = p_user_id;

    IF v_profile IS NULL THEN
        RAISE EXCEPTION 'Kullanici bulunamadi';
    END IF;

    SELECT jsonb_build_object(
        'total_distance_km', round(COALESCE(total_distance_meters, 0) / 1000.0, 1),
        'total_activities', COALESCE(total_activities, 0),
        'total_duration_seconds', COALESCE(total_duration_seconds, 0),
        'longest_run_km', round(COALESCE(longest_run_meters, 0) / 1000.0, 1),
        'this_week_km', (
            SELECT round(COALESCE(SUM(a.distance_meters), 0) / 1000.0, 1)
            FROM public.activities a
            WHERE a.user_id = p_user_id
              AND a.activity_type = 'running'
              AND a.start_time >= date_trunc('week', now())
        ),
        'this_month_km', (
            SELECT round(COALESCE(SUM(a.distance_meters), 0) / 1000.0, 1)
            FROM public.activities a
            WHERE a.user_id = p_user_id
              AND a.activity_type = 'running'
              AND a.start_time >= date_trunc('month', now())
        ),
        'last_activity_at', last_activity_at
    )
    INTO v_stats
    FROM public.user_statistics WHERE user_id = p_user_id;

    -- user_statistics satiri yoksa bile haftalik/aylik degerler dolsun
    IF v_stats IS NULL THEN
        v_stats := jsonb_build_object(
            'total_distance_km', 0,
            'total_activities', 0,
            'total_duration_seconds', 0,
            'longest_run_km', 0,
            'this_week_km', (
                SELECT round(COALESCE(SUM(a.distance_meters), 0) / 1000.0, 1)
                FROM public.activities a
                WHERE a.user_id = p_user_id
                  AND a.activity_type = 'running'
                  AND a.start_time >= date_trunc('week', now())
            ),
            'this_month_km', (
                SELECT round(COALESCE(SUM(a.distance_meters), 0) / 1000.0, 1)
                FROM public.activities a
                WHERE a.user_id = p_user_id
                  AND a.activity_type = 'running'
                  AND a.start_time >= date_trunc('month', now())
            ),
            'last_activity_at', NULL
        );
    END IF;

    SELECT COALESCE(SUM(points), 0)::int INTO v_points
    FROM public.user_race_points WHERE user_id = p_user_id;

    SELECT EXISTS (
        SELECT 1 FROM public.user_integrations
        WHERE user_id = p_user_id AND provider = 'strava'
    ) INTO v_strava;

    SELECT g.name INTO v_group_name
    FROM public.group_members gm
    JOIN public.training_groups g ON g.id = gm.group_id
    WHERE gm.user_id = p_user_id
    LIMIT 1;

    SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.start_time DESC), '[]'::jsonb)
    INTO v_recent
    FROM (
        SELECT a.title,
               a.start_time,
               round(COALESCE(a.distance_meters, 0) / 1000.0, 2) AS distance_km,
               a.duration_seconds,
               a.average_pace_seconds
        FROM public.activities a
        WHERE a.user_id = p_user_id
          AND a.activity_type = 'running'
        ORDER BY a.start_time DESC
        LIMIT 5
    ) r;

    v_load := public.athlete_load_snapshot(p_user_id);

    RETURN jsonb_build_object(
        'profile', v_profile,
        'group_name', v_group_name,
        'last_app_open_at', v_last_open,
        'total_points', v_points,
        'strava_connected', v_strava,
        'statistics', COALESCE(v_stats, '{}'::jsonb),
        'training_load', v_load,
        'recent_activities', v_recent
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_person_360(UUID) TO authenticated;
