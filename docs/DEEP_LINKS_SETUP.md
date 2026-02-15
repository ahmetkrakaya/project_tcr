# Deep Link / App Links Kurulum ve Test

Linke tıklayınca uygulamanın doğrudan ilgili sayfada açılması için hem Flutter hem rivlus.com tarafında ayarlar gerekir.

---

## Kopyala-yapıştır: Terminal komutları

**Bu projede Android SDK:** `~/SDKs/android` (Flutter ile aynı SDKs klasörü).

**Adım 1 – PATH’e adb ekle (bir kez):**
```bash
echo 'export PATH="$HOME/SDKs/android/platform-tools:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

**Adım 2 – Deep link loglarını izle (terminali açık bırak, sonra uygulamayı kapatıp linke tıkla):**
```bash
adb logcat | grep TCR_DEEPLINK
```
`adb` hâlâ yoksa tam yolla:
```bash
$HOME/SDKs/android/platform-tools/adb logcat | grep TCR_DEEPLINK
```

---

## 1. Cold start test – Uygulamayı kapatıp linkle açınca log nasıl görünür?

Uygulamayı **tamamen kapatıp** linke tıklayınca yeni bir process başlar; IDE’den çalıştırmadığın için o process’in logları IDE konsoluna düşmez. Logları görmek için şöyle yap:

### Android (simulator veya gerçek cihaz)

**`adb` komutu yoksa (zsh: command not found: adb):**  
`adb` Android SDK ile gelir. macOS’ta genelde: `~/Library/Android/sdk/platform-tools/adb`  
Önce tam yolu dene: `~/Library/Android/sdk/platform-tools/adb logcat | grep TCR_DEEPLINK`  
Kalıcı kullanım için PATH’e ekle (`.zshrc`):  
`export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"`  
Sonra `source ~/.zshrc`. SDK başka yerdeyse Android Studio → Settings → Android SDK → “Android SDK Location”a bak.

1. **Terminali aç** ve şu komutu çalıştır (bir kez çalıştır, açık kalsın):
   ```bash
   adb logcat | grep -E "TCR_DEEPLINK|flutter"
   ```
   veya sadece:
   ```bash
   adb logcat | grep TCR_DEEPLINK
   ```
2. Simülatörde/cihazda **uygulamayı tamamen kapat** (son uygulamalardan sil veya “Force stop”).
3. Linke tıkla (Mesajlar, Notlar, Chrome’da bir yerde `https://rivlus.com/e/BIR_ID` veya uygulama linki).
4. Uygulama açılınca **loglar bu terminalde** görünür. Yeni process’in çıktısı `adb logcat`’e düşer.

Yani: Önce `adb logcat`’i başlat, sonra uygulamayı kapatıp linke tıkla.

### iOS (simulator)

Simulator’da uygulamayı kapatıp linkle açınca process Xcode/flutter’a bağlı olmaz, o yüzden **cold start** logları IDE’de görünmeyebilir.

- **Seçenek A:** Uygulamayı **kapatma**, sadece **home’a at** (arka planda kalsın). Sonra Safari’de veya Notlar’da linke tıkla. Uygulama öne gelir; bazen debugger hâlâ bağlı kalır ve loglar Xcode / `flutter run` konsolunda çıkar.
- **Seçenek B:** Gerçek cihazda test et; Xcode’dan Run yap, cihazı bağlı bırak, uygulamayı kapatıp linke tıkla – bazen console’da görünür.
- **Seçenek C:** Logları uygulama içinde göstermek (aşağıdaki “Aranacak satırlar”ı dosyaya yazıp Ayarlar’da “Son deep link logu” gibi gösterebilirsin; istersen ekleyebiliriz).

---

## 2. Debug logları – Aranacak satırlar

Aranacak satırlar:

- `TCR_DEEPLINK getInitialUri: ...`  
  - `null` → Uygulama link ile açılmadı veya OS linki uygulamaya vermiyor.  
  - `https://rivlus.com/e/xxx` veya `tcr:///events/xxx` → Link geliyor, path’e çevrilip saklanıyor olmalı.
