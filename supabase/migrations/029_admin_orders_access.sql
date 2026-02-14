-- TCR Migration 029: Admin Orders Access
-- Admin'lerin tüm siparişleri görebilmesi ve yönetebilmesi için RLS policy

-- Admin'ler tüm siparişleri görebilir
CREATE POLICY "Admins can view all orders"
    ON public.marketplace_orders FOR SELECT
    USING (public.has_role(auth.uid(), 'super_admin'));

-- Admin'ler tüm siparişleri güncelleyebilir
CREATE POLICY "Admins can update all orders"
    ON public.marketplace_orders FOR UPDATE
    USING (public.has_role(auth.uid(), 'super_admin'))
    WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

-- Admin'ler sipariş oluşturabilir (seller_id olmadan)
CREATE POLICY "Admins can create orders"
    ON public.marketplace_orders FOR INSERT
    WITH CHECK (public.has_role(auth.uid(), 'super_admin'));
