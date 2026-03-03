-- TCR Migration 060: Fix marketplace_orders admin access
-- Amaç: Admin (super_admin) kullanıcıların marketplace_orders tablosunda
-- tüm siparişleri görebilmesini ve yönetebilmesini garanti altına almak.
-- 029_admin_orders_access.sql migration'ının eksik olduğu ortamlarda
-- gerekli policy'leri idempotent şekilde yeniden oluşturur.

-- Emin olmak için RLS'yi tekrar aç (idempotent, zaten açıksa hata vermez)
ALTER TABLE public.marketplace_orders
    ENABLE ROW LEVEL SECURITY;

-- Admin'ler tüm siparişleri görebilir
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'marketplace_orders'
          AND policyname = 'Admins can view all orders'
    ) THEN
        EXECUTE $policy$
            CREATE POLICY "Admins can view all orders"
                ON public.marketplace_orders FOR SELECT
                USING (public.has_role(auth.uid(), 'super_admin'));
        $policy$;
    END IF;
END;
$$;

-- Admin'ler tüm siparişleri güncelleyebilir
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'marketplace_orders'
          AND policyname = 'Admins can update all orders'
    ) THEN
        EXECUTE $policy$
            CREATE POLICY "Admins can update all orders"
                ON public.marketplace_orders FOR UPDATE
                USING (public.has_role(auth.uid(), 'super_admin'))
                WITH CHECK (public.has_role(auth.uid(), 'super_admin'));
        $policy$;
    END IF;
END;
$$;

-- Admin'ler sipariş oluşturabilir (seller_id olmadan da)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'marketplace_orders'
          AND policyname = 'Admins can create orders'
    ) THEN
        EXECUTE $policy$
            CREATE POLICY "Admins can create orders"
                ON public.marketplace_orders FOR INSERT
                WITH CHECK (public.has_role(auth.uid(), 'super_admin'));
        $policy$;
    END IF;
END;
$$;

