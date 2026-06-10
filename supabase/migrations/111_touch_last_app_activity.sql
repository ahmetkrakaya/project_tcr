-- Son kullanım zamanını güncelle (açılış sayacına eklemeden — arka plandan dönüşler için)
CREATE OR REPLACE FUNCTION public.touch_last_app_activity()
RETURNS VOID AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    UPDATE public.users
    SET last_app_open_at = NOW(), updated_at = NOW()
    WHERE id = v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Raporlarda "son giriş" = önce uygulama kullanımı, yoksa auth oturumu
CREATE OR REPLACE FUNCTION public.get_user_engagement_reports(p_event_type TEXT DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid() AND role = 'super_admin'
    ) INTO v_is_admin;

    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Sadece adminler bu raporu görüntüleyebilir';
    END IF;

    RETURN jsonb_build_object(
        'top_app_openers', COALESCE((
            SELECT jsonb_agg(row_to_json(t) ORDER BY t.open_count DESC)
            FROM (
                SELECT
                    u.id AS user_id,
                    TRIM(CONCAT(COALESCE(u.first_name, ''), ' ', COALESCE(u.last_name, ''))) AS full_name,
                    COUNT(*)::int AS open_count,
                    COALESCE(u.last_app_open_at, MAX(o.opened_at)) AS last_open_at
                FROM public.user_app_opens o
                JOIN public.users u ON u.id = o.user_id
                WHERE u.is_active = true
                GROUP BY u.id, u.first_name, u.last_name, u.last_app_open_at
                ORDER BY open_count DESC
                LIMIT 10
            ) t
        ), '[]'::jsonb),
        'inactive_app_users', COALESCE((
            SELECT jsonb_agg(row_to_json(t) ORDER BY t.last_activity_at NULLS FIRST, t.full_name)
            FROM (
                SELECT
                    u.id AS user_id,
                    TRIM(CONCAT(COALESCE(u.first_name, ''), ' ', COALESCE(u.last_name, ''))) AS full_name,
                    COALESCE(u.last_app_open_at, au.last_sign_in_at) AS last_activity_at
                FROM public.users u
                LEFT JOIN auth.users au ON au.id = u.id
                WHERE u.is_active = true
                  AND COALESCE(u.user_status, 'active') = 'active'
                  AND COALESCE(u.last_app_open_at, au.last_sign_in_at, '1970-01-01'::timestamptz)
                      < NOW() - INTERVAL '30 days'
            ) t
        ), '[]'::jsonb),
        'top_event_participants', COALESCE((
            SELECT jsonb_agg(row_to_json(t) ORDER BY t.participation_count DESC)
            FROM (
                SELECT
                    u.id AS user_id,
                    TRIM(CONCAT(COALESCE(u.first_name, ''), ' ', COALESCE(u.last_name, ''))) AS full_name,
                    COUNT(DISTINCT ep.event_id)::int AS participation_count
                FROM public.event_participants ep
                JOIN public.events e ON e.id = ep.event_id
                JOIN public.users u ON u.id = ep.user_id
                WHERE ep.status = 'going'
                  AND e.status != 'cancelled'
                  AND e.start_time <= NOW()
                  AND u.is_active = true
                  AND (p_event_type IS NULL OR e.event_type::text = p_event_type)
                GROUP BY u.id, u.first_name, u.last_name
                ORDER BY participation_count DESC
                LIMIT 10
            ) t
        ), '[]'::jsonb),
        'inactive_event_users', COALESCE((
            SELECT jsonb_agg(row_to_json(t) ORDER BY t.full_name)
            FROM (
                SELECT
                    u.id AS user_id,
                    TRIM(CONCAT(COALESCE(u.first_name, ''), ' ', COALESCE(u.last_name, ''))) AS full_name,
                    (
                        SELECT MAX(e.start_time)
                        FROM public.event_participants ep
                        JOIN public.events e ON e.id = ep.event_id
                        WHERE ep.user_id = u.id
                          AND ep.status = 'going'
                          AND e.status != 'cancelled'
                    ) AS last_participation_at
                FROM public.users u
                WHERE u.is_active = true
                  AND COALESCE(u.user_status, 'active') = 'active'
                  AND NOT EXISTS (
                      SELECT 1
                      FROM public.event_participants ep
                      JOIN public.events e ON e.id = ep.event_id
                      WHERE ep.user_id = u.id
                        AND ep.status = 'going'
                        AND e.status != 'cancelled'
                        AND e.start_time >= NOW() - INTERVAL '30 days'
                  )
            ) t
        ), '[]'::jsonb)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
