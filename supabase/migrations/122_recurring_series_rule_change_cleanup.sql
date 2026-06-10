-- =====================================================
-- 122: Seri düzenlemede tekrar kuralı değişince gelecek çiftleri önle
-- =====================================================
-- update_recurring_series_from_event() kuralı güncellediğinde mevcut
-- gelecek etkinliklerin start_time değerleri eski takvimde kalıyordu;
-- cron yeni kurala göre ek kayıt açıp çift oluşuma yol açıyordu.

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
  v_today_ist DATE := (now() AT TIME ZONE 'Europe/Istanbul')::date;
  v_allowed_keys TEXT[] := ARRAY[
    'title','description','event_type','status',
    'location_name','location_address','location_lat','location_lng',
    'route_id','training_group_id','weather_note','coach_notes',
    'participation_type','lane_config','banner_image_url',
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
    participation_type = COALESCE(v_filtered->>'participation_type', e.participation_type),
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

  -- Kural değiştiyse bugünden sonraki otomatik tekrarları sil; cron yeniden üretir.
  IF v_filtered ? 'recurrence_rule'
     AND v_new_rule IS DISTINCT FROM v_old_rule
     AND v_new_rule IS NOT NULL THEN
    DELETE FROM public.events e
    WHERE (e.parent_event_id = v_root_id OR e.id = v_root_id)
      AND (e.start_time AT TIME ZONE 'Europe/Istanbul')::date > v_today_ist
      AND COALESCE(e.is_recurrence_exception, false) = false;

    PERFORM public.create_next_recurring_events();
  END IF;
END;
$$;

COMMENT ON FUNCTION public.update_recurring_series_from_event(UUID, JSONB) IS
'Tekrarlayan seride verilen etkinlik ve sonrakileri günceller; kural değişince gelecek tekrarları yeniden planlar.';
