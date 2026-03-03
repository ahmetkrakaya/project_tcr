-- 065_chat_message_reports.sql
-- Amaç:
-- - Kullanıcıların etkinlik sohbetindeki mesajları "bildirmesi" için basit bir rapor tablosu eklemek
-- - Hangi mesajı, kim, ne zaman ve hangi gerekçeyle bildirmiş takip edilsin

-- 1) Rapor tablosu
CREATE TABLE IF NOT EXISTS public.chat_message_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id uuid NOT NULL,
    room_id uuid NOT NULL,
    reporter_id uuid NOT NULL,
    reason text,
    created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.chat_message_reports IS
'Kullanıcıların chat_messages tablosundaki mesajları uygunsuz olarak bildirmesi için rapor kayıtları.';

COMMENT ON COLUMN public.chat_message_reports.message_id IS
'Bildirilen chat mesajının ID''si (chat_messages.id).';

COMMENT ON COLUMN public.chat_message_reports.room_id IS
'Mesajın ait olduğu oda (chat_rooms.id).';

COMMENT ON COLUMN public.chat_message_reports.reporter_id IS
'Mesajı bildiren kullanıcının ID''si (users.id).';

COMMENT ON COLUMN public.chat_message_reports.reason IS
'Kullanıcının eklediği opsiyonel açıklama veya gerekçe.';

-- 2) Temel indexler
CREATE INDEX IF NOT EXISTS idx_chat_message_reports_message_id
    ON public.chat_message_reports (message_id);

CREATE INDEX IF NOT EXISTS idx_chat_message_reports_room_id
    ON public.chat_message_reports (room_id);

CREATE INDEX IF NOT EXISTS idx_chat_message_reports_reporter_id
    ON public.chat_message_reports (reporter_id);

CREATE INDEX IF NOT EXISTS idx_chat_message_reports_created_at
    ON public.chat_message_reports (created_at DESC);

-- 3) Basit RLS politikaları
ALTER TABLE public.chat_message_reports ENABLE ROW LEVEL SECURITY;

-- Sadece authenticated kullanıcılar insert edebilsin
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'chat_message_reports'
          AND policyname = 'chat_message_reports_insert_auth_only'
    ) THEN
        CREATE POLICY "chat_message_reports_insert_auth_only"
        ON public.chat_message_reports
        AS PERMISSIVE
        FOR INSERT
        TO authenticated
        WITH CHECK ( auth.uid() = reporter_id );
    END IF;
END
$$;

-- Okuma: sadece adminler/tcr backend kullanıyorsa, istenirse burada kısıtlanabilir.
-- Şimdilik yalnızca service role / backend tarafından okunacağını varsayıp
-- uygulama içinden SELECT yapılmadığı için ekstra READ policy eklemiyoruz.

