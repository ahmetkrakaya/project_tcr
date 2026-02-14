-- TCR Migration 007: Row Level Security (RLS) Policies
-- Güvenlik politikaları

-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ice_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ice_access_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.training_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pickup_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.training_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carpool_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carpool_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_room_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.anonymous_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.question_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_splits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_statistics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leaderboard_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listing_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listing_favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listing_messages ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- USERS POLICIES
-- ==========================================

-- Herkes kullanıcıları görebilir (temel bilgiler)
CREATE POLICY "Users are viewable by everyone"
    ON public.users FOR SELECT
    USING (true);

-- Kullanıcılar sadece kendi profillerini düzenleyebilir
CREATE POLICY "Users can update own profile"
    ON public.users FOR UPDATE
    USING (auth.uid() = id);

-- ==========================================
-- USER ROLES POLICIES
-- ==========================================

-- Herkes rolleri görebilir
CREATE POLICY "Roles are viewable by everyone"
    ON public.user_roles FOR SELECT
    USING (true);

-- Sadece super_admin rol atayabilir
CREATE POLICY "Only super_admin can manage roles"
    ON public.user_roles FOR ALL
    USING (public.has_role(auth.uid(), 'super_admin'));

-- ==========================================
-- ICE CARDS POLICIES (Hassas Veri)
-- ==========================================

-- Kullanıcı kendi ICE kartını görebilir
CREATE POLICY "Users can view own ICE card"
    ON public.ice_cards FOR SELECT
    USING (auth.uid() = user_id);

-- Admin/Coach ICE kartlarını görebilir (loglama gerekli)
CREATE POLICY "Admin/Coach can view ICE cards"
    ON public.ice_cards FOR SELECT
    USING (public.is_admin_or_coach());

-- Kullanıcılar kendi ICE kartlarını yönetebilir
CREATE POLICY "Users can manage own ICE card"
    ON public.ice_cards FOR ALL
    USING (auth.uid() = user_id);

-- ICE erişim logları sadece admin görebilir
CREATE POLICY "Only admin can view ICE logs"
    ON public.ice_access_logs FOR SELECT
    USING (public.has_role(auth.uid(), 'super_admin'));

-- ICE log ekleme (admin/coach)
CREATE POLICY "Admin/Coach can log ICE access"
    ON public.ice_access_logs FOR INSERT
    WITH CHECK (public.is_admin_or_coach());

-- ==========================================
-- TRAINING GROUPS POLICIES
-- ==========================================

CREATE POLICY "Training groups are viewable by everyone"
    ON public.training_groups FOR SELECT
    USING (true);

CREATE POLICY "Admin/Coach can manage training groups"
    ON public.training_groups FOR ALL
    USING (public.is_admin_or_coach());

-- ==========================================
-- GROUP MEMBERS POLICIES
-- ==========================================

CREATE POLICY "Group members are viewable by everyone"
    ON public.group_members FOR SELECT
    USING (true);

CREATE POLICY "Users can join/leave groups"
    ON public.group_members FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can leave groups"
    ON public.group_members FOR DELETE
    USING (auth.uid() = user_id OR public.is_admin_or_coach());

-- ==========================================
-- ROUTES POLICIES
-- ==========================================

CREATE POLICY "Routes are viewable by everyone"
    ON public.routes FOR SELECT
    USING (true);

CREATE POLICY "Admin/Coach can manage routes"
    ON public.routes FOR ALL
    USING (public.is_admin_or_coach());

-- ==========================================
-- EVENTS POLICIES
-- ==========================================

-- Yayınlanmış etkinlikler herkes tarafından görülebilir
CREATE POLICY "Published events are viewable by everyone"
    ON public.events FOR SELECT
    USING (status = 'published' OR created_by = auth.uid() OR public.is_admin_or_coach());

CREATE POLICY "Admin/Coach can manage events"
    ON public.events FOR ALL
    USING (public.is_admin_or_coach());

-- ==========================================
-- EVENT PARTICIPANTS POLICIES
-- ==========================================

CREATE POLICY "Event participants are viewable by everyone"
    ON public.event_participants FOR SELECT
    USING (true);

