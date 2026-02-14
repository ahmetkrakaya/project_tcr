# send-push-on-notification

`public.notifications` tablosuna INSERT olduğunda ilgili kullanıcının FCM token'ına push bildirim gönderir.

## Kurulum

1. **Firebase Service Account**: Firebase Console → Project Settings → Service accounts → "Generate new private key". İndirilen JSON dosyasının tam içeriğini alın.

2. **Supabase secret**: Edge Function secret olarak service account JSON'u ekleyin (string olarak, repoya koymayın):
   ```bash
   supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
   ```
   veya Dashboard → Project Settings → Edge Functions → Secrets → `FIREBASE_SERVICE_ACCOUNT_JSON` (tüm JSON tek satırda).

3. **Deploy**:
   ```bash
   supabase functions deploy send-push-on-notification
   ```

4. **Database Webhook**: Supabase Dashboard → Database → Webhooks → Create hook:
   - Table: `public.notifications`
   - Events: Insert
   - Type: Supabase Edge Functions
   - Function: `send-push-on-notification`
   - HTTP Headers: "Add auth header with service key" + Content-Type: application/json

## Webhook payload

Supabase, INSERT sonrası şu formatta POST atar:
`{ "type": "INSERT", "table": "notifications", "record": { "id", "user_id", "title", "body", "type", "data", ... }, "schema": "public", "old_record": null }`

Fonksiyon `record.user_id` ile `users.fcm_token` alır, FCM v1 API ile bildirimi gönderir. `data` alanı (event_id, post_id vb.) client'ta deep link için kullanılır.

---

## Push gelmiyorsa kontrol listesi

### 1. FCM token veritabanında mı?
- Supabase Dashboard → **Table Editor** → **users**
- Bildirimi almasını beklediğin kullanıcının satırında **fcm_token** sütunu dolu mu bak.
- **Boşsa:** Uygulamayı o cihazda aç, giriş yap, birkaç saniye bekle (token yazılıyor). Sonra sayfayı yenile; hâlâ boşsa uygulama tarafında izin / Firebase bağlantısı kontrol et.

### 2. Bildirim satırı gerçekten ekleniyor mu?
- **Table Editor** → **notifications**
- Test için bir etkinlik oluştur / duyuru yayınla veya bu tabloya **manuel bir satır INSERT et** (user_id = test kullanıcının id’si).
- **notifications**’da yeni satır yoksa sorun tetikleyicilerde (migration 052); webhook değil.

### 3. Webhook Edge Function’ı tetikleniyor mu?
- Supabase Dashboard → **Edge Functions** → **send-push-on-notification** → **Logs**
- **notifications**’a INSERT yaptıktan sonra log’larda yeni istek görünmeli.
- **Hiç istek yoksa:** Database Webhook doğru tablo (public.notifications) ve event (Insert) ile tanımlı mı kontrol et.
- Log’da `[send-push] Webhook body keys:` görünüyor mu bak.

### 4. Log’da ne yazıyor?
- **"Skipped: not INSERT notifications"** → Gelen body’de type/table farklı; webhook payload’ını log’dan kontrol et.
- **"No fcm_token for user_id: ..."** → Bu kullanıcının `users.fcm_token` boş; adım 1’e dön.
- **"Skipped: user has disabled notification type: ..."** → Kullanıcı ayarlardan bu türü kapatmış; push doğru şekilde gönderilmiyor (uygulama içi bildirimde görünür).
- **"FCM sent successfully"** → Sunucu tarafı tamam, bildirim FCM’e gitti; sorun cihaz / FCM tarafında (aşağıdaki maddeler).
- **"Google OAuth failed"** veya **"FCM send failed"** → Service account JSON veya Firebase proje ayarları; hata mesajını oku.

### 5. Ayar kapalı olmasına rağmen push geliyorsa
- **Migration 053 uygulandı mı?** `insert_notifications` herkese satır yazmalı; push filtresi sadece bu Edge Function’da. `supabase migration list` ile kontrol et; 053 yoksa `supabase db push` veya `supabase migration up`.
- **Edge Function güncel mi?** Bu repodaki `send-push-on-notification/index.ts` deploy edildi mi? `supabase functions deploy send-push-on-notification` ile yeniden deploy et.
- **Log’da `push_enabled`:** Edge Function log’unda `[send-push] user_id: ... type: post_created has_settings: true/false push_enabled: true/false` satırına bak. `push_enabled: false` ve ardından "Skipped: user has disabled..." görünmeli; görünmüyorsa `user_notification_settings` tablosunda bu kullanıcı için `settings->post_created` değerini kontrol et (false olmalı).

### 6. Android emülatör
- Çoğu **emülatör** FCM almaz; **Google Play / Google APIs** imajı kullanılsa bile bazen gelmez.
- Kesin test için **gerçek Android cihaz** kullan. Cihazda uygulamayı aç, giriş yap, `users.fcm_token` dolu olsun, sonra bildirim tetikle.

### 7. iOS gerçek cihaz
- **APNs:** Firebase Console → Project Settings → Cloud Messaging → iOS app’te APNs key (veya certificate) yüklü mü?
- Uygulama **gerçek cihazda** derlenmiş ve çalışıyor mu? (Simulator push almaz.)
- Xcode’da **Signing & Capabilities** → **Push Notifications** ve **Background Modes → Remote notifications** açık mı?

### 8. Manuel test (FCM’e gidiyor mu?)
- Log’da "FCM sent successfully" görüyorsan: Firebase Console → **Cloud Messaging** → "Send your first message" ile aynı cihazın FCM token’ını (users tablosundan kopyala) **Test mesajı** olarak gönder. Cihazda bu test mesajı çıkıyorsa FCM çalışıyordur; çıkmıyorsa cihaz / APNs / emülatör kısıtı.
