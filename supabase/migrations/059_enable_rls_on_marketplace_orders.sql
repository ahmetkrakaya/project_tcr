-- TCR Migration 059: Enable RLS on marketplace_orders
-- Amaç: Supabase Dashboard'da UNRESTRICTED uyarısını kaldırmak için
-- marketplace_orders tablosunda Row Level Security'yi aktif etmek.
--
-- Not:
-- - 026_marketplace_orders_and_tcr_products.sql içinde marketplace_orders için
--   RLS policy'leri zaten tanımlı.
-- - Ancak o migration'da `ENABLE ROW LEVEL SECURITY` çağrısı olmadığı için
--   tablo şu anda RLS'siz (UNRESTRICTED) görünüyor.
--
-- Bu migration yalnızca RLS'yi açar; mevcut policy'ler aynen kullanılmaya devam eder.

ALTER TABLE public.marketplace_orders
    ENABLE ROW LEVEL SECURITY;

