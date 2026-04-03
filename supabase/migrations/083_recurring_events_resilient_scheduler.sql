-- =====================================================
-- 083: Recurring events scheduler resilience
-- =====================================================
-- Problem:
-- - create_next_recurring_events() only scanned "yesterday".
-- - If daily cron is skipped once, the series can permanently miss next occurrences.
--
-- Solution:
-- - Rebuild create_next_recurring_events() to reconcile each recurring series:
--   * Walk forward from the latest known event in that series
--   * Fill missing occurrences (including missed days)
--   * Stop when at least one non-past occurrence exists
- Add lightweight run logs for observability
-- - Re-register cron job idempotently.

CREATE TABLE IF NOT EXISTS public.recurring_event_job_logs (
  id BIGSERIAL PRIMARY KEY,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ,
  created_events_count INT NOT NULL DEFAULT 0,
  processed_series_count INT NOT NULL DEFAULT 0,
  error_message TEXT
);

COMMENT ON TABLE public.recurring_event_job_logs IS
'create_next_recurring_events cron çalışması için özet log kayıtları';

CREATE OR REPLACE FUNCTION public.create_next_recurring_events()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_series RECORD;
  v_template RECORD;
  v_root_id UUID;
  v_anchor_date DATE;
  v_next_date DATE;
  v_new_id UUID;
  v_old_start TIMESTAMPTZ;
  v_old_end TIMESTAMPTZ;
  v_duration INTERVAL;
  v_new_start TIMESTAMPTZ;
  v_new_end TIMESTAMPTZ;
  v_iteration INT;
  v_exists BOOLEAN;
  v_today_ist DATE := (now() AT TIME ZONE 'Europe/Istanbul')::date;
  v_created_count INT := 0;
  v_series_count INT := 0;
  v_log_id BIGINT;