- `TCR_DEEPLINK main: pending path set -> /events/xxx`  
  → Path doğru set edildi, splash sonrası bu sayfaya gidilmeli.
- `TCR_DEEPLINK main: no initial uri or parse failed`  
  → İlk URI yok veya parse edilemedi (link gelmiyor veya format farklı).
- `TCR_DEEPLINK splash: navigating to /events/xxx`  
  → Splash, deep link path’e yönlendiriyor.

**Eğer hep `getInitialUri: null` görüyorsan:**  
Link büyük ihtimalle tarayıcıda açılıyor, uygulama “App Link” ile açılmıyor. Android’de assetlinks, iOS’ta AASA doğru ve erişilebilir olmalı (aşağıya bakın).

---

## 3. Android App Links (rivlus.com linki uygulamada açılsın)

Android’in `https://rivlus.com/e/...` ve `https://rivlus.com/m/...` linklerini doğrudan uygulamada açması için **assetlinks.json** doğrulanmalı. Bunun için SHA-256 parmak izi gerekir.

### SHA-256 fingerprint alma

**Play Console (yayınlanmış uygulama):**

1. [Google Play Console](https://play.google.com/console) → Uygulama → **Kurulum** → **Uygulama bütünlüğü** (App integrity).
2. **Uygulama imzalama** bölümünde **SHA-256 sertifika parmak izi**ni kopyala (tek satır, `AA:BB:CC:...` formatında).

**Yerel release keystore (henüz Play’e vermediysen):**

```bash
keytool -list -v -keystore /path/to/your/upload-keystore.jks -alias your-key-alias
```

Çıktıdaki **SHA256:** satırındaki değeri al (örn. `AA:BB:CC:DD:...`).

### Vercel’de environment variable

1. Vercel → **rivlus-site** projesi → **Settings** → **Environment Variables**.
2. Ekle:
   - **Name:** `ANDROID_SHA256_FINGERPRINT`
   - **Value:** Yukarıdaki SHA-256 değeri (örn. `AA:BB:CC:DD:EE:...`), **iki nokta üst üste ile**, boşluksuz.
3. **Save** → Sonra **Redeploy** (Deployments → son deploy → ⋮ → Redeploy).

### Doğrulama

- Tarayıcıda aç: `https://rivlus.com/.well-known/assetlinks.json`
- JSON içinde `sha256_cert_fingerprints` altında gerçek fingerprint’in görünmesi gerekir.  
  `PLACEHOLDER:SHA256:FINGERPRINT` görüyorsan env değişkeni tanımlı değil veya deploy eski.

---

## 4. iOS Universal Links

iOS tarafında `apple-app-site-association` (AASA) kullanılıyor. Projede `rivlus-site` içinde ayar var; Team ID ve Bundle ID doğru ise ekstra bir şey yapmana gerek olmaz.

Kontrol:

- `https://rivlus.com/.well-known/apple-app-site-association` açılmalı ve JSON dönmeli.
- Path’ler `/e/*` ve `/m/*` olmalı.

---

## 5. Özet

| Durum | Yapılacak |
|--------|-----------|
| Logda `getInitialUri: null` | Android: Vercel’de `ANDROID_SHA256_FINGERPRINT` set et, redeploy et. iOS: AASA’nın erişilebilir ve doğru olduğundan emin ol. |
| `getInitialUri: https://...` var ama yine login | Path parse veya splash/login akışı; loglarda `pending path set` ve `splash: navigating` var mı bak. |
| Link tarayıcıda açılıyor, uygulama hiç açılmıyor | App Links / Universal Links doğrulanmamış; assetlinks / AASA adımlarını uygula. |

Bu adımlardan sonra linki tekrar deneyip loglara bak; hâlâ `getInitialUri: null` ise sorun büyük ihtimalle assetlinks/AASA veya cihaz tarafı doğrulamadır.
