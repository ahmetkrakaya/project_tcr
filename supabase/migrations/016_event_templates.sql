-- TCR Migration 016: Event Templates
-- Etkinlik şablonları sistemi

-- Etkinlik şablonları
CREATE TABLE public.event_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,                    -- "Salı Tempo", "Pazar Uzun Koşu"
    description TEXT,
    event_type event_type DEFAULT 'training',
    location_name TEXT,
    location_address TEXT,
    location_lat DECIMAL(10, 8),
    location_lng DECIMAL(11, 8),
    route_id UUID REFERENCES public.routes(id) ON DELETE SET NULL,
    training_type_id UUID REFERENCES public.training_types(id) ON DELETE SET NULL,
    default_start_time TIME,               -- Varsayılan saat (08:00)
    duration_minutes INTEGER,              -- Varsayılan süre
    is_active BOOLEAN DEFAULT true,
    created_by UUID NOT NULL REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Şablon grup programları
CREATE TABLE public.event_template_group_programs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    template_id UUID NOT NULL REFERENCES public.event_templates(id) ON DELETE CASCADE,
    training_group_id UUID NOT NULL REFERENCES public.training_groups(id) ON DELETE CASCADE,
    program_content TEXT NOT NULL,
    route_id UUID REFERENCES public.routes(id) ON DELETE SET NULL,
    training_type_id UUID REFERENCES public.training_types(id) ON DELETE SET NULL,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_event_templates_created_by ON public.event_templates(created_by);
CREATE INDEX idx_event_templates_is_active ON public.event_templates(is_active);
CREATE INDEX idx_event_template_group_programs_template_id ON public.event_template_group_programs(template_id);

-- Trigger for updated_at
CREATE TRIGGER update_event_templates_updated_at
    BEFORE UPDATE ON public.event_templates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- RLS Policies
ALTER TABLE public.event_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_template_group_programs ENABLE ROW LEVEL SECURITY;

-- Event templates: Herkes okuyabilir, admin/coach oluşturabilir
CREATE POLICY "event_templates_select_policy" ON public.event_templates
    FOR SELECT USING (true);

CREATE POLICY "event_templates_insert_policy" ON public.event_templates
    FOR INSERT WITH CHECK (public.is_admin_or_coach());

CREATE POLICY "event_templates_update_policy" ON public.event_templates
    FOR UPDATE USING (public.is_admin_or_coach());

CREATE POLICY "event_templates_delete_policy" ON public.event_templates
    FOR DELETE USING (public.is_admin_or_coach());

-- Event template group programs: Herkes okuyabilir, admin/coach oluşturabilir
CREATE POLICY "event_template_group_programs_select_policy" ON public.event_template_group_programs
    FOR SELECT USING (true);

CREATE POLICY "event_template_group_programs_insert_policy" ON public.event_template_group_programs
    FOR INSERT WITH CHECK (public.is_admin_or_coach());

CREATE POLICY "event_template_group_programs_update_policy" ON public.event_template_group_programs
    FOR UPDATE USING (public.is_admin_or_coach());

CREATE POLICY "event_template_group_programs_delete_policy" ON public.event_template_group_programs
    FOR DELETE USING (public.is_admin_or_coach());