BEGIN
  INSERT INTO public.recurring_event_job_logs (started_at)
  VALUES (now())
  RETURNING id INTO v_log_id;

  -- Per recurring series, pick the latest event and reconcile forward.
  FOR v_series IN
    SELECT DISTINCT ON (COALESCE(e.parent_event_id, e.id))
      e.*
    FROM public.events e
    WHERE e.is_recurring = true
      AND e.recurrence_rule IS NOT NULL
      AND e.recurrence_rule <> ''
    ORDER BY COALESCE(e.parent_event_id, e.id), e.start_time DESC
  LOOP
    v_series_count := v_series_count + 1;
    v_root_id := COALESCE(v_series.parent_event_id, v_series.id);

    -- Template selection:
    -- If latest event is exception, use latest non-exception in series, else itself.
    IF v_series.is_recurrence_exception THEN
      SELECT * INTO v_template
      FROM public.events e2
      WHERE (e2.parent_event_id = v_root_id OR e2.id = v_root_id)
        AND e2.start_time < v_series.start_time
        AND e2.is_recurrence_exception = false
      ORDER BY e2.start_time DESC
      LIMIT 1;

      IF v_template.id IS NULL THEN
        SELECT * INTO v_template
        FROM public.events
        WHERE id = v_root_id;
      END IF;
    ELSE
      v_template := v_series;
    END IF;

    IF v_template.id IS NULL THEN
      CONTINUE;
    END IF;

    -- Anchor is the latest known occurrence date in this series.
    v_anchor_date := (v_series.start_time AT TIME ZONE 'Europe/Istanbul')::date;
    v_iteration := 0;

    -- Guard loop to avoid infinite iteration on malformed rules.
    WHILE v_iteration < 120 LOOP
      v_iteration := v_iteration + 1;

      v_next_date := public.next_occurrence_from_rrule(v_template.recurrence_rule, v_anchor_date);
      IF v_next_date IS NULL THEN
        EXIT;
      END IF;

      IF v_template.recurrence_end_date IS NOT NULL
         AND v_next_date > v_template.recurrence_end_date THEN
        EXIT;
      END IF;

      -- Check if the calculated next occurrence already exists in series.
      SELECT EXISTS (
        SELECT 1
        FROM public.events e3
        WHERE (e3.parent_event_id = v_root_id OR e3.id = v_root_id)
          AND (e3.start_time AT TIME ZONE 'Europe/Istanbul')::date = v_next_date
      ) INTO v_exists;

      IF v_exists THEN
        v_anchor_date := v_next_date;
        IF v_next_date >= v_today_ist THEN
          EXIT;
        END IF;
        CONTINUE;
      END IF;

      -- Create missing occurrence.
      v_old_start := v_template.start_time;
      v_old_end := v_template.end_time;
      v_duration := COALESCE(v_old_end - v_old_start, interval '0');
      v_new_start := (v_next_date + ((v_old_start AT TIME ZONE 'Europe/Istanbul')::time))::timestamp
                     AT TIME ZONE 'Europe/Istanbul';
      v_new_end := v_new_start + v_duration;
      v_new_id := gen_random_uuid();

      INSERT INTO public.events (
        id, title, description, event_type, status, start_time, end_time,
        location_name, location_address, location_lat, location_lng,
        route_id, training_group_id, max_participants, weather_api_data, weather_note, coach_notes,
        is_recurring, recurrence_rule, parent_event_id, recurrence_end_date, is_recurrence_exception,
        created_by, created_at, updated_at,
        training_type_id, participation_type, lane_config, banner_image_url, is_pinned, pinned_at,
        visibility
      )
      VALUES (
        v_new_id, v_template.title, v_template.description, v_template.event_type, v_template.status,
        v_new_start, v_new_end,
        v_template.location_name, v_template.location_address, v_template.location_lat, v_template.location_lng,
        v_template.route_id, v_template.training_group_id, v_template.max_participants,
        v_template.weather_api_data, v_template.weather_note, v_template.coach_notes,
        v_template.is_recurring, v_template.recurrence_rule, v_root_id, v_template.recurrence_end_date, false,
        v_template.created_by, now(), now(),
        v_template.training_type_id, v_template.participation_type, v_template.lane_config,
        v_template.banner_image_url, false, NULL,
        COALESCE(v_template.visibility, 'public')
      );

      INSERT INTO public.event_group_programs (
        event_id, training_group_id, program_content, route_id, order_index, training_type_id, workout_definition
      )
      SELECT
        v_new_id, training_group_id, program_content, route_id, order_index, training_type_id, workout_definition
      FROM public.event_group_programs
      WHERE event_id = v_template.id;

      INSERT INTO public.event_info_blocks (
        event_id, type, content, sub_content, color, icon, order_index
      )
      SELECT
        v_new_id, type, content, sub_content, color, icon, order_index
      FROM public.event_info_blocks
      WHERE event_id = v_template.id;

      v_created_count := v_created_count + 1;
      v_anchor_date := v_next_date;

      -- Once we have at least one non-past occurrence, stop for this series.
      IF v_next_date >= v_today_ist THEN
        EXIT;
      END IF;
    END LOOP;
  END LOOP;

  UPDATE public.recurring_event_job_logs
  SET
    finished_at = now(),
    created_events_count = v_created_count,
    processed_series_count = v_series_count
  WHERE id = v_log_id;
EXCEPTION
  WHEN OTHERS THEN
    IF v_log_id IS NOT NULL THEN
      UPDATE public.recurring_event_job_logs
      SET
        finished_at = now(),
        created_events_count = v_created_count,
        processed_series_count = v_series_count,
        error_message = SQLERRM
      WHERE id = v_log_id;
    END IF;
    RAISE;
END;
$$;

COMMENT ON FUNCTION public.create_next_recurring_events() IS
'Recurring serileri dayanıklı biçimde uzatır: eksikleri tamamlar ve en az bir gelecek occurrence üretir.';

-- Ensure cron job exists and is up to date (idempotent).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('create-next-recurring-events');
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;

    PERFORM cron.schedule(
      'create-next-recurring-events',
      '0 1 * * *',
      'SELECT public.create_next_recurring_events()'
    );
  END IF;
END
$$;
