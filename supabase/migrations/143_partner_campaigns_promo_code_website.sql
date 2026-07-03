-- Kampanya: online indirim kodu ve web sitesi

ALTER TABLE public.partner_campaigns
    ADD COLUMN IF NOT EXISTS promo_code TEXT,
    ADD COLUMN IF NOT EXISTS website_url TEXT;

COMMENT ON COLUMN public.partner_campaigns.promo_code IS
    'Partner tarafından tanımlanan indirim kodu (online alışverişlerde kullanılır)';

COMMENT ON COLUMN public.partner_campaigns.website_url IS
    'Kampanyanın geçerli olduğu web sitesi adresi';
