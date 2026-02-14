-- TCR Migration 038: Events participation type (Bireysel / Ekip)
-- Antrenman etkinliklerinde: Ekip = toplu antrenman (Katılıyorum/RSVP), Bireysel = isteğe bağlı (katılım kaydı yok)

ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS participation_type TEXT DEFAULT 'team'
CHECK (participation_type IN ('team', 'individual'));

COMMENT ON COLUMN public.events.participation_type IS 'team: toplu antrenman, katılım kaydı var; individual: isteğe bağlı bireysel antrenman, katılım kaydı yok';

-- Mevcut kayıtlar team kalır (default)

-- Şablonda da aynı alan: şablonla oluşturulan etkinlikte Bireysel/Ekip korunur
ALTER TABLE public.event_templates
ADD COLUMN IF NOT EXISTS participation_type TEXT DEFAULT 'team'
CHECK (participation_type IN ('team', 'individual'));

COMMENT ON COLUMN public.event_templates.participation_type IS 'team veya individual; şablondan etkinlik oluşturulurken kopyalanır';
