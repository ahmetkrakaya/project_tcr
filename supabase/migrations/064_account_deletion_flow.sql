-- 064_account_deletion_flow.sql
-- Kullanıcı hesabı silme akışı için alanlar ve fonksiyonlar

-- 1. Kullanıcı tablosuna (public.users) yeni alanlar
alter table public.users
  add column if not exists deletion_requested_at timestamptz,
  add column if not exists deletion_effective_at timestamptz,
  add column if not exists is_deleted boolean not null default false;

-- 2. Hesap silme talebi fonksiyonu
create or replace function public.request_account_deletion()
returns void
language plpgsql
security definer
as $$
declare
  v_user_id uuid;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Yetkisiz istek: kullanıcı bulunamadı';
  end if;

  update public.users
  set
    deletion_requested_at = now(),
    deletion_effective_at = now() + interval '15 days',
    updated_at = now()
  where id = v_user_id;
end;
$$;

-- 3. Hesap silme talebini iptal fonksiyonu
create or replace function public.cancel_account_deletion()
returns void
language plpgsql
security definer
as $$
declare
  v_user_id uuid;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Yetkisiz istek: kullanıcı bulunamadı';
  end if;

  update public.users
  set
    deletion_requested_at = null,
    deletion_effective_at = null,
    updated_at = now()
  where id = v_user_id
    and is_deleted = false;
end;
$$;

-- 4. Zamanı gelen hesap silme taleplerini işleyen fonksiyon
create or replace function public.process_account_deletions()
returns void
language plpgsql
security definer
as $$
begin
  -- Silinme tarihi geçmiş ve henüz silinmemiş hesapları işaretle
  update public.users
  set
    is_deleted = true,
    is_active = false,
    first_name = null,
    last_name = null,
    phone = null,
    avatar_url = null,
    bio = null,
    gender = 'unknown',
    birth_date = null,
    weight_kg = null,
    deletion_requested_at = null,
    updated_at = now()
  where
    is_deleted = false
    and deletion_effective_at is not null
    and deletion_effective_at <= now();
end;
$$;

