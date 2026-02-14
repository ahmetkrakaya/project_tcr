-- 043_add_user_profile_fields.sql
-- Kullanıcı profiline cinsiyet, doğum tarihi ve kilo alanları eklenir.

-- NOTE:
--  - gender    : male / female / other / unknown (varsayılan: unknown)
--  - birth_date: doğum tarihi (opsiyonel)
--  - weight_kg : kilo bilgisi (opsiyonel, kg cinsinden)

-- CINSIYET
alter table public.users
  add column if not exists gender text
    check (gender in ('male', 'female', 'unknown'))
    default 'unknown';

-- DOGUM TARIHI
alter table public.users
  add column if not exists birth_date date;

-- KILO (KG)
alter table public.users
  add column if not exists weight_kg numeric;

