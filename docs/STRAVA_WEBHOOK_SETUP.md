# Strava Webhook Otomatik Senkronizasyon Kurulum Rehberi

Bu rehber, Strava aktivitelerinin otomatik olarak uygulamanıza senkronize edilmesi için gerekli adımları içerir.

## 📋 Ön Gereksinimler

- Supabase projeniz aktif ve çalışıyor
- Supabase CLI kurulu (opsiyonel, Dashboard'dan da yapabilirsiniz)
- Strava API uygulamanız oluşturulmuş ve Client ID/Secret'ınız var

## 🚀 Adım 1: Supabase Edge Function Oluşturma

### Yöntem A: Supabase Dashboard (Önerilen - Daha Kolay)

1. **Supabase Dashboard'a gidin**: https://supabase.com/dashboard
2. Projenizi seçin
3. Sol menüden **Edge Functions** sekmesine tıklayın
4. **Create a new function** butonuna tıklayın
5. **Function name**: `strava-webhook` yazın
6. **Function code** alanına `supabase/functions/strava-webhook/index.ts` dosyasının içeriğini yapıştırın
7. **Deploy** butonuna tıklayın

### Yöntem B: Supabase CLI (Geliştiriciler için)

```bash
# Supabase CLI ile deploy
supabase functions deploy strava-webhook
```

## 🔐 Adım 2: Environment Variables (Secrets) Ayarlama

1. Supabase Dashboard'da **Project Settings** (sol altta dişli ikonu) > **Edge Functions** sekmesine gidin
2. **Secrets** bölümüne gidin
3. Şu 3 secret'ı ekleyin:

   **Secret 1:**
   - **Name**: `STRAVA_CLIENT_ID`
   - **Value**: Strava API uygulamanızın Client ID'si
   - **Add** butonuna tıklayın

   **Secret 2:**
   - **Name**: `STRAVA_CLIENT_SECRET`
   - **Value**: Strava API uygulamanızın Client Secret'ı
   - **Add** butonuna tıklayın

   **Secret 3:**
   - **Name**: `STRAVA_WEBHOOK_VERIFY_TOKEN`
   - **Value**: Rastgele bir string (örn: `tcr_webhook_verify_token_2026`)
   - **Not**: Bu token'ı not edin, Strava webhook subscription oluştururken kullanacaksınız
   - **Add** butonuna tıklayın

**Not**: `SUPABASE_URL` ve `SUPABASE_SERVICE_ROLE_KEY` otomatik olarak mevcuttur, eklemenize gerek yoktur.

## 🌐 Adım 3: Webhook URL'ini Bulma

1. Supabase Dashboard'da **Edge Functions** > **strava-webhook** fonksiyonuna gidin
2. **Function URL** kısmında URL'iniz görünecek:
   ```
   https://[PROJECT_REF].supabase.co/functions/v1/strava-webhook
   ```
3. Bu URL'yi kopyalayın ve not edin

**Not**: `[PROJECT_REF]` kısmı sizin proje referansınız olacak (örn: `lnodjfivycpyoytmwpcn`)

## 🔗 Adım 4: Strava Webhook Subscription Oluşturma

**⚠️ ÖNEMLİ:** Webhook subscription oluşturmadan **ÖNCE** Edge Function'ın deploy edildiğinden ve çalıştığından emin olun! Aksi takdirde Strava verification yapamaz ve hata alırsınız.

**Önemli:** Strava API Dashboard'da webhook yönetimi için bir UI yoktur. Webhook subscription'ları **yalnızca API ile** oluşturulabilir.

### Yöntem A: Terminal/Command Line (Önerilen)

1. **Terminal'i açın** (Mac: Terminal, Windows: PowerShell/CMD)
2. Aşağıdaki komutu çalıştırın (değerleri kendi bilgilerinizle değiştirin):

```bash
curl -X POST https://www.strava.com/api/v3/push_subscriptions \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "callback_url=https://[PROJECT_REF].supabase.co/functions/v1/strava-webhook" \
  -d "verify_token=tcr_webhook_verify_token_2026"
```

**Örnek:**
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
  "created_at": "2026-01-26T14:00:00Z"
}
```

### Yöntem B: Postman veya HTTP İstemcisi

1. **Postman** veya benzer bir HTTP istemcisi açın
2. **POST** request oluşturun:
   - **URL**: `https://www.strava.com/api/v3/push_subscriptions`
   - **Method**: `POST`
   - **Body** (form-data veya x-www-form-urlencoded):
     - `client_id`: Strava Client ID'niz
     - `client_secret`: Strava Client Secret'ınız
     - `callback_url`: Adım 3'te kopyaladığınız webhook URL'i
     - `verify_token`: Adım 2'de oluşturduğunuz verify token
3. **Send** butonuna tıklayın

### Yöntem C: Python Script (Opsiyonel)

Eğer Python kullanmak isterseniz:

```python
import requests

url = "https://www.strava.com/api/v3/push_subscriptions"
data = {
    "client_id": "YOUR_CLIENT_ID",
    "client_secret": "YOUR_CLIENT_SECRET",
    "callback_url": "https://[PROJECT_REF].supabase.co/functions/v1/strava-webhook",
    "verify_token": "tcr_webhook_verify_token_2026"
}

response = requests.post(url, data=data)
print(response.json())
```

**Not:** Webhook subscription oluşturulduğunda, Strava otomatik olarak webhook URL'inize bir GET request göndererek verification yapar. Edge Function'ınız bunu otomatik olarak handle eder.

