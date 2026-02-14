# Supabase Email Doğrulama Ayarları

Bu dokümantasyon, Supabase'de email doğrulama sisteminin nasıl ayarlanacağını açıklar.

## 1. Supabase Dashboard Ayarları

### Email Templates (Email Şablonları)

1. Supabase Dashboard'a giriş yapın
2. **Authentication** > **Email Templates** bölümüne gidin
3. **Confirm signup** template'ini düzenleyin

### Email Template Örneği

**Subject (Konu):**
```
TCR - Email Doğrulama Kodu
```

**Body (İçerik):**
```html
<h2>Hoş Geldiniz!</h2>
<p>Merhaba {{ .FirstName }},</p>
<p>TCR (Twenty City Runners) ailesine katılmak için email adresinizi doğrulamanız gerekiyor.</p>
<p><strong>Doğrulama Kodunuz:</strong> {{ .Token }}</p>
<p>Bu kodu uygulamaya girerek kayıt işleminizi tamamlayabilirsiniz.</p>
<p><small>Not: Bu kod 10 dakika geçerlidir. Eğer kodu girmeden uygulamayı kapatırsanız, tekrar kayıt olmanız gerekecektir.</small></p>
<p>İyi koşular!</p>
<p>TCR Ekibi</p>
```

### Email Provider Ayarları

1. **Authentication** > **Providers** bölümüne gidin
2. **Email** provider'ını aktif edin
3. **Confirm email** seçeneğini aktif edin

### Email Doğrulama Ayarları

1. **Authentication** > **Settings** bölümüne gidin
2. **Email Auth** bölümünde:
   - ✅ **Enable email confirmations** seçeneğini aktif edin
   - ✅ **Secure email change** seçeneğini aktif edin (opsiyonel)
   - **Confirmation URL** boş bırakın (mobil uygulama için gerekli değil)

### SMTP Ayarları (Opsiyonel - Production için önerilir)

Production ortamında kendi SMTP sunucunuzu kullanmak istiyorsanız:

1. **Settings** > **Auth** > **SMTP Settings** bölümüne gidin
2. SMTP bilgilerinizi girin:
   - **Host**: SMTP sunucu adresi (örn: smtp.gmail.com)
   - **Port**: SMTP portu (genellikle 587 veya 465)
   - **User**: SMTP kullanıcı adı
   - **Password**: SMTP şifresi
   - **Sender email**: Gönderen email adresi
   - **Sender name**: Gönderen adı (örn: TCR)

---

## Kendi Mail Adresinle Göndermek (Şirket maili yok)

Supabase varsayılan olarak `noreply@mail.app.supabase.io` ile atar. Kendi kişisel mail adresinle (Gmail, Outlook vb.) atmak için SMTP kullanman yeterli; **şirket maili gerekmez**.

### Seçenek 1: Gmail ile (En pratik, ücretsiz)

1. **Gmail’de 2 adımlı doğrulamayı aç**
   - Google Hesabı → Güvenlik → 2 Adımlı Doğrulama → Aç.

