-- =====================================================
-- 097: group_members SELECT RLS fix (üyelik okunabilir)
-- =====================================================
-- Uygulama akışı: bireysel antrenmanda kullanıcıya gösterilecek programı bulmak için
-- önce group_members'tan kullanıcının group_id'si okunur. Bu SELECT engellenirse
-- event_group_programs sorgusu hiç çalışmaz gibi görünür.

BEGIN;

ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

-- Farklı migration'larda geçen olası policy isimlerini temizle
DROP POLICY IF EXISTS "Group members are viewable by everyone" ON public.group_members;
DROP POLICY IF EXISTS "Anyone can view group members" ON public.group_members;

-- Güvenli minimum: kullanıcı kendi üyeliğini görebilsin; admin tümünü görebilsin.
-- (İsterseniz sonradan tekrar "true"ya genişletilebilir.)
CREATE POLICY "Users can view own group membership"
  ON public.group_members
  FOR SELECT
  USING (
    user_id = auth.uid()
    OR public.has_role(auth.uid(), 'super_admin')
  );

COMMIT;