**Yanıt:**
```json
{
  "id": 123456,
  "application_id": YOUR_APP_ID,
  "callback_url": "https://...",
  "created_at": "2024-01-26T10:00:00Z"
}
```

## ✅ Adım 5: Webhook Subscription'ı Kontrol Etme

Webhook subscription'ınızın başarıyla oluşturulduğunu kontrol edin:

```bash
curl -X GET "https://www.strava.com/api/v3/push_subscriptions?client_id=YOUR_CLIENT_ID&client_secret=YOUR_CLIENT_SECRET"
```

**Örnek:**
```bash
curl -X GET "https://www.strava.com/api/v3/push_subscriptions?client_id=198092&client_secret=0822fb63353132c51caaaf9051301427a01f98d3"
```

**Başarılı yanıt:**
```json
[
  {
    "id": 123456,
    "application_id": 198092,
    "callback_url": "https://lnodjfivycpyoytmwpcn.supabase.co/functions/v1/strava-webhook",
    "created_at": "2026-01-26T14:00:00Z"
  }
]
```

**Eğer boş array dönerse** `[]`, webhook subscription oluşturulmamış demektir. Adım 4'ü tekrar kontrol edin.

**Not:** Birden fazla webhook subscription'ınız olabilir. Tüm aktif subscription'ları göreceksiniz.

## 🧪 Adım 6: Test Etme

1. **Strava uygulamasında** veya **web sitesinde** yeni bir aktivite oluşturun (veya mevcut bir aktiviteyi düzenleyin)
2. Aktiviteyi kaydedin
3. **Birkaç saniye bekleyin** (webhook genellikle 1-5 saniye içinde gelir)
4. **Uygulamanızda** (TCR Feed veya Profil sayfasında) yeni aktivitenin göründüğünü kontrol edin

### Log Kontrolü

Eğer aktivite görünmüyorsa, logları kontrol edin:

1. Supabase Dashboard > **Edge Functions** > **strava-webhook** > **Logs** sekmesine gidin
2. Son log kayıtlarını kontrol edin
3. Hata varsa, hata mesajını okuyun

## 🔍 Sorun Giderme

### Problem: Webhook gelmiyor

**Çözüm:**
- Webhook subscription'ını kontrol edin (Adım 5'teki komutla)
- Callback URL'in doğru olduğundan emin olun
- Verify token'ın eşleştiğinden emin olun
- Edge Function'ın deploy edildiğinden emin olun
- Supabase Dashboard > Edge Functions > strava-webhook > Logs'ta hata var mı kontrol edin

### Problem: Aktivite kaydedilmiyor

**Çözüm:**
- Edge Function logs'larını kontrol edin
- `STRAVA_CLIENT_ID` ve `STRAVA_CLIENT_SECRET` secret'larının doğru olduğundan emin olun
- Kullanıcının `user_integrations` tablosunda Strava entegrasyonu olduğundan emin olun

### Problem: Token hatası

**Çözüm:**
- Kullanıcının Strava token'ının süresi dolmuş olabilir
- Edge Function otomatik olarak token yenilemeye çalışır, ancak refresh token yoksa hata verebilir
- Kullanıcıdan Strava entegrasyonunu yeniden bağlamasını isteyin

### Problem: CORS hatası

**Çözüm:**
- Edge Function'da CORS headers zaten var, ancak hala sorun varsa:
  - Supabase Dashboard > Edge Functions > strava-webhook > Settings
  - CORS ayarlarını kontrol edin

## 📊 Nasıl Çalışır?

1. **Kullanıcı Strava'da aktivite oluşturur/günceller**
2. **Strava webhook gönderir** → `https://[PROJECT_REF].supabase.co/functions/v1/strava-webhook`
3. **Edge Function webhook'u alır**:
   - GET request ise → Webhook verification (Strava subscription oluştururken)
   - POST request ise → Aktivite event'i işlenir
4. **Kullanıcı bulunur**: `user_integrations` tablosundan `provider_user_id` (athlete_id) ile
5. **Token kontrol edilir**: Süresi dolmuşsa otomatik yenilenir
6. **Aktivite çekilir**: Strava API'den aktivite detayları alınır
7. **Veritabanına kaydedilir**: `activities` tablosuna upsert edilir
8. **İstatistikler güncellenir**: `update_user_statistics` trigger otomatik çalışır

## 💡 Önemli Notlar

- **Webhook UI Yok**: Strava API Dashboard'da webhook yönetimi için UI yoktur. Tüm işlemler API ile yapılmalıdır.
- **Rate Limits**: Strava API rate limit'leri var (100 requests/15 dakika, 1000 requests/gün). Webhook'lar bu limit'e dahil değildir.
- **Gecikme**: Webhook genellikle 1-5 saniye içinde gelir, ancak bazen 30 saniyeye kadar sürebilir
- **Güvenlik**: Webhook verify token'ını güvenli tutun, sadece Strava subscription oluştururken kullanın
- **Test**: İlk kurulumdan sonra mutlaka test edin
- **Webhook Silme**: Eğer webhook subscription'ını silmek isterseniz:
  ```bash
  curl -X DELETE "https://www.strava.com/api/v3/push_subscriptions/SUBSCRIPTION_ID?client_id=YOUR_CLIENT_ID&client_secret=YOUR_CLIENT_SECRET"
  ```
  (`SUBSCRIPTION_ID` değerini Adım 5'teki response'dan alabilirsiniz)

## 🎉 Başarılı!

Artık Strava aktiviteleriniz otomatik olarak uygulamanıza senkronize edilecek! Kullanıcılar manuel senkronizasyon yapmak zorunda kalmayacak.
