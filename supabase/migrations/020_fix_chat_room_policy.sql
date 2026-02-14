-- TCR Migration 020: Fix Chat Room RLS Policy
-- Event katılımcılarının chat odasını görebilmesi için policy güncelleme
-- NOT: Recursive subquery sorunu düzeltildi

-- ==========================================
-- CHAT_ROOMS POLICIES
-- ==========================================

-- Mevcut policy'leri kaldır
DROP POLICY IF EXISTS "Chat rooms viewable by members or lobby" ON public.chat_rooms;
DROP POLICY IF EXISTS "Chat rooms viewable by members or event participants" ON public.chat_rooms;
DROP POLICY IF EXISTS "Admin/Coach can manage chat rooms" ON public.chat_rooms;
DROP POLICY IF EXISTS "Event participants can create event chat room" ON public.chat_rooms;

-- Chat rooms SELECT policy - Admin ve event katılımcıları
CREATE POLICY "Anyone can view chat rooms they have access to"
    ON public.chat_rooms FOR SELECT
    USING (
        room_type = 'lobby'
        OR public.is_admin_or_coach()
        OR (
            room_type = 'event' 
            AND event_id IN (
                SELECT event_id FROM public.event_participants 
                WHERE user_id = auth.uid() AND status = 'going'
            )
        )
    );

-- Chat rooms INSERT policy
CREATE POLICY "Event participants can create event chat"
    ON public.chat_rooms FOR INSERT
    WITH CHECK (
        public.is_admin_or_coach()
        OR (
            room_type = 'event'
            AND event_id IN (
                SELECT event_id FROM public.event_participants 
                WHERE user_id = auth.uid() AND status = 'going'
            )
        )
    );

-- Chat rooms UPDATE/DELETE - sadece admin
CREATE POLICY "Admin can manage chat rooms"
    ON public.chat_rooms FOR ALL
    USING (public.is_admin_or_coach());

-- ==========================================
-- CHAT_ROOM_MEMBERS POLICIES
-- ==========================================

DROP POLICY IF EXISTS "Chat room members viewable by room members" ON public.chat_room_members;
DROP POLICY IF EXISTS "Chat room members viewable by room members or event participants" ON public.chat_room_members;
DROP POLICY IF EXISTS "Users can join lobby" ON public.chat_room_members;
DROP POLICY IF EXISTS "Event participants can join event chat" ON public.chat_room_members;

-- Chat room members SELECT - Event katılımcıları oda üyelerini görebilir
CREATE POLICY "View chat room members"
    ON public.chat_room_members FOR SELECT
    USING (
        public.is_admin_or_coach()
        OR user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.chat_rooms cr
            WHERE cr.id = room_id
            AND cr.room_type = 'lobby'
        )
        OR EXISTS (
            SELECT 1 FROM public.chat_rooms cr
            WHERE cr.id = room_id
            AND cr.room_type = 'event'
            AND cr.event_id IN (
                SELECT event_id FROM public.event_participants 
                WHERE user_id = auth.uid() AND status = 'going'
            )
        )
    );

-- Chat room members INSERT - Kullanıcı kendini ekleyebilir
CREATE POLICY "Join chat room"
    ON public.chat_room_members FOR INSERT
    WITH CHECK (
        auth.uid() = user_id
        AND (
            -- Lobby'ye herkes katılabilir
            EXISTS (
                SELECT 1 FROM public.chat_rooms cr
                WHERE cr.id = room_id AND cr.room_type = 'lobby'
            )
            OR
            -- Event chat'e event katılımcıları katılabilir
            EXISTS (
                SELECT 1 FROM public.chat_rooms cr
                WHERE cr.id = room_id
                AND cr.room_type = 'event'
                AND cr.event_id IN (
                    SELECT event_id FROM public.event_participants 
                    WHERE user_id = auth.uid() AND status = 'going'
                )
            )
            OR
            -- Admin her yere ekleyebilir
            public.is_admin_or_coach()
        )
    );

-- Chat room members UPDATE - Mevcut üyeler kendi kayıtlarını güncelleyebilir
-- Bu politika, upsert işlemlerinde UPDATE kısmı için gereklidir
CREATE POLICY "Update own chat room membership"
    ON public.chat_room_members FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ==========================================
