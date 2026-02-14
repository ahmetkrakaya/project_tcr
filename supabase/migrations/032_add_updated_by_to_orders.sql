-- TCR Migration 032: Add updated_by to marketplace_orders
-- Durum güncelleyen kişiyi kaydetmek için

ALTER TABLE public.marketplace_orders
    ADD COLUMN updated_by UUID REFERENCES public.users(id);

-- Index for better query performance
CREATE INDEX idx_marketplace_orders_updated_by ON public.marketplace_orders(updated_by);
