-- TCR Migration 006: Marketplace (Pazar Yeri)
-- İkinci el ürün ve fırsat paylaşımı

-- Enum for listing types
CREATE TYPE listing_type AS ENUM ('second_hand', 'hot_deal', 'wanted');

-- Enum for listing status
CREATE TYPE listing_status AS ENUM ('active', 'sold', 'reserved', 'expired', 'deleted');

-- Enum for listing categories
CREATE TYPE listing_category AS ENUM (
    'running_shoes',
    'sports_wear',
    'accessories',
    'watches_trackers',
    'nutrition',
    'equipment',
    'books',
    'other'
);

-- Enum for condition
CREATE TYPE item_condition AS ENUM ('new', 'like_new', 'good', 'fair', 'poor');

-- Marketplace listings
CREATE TABLE public.marketplace_listings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    seller_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    listing_type listing_type NOT NULL DEFAULT 'second_hand',
    category listing_category NOT NULL DEFAULT 'other',
    title TEXT NOT NULL,
    description TEXT,
    price DECIMAL(10, 2), -- NULL ise "Fiyat Sorunuz" veya link paylaşımı
    currency TEXT DEFAULT 'TRY',
    condition item_condition,
    brand TEXT,
    size TEXT, -- Ayakkabı/kıyafet bedeni
    external_url TEXT, -- Hot deal linki
    status listing_status DEFAULT 'active',
    view_count INTEGER DEFAULT 0,
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '30 days'),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Listing images
CREATE TABLE public.listing_images (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    thumbnail_url TEXT,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Listing favorites (Favorilere ekleme)
CREATE TABLE public.listing_favorites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(listing_id, user_id)
);

-- Listing messages (Satıcı-Alıcı mesajlaşması)
CREATE TABLE public.listing_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Function to increment view count
CREATE OR REPLACE FUNCTION public.increment_listing_view(listing_uuid UUID)
RETURNS void AS $$
BEGIN
    UPDATE public.marketplace_listings
    SET view_count = view_count + 1
    WHERE id = listing_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get listings with filters
CREATE OR REPLACE FUNCTION public.get_marketplace_listings(
    filter_category listing_category DEFAULT NULL,
    filter_type listing_type DEFAULT NULL,
    filter_min_price DECIMAL DEFAULT NULL,
    filter_max_price DECIMAL DEFAULT NULL,
    filter_size TEXT DEFAULT NULL,
    search_query TEXT DEFAULT NULL,
    page_size INTEGER DEFAULT 20,
    page_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    listing_id UUID,
    seller_id UUID,
    seller_name TEXT,
    seller_avatar TEXT,
    listing_type listing_type,
    category listing_category,
    title TEXT,
    price DECIMAL,
    condition item_condition,
    size TEXT,
    primary_image TEXT,
    status listing_status,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ml.id,
        ml.seller_id,
        CONCAT(u.first_name, ' ', u.last_name),
        u.avatar_url,
        ml.listing_type,
        ml.category,
        ml.title,
        ml.price,
        ml.condition,
        ml.size,
        (SELECT li.image_url FROM public.listing_images li WHERE li.listing_id = ml.id ORDER BY li.sort_order LIMIT 1),
        ml.status,
        ml.created_at
    FROM public.marketplace_listings ml
    JOIN public.users u ON u.id = ml.seller_id
    WHERE ml.status = 'active'
      AND (filter_category IS NULL OR ml.category = filter_category)
      AND (filter_type IS NULL OR ml.listing_type = filter_type)
      AND (filter_min_price IS NULL OR ml.price >= filter_min_price)
      AND (filter_max_price IS NULL OR ml.price <= filter_max_price)
      AND (filter_size IS NULL OR ml.size = filter_size)
      AND (search_query IS NULL OR ml.title ILIKE '%' || search_query || '%' OR ml.description ILIKE '%' || search_query || '%')
    ORDER BY ml.created_at DESC
    LIMIT page_size
    OFFSET page_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to match listings with user preferences (ayakkabı numarası, beden)
CREATE OR REPLACE FUNCTION public.get_matching_listings(user_uuid UUID)
RETURNS TABLE (
    listing_id UUID,
    match_reason TEXT
) AS $$
DECLARE
    user_shoe_size TEXT;
    user_tshirt_size tshirt_size;
BEGIN
    SELECT shoe_size, tshirt_size INTO user_shoe_size, user_tshirt_size
    FROM public.users WHERE id = user_uuid;
    
    RETURN QUERY
    SELECT ml.id, 
        CASE 
            WHEN ml.category = 'running_shoes' AND ml.size = user_shoe_size THEN 'Ayakkabı numaranıza uygun'
            WHEN ml.category = 'sports_wear' AND ml.size = user_tshirt_size::TEXT THEN 'Bedeninize uygun'
            ELSE 'Genel eşleşme'
        END
    FROM public.marketplace_listings ml
    WHERE ml.status = 'active'
      AND (
          (ml.category = 'running_shoes' AND ml.size = user_shoe_size)
          OR (ml.category = 'sports_wear' AND ml.size = user_tshirt_size::TEXT)
      )
    ORDER BY ml.created_at DESC
    LIMIT 10;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Triggers
CREATE TRIGGER update_marketplace_listings_updated_at
    BEFORE UPDATE ON public.marketplace_listings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Indexes
CREATE INDEX idx_marketplace_listings_seller_id ON public.marketplace_listings(seller_id);
CREATE INDEX idx_marketplace_listings_status ON public.marketplace_listings(status);
CREATE INDEX idx_marketplace_listings_category ON public.marketplace_listings(category);
CREATE INDEX idx_marketplace_listings_listing_type ON public.marketplace_listings(listing_type);
CREATE INDEX idx_marketplace_listings_price ON public.marketplace_listings(price);
CREATE INDEX idx_marketplace_listings_created_at ON public.marketplace_listings(created_at DESC);
CREATE INDEX idx_listing_images_listing_id ON public.listing_images(listing_id);
CREATE INDEX idx_listing_favorites_user_id ON public.listing_favorites(user_id);
CREATE INDEX idx_listing_messages_listing_id ON public.listing_messages(listing_id);
CREATE INDEX idx_listing_messages_receiver_id ON public.listing_messages(receiver_id);
