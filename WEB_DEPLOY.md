# TCR Web - app.rivlus.com Deploy Rehberi

## Mimari

```
rivlus.com        → Mevcut rivlus-site (about, privacy, deep links)
app.rivlus.com    → Flutter web uygulaması (bu proje)
```

## Ön Gereksinimler

### 0. Proje henüz Git repo değilse

```bash
cd /Users/deskiyazilim/development/project_tcr
git init
git add .
git commit -m "Initial commit"
# GitHub’da yeni repo oluşturduktan sonra:
git remote add origin https://github.com/KULLANICI/project_tcr.git
git branch -M main
git push -u origin main
```

Bundan sonra güncellemeler için sadece `git add .` → `commit` → `push origin main` yeterli.

### 1. Firebase Web App Oluşturma

Firebase Console > Project Settings > Your apps > Add app > Web

```bash
flutterfire configure --platforms=web
```

`lib/firebase_options.dart` dosyasındaki `web` sabiti otomatik güncellenecek.
`PLACEHOLDER_WEB_APP_ID` değerini gerçek appId ile değiştirin.

### 2. Vercel Projesi Oluşturma

1. [vercel.com](https://vercel.com) > New Project
2. Framework Preset: Other
3. Build Command: (boş bırakın - GitHub Actions ile build ediliyor)
4. Output Directory: (boş bırakın)
5. Settings > Domains > `app.rivlus.com` ekleyin

### 3. Cloudflare DNS Ayarı

Cloudflare DNS panelinde yeni kayıt ekleyin:

| Type  | Name | Target              | Proxy |
|-------|------|---------------------|-------|
| CNAME | app  | cname.vercel-dns.com | DNS Only (gri bulut) |

**Önemli:** Proxy kapalı olmalı (gri bulut). Vercel kendi SSL sertifikasını kullanır.

### 4. GitHub Secrets

Repository Settings > Secrets and variables > Actions:

| Secret                    | Açıklama                                        |
|---------------------------|-------------------------------------------------|
| `VERCEL_TOKEN`            | Vercel > Settings > Tokens > Create             |
| `VERCEL_ORG_ID`           | Vercel > Settings > General > Your ID           |
| `VERCEL_WEB_PROJECT_ID`   | Vercel proje ID (Settings > General)            |
| `SUPABASE_URL`            | Supabase proje URL'i                            |
| `SUPABASE_ANON_KEY`       | Supabase anon key                               |
| `MAPBOX_ACCESS_TOKEN`     | Mapbox access token                             |
| `STRAVA_CLIENT_ID`        | Strava OAuth client ID                          |
| `STRAVA_CLIENT_SECRET`    | Strava OAuth client secret                      |

### 5. Supabase OAuth Ayarları

Supabase Dashboard > Authentication > URL Configuration:

- Site URL: `https://app.rivlus.com`
- Redirect URLs'e ekleyin:
  - `https://app.rivlus.com/auth/callback`
  - `https://app.rivlus.com/reset-password`

## Deploy

### rivlus-site (rivlus.com) ile fark

| | **rivlus-site** | **TCR web (app.rivlus.com)** |
|---|---|---|
| Proje türü | Statik site (HTML/JS) | Flutter web uygulaması |
| Deploy | Repo root’a push → Vercel doğrudan yayınlar | Önce `flutter build web` gerekir, çıktı `build/web/` |
| Senin yaptığın | `cd rivlus-site` → `git add .` → `commit` → `push` | Aşağıdaki iki yoldan biri |

TCR web’de **sadece `web/` klasörüne push yapmak yetmez**; yayınlanan dosyalar `build/web/` içinde oluşur ve bunlar `flutter build web` ile üretilir.

---

### Yöntem 1: Otomatik (önerilen) — push ile güncelleme

**Evet, önce Git’e atman gerekir.** Deploy, push’tan sonra tetiklenir: GitHub Actions repo’daki güncel kodu alır, build eder ve Vercel’e yollar. Yani yaptığın değişiklikler (WEB_DEPLOY.md, kod, web ikonları vb.) önce commit + push edilmiş olmalı.

Proje **kök dizininden** (project_tcr), `main` branch’e push et:

```bash
cd /Users/deskiyazilim/development/project_tcr   # proje kökü, web/ değil
git add .
git commit -m "update"
git push origin main
```

GitHub Actions otomatik olarak:

1. `flutter build web --release` çalıştırır
2. `build/web/` çıktısını Vercel’e deploy eder
3. app.rivlus.com güncellenir

Yani rivlus-site’ta yaptığın gibi “push atınca güncelleniyor” mantığı burada da geçerli; tek fark push’u **project_tcr** repo’sunun kökünden yapıyorsun, `web/` içinden değil.

---

### Yöntem 2: Manuel deploy

Git push kullanmadan doğrudan Vercel’e atmak istersen:

```bash
cd /Users/deskiyazilim/development/project_tcr

# 1. Web build (gerekirse env için --dart-define kullan)
flutter build web --release

# 2. Build çıktısına girip Vercel’e at
cd build/web
cp ../../vercel-web.json ./vercel.json
vercel deploy --prod
```

## Sık sorulanlar

**“project_tcr içinde rivlus-site klasörü var; push atarsam rivlus-site da gidecek, sorun olmaz mı?”**  
Olmez. İki site ayrı Vercel projelerine bağlı:
- **app.rivlus.com** → Bu repo’ya (project_tcr) bağlı; push’ta sadece **Flutter build** çalışır, `build/web/` deploy edilir.
- **rivlus.com** → Muhtemelen ayrı bir repo veya aynı repo’da farklı root; kendi deploy ayarına göre yayınlanır.

project_tcr’dan `git push` yaptığında sadece TCR web (app.rivlus.com) güncellenir. rivlus-site’ı ayrıca güncellemek istersen `cd rivlus-site` → kendi repo’suna push edersin (rivlus-site’ın kendi git’i varsa).

## Notlar

- Mevcut `rivlus-site` (rivlus.com) etkilenmez
- AASA ve assetlinks dosyaları rivlus.com'da kalır (mobil deep links)
- Web uygulamasında mapbox yerine flutter_map kullanılır
- Apple Watch, Health, bildirimler web'de devre dışıdır
