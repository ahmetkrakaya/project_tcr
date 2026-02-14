-- TCR Migration 004: Chat System
-- Mesajlaşma ve iletişim modülü

-- Enum for chat room types
CREATE TYPE chat_room_type AS ENUM ('lobby', 'group', 'event', 'direct', 'anonymous_qa');

-- Enum for message types
CREATE TYPE message_type AS ENUM ('text', 'image', 'system', 'announcement');

-- Chat rooms
CREATE TABLE public.chat_rooms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    room_type chat_room_type NOT NULL DEFAULT 'group',
    event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
    training_group_id UUID REFERENCES public.training_groups(id) ON DELETE CASCADE,
    avatar_url TEXT,
    is_active BOOLEAN DEFAULT true,
    is_read_only BOOLEAN DEFAULT false, -- Etkinlik odaları için
    read_only_at TIMESTAMPTZ, -- Ne zaman salt okunur oldu
    created_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Chat room members
CREATE TABLE public.chat_room_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    is_muted BOOLEAN DEFAULT false,
    last_read_at TIMESTAMPTZ DEFAULT NOW(),
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(room_id, user_id)
);

-- Chat messages
CREATE TABLE public.chat_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    message_type message_type DEFAULT 'text',
    content TEXT NOT NULL,
    image_url TEXT,
    reply_to_id UUID REFERENCES public.chat_messages(id),
    is_edited BOOLEAN DEFAULT false,
    edited_at TIMESTAMPTZ,
    is_deleted BOOLEAN DEFAULT false,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Anonymous questions (Anonim Soru-Cevap)
CREATE TABLE public.anonymous_questions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    question TEXT NOT NULL,
    asked_by UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE, -- Gizli tutulacak
    is_published BOOLEAN DEFAULT false, -- "Haftanın Köşesi"nde yayınlandı mı
    published_at TIMESTAMPTZ,
    is_featured BOOLEAN DEFAULT false, -- Öne çıkan soru
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Question answers (Sadece Coach/Admin cevaplayabilir)
CREATE TABLE public.question_answers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    question_id UUID NOT NULL REFERENCES public.anonymous_questions(id) ON DELETE CASCADE,
    answered_by UUID NOT NULL REFERENCES public.users(id),
    answer TEXT NOT NULL,
    is_official BOOLEAN DEFAULT true, -- Resmi cevap mı
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Function to create event chat room automatically
CREATE OR REPLACE FUNCTION public.create_event_chat_room()
RETURNS TRIGGER AS $$
DECLARE
    room_uuid UUID;
BEGIN
    IF NEW.status = 'published' AND OLD.status = 'draft' THEN
        -- Etkinlik yayınlandığında chat odası oluştur
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
        VALUES (room_uuid, NEW.created_by);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_event_published
    AFTER UPDATE OF status ON public.events
    FOR EACH ROW EXECUTE FUNCTION public.create_event_chat_room();

-- Function to add user to event chat when they RSVP "going"
CREATE OR REPLACE FUNCTION public.add_to_event_chat()
RETURNS TRIGGER AS $$
DECLARE
    room_uuid UUID;
BEGIN
    IF NEW.status = 'going' THEN
        -- Etkinliğin chat odasını bul
        SELECT id INTO room_uuid
        FROM public.chat_rooms
        WHERE event_id = NEW.event_id AND room_type = 'event';
        
        IF room_uuid IS NOT NULL THEN
            -- Kullanıcıyı odaya ekle (varsa atla)
            INSERT INTO public.chat_room_members (room_id, user_id)
            VALUES (room_uuid, NEW.user_id)
            ON CONFLICT (room_id, user_id) DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_event_rsvp
    AFTER INSERT OR UPDATE OF status ON public.event_participants
    FOR EACH ROW EXECUTE FUNCTION public.add_to_event_chat();

-- Function to make event chat read-only after 24 hours
CREATE OR REPLACE FUNCTION public.make_event_chat_readonly()
RETURNS void AS $$
BEGIN
    UPDATE public.chat_rooms
    SET is_read_only = true, read_only_at = NOW()
    WHERE room_type = 'event'
      AND is_read_only = false
      AND event_id IN (
          SELECT id FROM public.events
          WHERE end_time < NOW() - INTERVAL '24 hours'
      );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Triggers for updated_at
CREATE TRIGGER update_chat_rooms_updated_at
    BEFORE UPDATE ON public.chat_rooms
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_question_answers_updated_at
    BEFORE UPDATE ON public.question_answers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Indexes
CREATE INDEX idx_chat_rooms_room_type ON public.chat_rooms(room_type);
CREATE INDEX idx_chat_rooms_event_id ON public.chat_rooms(event_id);
CREATE INDEX idx_chat_rooms_training_group_id ON public.chat_rooms(training_group_id);
CREATE INDEX idx_chat_room_members_room_id ON public.chat_room_members(room_id);
CREATE INDEX idx_chat_room_members_user_id ON public.chat_room_members(user_id);
CREATE INDEX idx_chat_messages_room_id ON public.chat_messages(room_id);
CREATE INDEX idx_chat_messages_sender_id ON public.chat_messages(sender_id);
CREATE INDEX idx_chat_messages_created_at ON public.chat_messages(created_at DESC);
CREATE INDEX idx_anonymous_questions_is_published ON public.anonymous_questions(is_published);
CREATE INDEX idx_question_answers_question_id ON public.question_answers(question_id);

-- Create default Lobby chat room
INSERT INTO public.chat_rooms (name, description, room_type, is_active)
VALUES ('TCR Lobby', 'Herkesin katılabildiği genel sohbet odası', 'lobby', true);
