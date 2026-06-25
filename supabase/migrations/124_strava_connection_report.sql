-- Admin Strava bağlantı raporu

CREATE OR REPLACE FUNCTION public.get_strava_connection_report()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.admin_assert_super_admin();

    RETURN jsonb_build_object(
        'connected_count', (
            SELECT COUNT(DISTINCT u.id)::int
            FROM public.users u
            INNER JOIN public.user_integrations ui ON ui.user_id = u.id
            WHERE u.user_status = 'active'
              AND ui.provider = 'strava'
        ),
        'not_connected_count', (
            SELECT COUNT(*)::int
            FROM public.users u
            WHERE u.user_status = 'active'
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.user_integrations ui
                  WHERE ui.user_id = u.id
                    AND ui.provider = 'strava'
              )
        ),
        'not_connected_users', COALESCE((
            SELECT jsonb_agg(row_to_json(t) ORDER BY t.full_name)
            FROM (
                SELECT
                    u.id AS user_id,
                    TRIM(CONCAT(COALESCE(u.first_name, ''), ' ', COALESCE(u.last_name, ''))) AS full_name,
                    u.avatar_url
                FROM public.users u
                WHERE u.user_status = 'active'
                  AND NOT EXISTS (
                      SELECT 1
                      FROM public.user_integrations ui
                      WHERE ui.user_id = u.id
                        AND ui.provider = 'strava'
                  )
            ) t
        ), '[]'::jsonb)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_strava_connection_report() TO authenticated;
