-- =====================================================
-- 112: Mazaret bildirimi sistemi (etkileşim analizleri)
-- =====================================================

CREATE TABLE IF NOT EXISTS public.engagement_excuse_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    excuse_type TEXT NOT NULL CHECK (excuse_type IN ('inactive_app', 'inactive_event')),
    status TEXT NOT NULL DEFAULT 'awaiting_submission'
        CHECK (status IN ('awaiting_submission', 'submitted', 'accepted')),
    excuse_text TEXT,
    exempt_until TIMESTAMPTZ,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    submitted_at TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES public.users(id),
    created_by UUID NOT NULL REFERENCES public.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_engagement_excuse_user_type
    ON public.engagement_excuse_requests(user_id, excuse_type, status);

CREATE INDEX IF NOT EXISTS idx_engagement_excuse_status
    ON public.engagement_excuse_requests(status, sent_at DESC);

-- Aynı kullanıcı+tür için tek bekleyen/gönderilmiş talep
CREATE UNIQUE INDEX IF NOT EXISTS idx_engagement_excuse_pending_per_user_type
    ON public.engagement_excuse_requests(user_id, excuse_type)
    WHERE status IN ('awaiting_submission', 'submitted');

ALTER TABLE public.engagement_excuse_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view all engagement excuses" ON public.engagement_excuse_requests;
CREATE POLICY "Admins can view all engagement excuses"
    ON public.engagement_excuse_requests FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid() AND role = 'super_admin'
        )
    );

DROP POLICY IF EXISTS "Users can view own pending excuse" ON public.engagement_excuse_requests;
CREATE POLICY "Users can view own pending excuse"
    ON public.engagement_excuse_requests FOR SELECT
    USING (
        user_id = auth.uid()
        AND status = 'awaiting_submission'
    );

-- Aktif mazaret muafiyeti var mı?
CREATE OR REPLACE FUNCTION public.has_active_engagement_excuse(
    p_user_id UUID,
    p_excuse_type TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.engagement_excuse_requests e
        WHERE e.user_id = p_user_id
          AND e.excuse_type = p_excuse_type
          AND (
              e.status IN ('awaiting_submission', 'submitted')
              OR (
                  e.status = 'accepted'
                  AND (e.exempt_until IS NULL OR e.exempt_until > NOW())
              )
          )
    );
$$;