2. **Uygulama şifresi oluştur**
   - [Google Hesap sayfası](https://myaccount.google.com/) → Güvenlik → 2 Adımlı Doğrulama (açık olmalı) → **Uygulama şifreleri**.
   - “Uygulama seç” → **Posta** (veya “Diğer” yazıp “TCR” gibi bir isim ver).
   - **Oluştur** de; 16 karakterlik bir şifre gösterilir (boşluksuz kopyala, bunu Supabase’e gireceksin).

3. **Supabase’de SMTP’yi doldur**
   - Dashboard → **Project Settings** (sol alttaki dişli) → **Auth** → **SMTP Settings**.
   - **Enable Custom SMTP** aç.
   - Değerler:
     - **Sender email**: Kendi Gmail adresin (örn. `seninadin@gmail.com`).
     - **Sender name**: Görünen ad (örn. `TCR` veya `Twenty City Runners`).
     - **Host**: `smtp.gmail.com`
     - **Port**: `587`
     - **Username**: Aynı Gmail adresin.
     - **Password**: Az önce oluşturduğun 16 karakterlik uygulama şifresi (Gmail giriş şifren değil).
   - Kaydet.

Bundan sonra doğrulama ve şifre sıfırlama mailleri **senin Gmail adresinle** (örn. `TCR <seninadin@gmail.com>`) gidecek.

**Not:** Gmail günlük limiti kişisel hesaplarda yaklaşık 500 mail/gün. TCR gibi bir topluluk uygulaması için genelde yeterlidir; çok yüksek hacimde kullanırsan ileride SendGrid/Resend gibi bir servis düşünebilirsin.

### Seçenek 2: Outlook / Microsoft 365 (Kişisel)

- **Host**: `smtp-mail.outlook.com` veya `smtp.office365.com`
- **Port**: `587`
- **Username / Sender email**: Outlook adresin.
- **Password**: Hesap şifren veya (varsa) uygulama şifresi.

Microsoft hesap güvenliği sayfasından “Uygulama şifreleri” veya modern hesaplarda giriş izni vererek SMTP kullanabilirsin.

### Seçenek 3: İleride kendi domain’in olursa

Kendi domain’i (örn. `tcr.app`) alıp MX/SPF/DKIM ayarlarını yaptıktan sonra Resend, SendGrid, Mailgun gibi servislerle `noreply@tcr.app` gibi bir adres kullanabilirsin. Şimdilik Gmail ile başlamak yeterli.

## 2. Database Trigger Ayarları

Migration dosyaları (`018_remove_referral_system.sql` ve `019_user_approval_system.sql`) zaten email doğrulama trigger'larını içeriyor. Bu migration'ları çalıştırdığınızda:

- Email doğrulanmadan kullanıcı profili oluşturulmayacak
- Email doğrulandığında otomatik olarak profil oluşturulacak
- Varsayılan olarak `is_active = false` olacak (yetkili onayı bekliyor)

## 3. Kullanıcı Onay Sistemi

### Admin Onay Fonksiyonu

Admin kullanıcıları, `approve_user` fonksiyonunu kullanarak kullanıcıları onaylayabilir:

```sql
SELECT public.approve_user(
  'user_id_to_approve'::UUID,
  'admin_user_id'::UUID
);
```

### Manuel Onay (Supabase Dashboard)

1. **Table Editor** > **users** tablosuna gidin
2. Onaylanacak kullanıcıyı bulun
3. `is_active` kolonunu `true` yapın

### API ile Onay (Opsiyonel)

Eğer bir admin paneli oluşturmak isterseniz, Supabase client ile:

```dart
await supabase
  .from('users')
  .update({'is_active': true})
  .eq('id', userId);
```

## 4. Test Etme

### Development Ortamında

1. Supabase Dashboard'da **Authentication** > **Users** bölümüne gidin
2. Test kullanıcısı oluşturun
3. Email doğrulama linkini kontrol edin (Dashboard'da görünecek)

### Production Ortamında

1. Gerçek bir email adresi ile kayıt olun
2. Email'inizi kontrol edin
3. Doğrulama kodunu uygulamaya girin
4. Admin tarafından onaylanmayı bekleyin

## 5. Önemli Notlar

- Email doğrulama kodu 8 haneli bir sayıdır
- Kod 10 dakika geçerlidir
- Kullanıcı email doğrulamadan uygulamayı kapatırsa, tekrar kayıt olması gerekir
- Email doğrulandıktan sonra kullanıcı `is_active = false` durumunda olacak
- Admin onayından sonra kullanıcı giriş yapabilecek

## 6. Sorun Giderme

### Email gelmiyor mu?

1. **Spam** klasörünü kontrol edin
2. Supabase Dashboard'da **Authentication** > **Users** bölümünden email'i kontrol edin
3. SMTP ayarlarınızı kontrol edin (production için)

### Doğrulama kodu çalışmıyor mu?

1. Kodun 8 haneli olduğundan emin olun
2. Kodun 10 dakika içinde girildiğinden emin olun
3. Supabase Dashboard'da kullanıcının `email_confirmed_at` değerini kontrol edin

### Kullanıcı giriş yapamıyor mu?

1. Email doğrulanmış mı kontrol edin (`email_confirmed_at` NULL olmamalı)
2. Kullanıcı aktif mi kontrol edin (`is_active = true` olmalı)
3. Hata mesajını kontrol edin (kodda `USER_NOT_APPROVED` veya `EMAIL_NOT_CONFIRMED` hatası)

---

## 7. Şifremi Unuttum / Şifre Sıfırlama

Uygulama "Şifremi Unuttum" ile şifre sıfırlama e-postası gönderir. Link tıklandığında uygulama açılır ve kullanıcı yeni şifresini belirler.

### Mobil + Web (app.rivlus.com) – Link her zaman uygulamayı açsın

Proje hem mobil hem web (app.rivlus.com) üzerinde çalışıyorsa ve **şifre sıfırlama linkinin her zaman mobil uygulamayı açmasını** istiyorsanız (web sayfasına gitmesin):

1. Supabase Dashboard → **Authentication** → **URL Configuration**
2. **Site URL** alanına **custom scheme** girin (web adresi değil):
   ```
   tcr://reset-password
   ```
   Böylece e-postadaki linkin varsayılan hedefi uygulama olur; tıklanınca cihazda TCR uygulaması açılır.
3. **Redirect URLs** listesinde şunlar olsun (hepsi gerekli):
   - `tcr://reset-password` (mobil – e-postadaki link uygulamayı açar)
   - `https://app.rivlus.com/auth/callback` (web – OAuth vb.)
   - `https://app.rivlus.com/reset-password` (web’den şifre sıfırlama kullanılırsa)
4. **Save changes** ile kaydedin.

**Not:** Site URL’i `https://app.rivlus.com` yaparsanız, e-postadaki şifre sıfırlama linki tarayıcıda app.rivlus.com’u açar. Sadece test için web kullanıyorsanız ve asıl hedef mobil uygulama ise Site URL’i `tcr://reset-password` tutun.

### URL Configuration (genel – zorunlu)

1. Supabase Dashboard → **Authentication** → **URL Configuration**
2. **Redirect URLs** listesinde `tcr://reset-password` mutlaka olsun (yukarıdaki “Mobil + Web” adımlarında olduğu gibi).
3. Kaydedin. Bu URL olmadan e-postadaki link uygulamayı açamaz.

### E-posta nasıl gider?

- **Varsayılan**: Supabase kendi e-posta altyapısıyla mail atar. Günlük limit vardır, test için yeterlidir.
- **Production**: **Project Settings** → **Auth** → **SMTP Settings** bölümünden kendi SMTP’nizi (Gmail, SendGrid, vb.) tanımlayın; aynı SMTP hem kayıt doğrulama hem şifre sıfırlama mailleri için kullanılır.

### E-posta şablonu (opsiyonel)

1. **Authentication** → **Email Templates**
2. **Reset password** şablonunu seçin
3. Aşağıdaki örnek metni kopyalayıp yapıştırabilir veya kendi metninizi yazabilirsiniz. **Link mutlaka `{{ .ConfirmationURL }}` ile eklenmeli**; uygulama `redirectTo: tcr://reset-password` kullandığı için bu link uygulamayı açacaktır.

**Konu (Subject):**
```
TCR - Şifrenizi sıfırlayın
```

**İçerik (Body) – HTML:**
```html
<h2>Şifre Sıfırlama</h2>
<p>Merhaba,</p>
<p>TCR (Twenty City Runners) uygulamasında şifre sıfırlama talebinde bulundunuz.</p>
<p>Yeni şifrenizi belirlemek için aşağıdaki bağlantıya tıklayın:</p>
<p><a href="{{ .ConfirmationURL }}" style="display:inline-block; padding:12px 24px; background:#5C7A8A; color:#fff; text-decoration:none; border-radius:8px;">Şifremi sıfırla</a></p>
<p>Ya da bu linki kopyalayıp tarayıcıya yapıştırın:<br/><a href="{{ .ConfirmationURL }}">{{ .ConfirmationURL }}</a></p>
<p><small>Bu link 1 saat geçerlidir. Eğer şifre sıfırlama talebinde bulunmadıysanız bu e-postayı dikkate almayın.</small></p>
<p>İyi koşular!</p>
<p>TCR Ekibi</p>
```

**Düz metin alternatif (Plain text):**
```
Şifre Sıfırlama

Merhaba,

TCR (Twenty City Runners) uygulamasında şifre sıfırlama talebinde bulundunuz.

Yeni şifrenizi belirlemek için aşağıdaki bağlantıya tıklayın:
{{ .ConfirmationURL }}

Bu link 1 saat geçerlidir. Eğer şifre sıfırlama talebinde bulunmadıysanız bu e-postayı dikkate almayın.

İyi koşular!
TCR Ekibi
```

### Akış özeti

1. Kullanıcı giriş ekranında "Şifremi Unuttum"a tıklar
2. E-posta girer; uygulama `resetPasswordForEmail(email, redirectTo: 'tcr://reset-password')` çağırır
3. Supabase e-posta gönderir (içinde `tcr://reset-password` yönlendirmeli link vardır)
4. Kullanıcı e-postadaki linke tıklar → cihazda uygulama açılır (deep link)
5. Uygulama oturumu restore eder ve "Yeni şifre belirle" ekranını açar
6. Kullanıcı yeni şifreyi girip kaydeder; şifre güncellenir ve ana sayfaya yönlendirilir

### "Linkin süresi dolmuş" (otp_expired) hatası neden olur?

- **E-posta prefetch**: Gmail, Outlook vb. güvenlik taraması için linke otomatik istek atabiliyor. Bu istek kodu tek kullanımda tüketiyor; kullanıcı tıkladığında kod zaten geçersiz oluyor.
- **Süre**: PKCE kodu genelde kısa süre (ör. 5 dakika) geçerli; geç tıklanırsa `otp_expired` alınır.
- **Tek kullanım**: Kod yalnızca bir kez kullanılabilir; iki kez tıklanırsa ikinci seferde hata alınır.

Bu durumda uygulama "Linkin süresi dolmuş veya zaten kullanılmış..." mesajını gösterir. Kullanıcı giriş ekranından "Şifremi Unuttum" ile tekrar talep etmeli.