CREATE POLICY "Users can RSVP to events"
    ON public.event_participants FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own RSVP"
    ON public.event_participants FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can cancel own RSVP"
    ON public.event_participants FOR DELETE
    USING (auth.uid() = user_id);

-- ==========================================
-- PICKUP LOCATIONS POLICIES
-- ==========================================

CREATE POLICY "Pickup locations are viewable by everyone"
    ON public.pickup_locations FOR SELECT
    USING (true);

CREATE POLICY "Admin can manage pickup locations"
    ON public.pickup_locations FOR ALL
    USING (public.has_role(auth.uid(), 'super_admin'));

-- ==========================================
-- TRAINING SCHEDULES POLICIES
-- ==========================================

CREATE POLICY "Training schedules are viewable by everyone"
    ON public.training_schedules FOR SELECT
    USING (true);

CREATE POLICY "Admin/Coach can manage schedules"
    ON public.training_schedules FOR ALL
    USING (public.is_admin_or_coach());

-- ==========================================
-- CARPOOL OFFERS POLICIES
-- ==========================================

CREATE POLICY "Carpool offers are viewable by everyone"
    ON public.carpool_offers FOR SELECT
    USING (true);

CREATE POLICY "Users can create carpool offers"
    ON public.carpool_offers FOR INSERT
    WITH CHECK (auth.uid() = driver_id);

CREATE POLICY "Drivers can manage own offers"
    ON public.carpool_offers FOR UPDATE
    USING (auth.uid() = driver_id);

CREATE POLICY "Drivers can delete own offers"
    ON public.carpool_offers FOR DELETE
    USING (auth.uid() = driver_id);

-- ==========================================
-- CARPOOL REQUESTS POLICIES
-- ==========================================

CREATE POLICY "Carpool requests viewable by driver and passenger"
    ON public.carpool_requests FOR SELECT
    USING (
        auth.uid() = passenger_id 
        OR auth.uid() IN (SELECT driver_id FROM public.carpool_offers WHERE id = offer_id)
    );

CREATE POLICY "Users can create carpool requests"
    ON public.carpool_requests FOR INSERT
    WITH CHECK (auth.uid() = passenger_id);

CREATE POLICY "Driver can update request status"
    ON public.carpool_requests FOR UPDATE
    USING (
        auth.uid() IN (SELECT driver_id FROM public.carpool_offers WHERE id = offer_id)
        OR (auth.uid() = passenger_id AND status = 'pending') -- Yolcu iptal edebilir
    );

-- ==========================================
-- CHAT POLICIES
-- ==========================================

-- Lobby herkes görebilir, diğer odalar sadece üyeler
CREATE POLICY "Chat rooms viewable by members or lobby"
    ON public.chat_rooms FOR SELECT
    USING (
        room_type = 'lobby'
        OR id IN (SELECT room_id FROM public.chat_room_members WHERE user_id = auth.uid())
        OR public.is_admin_or_coach()
    );

CREATE POLICY "Admin/Coach can manage chat rooms"
    ON public.chat_rooms FOR ALL
    USING (public.is_admin_or_coach());

CREATE POLICY "Chat room members viewable by room members"
    ON public.chat_room_members FOR SELECT
    USING (
        room_id IN (SELECT room_id FROM public.chat_room_members WHERE user_id = auth.uid())
        OR public.is_admin_or_coach()
    );

CREATE POLICY "Users can join lobby"
    ON public.chat_room_members FOR INSERT
    WITH CHECK (
        auth.uid() = user_id
        AND room_id IN (SELECT id FROM public.chat_rooms WHERE room_type = 'lobby')
    );

-- Mesajlar sadece oda üyeleri tarafından görülebilir
CREATE POLICY "Messages viewable by room members"
    ON public.chat_messages FOR SELECT
    USING (
        room_id IN (SELECT room_id FROM public.chat_room_members WHERE user_id = auth.uid())
    );

