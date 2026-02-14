-- TCR Migration 049: Siparişlere seçilen beden bilgisi ekleme
-- Beden bazlı stok yönetimi için siparişte seçilen bedeni kaydetmek

-- selected_size kolonu ekle
ALTER TABLE public.marketplace_orders
ADD COLUMN IF NOT EXISTS selected_size TEXT;

-- Index ekle (sipariş sorgularında kullanılabilir)
CREATE INDEX IF NOT EXISTS idx_marketplace_orders_selected_size 
ON public.marketplace_orders(selected_size);

-- Açıklama ekle
COMMENT ON COLUMN public.marketplace_orders.selected_size IS 'Siparişte seçilen beden (S, M, L, XL vb.)';
