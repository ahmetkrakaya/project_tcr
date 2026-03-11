-- =====================================================
-- 079: user_donations - foundation_name -> foundation_id
-- =====================================================
-- Vakıf artık foundations tablosundan seçilecek.

-- 1) Mevcut foundation_name değerlerini foundations'a ekle
INSERT INTO public.foundations (name)
SELECT DISTINCT foundation_name FROM public.user_donations
WHERE foundation_name IS NOT NULL AND trim(foundation_name) != ''
ON CONFLICT (name) DO NOTHING;

-- 2) foundation_id sütununu ekle
ALTER TABLE public.user_donations
ADD COLUMN IF NOT EXISTS foundation_id UUID REFERENCES public.foundations(id) ON DELETE RESTRICT;

-- 3) Mevcut verileri güncelle
UPDATE public.user_donations ud
SET foundation_id = f.id
FROM public.foundations f
WHERE f.name = ud.foundation_name
  AND ud.foundation_id IS NULL;

-- 4) foundation_name'i kaldır, foundation_id'yi zorunlu yap
ALTER TABLE public.user_donations DROP COLUMN IF EXISTS foundation_name;
ALTER TABLE public.user_donations ALTER COLUMN foundation_id SET NOT NULL;
