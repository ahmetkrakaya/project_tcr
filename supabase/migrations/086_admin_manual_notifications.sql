-- ============================================================
-- 086: Admin manuel bildirim gönderimi (anlik + planli)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.admin_notification_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    type TEXT NOT NULL DEFAULT 'admin_manual',
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    audience JSONB NOT NULL DEFAULT '{}'::jsonb,
    data JSONB,
    scheduled_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed')),
    recipient_count INTEGER NOT NULL DEFAULT 0,
    processed_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_notification_queue_status_scheduled
ON public.admin_notification_queue(status, scheduled_at);

ALTER TABLE public.admin_notification_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Only super admins can view admin_notification_queue" ON public.admin_notification_queue;
CREATE POLICY "Only super admins can view admin_notification_queue"
    ON public.admin_notification_queue FOR SELECT
    USING (
      EXISTS (
        SELECT 1 FROM public.user_roles ur
        WHERE ur.user_id = auth.uid()
          AND ur.role = 'super_admin'
      )
    );

DROP POLICY IF EXISTS "Only backend can manage admin_notification_queue" ON public.admin_notification_queue;
CREATE POLICY "Only backend can manage admin_notification_queue"
    ON public.admin_notification_queue FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

CREATE OR REPLACE FUNCTION public.admin_assert_super_admin()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM public.user_roles ur
        WHERE ur.user_id = auth.uid()
          AND ur.role = 'super_admin'
    ) INTO v_is_admin;

    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Bu islem sadece adminler icindir';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_resolve_manual_notification_recipients(p_audience JSONB)
