-- 068_user_blocks.sql
-- Kullanıcı engelleme sistemi
-- Engelleyen kullanıcı, engellenen kullanıcının mesajlarını ve profil bilgilerini görmez

-- 1) user_blocks tablosu
CREATE TABLE IF NOT EXISTS public.user_blocks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    blocked_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_blocks_no_self_block CHECK (blocker_id <> blocked_id),
    CONSTRAINT user_blocks_unique UNIQUE (blocker_id, blocked_id)
);

COMMENT ON TABLE public.user_blocks IS
'Kullanıcıların diğer kullanıcıları engellemesi için kayıt tablosu.';

-- 2) İndeksler
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker_id
    ON public.user_blocks (blocker_id);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked_id
    ON public.user_blocks (blocked_id);

-- 3) RLS
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'user_blocks'
          AND policyname = 'user_blocks_select_own'
    ) THEN
        CREATE POLICY "user_blocks_select_own"
        ON public.user_blocks
        FOR SELECT TO authenticated
        USING (auth.uid() = blocker_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'user_blocks'
          AND policyname = 'user_blocks_insert_own'
    ) THEN
        CREATE POLICY "user_blocks_insert_own"
        ON public.user_blocks
        FOR INSERT TO authenticated
        WITH CHECK (auth.uid() = blocker_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'user_blocks'
          AND policyname = 'user_blocks_delete_own'
    ) THEN
        CREATE POLICY "user_blocks_delete_own"
        ON public.user_blocks
        FOR DELETE TO authenticated
        USING (auth.uid() = blocker_id);
    END IF;
END
$$;

-- 4) chat_message_reports tablosuna SELECT policy ekle
-- Kullanıcının kendi raporlarını görebilmesi için (raporlanan mesajları gizlemek amacıyla)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'chat_message_reports'
          AND policyname = 'chat_message_reports_select_own'
    ) THEN
        CREATE POLICY "chat_message_reports_select_own"
        ON public.chat_message_reports
        FOR SELECT TO authenticated
        USING (auth.uid() = reporter_id);
    END IF;
END
$$;
