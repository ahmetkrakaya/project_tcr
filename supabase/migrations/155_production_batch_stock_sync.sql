-- Üretim partisi kaydı/silmesi stok tablosuna delta uygular.
-- Satış düşümleriyle uyumlu olması için replace yerine upsert + delta kullanılır.

CREATE OR REPLACE FUNCTION public.apply_production_stock_delta(
    p_listing_id UUID,
    p_size TEXT,
    p_gender public.listing_gender,
    p_delta INTEGER
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_gender public.listing_gender;
    v_size TEXT;
BEGIN
    IF p_delta = 0 THEN
        RETURN;
    END IF;

    v_gender := COALESCE(p_gender, 'unisex'::public.listing_gender);
    v_size := COALESCE(NULLIF(btrim(p_size), ''), 'Standart');

    INSERT INTO public.listing_stock_by_size (listing_id, size, gender, quantity)
    VALUES (p_listing_id, v_size, v_gender, GREATEST(0, p_delta))
    ON CONFLICT (listing_id, size, gender)
    DO UPDATE SET
        quantity = GREATEST(0, public.listing_stock_by_size.quantity + p_delta),
        updated_at = NOW();

    -- Genel stok alanını beden stoklarının toplamına senkronla
    UPDATE public.marketplace_listings
    SET stock_quantity = (
        SELECT COALESCE(SUM(s.quantity), 0)
        FROM public.listing_stock_by_size s
        WHERE s.listing_id = p_listing_id
    )
    WHERE id = p_listing_id;
END;
$$;

COMMENT ON FUNCTION public.apply_production_stock_delta(UUID, TEXT, public.listing_gender, INTEGER) IS
    'Üretim partisi ekleme/düzenleme/silme sonrası beden+cinsiyet stok kovasına delta uygular.';

GRANT EXECUTE ON FUNCTION public.apply_production_stock_delta(UUID, TEXT, public.listing_gender, INTEGER)
    TO authenticated;
