
# App Store & Google Play – Ekran Görüntüsü Rehberi

## Profesyonel bir uygulamada kaç ekran görüntüsü olmalı?

| Mağaza        | Minimum | Önerilen (profesyonel) | Maksimum |
|---------------|---------|-------------------------|----------|
| **App Store** | 1       | **5–8**                 | 10       |
| **Google Play** | 2     | **5–8**                 | 8        |

- **5–8 ekran** hem hikâyeyi anlatır hem de kullanıcıyı yormaz. Tüm ekranları çekmek gerekmez.
- İlk 2–3 ekran çok önemli: mağaza önizlemesinde önce bunlar görünür.
- Her ekran **tek bir mesaj** vermeli: “Ne işe yarıyor?”, “Neden indirmeli?”.

---

## Boyut gereksinimleri (kısa)

- **App Store (iPhone):** 6.7" veya 6.5" çözünürlük (PNG/JPEG, max 10MB). En az bir set zorunlu.
- **Google Play (telefon):** 1080×1920 px (dikey) veya 1920×1080 px (yatay), PNG/JPEG, max 8MB. En az 2 ekran.

### App Store – Tam piksel boyutları (iPhone 6.5" ekran)

Simülatörden (örn. iPhone 17 Pro Max) aldığınız ekran görüntüleri farklı çözünürlükte olabilir. App Store Connect **sadece** aşağıdaki boyutları kabul eder. "Boyutlar yanlış" hatası alıyorsanız görselleri bu boyutlara getirmeniz gerekir:

| Yön    | Kabul edilen boyutlar   |
|--------|--------------------------|
| Dikey  | **1242 × 2688** veya **1284 × 2778** px |
| Yatay  | **2688 × 1242** veya **2778 × 1284** px |

**Çözüm:** Proje kökündeki `scripts/resize_screenshots_for_appstore.sh` script'ini kullanarak ekran görüntülerinizi otomatik olarak 1284×2778 px (dikey) boyutuna getirebilirsiniz. Ayrıntılar aşağıda.

### Google Play – Özellik grafiği (Feature Graphic)

Özellik grafiği **zorunludur**; liste sayfasında uygulamanızın üstünde görünür. Gereksinimler:

| Özellik | Değer |
|--------|--------|
| Boyut  | **1024 × 500** px |
| Format | PNG veya JPEG |
| Max    | 15 MB |

**Çözüm:** `scripts/resize_feature_graphic_for_google_play.sh` ile görseli 1024×500 px yapın:
- Tek dosya: `./scripts/resize_feature_graphic_for_google_play.sh ~/Desktop/feature.png`
- Klasör: `./scripts/resize_feature_graphic_for_google_play.sh ~/Desktop/graphics`  
Çıktı `google_play_feature_1024x500` alt klasörüne yazılır; bu dosyayı Play Console’da “Özellik grafiği” alanına yükleyin.

---

## TCR uygulaması – hangi ekranları çekmeli?

Uygulamanızdaki tüm route’lar incelendi. Aşağıdaki liste **öncelik sırasına** göre; sadece önerilen ekranları çekmeniz yeterli.

### Zorunlu (ilk 3–4 ekran)

| # | Ekran | Route / Sayfa | Neden |
|---|--------|----------------|--------|
| 1 | **Ana sayfa (Home)** | `/home` → `HomePage` | İlk izlenim; feed, harita, alt menü. Uygulamanın “merkezi” burada. |
| 2 | **Etkinlikler listesi** | `/events` → `EventsPage` | Çekirdek özellik: etkinlikleri keşfetme. |
| 3 | **Etkinlik detay** | `/events/:eventId` → `EventDetailPage` | Harita, tarih, katılımcılar, rota – değer önerisi net görünür. |
| 4 | **Profil** | `/profile` → `ProfilePage` | Kişisel alan, istatistikler, ICE kartı – “benim uygulamam” hissi. |

