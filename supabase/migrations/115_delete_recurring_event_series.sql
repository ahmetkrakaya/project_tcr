-- =====================================================
-- 115: Admin — tekrarlayan etkinlik serisini kaldır
-- Etkinlik kayıtları silinmez; yalnızca tekrar bağlantısı temizlenir.
-- =====================================================

CREATE OR REPLACE FUNCTION public.delete_recurring_event_series(p_root_event_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin BOOLEAN;
  v_affected INT;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles ur
    WHERE ur.user_id = auth.uid()
      AND ur.role = 'super_admin'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Bu işlem sadece adminler içindir';
  END IF;

  IF p_root_event_id IS NULL THEN
    RAISE EXCEPTION 'Geçersiz seri kimliği';
  END IF;

  UPDATE public.events e
  SET
    is_recurring = false,
    recurrence_rule = NULL,
    recurrence_end_date = NULL,
    parent_event_id = CASE
      WHEN e.parent_event_id = p_root_event_id THEN NULL
      ELSE e.parent_event_id
    END,
    updated_at = now()
  WHERE e.id = p_root_event_id
     OR e.parent_event_id = p_root_event_id;

  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected = 0 THEN
    RAISE EXCEPTION 'Tekrarlayan seri bulunamadı';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.delete_recurring_event_series(UUID) IS
  'Tekrarlayan seriyi listeden kaldırır: tekrar kuralları ve parent bağları silinir, etkinlik kayıtları kalır.';
