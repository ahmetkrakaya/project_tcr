-- TCR Migration 169: Grup pacer'ları
-- - Bir grupta birden fazla pacer olabilir.
-- - Bir pacer yalnızca tek bir grupta görev alabilir.
-- - Sadece 'pacer' rolündeki kullanıcılar atanabilir; atamaları adminler yapar.

CREATE TABLE IF NOT EXISTS public.group_pacers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id UUID NOT NULL REFERENCES public.training_groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
    assigned_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_group_pacers_group_id ON public.group_pacers(group_id);

COMMENT ON TABLE public.group_pacers IS
    'Antrenman gruplarına atanmış pacer''lar. user_id UNIQUE: bir pacer tek grupta görev alır.';

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
ALTER TABLE public.group_pacers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view group pacers" ON public.group_pacers;
CREATE POLICY "Authenticated users can view group pacers"
    ON public.group_pacers FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Admins can assign group pacers" ON public.group_pacers;
CREATE POLICY "Admins can assign group pacers"
    ON public.group_pacers FOR INSERT
    TO authenticated
    WITH CHECK (public.is_super_admin());

DROP POLICY IF EXISTS "Admins can update group pacers" ON public.group_pacers;
CREATE POLICY "Admins can update group pacers"
    ON public.group_pacers FOR UPDATE
    TO authenticated
    USING (public.is_super_admin())
    WITH CHECK (public.is_super_admin());

DROP POLICY IF EXISTS "Admins can remove group pacers" ON public.group_pacers;
CREATE POLICY "Admins can remove group pacers"
    ON public.group_pacers FOR DELETE
    TO authenticated
    USING (public.is_super_admin());

-- ------------------------------------------------------------
-- Sadece pacer rolündeki kullanıcılar atanabilir
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_group_pacer_has_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.has_role(NEW.user_id, 'pacer') THEN
        RAISE EXCEPTION 'Sadece Pacer rolündeki kullanıcılar gruba pacer olarak atanabilir';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_group_pacers_require_role ON public.group_pacers;
CREATE TRIGGER trg_group_pacers_require_role
    BEFORE INSERT OR UPDATE OF user_id ON public.group_pacers
    FOR EACH ROW EXECUTE FUNCTION public.ensure_group_pacer_has_role();

-- ------------------------------------------------------------
-- Pacer rolü kaldırılınca grup ataması da kalkar
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cleanup_group_pacer_on_role_removal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.role = 'pacer' THEN
        DELETE FROM public.group_pacers WHERE user_id = OLD.user_id;
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_roles_cleanup_group_pacer ON public.user_roles;
CREATE TRIGGER trg_user_roles_cleanup_group_pacer
    AFTER DELETE ON public.user_roles
    FOR EACH ROW EXECUTE FUNCTION public.cleanup_group_pacer_on_role_removal();
