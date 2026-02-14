-- TCR Migration 008: Storage Buckets
-- Supabase Storage bucket ve politikaları

-- NOT: Bu SQL dosyası referans amaçlıdır.
-- Storage bucket'ları Supabase Dashboard > Storage bölümünden oluşturulmalıdır.
-- Aşağıdaki SQL sadece storage politikalarını tanımlar.

-- ==========================================
-- BUCKET CONFIGURATIONS (Dashboard'da oluştur)
-- ==========================================
-- 1. avatars - Kullanıcı profil fotoğrafları (public)
-- 2. event-photos - Etkinlik fotoğrafları (public)
-- 3. routes - GPX dosyaları (public)
-- 4. listing-images - Pazar yeri görselleri (public)
-- 5. chat-images - Chat görselleri (authenticated)

-- ==========================================
-- AVATARS BUCKET POLICIES
-- ==========================================

-- Herkes avatarları görebilir
CREATE POLICY "Avatar images are publicly accessible"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'avatars');

-- Kullanıcılar kendi avatarını yükleyebilir
CREATE POLICY "Users can upload own avatar"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'avatars' 
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

-- Kullanıcılar kendi avatarını güncelleyebilir
CREATE POLICY "Users can update own avatar"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'avatars' 
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

-- Kullanıcılar kendi avatarını silebilir
CREATE POLICY "Users can delete own avatar"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'avatars' 
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

-- ==========================================
-- EVENT PHOTOS BUCKET POLICIES
-- ==========================================

-- Herkes etkinlik fotoğraflarını görebilir
CREATE POLICY "Event photos are publicly accessible"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'event-photos');

-- Etkinlik katılımcıları fotoğraf yükleyebilir
CREATE POLICY "Event participants can upload photos"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'event-photos'
        AND auth.role() = 'authenticated'
        -- Event ID klasör adından alınır, katılımcı kontrolü uygulama seviyesinde
    );

-- Admin/Coach tüm fotoğrafları yönetebilir
CREATE POLICY "Admin can manage all event photos"
    ON storage.objects FOR ALL
    USING (
        bucket_id = 'event-photos'
        AND public.is_admin_or_coach()
    );

-- ==========================================
-- ROUTES BUCKET POLICIES
-- ==========================================

-- Herkes rota dosyalarını görebilir
CREATE POLICY "Route files are publicly accessible"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'routes');

-- Admin/Coach rota dosyası yükleyebilir
CREATE POLICY "Admin/Coach can upload routes"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'routes'
        AND public.is_admin_or_coach()
    );

-- Admin/Coach rota dosyalarını yönetebilir
CREATE POLICY "Admin/Coach can manage routes"
    ON storage.objects FOR ALL
    USING (
        bucket_id = 'routes'
        AND public.is_admin_or_coach()
    );

-- ==========================================
-- LISTING IMAGES BUCKET POLICIES
-- ==========================================

-- Herkes ilan görsellerini görebilir
CREATE POLICY "Listing images are publicly accessible"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'listing-images');

-- Authenticated kullanıcılar görsel yükleyebilir
CREATE POLICY "Users can upload listing images"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'listing-images'
        AND auth.role() = 'authenticated'
    );

-- Kullanıcılar kendi klasörlerindeki görselleri yönetebilir
CREATE POLICY "Users can manage own listing images"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'listing-images'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Users can delete own listing images"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'listing-images'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

-- ==========================================
-- CHAT IMAGES BUCKET POLICIES
-- ==========================================

-- Authenticated kullanıcılar chat görsellerini görebilir
CREATE POLICY "Chat images accessible to authenticated users"
    ON storage.objects FOR SELECT
    USING (
        bucket_id = 'chat-images'
        AND auth.role() = 'authenticated'
    );

-- Authenticated kullanıcılar görsel yükleyebilir
CREATE POLICY "Users can upload chat images"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'chat-images'
        AND auth.role() = 'authenticated'
    );
