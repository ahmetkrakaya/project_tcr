-- TCR Migration 003: Carpooling (Ulaşım İmecesi)
-- Sürücü-Yolcu eşleştirme sistemi

-- Enum for carpool offer status
CREATE TYPE carpool_offer_status AS ENUM ('active', 'full', 'cancelled', 'completed');

-- Enum for carpool request status
CREATE TYPE carpool_request_status AS ENUM ('pending', 'accepted', 'rejected', 'cancelled');

-- Carpool offers (Sürücü ilanları)
CREATE TABLE public.carpool_offers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    driver_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    pickup_location_id UUID REFERENCES public.pickup_locations(id),
    custom_pickup_location TEXT, -- Eğer listede yoksa
    pickup_lat DECIMAL(10, 8),
    pickup_lng DECIMAL(11, 8),
    departure_time TIMESTAMPTZ NOT NULL,
    total_seats INTEGER NOT NULL CHECK (total_seats > 0 AND total_seats <= 8),
    available_seats INTEGER NOT NULL CHECK (available_seats >= 0),
    car_model TEXT,
    car_color TEXT,
    notes TEXT, -- "Bagajda yer var", "Sigara içilmez" vb.
    status carpool_offer_status DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT available_seats_check CHECK (available_seats <= total_seats)
);

-- Carpool requests (Yolcu talepleri)
CREATE TABLE public.carpool_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    offer_id UUID NOT NULL REFERENCES public.carpool_offers(id) ON DELETE CASCADE,
    passenger_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    seats_requested INTEGER DEFAULT 1 CHECK (seats_requested > 0 AND seats_requested <= 4),
    message TEXT, -- İsteğe bağlı mesaj
    status carpool_request_status DEFAULT 'pending',
    responded_at TIMESTAMPTZ,
    response_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(offer_id, passenger_id)
);

-- Triggers for updated_at
CREATE TRIGGER update_carpool_offers_updated_at
    BEFORE UPDATE ON public.carpool_offers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_carpool_requests_updated_at
    BEFORE UPDATE ON public.carpool_requests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to update available seats when request is accepted
CREATE OR REPLACE FUNCTION public.update_available_seats()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
        -- Koltuk sayısını azalt
        UPDATE public.carpool_offers
        SET available_seats = available_seats - NEW.seats_requested,
            status = CASE 
                WHEN available_seats - NEW.seats_requested <= 0 THEN 'full'::carpool_offer_status
                ELSE status
            END
        WHERE id = NEW.offer_id;
    ELSIF NEW.status = 'cancelled' AND OLD.status = 'accepted' THEN
        -- İptal edilirse koltuğu geri ver
        UPDATE public.carpool_offers
        SET available_seats = available_seats + OLD.seats_requested,
            status = 'active'::carpool_offer_status
        WHERE id = NEW.offer_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_carpool_request_status_change
    AFTER UPDATE OF status ON public.carpool_requests
    FOR EACH ROW EXECUTE FUNCTION public.update_available_seats();

-- Function to get carpool offers for an event
CREATE OR REPLACE FUNCTION public.get_event_carpool_offers(event_uuid UUID)
RETURNS TABLE (
    offer_id UUID,
    driver_name TEXT,
    driver_avatar TEXT,
    pickup_location TEXT,
    departure_time TIMESTAMPTZ,
    total_seats INTEGER,
    available_seats INTEGER,
    car_info TEXT,
    status carpool_offer_status
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        co.id,
        CONCAT(u.first_name, ' ', u.last_name),
        u.avatar_url,
        COALESCE(pl.name, co.custom_pickup_location),
        co.departure_time,
        co.total_seats,
        co.available_seats,
        CONCAT(co.car_model, ' - ', co.car_color),
        co.status
    FROM public.carpool_offers co
    JOIN public.users u ON u.id = co.driver_id
    LEFT JOIN public.pickup_locations pl ON pl.id = co.pickup_location_id
    WHERE co.event_id = event_uuid
    ORDER BY co.departure_time;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Indexes
CREATE INDEX idx_carpool_offers_event_id ON public.carpool_offers(event_id);
CREATE INDEX idx_carpool_offers_driver_id ON public.carpool_offers(driver_id);
CREATE INDEX idx_carpool_offers_status ON public.carpool_offers(status);
CREATE INDEX idx_carpool_offers_departure_time ON public.carpool_offers(departure_time);
CREATE INDEX idx_carpool_requests_offer_id ON public.carpool_requests(offer_id);
CREATE INDEX idx_carpool_requests_passenger_id ON public.carpool_requests(passenger_id);
CREATE INDEX idx_carpool_requests_status ON public.carpool_requests(status);