### Önerilen (5–6. ekranlar)

| # | Ekran | Route / Sayfa | Neden |
|---|--------|----------------|--------|
| 5 | **Pazar (Marketplace)** | `/marketplace` → `MarketplacePage` | Alışveriş / ekipman paylaşımı varsa mutlaka gösterilmeli. |
| 6 | **Antrenman grupları** | `/groups` → `GroupsPage` | Topluluk ve gruplar özelliği farklılaştırıcı. |

### İsteğe bağlı (7–8. ekranlar)

| # | Ekran | Route / Sayfa | Neden |
|---|--------|----------------|--------|
| 7 | **Rotalar (GPX)** | `/routes` → `RoutesPage` veya rota detay | Harita/rota özelliği güçlüyse eklenebilir. |
| 8 | **Aktivite feed / Liderlik** | `/home/feed` → `ActivityFeedPage` veya `LeaderboardPage` | Sosyal / rekabet tarafını göstermek için. |

---

## Çekmemeniz gereken ekranlar

- **Login / Register / Onboarding** – Değer önerisini göstermiyor; sadece tasarım çok güçlüyse 1 tanesi son sırada düşünülebilir.
- **Ayarlar, Bildirimler listesi** – Mağaza için anlamlı bir hikâye anlatmıyor.
- **Form ekranları** – Etkinlik oluşturma, ilan oluşturma, post oluşturma vb. (işlevsel ama “neden indirmeli?” sorusuna cevap vermiyor).
- **Şifre sıfırlama, e-posta doğrulama** – Store için gerek yok.

---

## Önerilen çekim seti (toplam 6 ekran)

Pratik ve profesyonel bir set için:

1. **Ana sayfa (Home)**  
2. **Etkinlikler listesi (Events)**  
3. **Etkinlik detay (Event detail)** – Mümkünse harita ve bilgi dolu bir etkinlik seçin.  
4. **Profil (Profile)**  
5. **Pazar (Marketplace)**  
6. **Antrenman grupları (Groups)**  

Bu 6 ekran hem App Store hem Google Play için yeterli ve tutarlı bir hikâye sunar. İsterseniz 7–8 olarak **Rotalar** veya **Aktivite feed / Liderlik** ekleyebilirsiniz.

---

## Nasıl çekebilirsiniz?

- **Simülatör/emülatör:** iOS Simulator veya Android Emulator’da ilgili sayfaya gidip ekran görüntüsü alın (Cmd+S / ekran görüntüsü kısayolu).
- **Gerçek cihaz:** Test verisi ile dolu bir hesapla aynı ekranları açıp sistem ekran görüntüsü alın.
- **Flutter:** `flutter run` ile çalıştırıp ilgili route’lara manuel veya test ile gidip çekebilirsiniz.

### Simülatör ekran görüntüsü "boyutlar yanlış" hatası

iPhone 17 Pro Max (veya başka yeni simülatör) ile aldığınız ekran görüntüleri App Store'un beklediği sabit boyutlardan farklı olabilir. Yapmanız gerekenler:

1. **Sadece cihaz ekranını kaydedin** — Simülatör penceresinin üstündeki kontrol çubuğu ekran görüntüsünde olmamalı. Simülatör odaktayken **Cmd + S** kullanın; sadece cihaz ekranı PNG olarak kaydedilir.
2. **Boyutu App Store'a uygun hale getirin** — Proje kökünden: `chmod +x scripts/resize_screenshots_for_appstore.sh` sonra `./scripts/resize_screenshots_for_appstore.sh path/to/screenshots`. Script görselleri **1284×2778 px** yapar ve `appstore_1284x2778` alt klasörüne yazar. Bu dosyaları App Store Connect'e yükleyin.

İsterseniz bir sonraki adımda “hangi cihaz boyutlarında çekeyim?” veya “her ekran için kısa başlık/açıklama metni” listesi de çıkarılabilir.
