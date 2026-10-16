-- TCR Migration 168: Koç (coach) rolünün kaldırılması
-- - Koç kullanıcıları düz üyeye (member) düşürülür.
-- - Koça yetki veren tüm RLS/storage politikaları ve SQL fonksiyonları
--   yalnızca super_admin'e açık olacak şekilde yeniden yazılır.
-- - Manuel bildirim kitlesindeki "coaches" filtresi "pacers" olur.
-- - is_admin_or_coach() / assert_admin_or_coach() kaldırılır.
-- - Postgres enum değeri silmeyi desteklemediği için 'coach' tipte kalır,
--   CHECK constraint ile kullanımı engellenir.

-- ============================================================
-- 1) Veri: koçları üyeye çevir
-- ============================================================
INSERT INTO public.user_roles (user_id, role)
SELECT DISTINCT ur.user_id, 'member'::user_role
FROM public.user_roles ur
WHERE ur.role = 'coach'
ON CONFLICT (user_id, role) DO NOTHING;

DELETE FROM public.user_roles WHERE role = 'coach';

ALTER TABLE public.user_roles
    DROP CONSTRAINT IF EXISTS user_roles_no_coach;
ALTER TABLE public.user_roles
    ADD CONSTRAINT user_roles_no_coach CHECK (role <> 'coach');

COMMENT ON CONSTRAINT user_roles_no_coach ON public.user_roles IS
    'coach rolü kaldırıldı (168). Enum değeri geriye dönük uyumluluk için tipte duruyor ama atanamaz.';

-- ============================================================
-- 2) Yardımcı: super admin assert
-- ============================================================
CREATE OR REPLACE FUNCTION public.assert_super_admin()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Bu islem sadece adminler icindir';
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.assert_super_admin() TO authenticated;

-- ============================================================
-- 3) Manuel bildirim kitlesi: coaches -> pacers
-- ============================================================
DO $$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid)
    INTO v_def
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'admin_resolve_manual_notification_recipients';

    IF v_def IS NULL THEN
        RAISE EXCEPTION 'admin_resolve_manual_notification_recipients bulunamadi';
    END IF;

    v_def := replace(v_def, '''coaches''', '''pacers''');
    v_def := replace(v_def, 'v_coaches', 'v_pacers');
    v_def := regexp_replace(v_def, 'role\s*=\s*''coach''', 'role = ''pacer''', 'g');

    EXECUTE v_def;
END;
$$;

-- ============================================================
-- 4) Fonksiyonlar: koç kontrollerini super_admin'e indir
-- ============================================================
DO $$
DECLARE
    r RECORD;
    v_def TEXT;
    v_new TEXT;
BEGIN
    FOR r IN
        SELECT p.oid, p.proname
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.prokind = 'f'
          AND p.proname NOT IN ('is_admin_or_coach', 'assert_admin_or_coach')
          AND (
              p.prosrc ~ '''coach'''
              OR p.prosrc ~ 'is_admin_or_coach\s*\('
              OR p.prosrc ~ 'assert_admin_or_coach\s*\('
          )
    LOOP
        v_def := pg_get_functiondef(r.oid);
        v_new := v_def;

        v_new := regexp_replace(v_new, 'is_admin_or_coach\s*\(\s*\)', 'is_super_admin()', 'g');
        v_new := regexp_replace(v_new, 'assert_admin_or_coach\s*\(\s*\)', 'assert_super_admin()', 'g');
        v_new := regexp_replace(v_new, 'IN\s*\(\s*''super_admin''\s*,\s*''coach''\s*\)', '= ''super_admin''', 'gi');
        v_new := regexp_replace(v_new, 'IN\s*\(\s*''coach''\s*,\s*''super_admin''\s*\)', '= ''super_admin''', 'gi');
        v_new := regexp_replace(v_new, '\s+OR\s+([a-z_]+\.)?role\s*=\s*''coach''', '', 'gi');

        IF v_new <> v_def THEN
            RAISE NOTICE 'coach kontrolu kaldiriliyor: %', r.proname;
            EXECUTE v_new;
        END IF;
    END LOOP;
END;
$$;

-- ============================================================
-- 5) Politikalar (public + storage): koç kontrollerini super_admin'e indir
-- ============================================================
DO $$
DECLARE
    r RECORD;
    v_qual TEXT;
    v_check TEXT;
    v_sql TEXT;
