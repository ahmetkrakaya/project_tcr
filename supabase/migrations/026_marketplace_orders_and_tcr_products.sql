-- TCR Migration 026: Marketplace Orders and TCR Products
-- Sipariş sistemi ve TCR ürünleri desteği

-- Enum'a 'tcr_product' ekle
ALTER TYPE listing_type ADD VALUE IF NOT EXISTS 'tcr_product';

-- Sipariş durumu enum'u
CREATE TYPE order_status AS ENUM ('pending', 'confirmed', 'cancelled', 'completed');

-- Marketplace siparişleri tablosu
CREATE TABLE public.marketplace_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
    buyer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    seller_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    quantity INTEGER DEFAULT 1,
    total_price DECIMAL(10, 2) NOT NULL,
    currency TEXT DEFAULT 'TRY',
    status order_status DEFAULT 'pending',
    buyer_note TEXT, -- Alıcı notu (teslimat adresi, iletişim bilgisi vs.)
    seller_note TEXT, -- Satıcı notu
    confirmed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    cancelled_by UUID REFERENCES public.users(id),
    cancellation_reason TEXT,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Sipariş geçmişi için index'ler
CREATE INDEX idx_marketplace_orders_listing_id ON public.marketplace_orders(listing_id);
CREATE INDEX idx_marketplace_orders_buyer_id ON public.marketplace_orders(buyer_id);
CREATE INDEX idx_marketplace_orders_seller_id ON public.marketplace_orders(seller_id);
CREATE INDEX idx_marketplace_orders_status ON public.marketplace_orders(status);
CREATE INDEX idx_marketplace_orders_created_at ON public.marketplace_orders(created_at DESC);

-- Trigger for updated_at
CREATE TRIGGER update_marketplace_orders_updated_at
    BEFORE UPDATE ON public.marketplace_orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function: Sipariş oluşturulduğunda listing'i reserved yap (TCR ürünleri için)
CREATE OR REPLACE FUNCTION public.handle_order_created()
RETURNS TRIGGER AS $$
BEGIN
    -- Eğer listing_type 'tcr_product' ise ve stok kontrolü yapılacaksa burada yapılabilir
    -- Şimdilik sadece trigger oluşturuyoruz
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Sipariş oluşturulduğunda
CREATE TRIGGER on_order_created
    AFTER INSERT ON public.marketplace_orders
    FOR EACH ROW EXECUTE FUNCTION public.handle_order_created();

-- Function: Sipariş onaylandığında listing'i sold yapabilir
CREATE OR REPLACE FUNCTION public.handle_order_confirmed()
RETURNS TRIGGER AS $$
BEGIN
    -- Sipariş onaylandığında listing durumunu güncelle
    IF NEW.status = 'confirmed' AND OLD.status != 'confirmed' THEN
        UPDATE public.marketplace_listings
        SET status = 'reserved'
        WHERE id = NEW.listing_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Sipariş onaylandığında
CREATE TRIGGER on_order_confirmed
    AFTER UPDATE ON public.marketplace_orders
    FOR EACH ROW EXECUTE FUNCTION public.handle_order_confirmed();

-- Function: Sipariş iptal edildiğinde listing'i tekrar active yap
CREATE OR REPLACE FUNCTION public.handle_order_cancelled()
RETURNS TRIGGER AS $$
BEGIN
    -- Sipariş iptal edildiğinde listing durumunu tekrar active yap
    IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
        UPDATE public.marketplace_listings
        SET status = 'active'
        WHERE id = NEW.listing_id AND status = 'reserved';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Sipariş iptal edildiğinde
CREATE TRIGGER on_order_cancelled
    AFTER UPDATE ON public.marketplace_orders
    FOR EACH ROW EXECUTE FUNCTION public.handle_order_cancelled();

-- RLS Policies for marketplace_orders
-- Herkes kendi siparişlerini görebilir (alıcı veya satıcı olarak)
CREATE POLICY "Users can view own orders"
    ON public.marketplace_orders FOR SELECT
    USING (auth.uid() = buyer_id OR auth.uid() = seller_id);

-- Alıcılar sipariş oluşturabilir
CREATE POLICY "Buyers can create orders"
    ON public.marketplace_orders FOR INSERT
    WITH CHECK (auth.uid() = buyer_id);

-- Alıcılar kendi siparişlerini güncelleyebilir (iptal etme vs.)
CREATE POLICY "Buyers can update own orders"
    ON public.marketplace_orders FOR UPDATE
    USING (auth.uid() = buyer_id)
    WITH CHECK (auth.uid() = buyer_id);

-- Satıcılar kendi ürünlerine gelen siparişleri onaylayabilir/iptal edebilir
CREATE POLICY "Sellers can update orders for their listings"
    ON public.marketplace_orders FOR UPDATE
    USING (auth.uid() = seller_id)
    WITH CHECK (auth.uid() = seller_id);

-- RLS Policies for marketplace_listings - TCR ürünleri için admin kontrolü
-- TCR ürünleri sadece adminler oluşturabilir
CREATE POLICY "Only admins can create TCR products"
    ON public.marketplace_listings FOR INSERT
    WITH CHECK (
        listing_type != 'tcr_product' OR 
        public.has_role(auth.uid(), 'super_admin')
    );

-- TCR ürünleri sadece adminler güncelleyebilir
CREATE POLICY "Only admins can update TCR products"
    ON public.marketplace_listings FOR UPDATE
    USING (
        listing_type != 'tcr_product' OR 
        public.has_role(auth.uid(), 'super_admin')
    )
    WITH CHECK (
        listing_type != 'tcr_product' OR 
        public.has_role(auth.uid(), 'super_admin')
    );

-- TCR ürünleri sadece adminler silebilir
CREATE POLICY "Only admins can delete TCR products"
    ON public.marketplace_listings FOR DELETE
    USING (
        listing_type != 'tcr_product' OR 
        public.has_role(auth.uid(), 'super_admin')
    );
