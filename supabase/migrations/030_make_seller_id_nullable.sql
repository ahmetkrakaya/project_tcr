-- TCR Migration 030: Make seller_id nullable in marketplace_orders
-- Admin'ler sipariş oluşturduğunda satıcı ID'sine gerek yok

ALTER TABLE public.marketplace_orders
    ALTER COLUMN seller_id DROP NOT NULL;
