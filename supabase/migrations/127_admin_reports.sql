-- ============================================================
-- 127: Admin Raporlari - Etkinlik Turu Trendi, Grup Durum, Kisi 360
-- ============================================================
-- Hepsi SECURITY DEFINER + assert_admin_or_coach() korumali.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Etkinlik turu trendi: ay x tur kirilimi
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_event_type_trend(
    p_start DATE DEFAULT (CURRENT_DATE - 180),
    p_end   DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    PERFORM public.assert_admin_or_coach();

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.month, t.event_type), '[]'::jsonb)
    INTO v_result
    FROM (
        SELECT
            to_char(date_trunc('month', e.start_time), 'YYYY-MM') AS month,
            e.event_type::text AS event_type,
            COUNT(DISTINCT e.id)::int AS events,
            COUNT(DISTINCT ep.user_id) FILTER (WHERE ep.status = 'going')::int AS participants
        FROM public.events e
        LEFT JOIN public.event_participants ep ON ep.event_id = e.id
        WHERE e.status IN ('published', 'completed')
          AND e.start_time::date >= p_start
          AND e.start_time::date <= p_end
        GROUP BY 1, 2
    ) t;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_event_type_trend(DATE, DATE) TO authenticated;

-- ------------------------------------------------------------
-- 2) Grup durum panosu
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_group_status_overview()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    PERFORM public.assert_admin_or_coach();

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.member_count DESC, t.name), '[]'::jsonb)
    INTO v_result
    FROM (
        SELECT
            g.id,
            g.name,
            g.group_type,
            g.color,
            COALESCE(mc.member_count, 0)::int AS member_count,
            COALESCE(act.active_members, 0)::int AS active_members_7d,
            (COALESCE(mc.member_count, 0) - COALESCE(act30.active_members, 0))::int AS passive_members_30d,
            COALESCE(pend.pending_count, 0)::int AS pending_requests,
            round(COALESCE(act.total_km, 0), 1) AS distance_7d_km
        FROM public.training_groups g
        LEFT JOIN (
            SELECT group_id, COUNT(*) AS member_count
            FROM public.group_members GROUP BY group_id
        ) mc ON mc.group_id = g.id
        -- son 7 gun kosan uye sayisi + toplam km
        LEFT JOIN (
            SELECT gm.group_id,
                   COUNT(DISTINCT a.user_id) AS active_members,
                   COALESCE(SUM(a.distance_meters), 0) / 1000.0 AS total_km
            FROM public.group_members gm
            JOIN public.activities a ON a.user_id = gm.user_id
            WHERE a.activity_type = 'running'
              AND (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 7
            GROUP BY gm.group_id
        ) act ON act.group_id = g.id
        -- son 30 gun aktif uye (uygulama acilisi VEYA aktivite)
        LEFT JOIN (
            SELECT gm.group_id, COUNT(DISTINCT gm.user_id) AS active_members
            FROM public.group_members gm
            JOIN public.users u ON u.id = gm.user_id
            WHERE u.last_app_open_at > NOW() - INTERVAL '30 days'
               OR EXISTS (
                   SELECT 1 FROM public.activities a
                   WHERE a.user_id = gm.user_id
                     AND (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 30
               )
            GROUP BY gm.group_id
        ) act30 ON act30.group_id = g.id
        LEFT JOIN (
            SELECT group_id, COUNT(*) AS pending_count
            FROM public.group_join_requests
            WHERE status = 'pending'
            GROUP BY group_id
        ) pend ON pend.group_id = g.id
        WHERE g.is_active = true
    ) t;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_group_status_overview() TO authenticated;

-- ------------------------------------------------------------
-- 3) Kisi 360: tek kullanicinin birlesik ozeti
-- ------------------------------------------------------------
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
        -- Haftalik/aylik degerleri cache yerine activities'ten canli hesapla
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