-- CHAT_MESSAGES POLICIES
-- ==========================================

DROP POLICY IF EXISTS "Messages viewable by room members" ON public.chat_messages;
DROP POLICY IF EXISTS "Messages viewable by room members or event participants" ON public.chat_messages;
DROP POLICY IF EXISTS "Members can send messages" ON public.chat_messages;
DROP POLICY IF EXISTS "Members or event participants can send messages" ON public.chat_messages;

-- Mesajları görüntüleme - Event katılımcıları görebilir
CREATE POLICY "View chat messages"
    ON public.chat_messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.chat_rooms cr
            WHERE cr.id = room_id
            AND (
                cr.room_type = 'lobby'
                OR public.is_admin_or_coach()
                OR (
                    cr.room_type = 'event'
                    AND cr.event_id IN (
                        SELECT event_id FROM public.event_participants 
                        WHERE user_id = auth.uid() AND status = 'going'
                    )
                )
            )
        )
    );

-- Mesaj gönderme - Event katılımcıları gönderebilir (read-only değilse)
CREATE POLICY "Send chat messages"
    ON public.chat_messages FOR INSERT
    WITH CHECK (
        auth.uid() = sender_id
        AND EXISTS (
            SELECT 1 FROM public.chat_rooms cr
            WHERE cr.id = room_id
            AND cr.is_read_only = false
            AND (
                cr.room_type = 'lobby'
                OR public.is_admin_or_coach()
                OR (
                    cr.room_type = 'event'
                    AND cr.event_id IN (
                        SELECT event_id FROM public.event_participants 
                        WHERE user_id = auth.uid() AND status = 'going'
                    )
                )
            )
        )
    );

-- Mesaj güncelleme - Sadece kendi mesajını
CREATE POLICY "Update own messages"
    ON public.chat_messages FOR UPDATE
    USING (sender_id = auth.uid())
    WITH CHECK (sender_id = auth.uid());

-- Mesaj silme (soft delete) - Sadece kendi mesajını veya admin
CREATE POLICY "Delete own messages"
    ON public.chat_messages FOR DELETE
    USING (sender_id = auth.uid() OR public.is_admin_or_coach());

-- ==========================================
-- EVENT CHAT ROOM AUTO-CREATE TRIGGER
-- ==========================================

-- Mevcut trigger'ı kaldır
DROP TRIGGER IF EXISTS on_event_published ON public.events;
DROP FUNCTION IF EXISTS public.create_event_chat_room();

-- Yeni fonksiyon: Hem INSERT hem UPDATE'de çalışır
CREATE OR REPLACE FUNCTION public.create_event_chat_room()
RETURNS TRIGGER AS $$
DECLARE
    room_uuid UUID;
    existing_room UUID;
BEGIN
    -- Sadece published event'ler için chat odası oluştur
    IF NEW.status = 'published' THEN
        -- Chat odası zaten var mı kontrol et
        SELECT id INTO existing_room
        FROM public.chat_rooms
        WHERE event_id = NEW.id AND room_type = 'event';
        
        -- Yoksa oluştur
        IF existing_room IS NULL THEN
            INSERT INTO public.chat_rooms (name, room_type, event_id, created_by)
            VALUES (
                NEW.title || ' - Etkinlik Sohbeti',
                'event',
                NEW.id,
                NEW.created_by
            )
            RETURNING id INTO room_uuid;
            
            -- Etkinliği oluşturanı odaya ekle
            INSERT INTO public.chat_room_members (room_id, user_id)
            VALUES (room_uuid, NEW.created_by)
            ON CONFLICT (room_id, user_id) DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- INSERT trigger - Etkinlik oluşturulduğunda
CREATE TRIGGER on_event_insert_create_chat
    AFTER INSERT ON public.events
    FOR EACH ROW EXECUTE FUNCTION public.create_event_chat_room();

-- UPDATE trigger - Draft'tan published'a geçtiğinde
CREATE TRIGGER on_event_update_create_chat
    AFTER UPDATE OF status ON public.events
    FOR EACH ROW 
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION public.create_event_chat_room();
