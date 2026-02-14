-- TCR Migration 034: Fix Chat Room Members UPDATE Policy
-- upsert işlemlerinde UPDATE kısmının çalışması için UPDATE politikası ekleniyor
-- Sorun: Kullanıcı ilk katıldığında INSERT çalışıyor, sonraki denemelerde UPDATE yapılmaya çalışılıyor
-- ancak UPDATE için RLS politikası olmadığı için hata veriyordu.

-- Chat room members UPDATE - Mevcut üyeler kendi kayıtlarını güncelleyebilir
-- Bu politika, upsert işlemlerinde UPDATE kısmı için gereklidir
-- Örneğin: last_read_at güncellemesi veya mevcut üyeliğin yeniden eklenmesi
CREATE POLICY "Update own chat room membership"
    ON public.chat_room_members FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
