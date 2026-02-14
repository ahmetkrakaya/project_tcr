-- =====================================================
-- 013: Event Group Programs - Grup Bazlı Antrenman Programları
-- =====================================================
-- Bir etkinliğe birden fazla grup ve her grup için özel program eklenmesini sağlar

-- Event Group Programs Tablosu
CREATE TABLE IF NOT EXISTS public.event_group_programs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    training_group_id UUID NOT NULL REFERENCES public.training_groups(id) ON DELETE CASCADE,
    program_content TEXT NOT NULL,  -- "80dk canlı koşu" gibi antrenman açıklaması
    route_id UUID REFERENCES public.routes(id) ON DELETE SET NULL,  -- Opsiyonel grup rotası
    order_index INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Her etkinlikte bir grup sadece bir kez olabilir
    UNIQUE(event_id, training_group_id)
);

-- Indexler
CREATE INDEX IF NOT EXISTS idx_event_group_programs_event_id 
    ON public.event_group_programs(event_id);
CREATE INDEX IF NOT EXISTS idx_event_group_programs_group_id 
    ON public.event_group_programs(training_group_id);
CREATE INDEX IF NOT EXISTS idx_event_group_programs_order 
    ON public.event_group_programs(event_id, order_index);

-- RLS Aktif Et
ALTER TABLE public.event_group_programs ENABLE ROW LEVEL SECURITY;

-- Herkes okuyabilir (yayınlanmış etkinlikler için)
CREATE POLICY "Anyone can view group programs of published events"
    ON public.event_group_programs FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.events 
            WHERE events.id = event_group_programs.event_id 
            AND events.status = 'published'
        )
    );

-- Admin ve Coach oluşturabilir
CREATE POLICY "Admins and coaches can create group programs"
    ON public.event_group_programs FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Admin ve Coach güncelleyebilir
CREATE POLICY "Admins and coaches can update group programs"
    ON public.event_group_programs FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Admin ve Coach silebilir
CREATE POLICY "Admins and coaches can delete group programs"
    ON public.event_group_programs FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_event_group_program_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER event_group_program_updated_at
    BEFORE UPDATE ON public.event_group_programs
    FOR EACH ROW EXECUTE FUNCTION update_event_group_program_updated_at();

-- training_groups tablosuna member_count için fonksiyon
CREATE OR REPLACE FUNCTION public.get_group_member_count(group_uuid UUID)
RETURNS INTEGER AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM public.group_members
        WHERE group_id = group_uuid
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Kullanıcının bir gruba üye olup olmadığını kontrol eden fonksiyon
CREATE OR REPLACE FUNCTION public.is_group_member(group_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS(
        SELECT 1 FROM public.group_members
        WHERE group_id = group_uuid AND user_id = user_uuid
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Group members tablosu için RLS politikaları (eğer yoksa)
DO $$
BEGIN
    -- RLS'i aktif et
    ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
EXCEPTION
    WHEN others THEN NULL;
END $$;

-- Herkes grup üyelerini görebilir
DROP POLICY IF EXISTS "Anyone can view group members" ON public.group_members;
CREATE POLICY "Anyone can view group members"
    ON public.group_members FOR SELECT
    USING (true);

-- Admin/Coach üye ekleyebilir
DROP POLICY IF EXISTS "Admins can manage group members" ON public.group_members;
CREATE POLICY "Admins can manage group members"
    ON public.group_members FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
        OR user_id = auth.uid()  -- Kullanıcı kendini ekleyebilir
    );

-- Kullanıcı kendini çıkarabilir, admin herkesi çıkarabilir
DROP POLICY IF EXISTS "Users can leave groups" ON public.group_members;
CREATE POLICY "Users can leave groups"
    ON public.group_members FOR DELETE
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Training groups tablosu için RLS politikaları (eğer yoksa)
DO $$
BEGIN
    ALTER TABLE public.training_groups ENABLE ROW LEVEL SECURITY;
EXCEPTION
    WHEN others THEN NULL;
END $$;

-- Herkes grupları görebilir
DROP POLICY IF EXISTS "Anyone can view training groups" ON public.training_groups;
CREATE POLICY "Anyone can view training groups"
    ON public.training_groups FOR SELECT
    USING (true);

-- Admin/Coach grup oluşturabilir
DROP POLICY IF EXISTS "Admins can create training groups" ON public.training_groups;
CREATE POLICY "Admins can create training groups"
    ON public.training_groups FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Admin/Coach grup güncelleyebilir
DROP POLICY IF EXISTS "Admins can update training groups" ON public.training_groups;
CREATE POLICY "Admins can update training groups"
    ON public.training_groups FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Admin/Coach grup silebilir
DROP POLICY IF EXISTS "Admins can delete training groups" ON public.training_groups;
CREATE POLICY "Admins can delete training groups"
    ON public.training_groups FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Varsayılan grupları ekle (eğer yoksa)
INSERT INTO public.training_groups (name, description, target_distance, difficulty_level, color, icon, is_active)
VALUES 
    ('21K', 'Yarı maraton mesafesine hazırlanan koşucular', '21K', 4, '#EF4444', 'directions_run', true),
    ('10K', '10 kilometre mesafesine hazırlanan koşucular', '10K', 3, '#F59E0B', 'directions_run', true),
    ('Yürü-Koş', 'Yürüyüş ve koşu kombinasyonu yapan grup', '5K', 2, '#10B981', 'directions_walk', true),
    ('Yeni Başlayanlar', 'Koşuya yeni başlayan veya temel kondisyon çalışan grup', '3K', 1, '#3B82F6', 'accessibility_new', true)
ON CONFLICT DO NOTHING;
