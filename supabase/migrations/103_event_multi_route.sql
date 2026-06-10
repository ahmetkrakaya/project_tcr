-- =====================================================
-- 103: Etkinliklere birden fazla rota desteği
-- =====================================================
-- Sadece antrenman etkinliklerinde kullanılır.
-- Katılımcılar RSVP sırasında hangi rotaya katılacaklarını seçer.

-- 1) event_route_options: etkinlik ↔ rota çoka-çok ilişkisi
CREATE TABLE public.event_route_options (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    route_id UUID NOT NULL REFERENCES public.routes(id) ON DELETE CASCADE,
    label TEXT,          -- Opsiyonel ek etiket (varsayılan olarak rota adı kullanılır)
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(event_id, route_id)
);

CREATE INDEX idx_event_route_options_event_id ON public.event_route_options(event_id);

ALTER TABLE public.event_route_options ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Event route options viewable by authenticated"
    ON public.event_route_options FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Admins and coaches manage event route options"
    ON public.event_route_options FOR ALL
    TO authenticated
    USING (public.is_admin_or_coach())
    WITH CHECK (public.is_admin_or_coach());

-- 2) event_participants: katılımcının seçtiği rota
ALTER TABLE public.event_participants
ADD COLUMN IF NOT EXISTS selected_route_id UUID REFERENCES public.routes(id) ON DELETE SET NULL;
