-- Kullanıcı sadece bir gruba üye olabilir.
-- Grup değiştirmek için önce mevcut gruptan ayrılması gerekir.

-- Önce bir kullanıcının birden fazla grupta olduğu kayıtları temizle (en son katıldığı grubu tut)
DELETE FROM public.group_members gm
WHERE gm.id NOT IN (
  SELECT DISTINCT ON (user_id) id
  FROM public.group_members
  ORDER BY user_id, joined_at DESC
);

ALTER TABLE public.group_members
  ADD CONSTRAINT group_members_user_id_unique UNIQUE (user_id);
