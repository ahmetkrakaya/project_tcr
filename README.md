# TCR - Twenty City Runners

Koşu kulübü mobil uygulaması - Flutter & Supabase

## Özellikler

### 🔐 Kimlik Doğrulama
- Google ve Apple ile giriş
- Referans kodu sistemi
- Profil yönetimi
- ICE (Acil Durum) kartı

### 📅 Etkinlik Yönetimi
- Dinamik takvim
- RSVP sistemi
- Antrenman grupları
- Hava durumu entegrasyonu

### 🚗 Ulaşım İmecesi (Carpooling)
- Araç paylaşımı
- Kalkış noktaları
- Otomatik eşleştirme

### 🗺️ Harita & Rota
- GPX dosya desteği
- 2D/3D harita görünümü
- Yükseklik profili
- flutter_map (OpenStreetMap) ile harita ve rota

### 💬 İletişim
- Genel sohbet (Lobby)
- Grup odaları
- Etkinlik sohbetleri
- Anonim soru-cevap

### 🏃 Aktivite Takibi
- Health Connect / HealthKit entegrasyonu
- TCR Feed
- Lider tablosu
- İstatistikler

### 📸 Fotoğraf Galerisi
- Etkinlik albümleri
- Yüksek kalite depolama
- Supabase Storage

### 🛒 Pazar Yeri
- İkinci el ürünler
- Sıcak fırsatlar
- Ayakkabı/beden eşleştirme

### 🧮 Araçlar
- Pace hesaplayıcı
- Pist kulvar hesaplayıcı

## Kurulum

### Gereksinimler
- Flutter 3.9+
- Dart 3.0+
- Supabase hesabı

### 1. Bağımlılıkları Yükle
```bash
flutter pub get
```

### 2. Supabase Kurulumu
1. [supabase.com](https://supabase.com) adresinden proje oluşturun
2. `supabase/migrations/` klasöründeki SQL dosyalarını sırayla çalıştırın
3. Authentication > Providers bölümünden Google ve Apple'ı aktifleştirin
4. Storage bölümünden bucket'ları oluşturun:
   - `avatars` (public)
   - `event-photos` (public)
   - `routes` (public)
   - `listing-images` (public)
   - `chat-images` (authenticated)

### 3. Environment Variables
Uygulamayı çalıştırırken aşağıdaki değişkenleri tanımlayın:

```bash
flutter run \
  --dart-define=SUPABASE_URL=your-url \
  --dart-define=SUPABASE_ANON_KEY=your-key \
  --dart-define=OPENWEATHERMAP_API_KEY=your-key
```

### 4. Kod Oluşturma (Code Generation)
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### 5. Uygulamayı Çalıştır
```bash
flutter run
```

## Proje Yapısı

```
lib/
├── core/
│   ├── constants/     # Sabitler
│   ├── errors/        # Hata sınıfları
│   ├── network/       # API client
│   ├── router/        # Go Router
│   ├── theme/         # Tema ve renkler
│   └── utils/         # Yardımcı fonksiyonlar
├── features/
│   ├── auth/          # Kimlik doğrulama
│   ├── events/        # Etkinlikler
│   ├── chat/          # Sohbet
│   ├── maps/          # Haritalar
│   ├── activity/      # Aktiviteler
│   ├── gallery/       # Galeri
│   ├── marketplace/   # Pazar yeri
│   ├── profile/       # Profil
│   ├── home/          # Ana sayfa
│   └── tools/         # Araçlar
├── shared/
│   ├── widgets/       # Paylaşılan widgetlar
│   └── providers/     # Riverpod providers
└── main.dart
```

## Veritabanı Şeması

Migration dosyaları `supabase/migrations/` klasöründe:

1. `001_users_and_roles.sql` - Kullanıcılar ve roller
2. `002_events_and_routes.sql` - Etkinlikler ve rotalar
3. `003_carpooling.sql` - Ulaşım imecesi
4. `004_chat.sql` - Sohbet sistemi
5. `005_activities.sql` - Aktivite takibi
6. `006_marketplace.sql` - Pazar yeri
7. `007_rls_policies.sql` - Güvenlik politikaları
8. `008_storage_buckets.sql` - Depolama politikaları

## Teknolojiler

- **Flutter** - Cross-platform UI
- **Riverpod** - State management
- **Go Router** - Navigation
- **Supabase** - Backend (Auth, Database, Storage, Realtime)
- **flutter_map** - Haritalar (OpenStreetMap)
- **Freezed** - Immutable models

## Lisans

Bu proje TCR kulübüne özeldir.
