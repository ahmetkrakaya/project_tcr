-- TCR Migration 147: Restore buyer order creation policy
-- Sorun: Migration 031, normal üyelerin sipariş oluşturma iznini (RLS policy)
--        kaldırdı. Bu nedenle sadece admin yetkisiyle sipariş verilebiliyordu,
--        normal üyeler hata alıyordu.
-- Çözüm: "Buyers can create orders" policy'sini yeniden oluştur.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'marketplace_orders'
          AND policyname = 'Buyers can create orders'
    ) THEN
        EXECUTE $policy$
            CREATE POLICY "Buyers can create orders"
                ON public.marketplace_orders FOR INSERT
                WITH CHECK (auth.uid() = buyer_id);
        $policy$;
    END IF;
END;
$$;
