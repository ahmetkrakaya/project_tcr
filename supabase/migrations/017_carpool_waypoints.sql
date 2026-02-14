-- TCR Migration 017: Carpool Waypoints (Güzergah Noktaları)
-- Carpool ilanlarına güzergah desteği ekleme

-- Carpool offer waypoints (Güzergah noktaları)
CREATE TABLE public.carpool_offer_waypoints (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    offer_id UUID NOT NULL REFERENCES public.carpool_offers(id) ON DELETE CASCADE,
    pickup_location_id UUID REFERENCES public.pickup_locations(id),
    custom_location_name TEXT, -- Eğer listede yoksa
    lat DECIMAL(10, 8),
    lng DECIMAL(11, 8),
    sort_order INTEGER NOT NULL, -- Sıralama (0 = ilk nokta, 1 = ikinci nokta, vb.)
    estimated_arrival_time TIMESTAMPTZ, -- Bu noktaya tahmini varış saati
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_carpool_offer_waypoints_offer_id ON public.carpool_offer_waypoints(offer_id);
CREATE INDEX idx_carpool_offer_waypoints_sort_order ON public.carpool_offer_waypoints(offer_id, sort_order);

-- RLS Policies
ALTER TABLE public.carpool_offer_waypoints ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Carpool waypoints are viewable by everyone"
    ON public.carpool_offer_waypoints FOR SELECT
    USING (true);

CREATE POLICY "Users can create waypoints for own offers"
    ON public.carpool_offer_waypoints FOR INSERT
    WITH CHECK (
        auth.uid() IN (
            SELECT driver_id FROM public.carpool_offers WHERE id = offer_id
        )
    );

CREATE POLICY "Users can update waypoints for own offers"
    ON public.carpool_offer_waypoints FOR UPDATE
    USING (
        auth.uid() IN (
            SELECT driver_id FROM public.carpool_offers WHERE id = offer_id
        )
    );

CREATE POLICY "Users can delete waypoints for own offers"
    ON public.carpool_offer_waypoints FOR DELETE
    USING (
        auth.uid() IN (
            SELECT driver_id FROM public.carpool_offers WHERE id = offer_id
        )
    );

-- Bir kullanıcının bir etkinlikte sadece bir aktif ilanı olabilir
CREATE UNIQUE INDEX idx_carpool_offers_user_event_active 
    ON public.carpool_offers(driver_id, event_id) 
    WHERE status = 'active';
