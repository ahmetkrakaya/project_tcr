-- =====================================================
-- 066: Group Types - Normal ve Performans Grup Turleri
-- =====================================================
-- training_groups tablosuna group_type kolonu eklenir.
-- Performans gruplarina katilim talep sistemi (group_join_requests).
-- Performans gruplari icin kisisel antrenman programlari (event_member_programs).

-- =====================================================
-- 1) training_groups tablosuna group_type kolonu
-- =====================================================
ALTER TABLE public.training_groups
    ADD COLUMN IF NOT EXISTS group_type TEXT NOT NULL DEFAULT 'normal'
    CHECK (group_type IN ('normal', 'performance'));

-- =====================================================
-- 2) group_join_requests tablosu
-- =====================================================
CREATE TABLE IF NOT EXISTS public.group_join_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES public.training_groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    requested_at TIMESTAMPTZ DEFAULT NOW(),
    responded_at TIMESTAMPTZ,
    responded_by UUID REFERENCES public.users(id),
    UNIQUE(group_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_group_join_requests_group
    ON public.group_join_requests(group_id);
CREATE INDEX IF NOT EXISTS idx_group_join_requests_user
    ON public.group_join_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_group_join_requests_status
    ON public.group_join_requests(group_id, status);

ALTER TABLE public.group_join_requests ENABLE ROW LEVEL SECURITY;

-- Kullanici kendi taleplerini gorebilir, admin/coach tum talepleri gorebilir
CREATE POLICY "Users can view own join requests"
    ON public.group_join_requests FOR SELECT
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Kullanici kendisi icin talep olusturabilir
CREATE POLICY "Users can create join requests"
    ON public.group_join_requests FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Admin/Coach talepleri guncelleyebilir (onay/red)
CREATE POLICY "Admins can update join requests"
    ON public.group_join_requests FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Kullanici kendi bekleyen talebini silebilir, admin hepsini silebilir
CREATE POLICY "Users can delete own pending requests"
    ON public.group_join_requests FOR DELETE
    USING (
        (user_id = auth.uid() AND status = 'pending')
        OR EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- =====================================================
-- 3) event_member_programs tablosu
-- =====================================================
CREATE TABLE IF NOT EXISTS public.event_member_programs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    training_group_id UUID NOT NULL REFERENCES public.training_groups(id) ON DELETE CASCADE,
    program_content TEXT NOT NULL,
    workout_definition JSONB,
    route_id UUID REFERENCES public.routes(id) ON DELETE SET NULL,
    training_type_id UUID REFERENCES public.training_types(id),
    order_index INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_event_member_programs_event
    ON public.event_member_programs(event_id);
CREATE INDEX IF NOT EXISTS idx_event_member_programs_user
    ON public.event_member_programs(user_id);
CREATE INDEX IF NOT EXISTS idx_event_member_programs_group
    ON public.event_member_programs(training_group_id);

ALTER TABLE public.event_member_programs ENABLE ROW LEVEL SECURITY;

-- Kullanici kendi programini gorebilir, admin hepsini gorebilir
CREATE POLICY "Users can view own member programs"
    ON public.event_member_programs FOR SELECT
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Admin/Coach program olusturabilir
CREATE POLICY "Admins can create member programs"
    ON public.event_member_programs FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Admin/Coach program guncelleyebilir
CREATE POLICY "Admins can update member programs"
    ON public.event_member_programs FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Admin/Coach program silebilir
CREATE POLICY "Admins can delete member programs"
    ON public.event_member_programs FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_event_member_program_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER event_member_program_updated_at
    BEFORE UPDATE ON public.event_member_programs
    FOR EACH ROW EXECUTE FUNCTION update_event_member_program_updated_at();

-- =====================================================
-- 4) approve_group_join_request RPC
-- =====================================================
CREATE OR REPLACE FUNCTION public.approve_group_join_request(
    request_id UUID,
    admin_user_id UUID
)
RETURNS VOID AS $$
DECLARE
    v_user_id UUID;
    v_group_id UUID;
    v_current_group_id UUID;
BEGIN
    -- Talebi al
    SELECT user_id, group_id INTO v_user_id, v_group_id
    FROM public.group_join_requests
    WHERE id = request_id AND status = 'pending';

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Talep bulunamadi veya zaten islendi';
    END IF;

    -- Kullanicinin mevcut grubunu kontrol et
    SELECT group_id INTO v_current_group_id
    FROM public.group_members
    WHERE user_id = v_user_id;

    -- Mevcut gruptan cikar
    IF v_current_group_id IS NOT NULL THEN
        DELETE FROM public.group_members
        WHERE user_id = v_user_id AND group_id = v_current_group_id;
    END IF;

    -- Yeni gruba ekle
    INSERT INTO public.group_members (group_id, user_id)
    VALUES (v_group_id, v_user_id)
    ON CONFLICT (user_id) DO UPDATE SET group_id = v_group_id;

    -- Talebi onayla
    UPDATE public.group_join_requests
    SET status = 'approved',
        responded_at = NOW(),
        responded_by = admin_user_id
    WHERE id = request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
