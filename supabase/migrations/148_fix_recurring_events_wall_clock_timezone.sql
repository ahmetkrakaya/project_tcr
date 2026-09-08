-- ============================================================
-- 148: Tekrarlayan etkinlik üretiminde duvar saati timezone düzeltmesi
--
-- start_time DB'de Türkiye duvar saati olarak UTC bileşenlerine yazılır
-- (ör. 21:00 → 21:00+00). create_next_recurring_events ve
-- update_recurring_series_from_event ise AT TIME ZONE 'Europe/Istanbul'
-- kullanıyordu; 21:00+ etkinliklerde gün +1 kayıyor:
--   Çarşamba 21:00 → anchor Perşembe 00:00 → sonraki "Cuma" yazımı
--   Perşembe 21:00 olarak saklanıyor → sonra Salı, ...
--
-- Çözüm: 145'teki event_start_wall_time / UTC duvar saati ile hizala.
-- ============================================================

-- ------------------------------------------------------------
-- update_recurring_series_from_event
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_recurring_series_from_event(
  p_event_id UUID,
  p_updates JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_start TIMESTAMPTZ;
  v_root_id UUID;
  v_old_rule TEXT;
  v_new_rule TEXT;
  v_today_ist DATE := (public.ist_wall_now())::date;
  v_allowed_keys TEXT[] := ARRAY[
    'title','description','event_type','status',
    'location_name','location_address','location_lat','location_lng',
    'route_id','training_group_id','weather_note','coach_notes',
    'lane_config','banner_image_url',
    'is_recurring','recurrence_rule','recurrence_end_date'
  ];
  v_key TEXT;
  v_filtered JSONB := '{}'::jsonb;
BEGIN
  SELECT start_time, COALESCE(parent_event_id, id) INTO v_event_start, v_root_id
  FROM public.events WHERE id = p_event_id;

  IF v_event_start IS NULL THEN
    RETURN;
  END IF;
  IF p_updates IS NULL OR jsonb_typeof(p_updates) != 'object' THEN
    RETURN;
  END IF;

  FOR v_key IN SELECT jsonb_object_keys(p_updates)
  LOOP
    IF v_key = ANY(v_allowed_keys) THEN
      v_filtered := v_filtered || jsonb_build_object(v_key, p_updates->v_key);
    END IF;
  END LOOP;

  IF v_filtered = '{}'::jsonb THEN
    RETURN;
  END IF;

  SELECT e.recurrence_rule INTO v_old_rule
  FROM public.events e
  WHERE e.id = v_root_id;

  v_new_rule := CASE
    WHEN v_filtered ? 'is_recurring'
         AND COALESCE((v_filtered->>'is_recurring')::boolean, true) = false
      THEN NULL
    WHEN v_filtered ? 'recurrence_rule'
      THEN NULLIF((v_filtered->>'recurrence_rule')::text, '')
    ELSE v_old_rule
  END;

  UPDATE public.events e
  SET
    title = COALESCE((v_filtered->>'title')::text, e.title),
    description = CASE WHEN v_filtered ? 'description' THEN v_filtered->>'description' ELSE e.description END,
    event_type = COALESCE((v_filtered->>'event_type')::event_type, e.event_type),
    status = COALESCE((v_filtered->>'status')::event_status, e.status),
    location_name = COALESCE(v_filtered->>'location_name', e.location_name),
    location_address = CASE WHEN v_filtered ? 'location_address' THEN v_filtered->>'location_address' ELSE e.location_address END,
    location_lat = CASE WHEN v_filtered ? 'location_lat' THEN (v_filtered->>'location_lat')::decimal ELSE e.location_lat END,
    location_lng = CASE WHEN v_filtered ? 'location_lng' THEN (v_filtered->>'location_lng')::decimal ELSE e.location_lng END,
    route_id = CASE WHEN v_filtered ? 'route_id' THEN (v_filtered->>'route_id')::uuid ELSE e.route_id END,
    training_group_id = CASE WHEN v_filtered ? 'training_group_id' THEN (v_filtered->>'training_group_id')::uuid ELSE e.training_group_id END,
    weather_note = CASE WHEN v_filtered ? 'weather_note' THEN v_filtered->>'weather_note' ELSE e.weather_note END,
    coach_notes = CASE WHEN v_filtered ? 'coach_notes' THEN v_filtered->>'coach_notes' ELSE e.coach_notes END,
    lane_config = CASE WHEN v_filtered ? 'lane_config' THEN (v_filtered->'lane_config')::jsonb ELSE e.lane_config END,
    banner_image_url = CASE WHEN v_filtered ? 'banner_image_url' THEN v_filtered->>'banner_image_url' ELSE e.banner_image_url END,
    is_recurring = CASE
      WHEN v_filtered ? 'is_recurring' THEN COALESCE((v_filtered->>'is_recurring')::boolean, e.is_recurring)
      ELSE e.is_recurring
    END,
    recurrence_rule = CASE
      WHEN v_filtered ? 'is_recurring'
           AND COALESCE((v_filtered->>'is_recurring')::boolean, e.is_recurring) = false
        THEN NULL
      WHEN v_filtered ? 'recurrence_rule'
        THEN NULLIF((v_filtered->>'recurrence_rule')::text, '')
      ELSE e.recurrence_rule
    END,
    recurrence_end_date = CASE
      WHEN v_filtered ? 'is_recurring'
           AND COALESCE((v_filtered->>'is_recurring')::boolean, e.is_recurring) = false
        THEN NULL
      WHEN v_filtered ? 'recurrence_end_date'
        THEN (v_filtered->>'recurrence_end_date')::date
      ELSE e.recurrence_end_date
    END,
    updated_at = now()
  WHERE (e.parent_event_id = v_root_id OR e.id = v_root_id)
    AND e.start_time >= v_event_start;

  IF v_filtered ? 'recurrence_rule'
     AND v_new_rule IS DISTINCT FROM v_old_rule
     AND v_new_rule IS NOT NULL THEN
    DELETE FROM public.events e
    WHERE (e.parent_event_id = v_root_id OR e.id = v_root_id)
      AND (public.event_start_wall_time(e.start_time))::date > v_today_ist
      AND COALESCE(e.is_recurrence_exception, false) = false;

    PERFORM public.create_next_recurring_events();
  END IF;
END;
$$;

COMMENT ON FUNCTION public.update_recurring_series_from_event(UUID, JSONB) IS
'Tekrarlayan seride verilen etkinlik ve sonrakileri günceller; kural değişince gelecek tekrarları duvar saati ile yeniden planlar.';

-- ------------------------------------------------------------
-- create_next_recurring_events
-- ------------------------------------------------------------
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
  v_wall_time TIME;
  v_new_start TIMESTAMPTZ;
  v_new_end TIMESTAMPTZ;
  v_iteration INT;
  v_exists BOOLEAN;
  v_today_ist DATE := (public.ist_wall_now())::date;
  v_created_count INT := 0;
  v_series_count INT := 0;
  v_log_id BIGINT;
BEGIN
  INSERT INTO public.recurring_event_job_logs (started_at)
  VALUES (now())
  RETURNING id INTO v_log_id;

  FOR v_series IN
    SELECT DISTINCT ON (COALESCE(e.parent_event_id, e.id))
      e.*
    FROM public.events e
    WHERE
      e.parent_event_id IS NOT NULL
      OR e.is_recurring = true
      OR (e.recurrence_rule IS NOT NULL AND e.recurrence_rule <> '')
    ORDER BY COALESCE(e.parent_event_id, e.id), e.start_time DESC
  LOOP
    v_series_count := v_series_count + 1;
    v_root_id := COALESCE(v_series.parent_event_id, v_series.id);

    IF v_series.is_recurring IS DISTINCT FROM true
       OR v_series.recurrence_rule IS NULL
       OR v_series.recurrence_rule = '' THEN
      CONTINUE;
    END IF;

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

    -- Duvar saati tarihi (TR bileşenleri UTC olarak saklanır)
    v_anchor_date := (public.event_start_wall_time(v_series.start_time))::date;
    v_iteration := 0;

    WHILE v_iteration < 120 LOOP
      v_iteration := v_iteration + 1;

      IF (v_anchor_date + 1) > v_today_ist THEN
        EXIT;
      END IF;

      v_next_date := public.next_occurrence_from_rrule(v_template.recurrence_rule, v_anchor_date);
      IF v_next_date IS NULL THEN
        EXIT;
      END IF;

      IF v_template.recurrence_end_date IS NOT NULL
         AND v_next_date > v_template.recurrence_end_date THEN
        EXIT;
      END IF;

      SELECT EXISTS (
        SELECT 1
        FROM public.events e3
        WHERE (e3.parent_event_id = v_root_id OR e3.id = v_root_id)
          AND (public.event_start_wall_time(e3.start_time))::date = v_next_date
      ) INTO v_exists;

      IF v_exists THEN
        v_anchor_date := v_next_date;
        IF v_next_date >= v_today_ist THEN
          EXIT;
        END IF;
        CONTINUE;
      END IF;

      v_old_start := v_template.start_time;
      v_old_end := v_template.end_time;
      v_duration := COALESCE(v_old_end - v_old_start, interval '0');
      v_wall_time := (public.event_start_wall_time(v_old_start))::time;
      -- Duvar saatini yine UTC bileşeni olarak yaz (uygulama konvansiyonu)
      v_new_start := (v_next_date + v_wall_time)::timestamp AT TIME ZONE 'UTC';
      v_new_end := v_new_start + v_duration;
      v_new_id := gen_random_uuid();

      INSERT INTO public.events (
        id, title, description, event_type, status, start_time, end_time,
        location_name, location_address, location_lat, location_lng,
        route_id, training_group_id, max_participants, weather_api_data, weather_note, coach_notes,
        is_recurring, recurrence_rule, parent_event_id, recurrence_end_date, is_recurrence_exception,
        created_by, created_at, updated_at,
        training_type_id, lane_config, banner_image_url, is_pinned, pinned_at,
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
        v_template.training_type_id, v_template.lane_config,
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

      INSERT INTO public.event_route_options (event_id, route_id, label, sort_order)
      SELECT v_new_id, route_id, label, sort_order
      FROM public.event_route_options
      WHERE event_id = v_template.id;

      v_created_count := v_created_count + 1;
      v_anchor_date := v_next_date;

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
'Tekrarlayan seriler için sonraki etkinliği duvar saati (UTC bileşenleri) ile oluşturur; 21:00+ kaymasını önler.';
