-- =====================================================
-- 055: Tekrarlayan Etkinlikler
-- =====================================================
-- recurrence_end_date, is_recurrence_exception ve
-- sonraki tekrarı oluşturan fonksiyon + pg_cron

-- events tablosuna yeni sütunlar
ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS recurrence_end_date DATE,
ADD COLUMN IF NOT EXISTS is_recurrence_exception BOOLEAN DEFAULT false;

COMMENT ON COLUMN public.events.recurrence_end_date IS 'Tekrarlamanın bittiği tarih (opsiyonel)';
COMMENT ON COLUMN public.events.is_recurrence_exception IS 'Sadece bu tekrar düzenlendi; sonraki oluşturulurken şablon olarak kullanılmaz';

-- RRULE'dan sonraki tekrar tarihini hesapla (WEEKLY, MONTHLY, YEARLY)
-- from_date: az önce gerçekleşen etkinlik tarihi; dönen değer: ondan sonraki occurrence
CREATE OR REPLACE FUNCTION public.next_occurrence_from_rrule(
  p_rrule TEXT,
  p_from_date DATE
)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_freq TEXT;
  v_byday TEXT;
  v_bymonthday INT;
  v_bymonth INT;
  v_days INT[];
  v_dow INT;
  v_candidate DATE;
  v_i INT;
  v_part TEXT;
  v_key TEXT;
  v_val TEXT;
  v_pos INT;
BEGIN
  IF p_rrule IS NULL OR p_rrule = '' THEN
    RETURN NULL;
  END IF;

  -- Parse key=value pairs (basit parse)
  v_freq := NULL;
  v_byday := NULL;
  v_bymonthday := NULL;
  v_bymonth := NULL;

  FOR v_part IN SELECT trim(s) FROM regexp_split_to_table(p_rrule, ';') AS s
  LOOP
    v_pos := position('=' in v_part);
    IF v_pos > 0 THEN
      v_key := upper(split_part(v_part, '=', 1));
      v_val := split_part(v_part, '=', 2);
      CASE v_key
        WHEN 'FREQ' THEN v_freq := upper(v_val);
        WHEN 'BYDAY' THEN v_byday := upper(v_val);
        WHEN 'BYMONTHDAY' THEN v_bymonthday := v_val::int;
        WHEN 'BYMONTH' THEN v_bymonth := v_val::int;
        ELSE NULL;
      END CASE;
    END IF;
  END LOOP;

  -- WEEKLY;BYDAY=TU veya TU,TH
  IF v_freq = 'WEEKLY' AND v_byday IS NOT NULL THEN
    -- BYDAY: SU,MO,TU,WE,TH,FR,SA -> PostgreSQL dow: 0=Sun, 1=Mon, ... 6=Sat
    v_days := ARRAY[]::int[];
    FOR v_part IN SELECT trim(s) FROM regexp_split_to_table(v_byday, ',') AS s
    LOOP
      CASE v_part
        WHEN 'SU' THEN v_days := array_append(v_days, 0);
        WHEN 'MO' THEN v_days := array_append(v_days, 1);
        WHEN 'TU' THEN v_days := array_append(v_days, 2);
        WHEN 'WE' THEN v_days := array_append(v_days, 3);
        WHEN 'TH' THEN v_days := array_append(v_days, 4);
        WHEN 'FR' THEN v_days := array_append(v_days, 5);
        WHEN 'SA' THEN v_days := array_append(v_days, 6);
        ELSE NULL;
      END CASE;
    END LOOP;
    v_candidate := p_from_date + 1;
    FOR v_i IN 1..8
    LOOP
      v_dow := extract(dow FROM v_candidate)::int;
      IF v_dow = ANY(v_days) THEN
        RETURN v_candidate;
      END IF;
      v_candidate := v_candidate + 1;
    END LOOP;
    RETURN p_from_date + 7;
  END IF;

  -- MONTHLY;BYMONTHDAY=15
  IF v_freq = 'MONTHLY' AND v_bymonthday IS NOT NULL THEN
    v_candidate := date_trunc('month', p_from_date + 1)::date + (v_bymonthday - 1);
    IF v_candidate <= p_from_date THEN
      v_candidate := date_trunc('month', p_from_date + interval '1 month')::date + (v_bymonthday - 1);
    END IF;
    RETURN v_candidate;
  END IF;

  -- YEARLY;BYMONTH=4;BYMONTHDAY=23
  IF v_freq = 'YEARLY' AND v_bymonth IS NOT NULL AND v_bymonthday IS NOT NULL THEN
    v_candidate := make_date(extract(year FROM p_from_date)::int, v_bymonth, least(v_bymonthday, 28));
    IF v_candidate <= p_from_date THEN
      v_candidate := make_date(extract(year FROM p_from_date)::int + 1, v_bymonth, least(v_bymonthday, 28));
    END IF;
    RETURN v_candidate;
  END IF;

  RETURN NULL;
END;
$$;

-- Sonraki tekrarlayan etkinliği oluştur (dün gerçekleşen her tekrarlayan etkinlik için)
CREATE OR REPLACE FUNCTION public.create_next_recurring_events()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event RECORD;
  v_template RECORD;
  v_root_id UUID;
  v_next_date DATE;
  v_new_id UUID;
  v_old_start TIMESTAMPTZ;
  v_old_end TIMESTAMPTZ;
  v_duration INTERVAL;
  v_new_start TIMESTAMPTZ;
  v_new_end TIMESTAMPTZ;
  v_prog RECORD;
  v_block RECORD;
