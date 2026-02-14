-- TCR Migration 031: Remove buyer order creation policy
-- Artık sadece admin'ler sipariş oluşturabilir

-- Eski buyer policy'sini kaldır
DROP POLICY IF EXISTS "Buyers can create orders" ON public.marketplace_orders;