BEGIN
    FOR r IN
        SELECT schemaname, tablename, policyname, qual, with_check
        FROM pg_policies
        WHERE schemaname IN ('public', 'storage')
          AND (
              COALESCE(qual, '') ~ '''coach''|is_admin_or_coach\s*\('
              OR COALESCE(with_check, '') ~ '''coach''|is_admin_or_coach\s*\('
          )
    LOOP
        v_qual := r.qual;
        v_check := r.with_check;

        IF v_qual IS NOT NULL THEN
            v_qual := regexp_replace(v_qual, '(public\.)?is_admin_or_coach\s*\(\s*\)', 'public.is_super_admin()', 'g');
            v_qual := regexp_replace(v_qual, '''super_admin''::(public\.)?user_role\s*,\s*''coach''::(public\.)?user_role', '''super_admin''::user_role', 'g');
            v_qual := regexp_replace(v_qual, '''coach''::(public\.)?user_role\s*,\s*''super_admin''::(public\.)?user_role', '''super_admin''::user_role', 'g');
            v_qual := regexp_replace(v_qual, '\(([a-z_]+\.)?role\s*=\s*''coach''::(public\.)?user_role\)', '(false)', 'g');
        END IF;

        IF v_check IS NOT NULL THEN
            v_check := regexp_replace(v_check, '(public\.)?is_admin_or_coach\s*\(\s*\)', 'public.is_super_admin()', 'g');
            v_check := regexp_replace(v_check, '''super_admin''::(public\.)?user_role\s*,\s*''coach''::(public\.)?user_role', '''super_admin''::user_role', 'g');
            v_check := regexp_replace(v_check, '''coach''::(public\.)?user_role\s*,\s*''super_admin''::(public\.)?user_role', '''super_admin''::user_role', 'g');
            v_check := regexp_replace(v_check, '\(([a-z_]+\.)?role\s*=\s*''coach''::(public\.)?user_role\)', '(false)', 'g');
        END IF;

        v_sql := format('ALTER POLICY %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
        IF v_qual IS NOT NULL THEN
            v_sql := v_sql || format(' USING (%s)', v_qual);
        END IF;
        IF v_check IS NOT NULL THEN
            v_sql := v_sql || format(' WITH CHECK (%s)', v_check);
        END IF;

        RAISE NOTICE 'coach kontrolu kaldiriliyor: %.% / %', r.schemaname, r.tablename, r.policyname;
        EXECUTE v_sql;
    END LOOP;
END;
$$;

-- Politika isimlerindeki "coach" ifadelerini temizle.
-- storage.objects'in sahibi postgres olmadığından RENAME yapılamaz;
-- storage politikaları yeni isimle yeniden oluşturulup eskisi silinir.
DO $$
DECLARE
    r RECORD;
    v_name TEXT;
    v_sql TEXT;
BEGIN
    FOR r IN
        SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
        FROM pg_policies
        WHERE schemaname IN ('public', 'storage')
          AND policyname ~* 'coach'
    LOOP
        v_name := r.policyname;
        v_name := regexp_replace(v_name, 'Admin/Coach', 'Admin', 'g');
        v_name := regexp_replace(v_name, 'Admins and coaches', 'Admins', 'g');
        v_name := regexp_replace(v_name, 'admin or coach', 'admin', 'gi');
        v_name := regexp_replace(v_name, '\s*(and|or|/)\s*coach(es)?', '', 'gi');

        IF v_name <> r.policyname AND NOT EXISTS (
            SELECT 1 FROM pg_policies p
            WHERE p.schemaname = r.schemaname
              AND p.tablename = r.tablename
              AND p.policyname = v_name
        ) THEN
            IF r.schemaname = 'storage' THEN
                v_sql := format(
                    'CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s',
                    v_name, r.schemaname, r.tablename, r.permissive, r.cmd,
                    (SELECT string_agg(quote_ident(role_name), ', ') FROM unnest(r.roles) AS role_name)
                );
                IF r.qual IS NOT NULL THEN
                    v_sql := v_sql || format(' USING (%s)', r.qual);
                END IF;
                IF r.with_check IS NOT NULL THEN
                    v_sql := v_sql || format(' WITH CHECK (%s)', r.with_check);
                END IF;

                EXECUTE v_sql;
                EXECUTE format('DROP POLICY %I ON %I.%I',
                    r.policyname, r.schemaname, r.tablename);
            ELSE
                EXECUTE format('ALTER POLICY %I ON %I.%I RENAME TO %I',
                    r.policyname, r.schemaname, r.tablename, v_name);
            END IF;
        END IF;
    END LOOP;
END;
$$;

-- ============================================================
-- 6) Doğrulama: koç referansı kalmamalı
-- ============================================================
DO $$
DECLARE
    v_left TEXT;
BEGIN
    SELECT string_agg(format('%s.%s / %s', schemaname, tablename, policyname), ', ')
    INTO v_left
    FROM pg_policies
    WHERE schemaname IN ('public', 'storage')
      AND (
          COALESCE(qual, '') ~ '''coach''|is_admin_or_coach\s*\('
          OR COALESCE(with_check, '') ~ '''coach''|is_admin_or_coach\s*\('
      );

    IF v_left IS NOT NULL THEN
        RAISE EXCEPTION 'Hala coach referansi iceren politikalar var: %', v_left;
    END IF;

    SELECT string_agg(p.proname, ', ')
    INTO v_left
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname NOT IN ('is_admin_or_coach', 'assert_admin_or_coach')
      AND (
          p.prosrc ~ '''coach'''
          OR p.prosrc ~ 'is_admin_or_coach\s*\('
          OR p.prosrc ~ 'assert_admin_or_coach\s*\('
      );

    IF v_left IS NOT NULL THEN
        RAISE EXCEPTION 'Hala coach referansi iceren fonksiyonlar var: %', v_left;
    END IF;

    SELECT string_agg(format('%s.%s', schemaname, viewname), ', ')
    INTO v_left
    FROM pg_views
    WHERE schemaname = 'public'
      AND definition ~ '''coach''|is_admin_or_coach\s*\(';

    IF v_left IS NOT NULL THEN
        RAISE EXCEPTION 'Hala coach referansi iceren view''lar var: %', v_left;
    END IF;
END;
$$;

-- ============================================================
-- 7) Eski yardımcıları kaldır (CASCADE yok: bağımlılık kaldıysa hata verir)
-- ============================================================
DROP FUNCTION IF EXISTS public.is_admin_or_coach();
DROP FUNCTION IF EXISTS public.assert_admin_or_coach();