-- Salt okunur olmayan odalara mesaj gönderilebilir
CREATE POLICY "Members can send messages"
    ON public.chat_messages FOR INSERT
    WITH CHECK (
        auth.uid() = sender_id
        AND room_id IN (
            SELECT cr.id FROM public.chat_rooms cr
            JOIN public.chat_room_members crm ON crm.room_id = cr.id
            WHERE crm.user_id = auth.uid() AND cr.is_read_only = false
        )
    );

-- ==========================================
-- ANONYMOUS QUESTIONS POLICIES
-- ==========================================

-- Yayınlanmış sorular herkes görebilir
CREATE POLICY "Published questions are viewable"
    ON public.anonymous_questions FOR SELECT
    USING (is_published = true OR asked_by = auth.uid() OR public.is_admin_or_coach());

CREATE POLICY "Users can ask questions"
    ON public.anonymous_questions FOR INSERT
    WITH CHECK (auth.uid() = asked_by);

CREATE POLICY "Admin/Coach can manage questions"
    ON public.anonymous_questions FOR UPDATE
    USING (public.is_admin_or_coach());

-- Cevaplar herkes görebilir
CREATE POLICY "Answers are viewable by everyone"
    ON public.question_answers FOR SELECT
    USING (true);

-- Sadece admin/coach cevaplayabilir
CREATE POLICY "Only Admin/Coach can answer"
    ON public.question_answers FOR INSERT
    WITH CHECK (public.is_admin_or_coach());

-- ==========================================
-- ACTIVITIES POLICIES
-- ==========================================

-- Public aktiviteler herkes görebilir
CREATE POLICY "Public activities are viewable"
    ON public.activities FOR SELECT
    USING (is_public = true OR user_id = auth.uid());

CREATE POLICY "Users can manage own activities"
    ON public.activities FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Activity splits viewable with activity"
    ON public.activity_splits FOR SELECT
    USING (
        activity_id IN (
            SELECT id FROM public.activities 
            WHERE is_public = true OR user_id = auth.uid()
        )
    );

CREATE POLICY "Users can manage own activity splits"
    ON public.activity_splits FOR ALL
    USING (
        activity_id IN (SELECT id FROM public.activities WHERE user_id = auth.uid())
    );

-- İstatistikler herkes görebilir
CREATE POLICY "User statistics are viewable"
    ON public.user_statistics FOR SELECT
    USING (true);

CREATE POLICY "Users can update own statistics"
    ON public.user_statistics FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Leaderboard is viewable by everyone"
    ON public.leaderboard_entries FOR SELECT
    USING (true);

-- ==========================================
-- MARKETPLACE POLICIES
-- ==========================================

-- Aktif ilanlar herkes görebilir
CREATE POLICY "Active listings are viewable"
    ON public.marketplace_listings FOR SELECT
    USING (status = 'active' OR seller_id = auth.uid());

CREATE POLICY "Users can create listings"
    ON public.marketplace_listings FOR INSERT
    WITH CHECK (auth.uid() = seller_id);

CREATE POLICY "Sellers can manage own listings"
    ON public.marketplace_listings FOR UPDATE
    USING (auth.uid() = seller_id);

CREATE POLICY "Sellers can delete own listings"
    ON public.marketplace_listings FOR DELETE
    USING (auth.uid() = seller_id);

-- İlan görselleri
CREATE POLICY "Listing images viewable with listing"
    ON public.listing_images FOR SELECT
    USING (
        listing_id IN (
            SELECT id FROM public.marketplace_listings 
            WHERE status = 'active' OR seller_id = auth.uid()
        )
    );

CREATE POLICY "Sellers can manage listing images"
    ON public.listing_images FOR ALL
    USING (
        listing_id IN (SELECT id FROM public.marketplace_listings WHERE seller_id = auth.uid())
    );

-- Favoriler
CREATE POLICY "Users can view own favorites"
    ON public.listing_favorites FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own favorites"
    ON public.listing_favorites FOR ALL
    USING (auth.uid() = user_id);

-- Mesajlar
CREATE POLICY "Listing messages viewable by sender/receiver"
    ON public.listing_messages FOR SELECT
    USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

CREATE POLICY "Users can send listing messages"
    ON public.listing_messages FOR INSERT
    WITH CHECK (auth.uid() = sender_id);
