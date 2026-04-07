-- =====================================================
-- 096: event_group_programs SELECT RLS - bireysel görünürlük
-- =====================================================
-- İstenen davranış:
-- - Grup/Ekip antrenmanı: mevcut davranış değişmesin (yayınlanmış etkinlikte görülebilir)
-- - Bireysel antrenman: kullanıcı sadece üyesi olduğu grubun programını görebilsin
--
-- Not: event_group_programs satırları için SELECT RLS'i burada daraltıyoruz.
--      Uygulama tarafında sorgu zaten training_group_id ile filtreli gelebilir;
--      ancak RLS her durumda güvenlik sınırıdır.

BEGIN;

-- Eski geniş policy'yi kaldır
DROP POLICY IF EXISTS "Anyone can view group programs of published events"
  ON public.event_group_programs;

-- Yeni SELECT policy
CREATE POLICY "View group programs (team vs individual)"
  ON public.event_group_programs
  FOR SELECT
  USING (
    -- Admin her zaman görebilsin (debug/denetim)
    EXISTS (
      SELECT 1
      FROM public.user_roles ur
      WHERE ur.user_id = auth.uid()
        AND ur.role = 'super_admin'
    )
    OR EXISTS (
      SELECT 1
      FROM public.events e
      WHERE e.id = event_group_programs.event_id
        AND e.status = 'published'
        AND (
          -- team/ekip (veya null): eski davranış
          COALESCE(e.participation_type, 'team') <> 'individual'
          -- bireysel: sadece ilgili grubun üyeleri
          OR public.is_group_member(event_group_programs.training_group_id, auth.uid())
        )
    )
  );

COMMIT;