BEGIN
  FOR v_event IN
    SELECT e.*
    FROM public.events e
    WHERE (e.start_time AT TIME ZONE 'Europe/Istanbul')::date = (current_date AT TIME ZONE 'Europe/Istanbul')::date - 1
      AND e.is_recurring = true
      AND e.recurrence_rule IS NOT NULL
      AND e.recurrence_rule != ''
  LOOP
    -- Şablon: exception ise kök veya serideki bir önceki; değilse kendisi
    IF v_event.is_recurrence_exception THEN
      v_root_id := COALESCE(v_event.parent_event_id, v_event.id);
      SELECT * INTO v_template
      FROM public.events
      WHERE (parent_event_id = v_root_id OR id = v_root_id)
        AND start_time < v_event.start_time
        AND is_recurrence_exception = false
      ORDER BY start_time DESC
      LIMIT 1;
      IF v_template.id IS NULL THEN
        SELECT * INTO v_template FROM public.events WHERE id = v_root_id;
      END IF;
    ELSE
      v_template := v_event;
    END IF;

    IF v_template.id IS NULL THEN
      CONTINUE;
    END IF;

    v_root_id := COALESCE(v_template.parent_event_id, v_template.id);
    v_next_date := public.next_occurrence_from_rrule(v_template.recurrence_rule, (v_event.start_time AT TIME ZONE 'Europe/Istanbul')::date);

    IF v_next_date IS NULL THEN
      CONTINUE;
    END IF;
    IF v_template.recurrence_end_date IS NOT NULL AND v_next_date > v_template.recurrence_end_date THEN
      CONTINUE;
    END IF;

    v_old_start := v_template.start_time;
    v_old_end := v_template.end_time;
    v_duration := COALESCE(v_old_end - v_old_start, interval '0');
    v_new_start := (v_next_date + ((v_old_start AT TIME ZONE 'Europe/Istanbul')::time))::timestamp AT TIME ZONE 'Europe/Istanbul';
    v_new_end := v_new_start + v_duration;

    v_new_id := gen_random_uuid();

    INSERT INTO public.events (
      id, title, description, event_type, status, start_time, end_time,
      location_name, location_address, location_lat, location_lng,
      route_id, training_group_id, max_participants, weather_api_data, weather_note, coach_notes,
      is_recurring, recurrence_rule, parent_event_id, recurrence_end_date, is_recurrence_exception,
      created_by, created_at, updated_at,
      training_type_id, participation_type, lane_config, banner_image_url, is_pinned, pinned_at
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
      v_template.banner_image_url, false, NULL
    );

    -- event_group_programs kopyala
    INSERT INTO public.event_group_programs (event_id, training_group_id, program_content, route_id, order_index, training_type_id, workout_definition)
    SELECT v_new_id, training_group_id, program_content, route_id, order_index, training_type_id, workout_definition
    FROM public.event_group_programs
    WHERE event_id = v_template.id;

    -- event_info_blocks kopyala
    INSERT INTO public.event_info_blocks (event_id, type, content, sub_content, color, icon, order_index)
    SELECT v_new_id, type, content, sub_content, color, icon, order_index
    FROM public.event_info_blocks
    WHERE event_id = v_template.id;

  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.next_occurrence_from_rrule(TEXT, DATE) IS 'RRULE (WEEKLY/MONTHLY/YEARLY) ve from_date ile sonraki tekrar tarihini döner';
COMMENT ON FUNCTION public.create_next_recurring_events() IS 'Dün gerçekleşen tekrarlayan etkinlikler için bir sonraki tekrarı oluşturur; pg_cron ile günlük çalıştırılır';

-- Seri güncellemesi: bu etkinlik ve sonrakileri p_updates ile güncelle (tüm sonrakileri düzenle)
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
  v_allowed_keys TEXT[] := ARRAY[
    'title','description','event_type','status',
    'location_name','location_address','location_lat','location_lng',
    'route_id','training_group_id','weather_note','coach_notes',
    'participation_type','lane_config','banner_image_url'
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

  -- Sadece izin verilen alanları güncelle (id, created_by, is_recurring, recurrence_rule, parent_event_id vb. değiştirilmez)
  FOR v_key IN SELECT jsonb_object_keys(p_updates)
  LOOP
    IF v_key = ANY(v_allowed_keys) THEN
      v_filtered := v_filtered || jsonb_build_object(v_key, p_updates->v_key);
    END IF;
  END LOOP;

  IF v_filtered = '{}'::jsonb THEN
    RETURN;
  END IF;

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
    participation_type = COALESCE(v_filtered->>'participation_type', e.participation_type),
    lane_config = CASE WHEN v_filtered ? 'lane_config' THEN (v_filtered->'lane_config')::jsonb ELSE e.lane_config END,
    banner_image_url = CASE WHEN v_filtered ? 'banner_image_url' THEN v_filtered->>'banner_image_url' ELSE e.banner_image_url END,
    updated_at = now()
  WHERE (e.parent_event_id = v_root_id OR e.id = v_root_id)
    AND e.start_time >= v_event_start;
END;
$$;

COMMENT ON FUNCTION public.update_recurring_series_from_event(UUID, JSONB) IS 'Tekrarlayan seride verilen etkinlik ve sonrakileri p_updates alanlarıyla günceller';

-- pg_cron extension ve günlük job (Supabase'de extension dashboard'dan açılabiliyor; burada sadece job'u ekliyoruz)
-- Not: Extension ilk kez CREATE EXTENSION pg_cron; ile açılmalı (Supabase Dashboard > Database > Extensions)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'create-next-recurring-events',
      '0 1 * * *',
      'SELECT public.create_next_recurring_events()'
    );
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END
$$;
