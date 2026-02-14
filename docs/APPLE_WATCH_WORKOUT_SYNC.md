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

## Sık karşılaşılan durumlar
- **Desteklenmiyor**: iOS sürümü 17’den düşükse.
- **Yetki Gerekli**: `Bağla / Yetki Ver` ile WorkoutScheduler izni verilmemişse.
- **Plan görünmüyor**:
  - Watch’unuz uygulamayla eşleşmiş olmalı.
  - watchOS sürümü uyumlu olmalı.
  - Aynı antrenman daha önce gönderildiyse Auto Send tekrar göndermeyebilir (idempotency).

