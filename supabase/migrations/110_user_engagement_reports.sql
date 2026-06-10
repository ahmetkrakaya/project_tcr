-- =====================================================
-- 110: Kullanıcı etkileşim raporları (uygulama açılışı + admin analizleri)
-- =====================================================

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS last_app_open_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.user_app_opens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_app_opens_user_opened
    ON public.user_app_opens(user_id, opened_at DESC);

ALTER TABLE public.user_app_opens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can insert own app opens" ON public.user_app_opens;
CREATE POLICY "Users can insert own app opens"
    ON public.user_app_opens FOR INSERT
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Admins can read app opens" ON public.user_app_opens;
CREATE POLICY "Admins can read app opens"
    ON public.user_app_opens FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- Uygulama açılışını kaydet (her soğuk başlatmada 1 kayıt — istemci tarafında tekilleştirilir)
CREATE OR REPLACE FUNCTION public.record_app_open()
RETURNS VOID AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO public.user_app_opens (user_id) VALUES (v_user_id);

    UPDATE public.users
    SET last_app_open_at = NOW(), updated_at = NOW()
    WHERE id = v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Admin kullanıcı etkileşim raporları
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
                    MAX(o.opened_at) AS last_open_at
                FROM public.user_app_opens o
                JOIN public.users u ON u.id = o.user_id
                WHERE u.is_active = true
                GROUP BY u.id, u.first_name, u.last_name
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
                    GREATEST(
                        COALESCE(u.last_app_open_at, '1970-01-01'::timestamptz),
                        COALESCE(au.last_sign_in_at, '1970-01-01'::timestamptz)
                    ) AS last_activity_at
                FROM public.users u
                LEFT JOIN auth.users au ON au.id = u.id
                WHERE u.is_active = true
                  AND COALESCE(u.user_status, 'active') = 'active'
                  AND GREATEST(
                        COALESCE(u.last_app_open_at, '1970-01-01'::timestamptz),
                        COALESCE(au.last_sign_in_at, '1970-01-01'::timestamptz)
                      ) < NOW() - INTERVAL '30 days'
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
