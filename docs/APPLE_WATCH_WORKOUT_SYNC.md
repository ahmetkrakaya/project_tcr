# Apple Watch Antrenman Senkronizasyonu (WorkoutKit)

Bu doküman, uygulamanın Apple Watch `Workout` uygulamasına antrenman planı göndermesini (TrainingPeaks benzeri) test etmek içindir.

## Gereksinimler
- **iOS 17+**
- **watchOS 10+**
- Apple Watch Series 4+

## Uygulama içi ayar (TCR)
1. `Bağlantılar` sayfasına gir.
2. `Apple Watch` kartında **Bağla / Yetki Ver** ile izin ver.
3. Gönderim modunu seç:
   - **Auto Send Workouts**: bugün + 6 gün içindeki antrenmanlar (en yakın 15 plan) otomatik gönderilir.
   - **On-demand Workouts**: etkinlik programından tek tek gönderilir.

## Auto Send (7 gün)
- Auto Send açıkken, uygulama açılışında (veya `Bağlantılar > Şimdi Senkronla`) senkron çalışır.
- Kaynak: **7 gün içindeki antrenman etkinlikleri** ve kullanıcının gruplarına göre filtrelenmiş `event_group_programs`.
- Not: WorkoutKit planlı antrenmanlarda pratik olarak **15 scheduled workout** sınırı olduğu için en yakın 15 antrenman gönderilir.

## On-demand (Tek tek gönder)
1. Bir antrenman etkinliğine gir.
2. `Senin Programın` kartında sağ üst menüden **Apple Watch’a Gönder**’i seç.

## Apple Watch tarafı kontrol
- Apple Watch’ta `Workout` uygulamasına gir.
- `Antrenman` sekmesinde planlı antrenmanların görünmesi gerekir.
- Ayrıca iPhone `Fitness` uygulamasında planlar görünebilir.

## Yinelemeli (interval) antrenmanların görünümü
- Uygulama içindeki tekrar blokları (`repeat` adımları), Apple Watch tarafında **Interval Block** olarak gönderilir.
- Örnek yapı:
  - Isınma (warmup)
  - Yineleme: 2x (Ana Evre + Toparlanma)
  - Soğuma (cooldown)
- Apple Watch `Workout` uygulamasında bu yapı tek bir satırda **“Yineleme x2”** olarak görünür, altında içindeki çalışma ve toparlanma adımları listelenir.

## Test senaryoları

### 1. Basit antrenman (repeat yok)
- 5 dk ısınma, 20 dk ana, 5 dk soğuma içeren basit bir antrenman oluştur.
- Apple Watch’a gönder.
- Watch’taki planda üç adımın ayrı ayrı listelendiğini ve sürelerin doğru olduğunu kontrol et.

### 2. Tek tekrar bloğu
- Yapı:
  - 10 dk ısınma
  - Yineleme: 3x (5 dk ana + 2 dk toparlanma)
  - 5 dk soğuma
- Bu antrenmanı Apple Watch’a gönder:
  - Watch’ta ısınma ve soğumanın ayrı adımlar olarak göründüğünü,
  - Ortadaki kısmın tek satırda **“Yineleme x3”** olarak listelendiğini,
  - Yineleme detayına girildiğinde 5 dk ana + 2 dk toparlanma adımlarının sırasıyla göründüğünü doğrula.

### 3. Garmin entegrasyonunun kontrolü
- Aynı interval antrenmanı Garmin’e de gönder.
- Garmin Connect / saat tarafında:
  - Repeat bloğunun eskiden olduğu gibi **Garmin’in tekrar tipiyle** (örneğin `Repeat x3`) göründüğünü,
  - Adım sayısı ve sürelerin değişmediğini doğrula.

### 4. Debug örnek antrenman
- Geliştirici menüsünden veya kod içindeki `sendDebugSampleWorkout()` fonksiyonunu kullanarak örnek antrenmanı gönder.
- Bu antrenman basit warmup-main-cooldown yapısını içerir; watch’ta blokların doğru yer ve sırada göründüğünü kontrol et.

## Sık karşılaşılan durumlar
- **Desteklenmiyor**: iOS sürümü 17’den düşükse.
- **Yetki Gerekli**: `Bağla / Yetki Ver` ile WorkoutScheduler izni verilmemişse.
- **Plan görünmüyor**:
  - Watch’unuz uygulamayla eşleşmiş olmalı.
  - watchOS sürümü uyumlu olmalı.
  - Aynı antrenman daha önce gönderildiyse Auto Send tekrar göndermeyebilir (idempotency).

