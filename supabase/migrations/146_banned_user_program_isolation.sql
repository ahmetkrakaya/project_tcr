-- ============================================================
-- 146: Banlanan kullanicilarin program fonksiyonlarindan izole edilmesi
-- ============================================================
-- Ban: gruptan cikar, cihaz sync kapat, gelecek RSVP temizle (token korunur)
-- Reaktivasyon: hesap + sync geri acilir; grup uyeligi otomatik geri gelmez
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_user_program_eligible(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.users u
        WHERE u.id = p_user_id
          AND u.is_active = true
          AND u.user_status = 'active'
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_user_program_eligible(UUID) TO authenticated;

-- Ban: program erisimini kes
CREATE OR REPLACE FUNCTION public.deactivate_user(user_id_to_deactivate UUID, deactivated_by UUID)
RETURNS BOOLEAN AS $$
DECLARE
  is_approver_admin BOOLEAN;
  target_is_super_admin BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = deactivated_by AND role = 'super_admin'
  ) INTO is_approver_admin;

  IF NOT is_approver_admin THEN
    RAISE EXCEPTION 'Sadece adminler kullanıcı banlayabilir';
  END IF;

  IF user_id_to_deactivate = deactivated_by THEN
    RAISE EXCEPTION 'Kendinizi banlayamazsınız';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = user_id_to_deactivate AND role = 'super_admin'
  ) INTO target_is_super_admin;

  IF target_is_super_admin THEN
    RAISE EXCEPTION 'Admin kullanıcı banlanamaz';
  END IF;

  UPDATE public.users
  SET is_active = false, user_status = 'banned', updated_at = NOW()
  WHERE id = user_id_to_deactivate;

  DELETE FROM public.group_members
  WHERE user_id = user_id_to_deactivate;

  UPDATE public.group_join_requests
  SET
    status = 'rejected',
    responded_at = NOW(),
    responded_by = deactivated_by
  WHERE user_id = user_id_to_deactivate
    AND status = 'pending';

  UPDATE public.user_integrations
  SET sync_enabled = false, updated_at = NOW()
  WHERE user_id = user_id_to_deactivate;

  DELETE FROM public.event_participants ep
  USING public.events e
  WHERE ep.event_id = e.id
    AND ep.user_id = user_id_to_deactivate
    AND ep.status = 'going'
    AND e.start_time > NOW();

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Reaktivasyon: hesap + entegrasyon sync geri ac (grup otomatik degil)
CREATE OR REPLACE FUNCTION public.reactivate_user(user_id_to_reactivate UUID, reactivated_by UUID)
RETURNS BOOLEAN AS $$
DECLARE
  is_approver_admin BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = reactivated_by AND role = 'super_admin'
  ) INTO is_approver_admin;

  IF NOT is_approver_admin THEN
    RAISE EXCEPTION 'Sadece adminler kullanıcı yeniden aktif yapabilir';
  END IF;

  UPDATE public.users
  SET is_active = true, user_status = 'active', updated_at = NOW()
  WHERE id = user_id_to_reactivate;

  UPDATE public.user_integrations
  SET sync_enabled = true, updated_at = NOW()
  WHERE user_id = user_id_to_reactivate
    AND access_token IS NOT NULL;

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Etkinlik turu trendi: yalnizca aktif uyeler
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
            COUNT(DISTINCT ep.user_id) FILTER (
                WHERE ep.status = 'going'
                  AND public.is_user_program_eligible(ep.user_id)
            )::int AS participants
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

-- Grup durum panosu: yalnizca aktif uyeler
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
            SELECT gm.group_id, COUNT(*) AS member_count
            FROM public.group_members gm
            JOIN public.users u ON u.id = gm.user_id
            WHERE u.is_active = true
              AND u.user_status = 'active'
            GROUP BY gm.group_id
        ) mc ON mc.group_id = g.id
        LEFT JOIN (
            SELECT gm.group_id,
                   COUNT(DISTINCT a.user_id) AS active_members,
                   COALESCE(SUM(a.distance_meters), 0) / 1000.0 AS total_km
            FROM public.group_members gm
            JOIN public.users u ON u.id = gm.user_id
            JOIN public.activities a ON a.user_id = gm.user_id
            WHERE u.is_active = true
              AND u.user_status = 'active'
              AND a.activity_type = 'running'
              AND (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 7
            GROUP BY gm.group_id
        ) act ON act.group_id = g.id
        LEFT JOIN (
            SELECT gm.group_id, COUNT(DISTINCT gm.user_id) AS active_members
            FROM public.group_members gm
            JOIN public.users u ON u.id = gm.user_id
            WHERE u.is_active = true
              AND u.user_status = 'active'
              AND (
                  u.last_app_open_at > NOW() - INTERVAL '30 days'
                  OR EXISTS (
                      SELECT 1 FROM public.activities a
                      WHERE a.user_id = gm.user_id
                        AND (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 30
                  )
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

-- Mevcut banli kullanicilari yeni kurallara gore temizle
DELETE FROM public.group_members gm
USING public.users u
WHERE gm.user_id = u.id
  AND u.user_status = 'banned';

UPDATE public.user_integrations ui
SET sync_enabled = false, updated_at = NOW()
FROM public.users u
WHERE ui.user_id = u.id
  AND u.user_status = 'banned';

DELETE FROM public.event_participants ep
USING public.events e, public.users u
WHERE ep.event_id = e.id
  AND ep.user_id = u.id
  AND ep.status = 'going'
  AND e.start_time > NOW()
  AND u.user_status = 'banned';
