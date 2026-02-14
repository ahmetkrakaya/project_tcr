# Webhook Sorun Giderme Rehberi

## Sorun: Aktivite Event'leri Gelmiyor

Loglarda sadece verification (GET) request'leri görünüyor, ama aktivite event'leri (POST) gelmiyor.

## Kontrol Listesi

### 1. Webhook Subscription Kontrolü

```bash
curl -X GET "https://www.strava.com/api/v3/push_subscriptions?client_id=198092&client_secret=0822fb63353132c51caaaf9051301427a01f98d3"
```

**Beklenen yanıt:**
```json
[{
  "id": 327261,
  "callback_url": "https://lnodjfivycpyoytmwpcn.supabase.co/functions/v1/strava-webhook",
  "created_at": "2026-01-26T12:02:56+00:00"
}]
```

### 2. Strava'da Aktivite Oluşturma

- **Önemli:** Strava'da aktivite oluşturduktan sonra **mutlaka kaydedin** (Save butonuna tıklayın)
- Sadece kaydedilmemiş aktiviteler webhook göndermez
- Mevcut aktiviteleri düzenleyip kaydetmek de webhook tetikler

### 3. Edge Function Logs Kontrolü

Supabase Dashboard > Edge Functions > strava-webhook > Logs

**Aranacak log mesajları:**
- `[Webhook] Event received:` - POST request geldiğinde
- `[Webhook] Processing activity` - Aktivite işlenirken
- `[Webhook] Activity X synced successfully` - Başarılı kayıt

**Eğer bu loglar yoksa:**
- Strava webhook göndermiyor olabilir
- POST request Edge Function'a ulaşmıyor olabilir

### 4. Edge Function POST Request Testi

Manuel olarak POST request göndererek test edin:

```bash
curl -X POST https://lnodjfivycpyoytmwpcn.supabase.co/functions/v1/strava-webhook \
  -H "Content-Type: application/json" \
  -d '{
    "object_type": "activity",
    "object_id": 123456789,
    "aspect_type": "create",
    "owner_id": YOUR_ATHLETE_ID,
    "subscription_id": 327261,
    "event_time": 1706284800
  }'
```

**Not:** `YOUR_ATHLETE_ID` yerine Strava athlete ID'nizi yazın (user_integrations tablosundan `provider_user_id`)

### 5. Strava Webhook Subscription Yeniden Oluşturma

Eğer hala çalışmıyorsa, subscription'ı silip yeniden oluşturun:

```bash
# Mevcut subscription'ı sil
curl -X DELETE "https://www.strava.com/api/v3/push_subscriptions/327261?client_id=198092&client_secret=0822fb63353132c51caaaf9051301427a01f98d3"

# Yeni subscription oluştur
curl -X POST https://www.strava.com/api/v3/push_subscriptions \
  -d "client_id=198092" \
  -d "client_secret=0822fb63353132c51caaaf9051301427a01f98d3" \
  -d "callback_url=https://lnodjfivycpyoytmwpcn.supabase.co/functions/v1/strava-webhook" \
  -d "verify_token=tcr_webhook_verify_token_2026"
```

### 6. Strava API Rate Limit Kontrolü

Strava API rate limit'lerini kontrol edin:
- 100 requests / 15 dakika
- 1000 requests / gün

Webhook'lar bu limit'e dahil değildir, ama genel API kullanımınız limit'e ulaştıysa sorun olabilir.

### 7. Veritabanı Kontrolü

Kullanıcının `user_integrations` tablosunda Strava entegrasyonu olduğundan emin olun:

```sql
SELECT * FROM user_integrations 
WHERE provider = 'strava' 
AND provider_user_id = 'YOUR_ATHLETE_ID';
```

**Kontrol edilecekler:**
- `provider_user_id` (athlete_id) doğru mu?
- `access_token` ve `refresh_token` var mı?
- `token_expires_at` geçerli mi?

### 8. Edge Function Authorization Sorunu

POST request'ler için de authorization sorunu olabilir. Edge Function'ın public olduğundan emin olun:

1. Supabase Dashboard > Edge Functions > strava-webhook > Details
2. "Require Authorization" kapalı olmalı
3. Veya function public olmalı

## Yaygın Sorunlar ve Çözümleri

### Sorun: "No integration found for athlete"

**Çözüm:**
- `user_integrations` tablosunda `provider_user_id` (athlete_id) doğru eşleşiyor mu kontrol edin
- Strava'da bağlantıyı yeniden yapın (uygulamadan)

### Sorun: "Token expired"

**Çözüm:**
- Edge Function otomatik olarak token yenilemeye çalışır
- Eğer `refresh_token` yoksa, kullanıcıdan Strava bağlantısını yeniden yapmasını isteyin

### Sorun: "Failed to fetch activity"

**Çözüm:**
- Strava API rate limit kontrolü yapın
- Token'ın geçerli olduğundan emin olun
- Aktivite ID'sinin doğru olduğunu kontrol edin

## Test Senaryosu

1. **Strava'da yeni aktivite oluşturun:**
   - Strava uygulaması veya web sitesi
   - "Create Activity" > Aktivite detaylarını girin > **Save**

2. **30 saniye bekleyin** (webhook gecikmesi olabilir)

3. **Logs kontrol edin:**
   - Supabase Dashboard > Edge Functions > strava-webhook > Logs
   - `[Webhook] Event received` mesajını arayın

4. **Veritabanı kontrol edin:**
   - `activities` tablosunda yeni aktivite var mı?
   - `source = 'strava'` ve `external_id` doğru mu?

## Hala Çalışmıyorsa

1. Edge Function logs'larını detaylı kontrol edin
2. Strava webhook subscription'ı yeniden oluşturun
3. Kullanıcının Strava entegrasyonunu yeniden bağlayın
4. Test aktivitesi oluşturup bekleyin (bazen 1-2 dakika sürebilir)