-- Admin: mazaret bildirimi gönder
CREATE OR REPLACE FUNCTION public.send_engagement_excuse_requests(
    p_user_ids UUID[],
    p_excuse_type TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_request_id UUID;
    v_title TEXT := 'Mazaret Bildir';
    v_body TEXT;
    v_data JSONB;
    v_sent_ids UUID[] := '{}';
    v_skipped_ids UUID[] := '{}';
    v_recipient_ids UUID[] := '{}';
BEGIN
    PERFORM public.admin_assert_super_admin();

    IF p_excuse_type NOT IN ('inactive_app', 'inactive_event') THEN
        RAISE EXCEPTION 'Geçersiz mazaret türü';
    END IF;

    IF p_user_ids IS NULL OR array_length(p_user_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'Kullanıcı listesi boş';
    END IF;

    IF p_excuse_type = 'inactive_app' THEN
        v_body := 'Son 30 gündür uygulamaya giriş yapmadığınız tespit edildi. Uygulamayı kullanmaya devam edebilmek için mazaretinizi bildirmeniz gerekmektedir. Uygulamayı açtığınızda mazaret formu karşınıza çıkacaktır.';
    ELSE
        v_body := 'Son 30 gündür hiçbir etkinliğe katılmadığınız tespit edildi. Kulüp aktivitelerine katılım önemlidir. Uygulamayı kullanmaya devam edebilmek için mazaretinizi bildirmeniz gerekmektedir.';
    END IF;

    FOREACH v_user_id IN ARRAY p_user_ids
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = v_user_id
              AND u.is_active = true
              AND COALESCE(u.user_status, 'active') = 'active'
        ) THEN
            v_skipped_ids := array_append(v_skipped_ids, v_user_id);
            CONTINUE;
        END IF;

        IF public.has_active_engagement_excuse(v_user_id, p_excuse_type) THEN
            v_skipped_ids := array_append(v_skipped_ids, v_user_id);
            CONTINUE;
        END IF;

        INSERT INTO public.engagement_excuse_requests (
            user_id, excuse_type, status, created_by
        ) VALUES (
            v_user_id, p_excuse_type, 'awaiting_submission', auth.uid()
        )
        RETURNING id INTO v_request_id;

        v_data := jsonb_build_object(
            'excuse_request_id', v_request_id::text,
            'excuse_type', p_excuse_type,
            'target', 'engagement_excuse'
        );

        PERFORM public.insert_notifications(
            'engagement_excuse_request',
            v_title,
            v_body,
            v_data,
            ARRAY[v_user_id]
        );

        v_sent_ids := array_append(v_sent_ids, v_user_id);
        v_recipient_ids := array_append(v_recipient_ids, v_user_id);
    END LOOP;

    RETURN jsonb_build_object(
        'sent_count', COALESCE(array_length(v_sent_ids, 1), 0),
        'skipped_count', COALESCE(array_length(v_skipped_ids, 1), 0),
        'sent_user_ids', to_jsonb(v_sent_ids),
        'skipped_user_ids', to_jsonb(v_skipped_ids)
    );
END;
$$;

-- Kullanıcı: bekleyen mazaret talebi
CREATE OR REPLACE FUNCTION public.get_pending_engagement_excuse()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_row RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT
        e.id,
        e.excuse_type,
        e.status,
        e.sent_at
    INTO v_row
    FROM public.engagement_excuse_requests e
    WHERE e.user_id = v_user_id
      AND e.status = 'awaiting_submission'
    ORDER BY e.sent_at DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    RETURN jsonb_build_object(
        'id', v_row.id,
        'excuse_type', v_row.excuse_type,
        'status', v_row.status,
        'sent_at', v_row.sent_at
    );
END;
$$;

-- Kullanıcı: mazaret gönder
CREATE OR REPLACE FUNCTION public.submit_engagement_excuse(
    p_request_id UUID,
    p_text TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_trimmed TEXT := btrim(p_text);
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Oturum açılmamış';
    END IF;

    IF char_length(v_trimmed) < 30 THEN
        RAISE EXCEPTION 'Mazaret en az 30 karakter olmalıdır';
    END IF;

    UPDATE public.engagement_excuse_requests
    SET
        excuse_text = v_trimmed,
        status = 'submitted',
        submitted_at = NOW(),
        updated_at = NOW()
    WHERE id = p_request_id
      AND user_id = v_user_id
      AND status = 'awaiting_submission';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Geçerli mazaret talebi bulunamadı';
    END IF;

    RETURN true;
END;
$$;

-- Admin: mazaretleri listele
CREATE OR REPLACE FUNCTION public.get_engagement_excuse_admin_reports()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.admin_assert_super_admin();

    RETURN jsonb_build_object(
        'awaiting_submission', COALESCE((
            SELECT jsonb_agg(row_to_json(t) ORDER BY t.sent_at DESC)
            FROM (
                SELECT
                    e.id AS request_id,
                    e.user_id,
                    TRIM(CONCAT(COALESCE(u.first_name, ''), ' ', COALESCE(u.last_name, ''))) AS full_name,
                    e.excuse_type,
                    e.status,
                    e.sent_at,
                    e.submitted_at,
                    e.exempt_until
                FROM public.engagement_excuse_requests e
                JOIN public.users u ON u.id = e.user_id
                WHERE e.status = 'awaiting_submission'
                  AND u.is_active = true
                  AND COALESCE(u.user_status, 'active') = 'active'
            ) t
        ), '[]'::jsonb),
        'submitted', COALESCE((
            SELECT jsonb_agg(row_to_json(t) ORDER BY t.submitted_at DESC NULLS LAST)
            FROM (
                SELECT
                    e.id AS request_id,
                    e.user_id,
                    TRIM(CONCAT(COALESCE(u.first_name, ''), ' ', COALESCE(u.last_name, ''))) AS full_name,
                    e.excuse_type,
                    e.status,
                    e.excuse_text,
                    e.sent_at,
                    e.submitted_at,
                    e.exempt_until
                FROM public.engagement_excuse_requests e
                JOIN public.users u ON u.id = e.user_id
                WHERE e.status = 'submitted'
                  AND u.is_active = true
                  AND COALESCE(u.user_status, 'active') = 'active'
            ) t
        ), '[]'::jsonb),
        'accepted', COALESCE((
            SELECT jsonb_agg(row_to_json(t) ORDER BY t.reviewed_at DESC NULLS LAST)
            FROM (
                SELECT
                    e.id AS request_id,
                    e.user_id,
                    TRIM(CONCAT(COALESCE(u.first_name, ''), ' ', COALESCE(u.last_name, ''))) AS full_name,
                    e.excuse_type,
                    e.status,
                    e.excuse_text,
                    e.sent_at,
                    e.submitted_at,
                    e.exempt_until,
                    e.reviewed_at
                FROM public.engagement_excuse_requests e
                JOIN public.users u ON u.id = e.user_id
                WHERE e.status = 'accepted'
                  AND (e.exempt_until IS NULL OR e.exempt_until > NOW())
            ) t
        ), '[]'::jsonb)
    );
END;
$$;

-- Admin: mazareti kabul et veya banla
CREATE OR REPLACE FUNCTION public.review_engagement_excuse(
    p_request_id UUID,
    p_action TEXT,
    p_exempt_until TIMESTAMPTZ DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_status TEXT;
BEGIN
    PERFORM public.admin_assert_super_admin();

    IF p_action NOT IN ('accept', 'ban') THEN
        RAISE EXCEPTION 'Geçersiz işlem';
    END IF;

    SELECT e.user_id, e.status
    INTO v_user_id, v_status
    FROM public.engagement_excuse_requests e
    WHERE e.id = p_request_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mazaret talebi bulunamadı';
    END IF;

    IF v_status <> 'submitted' THEN
        RAISE EXCEPTION 'Sadece gönderilmiş mazaretler değerlendirilebilir';
    END IF;

    IF p_action = 'ban' THEN
        PERFORM public.deactivate_user(v_user_id, auth.uid());
        RETURN true;
    END IF;

    UPDATE public.engagement_excuse_requests
    SET
        status = 'accepted',
        exempt_until = p_exempt_until,
        reviewed_at = NOW(),
        reviewed_by = auth.uid(),
        updated_at = NOW()
    WHERE id = p_request_id;

    RETURN true;
END;
$$;

-- Etkileşim raporlarından muaf kullanıcıları çıkar
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
                  AND NOT EXISTS (
                      SELECT 1
                      FROM public.engagement_excuse_requests e
                      WHERE e.user_id = u.id
                        AND e.excuse_type = 'inactive_app'
                        AND e.status = 'accepted'
                        AND (e.exempt_until IS NULL OR e.exempt_until > NOW())
                  )
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
                  AND NOT EXISTS (
                      SELECT 1
                      FROM public.engagement_excuse_requests e
                      WHERE e.user_id = u.id
                        AND e.excuse_type = 'inactive_event'
                        AND e.status = 'accepted'
                        AND (e.exempt_until IS NULL OR e.exempt_until > NOW())
                  )
            ) t
        ), '[]'::jsonb)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.send_engagement_excuse_requests(UUID[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_engagement_excuse() TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_engagement_excuse(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_engagement_excuse_admin_reports() TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_engagement_excuse(UUID, TEXT, TIMESTAMPTZ) TO authenticated;
