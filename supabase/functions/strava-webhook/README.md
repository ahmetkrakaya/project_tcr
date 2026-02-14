# Strava Webhook Handler

Bu Edge Function, Strava'dan gelen webhook'ları işler ve aktiviteleri otomatik olarak Supabase veritabanına senkronize eder.

## Kurulum

### 1. Environment Variables Ayarla

Supabase Dashboard'da **Project Settings > Edge Functions > Secrets** bölümüne gidin ve şu değişkenleri ekleyin:

- `STRAVA_CLIENT_ID`: Strava uygulamanızın Client ID'si
- `STRAVA_CLIENT_SECRET`: Strava uygulamanızın Client Secret'ı
- `STRAVA_WEBHOOK_VERIFY_TOKEN`: Webhook verification için kullanılacak token (rastgele bir string, örn: `tcr_webhook_verify_token_2024`)

### 2. Edge Function'ı Deploy Et

```bash
# Supabase CLI ile deploy
supabase functions deploy strava-webhook

# Veya Supabase Dashboard'dan:
# Project > Edge Functions > New Function > Upload from file
```

### 3. Webhook URL'ini Al

Deploy sonrası webhook URL'iniz şu formatta olacak:
```
https://[PROJECT_REF].supabase.co/functions/v1/strava-webhook
```

### 4. Strava Webhook Subscription Oluştur

#### Strava API Dashboard'dan:

1. [Strava API Dashboard](https://www.strava.com/settings/api) sayfasına gidin
2. **Webhooks** bölümüne gidin
3. **Create Subscription** butonuna tıklayın
4. Şu bilgileri girin:
   - **Callback URL**: `https://[PROJECT_REF].supabase.co/functions/v1/strava-webhook`
   - **Verify Token**: `tcr_webhook_verify_token_2024` (veya kendi token'ınız)
   - **Subscribe to**: `activity:create,activity:update` (veya sadece `activity:create`)

5. **Create** butonuna tıklayın

#### veya Strava API ile:

```bash
curl -X POST https://www.strava.com/api/v3/push_subscriptions \
  -d client_id=YOUR_CLIENT_ID \
  -d client_secret=YOUR_CLIENT_SECRET \
  -d callback_url=https://[PROJECT_REF].supabase.co/functions/v1/strava-webhook \
  -d verify_token=tcr_webhook_verify_token_2024
```

### 5. Webhook Subscription'ı Test Et

```bash
# Subscription'ı kontrol et
curl -X GET "https://www.strava.com/api/v3/push_subscriptions?client_id=YOUR_CLIENT_ID&client_secret=YOUR_CLIENT_SECRET"
```

## Nasıl Çalışır?

1. Kullanıcı Strava'da yeni bir aktivite oluşturur veya günceller
2. Strava webhook gönderir → `https://[PROJECT_REF].supabase.co/functions/v1/strava-webhook`
3. Edge Function webhook'u alır ve doğrular
4. Athlete ID'ye göre kullanıcıyı bulur (`user_integrations` tablosundan)
5. Aktiviteyi Strava API'den çeker
6. Aktiviteyi Supabase `activities` tablosuna kaydeder
7. `update_user_statistics` trigger otomatik olarak istatistikleri günceller

## Test

Yeni bir aktivite oluşturup Strava'da kaydedin. Birkaç saniye içinde aktivite uygulamanızda görünmelidir.

## Sorun Giderme

- **Webhook gelmiyor**: Strava API Dashboard'da webhook subscription'ı kontrol edin
- **Aktivite kaydedilmiyor**: Edge Function logs'ları kontrol edin (Supabase Dashboard > Edge Functions > strava-webhook > Logs)
- **Token hatası**: `STRAVA_CLIENT_ID` ve `STRAVA_CLIENT_SECRET` environment variable'larını kontrol edin