RETURNS UUID[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_everyone BOOLEAN := COALESCE((p_audience->>'everyone')::BOOLEAN, false);
    v_admins BOOLEAN := COALESCE((p_audience->>'admins')::BOOLEAN, false);
    v_coaches BOOLEAN := COALESCE((p_audience->>'coaches')::BOOLEAN, false);
    v_members BOOLEAN := COALESCE((p_audience->>'members')::BOOLEAN, false);
    v_group_ids UUID[] := ARRAY(
      SELECT jsonb_array_elements_text(COALESCE(p_audience->'group_ids', '[]'::jsonb))::UUID
    );
    v_strava_connected BOOLEAN := (p_audience->>'strava_connected')::BOOLEAN;
    v_garmin_connected BOOLEAN := (p_audience->>'garmin_connected')::BOOLEAN;
    v_vdot_missing BOOLEAN := COALESCE((p_audience->>'vdot_missing')::BOOLEAN, false);
    v_has_primary_filter BOOLEAN;
    v_recipients UUID[];
BEGIN
    v_has_primary_filter := (v_admins OR v_coaches OR v_members OR array_length(v_group_ids, 1) IS NOT NULL);

    SELECT ARRAY_AGG(DISTINCT u.id)
    INTO v_recipients
    FROM public.users u
    WHERE u.is_active = true
      AND (
        v_everyone = true
        OR v_has_primary_filter = false
        OR (
          (v_admins AND EXISTS (
            SELECT 1 FROM public.user_roles ur
            WHERE ur.user_id = u.id AND ur.role = 'super_admin'
          ))
          OR (v_coaches AND EXISTS (
            SELECT 1 FROM public.user_roles ur
            WHERE ur.user_id = u.id AND ur.role = 'coach'
          ))
          OR (v_members AND EXISTS (
            SELECT 1 FROM public.user_roles ur
            WHERE ur.user_id = u.id AND ur.role = 'member'
          ))
          OR (
            array_length(v_group_ids, 1) IS NOT NULL
            AND EXISTS (
              SELECT 1
              FROM public.group_members gm
              WHERE gm.user_id = u.id
                AND gm.group_id = ANY(v_group_ids)
            )
          )
        )
      )
      AND (
        v_strava_connected IS NULL
        OR (
          v_strava_connected = true
          AND EXISTS (
            SELECT 1
            FROM public.user_integrations ui
            WHERE ui.user_id = u.id
              AND ui.provider = 'strava'
              AND ui.sync_enabled = true
          )
        )
        OR (
          v_strava_connected = false
          AND NOT EXISTS (
            SELECT 1
            FROM public.user_integrations ui
            WHERE ui.user_id = u.id
              AND ui.provider = 'strava'
              AND ui.sync_enabled = true
          )
        )
      )
      AND (
        v_garmin_connected IS NULL
        OR (
          v_garmin_connected = true
          AND EXISTS (
            SELECT 1
            FROM public.user_integrations ui
            WHERE ui.user_id = u.id
              AND ui.provider = 'garmin'
              AND ui.sync_enabled = true
          )
        )
        OR (
          v_garmin_connected = false
          AND NOT EXISTS (
            SELECT 1
            FROM public.user_integrations ui
            WHERE ui.user_id = u.id
              AND ui.provider = 'garmin'
              AND ui.sync_enabled = true
          )
        )
      )
      AND (
        v_vdot_missing = false
        OR u.vdot IS NULL
        OR u.vdot <= 0
      );

    RETURN v_recipients;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_create_manual_notification(
    p_title TEXT,
    p_body TEXT,
    p_audience JSONB,
    p_schedule_at TIMESTAMPTZ DEFAULT NULL,
    p_route_target TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recipients UUID[];
    v_data JSONB := jsonb_build_object('source', 'admin_manual');
    v_queue_id UUID;
BEGIN
    PERFORM public.admin_assert_super_admin();

    v_recipients := public.admin_resolve_manual_notification_recipients(p_audience);
    IF v_recipients IS NULL OR array_length(v_recipients, 1) IS NULL OR array_length(v_recipients, 1) = 0 THEN
        RAISE EXCEPTION 'Secilen filtrelere uygun alici bulunamadi';
    END IF;

    IF p_route_target IS NOT NULL AND btrim(p_route_target) <> '' THEN
        v_data := v_data || jsonb_build_object('target', p_route_target);
    END IF;

    INSERT INTO public.admin_notification_queue (
        created_by,
        type,
        title,
        body,
        audience,
        data,
        scheduled_at,
        status,
        recipient_count,
        processed_at
    ) VALUES (
        auth.uid(),
        'admin_manual',
        p_title,
        p_body,
        p_audience,
        v_data,
        p_schedule_at,
        CASE WHEN p_schedule_at IS NULL OR p_schedule_at <= NOW() THEN 'sent' ELSE 'pending' END,
        array_length(v_recipients, 1),
        CASE WHEN p_schedule_at IS NULL OR p_schedule_at <= NOW() THEN NOW() ELSE NULL END
    )
    RETURNING id INTO v_queue_id;

    IF p_schedule_at IS NULL OR p_schedule_at <= NOW() THEN
        PERFORM public.insert_notifications(
            'admin_manual',
            p_title,
            p_body,
            v_data,
            v_recipients
        );
    END IF;

    RETURN v_queue_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.process_pending_admin_notifications()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_job RECORD;
    v_recipients UUID[];
BEGIN
    FOR v_job IN
        SELECT id, title, body, audience, data
        FROM public.admin_notification_queue
        WHERE status = 'pending'
          AND scheduled_at IS NOT NULL
          AND scheduled_at <= NOW()
        ORDER BY scheduled_at ASC
    LOOP
        BEGIN
            v_recipients := public.admin_resolve_manual_notification_recipients(v_job.audience);
            IF v_recipients IS NULL OR array_length(v_recipients, 1) IS NULL OR array_length(v_recipients, 1) = 0 THEN
                UPDATE public.admin_notification_queue
                SET status = 'failed',
                    error_message = 'Alici bulunamadi',
                    processed_at = NOW(),
                    recipient_count = 0
                WHERE id = v_job.id;
                CONTINUE;
            END IF;

            PERFORM public.insert_notifications(
                'admin_manual',
                v_job.title,
                v_job.body,
                v_job.data,
                v_recipients
            );

            UPDATE public.admin_notification_queue
            SET status = 'sent',
                processed_at = NOW(),
                error_message = NULL,
                recipient_count = array_length(v_recipients, 1)
            WHERE id = v_job.id;
        EXCEPTION
            WHEN OTHERS THEN
                UPDATE public.admin_notification_queue
                SET status = 'failed',
                    error_message = SQLERRM,
                    processed_at = NOW()
                WHERE id = v_job.id;
        END;
    END LOOP;
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('process-admin-manual-notifications');
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'process-admin-manual-notifications',
      '*/5 * * * *',
      'SELECT public.process_pending_admin_notifications()'
    );
  END IF;
END
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_manual_notification(TEXT, TEXT, JSONB, TIMESTAMPTZ, TEXT) TO authenticated;

