# Hızlı Edge Function Deploy Rehberi

## Sorun: "GET to callback URL does not return 200" Hatası

Bu hata, Edge Function'ın henüz deploy edilmediği veya erişilemediği anlamına gelir.

## Çözüm: Edge Function'ı Deploy Edin

### Yöntem 1: Supabase Dashboard (En Kolay)

1. **Supabase Dashboard'a gidin**: https://supabase.com/dashboard
2. Projenizi seçin (`lnodjfivycpyoytmwpcn`)
3. Sol menüden **Edge Functions** sekmesine tıklayın
4. **Create a new function** butonuna tıklayın
5. **Function name**: `strava-webhook` yazın
6. **Function code** alanına `supabase/functions/strava-webhook/index.ts` dosyasının içeriğini yapıştırın
   - Dosyayı açın ve tüm içeriği kopyalayın
   - Supabase Dashboard'a yapıştırın
7. **Deploy** butonuna tıklayın
8. Deploy tamamlanana kadar bekleyin (birkaç saniye sürer)

### Yöntem 2: Supabase CLI

curl "https://lnodjfivycpyoytmwpcn.supabase.co/functions/v1/strava-webhook?hub.mode=subscribe&hub.verify_token=tcr_webhook_verify_token_2026&hub.challenge=test123"

```bash
# Proje klasörüne gidin
cd /Users/deskiyazilim/development/project_tcr

# Supabase'e login olun (ilk kez ise)
supabase login

# Edge Function'ı deploy edin
supabase functions deploy strava-webhook
```

## ⚠️ ÖNEMLİ: Edge Function'ı Public Yapın

Supabase Edge Functions varsayılan olarak authorization header bekler. Strava webhook verification için GET request'lerde authorization header yoktur. Bu yüzden Edge Function'ı **public** yapmanız gerekiyor:

1. Supabase Dashboard > **Edge Functions** > **strava-webhook** sayfasına gidin
2. **Details** sekmesine tıklayın
3. **Require Authorization** seçeneğini **KAPATIN** (varsa)
4. Veya **Settings** sekmesinde **Public** seçeneğini **AÇIN**

**Not:** Eğer bu seçenekler yoksa, Supabase'in yeni versiyonunda Edge Functions otomatik olarak public olabilir. Test ederek kontrol edin.

## Deploy Sonrası Kontrol

1. Supabase Dashboard > **Edge Functions** > **strava-webhook** sayfasına gidin
2. **Function URL** kısmında URL'inizi görün:
   ```
   https://lnodjfivycpyoytmwpcn.supabase.co/functions/v1/strava-webhook
   ```
3. Bu URL'yi tarayıcıda açın veya curl ile test edin:

```bash
curl "https://lnodjfivycpyoytmwpcn.supabase.co/functions/v1/strava-webhook?hub.mode=subscribe&hub.verify_token=tcr_webhook_verify_token_2026&hub.challenge=test123"
```

**Beklenen yanıt:**
```json
{"hub.challenge":"test123"}
```

**Eğer hala 401 hatası alıyorsanız:**
- Edge Function'ı yeniden deploy edin (güncellenmiş kod ile)
- Supabase Dashboard'da function ayarlarını kontrol edin
- Function'ın public olduğundan emin olun

## Secrets Kontrolü

Edge Function'ın çalışması için secrets'ların ayarlanmış olması gerekir:

1. Supabase Dashboard > **Project Settings** > **Edge Functions** > **Secrets**
2. Şu 3 secret'ın olduğundan emin olun:
   - `STRAVA_CLIENT_ID` = `198092`
   - `STRAVA_CLIENT_SECRET` = `0822fb63353132c51caaaf9051301427a01f98d3`
   - `STRAVA_WEBHOOK_VERIFY_TOKEN` = `tcr_webhook_verify_token_2026`

## Webhook Subscription Oluşturma

Edge Function deploy edildikten ve test başarılı olduktan sonra:

```bash
curl -X POST https://www.strava.com/api/v3/push_subscriptions \
  -d "client_id=198092" \
  -d "client_secret=0822fb63353132c51caaaf9051301427a01f98d3" \
  -d "callback_url=https://lnodjfivycpyoytmwpcn.supabase.co/functions/v1/strava-webhook" \
  -d "verify_token=tcr_webhook_verify_token_2026"
```

**Başarılı yanıt:**
```json
{
  "id": 123456,
  "application_id": 198092,
  "callback_url": "https://lnodjfivycpyoytmwpcn.supabase.co/functions/v1/strava-webhook",
  "created_at": "2026-01-26T15:00:00Z"
}
```

## Sorun Giderme

### Hala "GET to callback URL does not return 200" hatası alıyorsanız:

1. **Edge Function deploy edildi mi?**
   - Supabase Dashboard > Edge Functions > strava-webhook sayfasını kontrol edin
   - Function URL'in çalıştığını doğrulayın

2. **Secrets ayarlandı mı?**
   - Project Settings > Edge Functions > Secrets kontrol edin

3. **URL doğru mu?**
   - `https://lnodjfivycpyoytmwpcn.supabase.co/functions/v1/strava-webhook`
   - Sonunda `/` olmamalı

4. **Verify token eşleşiyor mu?**
   - Secret'taki token ile curl komutundaki token aynı olmalı

5. **Logs kontrol edin:**
   - Supabase Dashboard > Edge Functions > strava-webhook > Logs
   - Hata mesajlarını kontrol edin
