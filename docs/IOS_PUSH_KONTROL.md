# iOS Push Bildirim Gelmiyorsa Kontrol Listesi

## 1. Gerçek cihaz kullan
iOS **Simulator** push **almaz**. Mutlaka **gerçek iPhone** ile test et.

---

## 2. Firebase Console – APNs ayarı
- [Firebase Console](https://console.firebase.google.com) → Proje → **Project Settings** (dişli) → **Cloud Messaging**
- Aşağı kaydır → **Apple app configuration** (iOS uygulaman)
- **APNs Authentication Key** veya **APNs Certificates** dolu mu?

### APNs Authentication Key (önerilen)
- **Key ID**, **Team ID**, **Bundle ID** (örn. `com.rivlus.projectTcr`) girilmiş olmalı
- **.p8 dosyası** yüklenmiş olmalı (Apple Developer → Keys → Push Notifications ile oluşturduğun key)
- Bundle ID, Xcode’daki **Runner** target → **General** → **Bundle Identifier** ile **birebir aynı** olmalı

### Hatalıysa
- Key’i silip tekrar yükle
- Team ID / Bundle ID yanlış yazılmış olabilir; Apple Developer ve Xcode’dan kontrol et

---

## 3. Bildirim izni
- iPhone’da **Ayarlar → Twenty City Runners → Bildirimler** → **İzin Ver** açık mı?
- Uygulama ilk açılışta “Bildirimlere izin ver” diye soruyor; **İzin Ver** seçilmiş olmalı

---

## 4. FCM token doğru mu?
- Supabase **Table Editor** → **users** → test ettiğin kullanıcı
- **fcm_token** sütunu dolu mu?
- **Önemli:** Aynı hesapla hem Android hem iOS’ta giriş yaptıysan, token **son açılan cihazın** token’ı olur; önceki cihaza artık push gitmez. iOS test için o kullanıcıyı **sadece iPhone’da** aç, token’ın güncellenmesini bekle, sonra bildirimi tetikle.

---

## 5. Apple Developer – App ID
- [developer.apple.com](https://developer.apple.com) → **Certificates, Identifiers & Profiles** → **Identifiers**
- Uygulamanın **App ID**’sini aç (Bundle ID: `com.rivlus.projectTcr` veya ne kullanıyorsan)
- **Push Notifications** **Enabled** ve yeşil tikli mi? Değilse **Edit** → **Push Notifications** işaretle → Save

---

## 6. Test: Firebase’ten tek cihaza gönder (token MUTLAKA iPhone’dan)

Firebase test mesajı da gitmiyorsa büyük ihtimalle **testte kullandığın token Android’e ait**. Aynı hesapla hem Android hem iPhone’da giriş yapıyorsan Supabase’teki `fcm_token` **son açılan cihazın** token’ıdır; o token Android ise mesaj iPhone’a hiç gitmez.

### Doğru test adımları
1. **Android’de uygulamayı tamamen kapat** (veya o hesapla Android’de giriş yapma).
2. **Sadece iPhone’da** uygulamayı aç, o hesapla giriş yap.
3. **10–20 saniye bekle** (token Supabase’e yazılsın).
4. Supabase **Table Editor** → **users** → bu kullanıcı → **fcm_token** değerini **şimdi** kopyala (artık iPhone’un token’ı olmalı).
5. Firebase Console → **Engage** → **Messaging** → **Send your first message** / **New campaign** → **Send test message**.
6. Bu **yeni kopyaladığın** token’ı yapıştır → Gönder.

- **Cihazda bildirim çıkıyorsa:** FCM + APNs çalışıyor; sorun token karışıklığıydı.
- **Hâlâ çıkmıyorsa:** Aşağıdaki 7 ve 8’e geç.

### İstersen token’ı uygulama içinde gör (debug)
- Geliştirme sırasında FCM token’ını görmek için `FcmService.getToken()` sonucunu `debugPrint` veya bir AlertDialog ile gösterebilirsin; böylece “bu cihazın token’ı bu mu?” diye kontrol edebilirsin.

---

## 7. Firebase’te Team ID / Bundle ID
- Firebase’teki **Team ID**, Apple Developer’daki **Membership** → **Team ID** (10 karakter) ile **birebir aynı** olmalı.
- **Bundle ID** Firebase’te `com.rivlus.projectTcr` ise Xcode’daki Runner Bundle Identifier da aynı olmalı (projede uyumlu).

## 8. Yeni APNs key dene
- Bazen .p8 dosyası yanlış/eksik yüklenmiş olabiliyor. Apple Developer → **Keys** → yeni key oluştur (Push Notifications işaretli) → .p8 indir (sadece bir kez iner).
- Firebase → **Apple app configuration** → mevcut APNs key’i sil → **Upload** ile yeni .p8’i yükle (Key ID + Team ID + Bundle ID gir).
- Uygulamayı iPhone’da tekrar aç, token’ı tekrar al (6. adımdaki gibi sadece iPhone ile), Firebase test mesajını tekrar gönder.

## 9. Debug / Release
- Xcode’dan **Run** (Debug) ile çalıştırıyorsan APNs **development** (sandbox) kullanır. Firebase’e yüklediğin **.p8 key** hem development hem production için geçerli olmalı.
- **Archive / TestFlight** ile test ediyorsan **production** kullanılır; key yine aynı .p8 ile çalışır.

Özet: En sık neden **Firebase’te APNs key/certificate eksik veya hatalı**; ikinci neden **Simulator’da test**. Önce 2 ve 1’i netleştir.
