import 'dart:math';

/// VDOT Calculator
/// 
/// VDOT, bir koşucunun fitness seviyesini ölçen bir değerdir.
/// Yarış performansına dayanarak hesaplanır.
/// Eşik (threshold) pace hesaplanır; diğer antrenman türlerinin pace'leri
/// training_types tablosundaki offset değerleriyle türetilir.
class VdotCalculator {
  VdotCalculator._();

  /// Yarış sonucundan VDOT hesapla
  /// 
  /// [distanceMeters] - Yarış mesafesi (metre)
  /// [durationSeconds] - Yarış süresi (saniye)
  static double calculateFromRace(double distanceMeters, int durationSeconds) {
    if (distanceMeters <= 0 || durationSeconds <= 0) return 0;

    final timeMinutes = durationSeconds / 60.0;
    final velocity = distanceMeters / timeMinutes; // m/min

    // Jack Daniels formülü
    // VO2 = -4.60 + 0.182258 * velocity + 0.000104 * velocity^2
    final vo2 = -4.60 + 0.182258 * velocity + 0.000104 * pow(velocity, 2);

    // Percent VO2max
    // %VO2max = 0.8 + 0.1894393 * e^(-0.012778 * time) + 0.2989558 * e^(-0.1932605 * time)
    final percentVo2max = 0.8 +
        0.1894393 * exp(-0.012778 * timeMinutes) +
        0.2989558 * exp(-0.1932605 * timeMinutes);

    // VDOT = VO2 / %VO2max
    final vdot = vo2 / percentVo2max;
    final clampedVdot = vdot.clamp(20.0, 85.0);

    return clampedVdot;
  }

  /// Standart yarış mesafeleri
  static const Map<String, double> standardDistances = {
    '1.5K': 1500,
    '3K': 3000,
    '5K': 5000,
    '10K': 10000,
    '15K': 15000,
    '21K': 21097.5,
    '42K': 42195,
  };

  /// VDOT'tan eşik (threshold) pace hesapla (saniye/km)
  /// %88 VO2max yoğunluğunda hesaplanır.
  static int getThresholdPace(double vdot) {
    if (vdot <= 0) return 0;
    return _calculatePaceFromVdot(vdot, 0.88).round();
  }

  /// Eşik pace + offset'lerden pace aralığı hesapla.
  /// Dönen tuple: (hızlı pace sn/km, yavaş pace sn/km).
  /// Offset null ise null döner (Fartlek gibi değişken türler).
  static (int paceMinSec, int paceMaxSec)? getPaceRangeFromOffsets(
    double vdot,
    int? offsetMin,
    int? offsetMax,
  ) {
    if (vdot <= 0 || offsetMin == null || offsetMax == null) return null;
    final threshold = getThresholdPace(vdot);
    if (threshold <= 0) return null;
    return (threshold + offsetMin, threshold + offsetMax);
  }

  /// Pace aralığını formatlanmış string olarak döndür.
  /// Örnek: "4:30 / 4:45"
  static String? formatPaceRange(
    double vdot,
    int? offsetMin,
    int? offsetMax,
  ) {
    final range = getPaceRangeFromOffsets(vdot, offsetMin, offsetMax);
    if (range == null) return null;
    if (range.$1 == range.$2) {
      // Offset'ler aynıysa (threshold gibi) tek değer göster
      return formatPace(range.$1);
    }
    return '${formatPace(range.$1)} / ${formatPace(range.$2)}';
  }

  /// Segment türüne göre pace önerisi (offset bazlı).
  /// Isınma, Toparlanma, Soğuma için easy/recovery pace (sabit offset +45/+75).
  /// Ana Antrenman için antrenman türünün offset'leri kullanılır.
  static String? getPaceForSegmentType(
    double vdot,
    String segmentType, // 'warmup', 'main', 'recovery', 'cooldown'
    int? offsetMin,
    int? offsetMax,
  ) {
    if (vdot <= 0) return null;

    final lowerSegmentType = segmentType.toLowerCase();

    // Isınma, Toparlanma, Soğuma için easy/recovery pace aralığı
    // Easy Run offset'leri: +45 / +75 (sabit)
    if (lowerSegmentType == 'warmup' ||
        lowerSegmentType == 'recovery' ||
        lowerSegmentType == 'cooldown') {
      return formatPaceRange(vdot, 45, 75);
    }

    // Ana Antrenman için antrenman türünün offset'lerini kullan
    if (lowerSegmentType == 'main') {
      if (offsetMin != null && offsetMax != null) {
        return formatPaceRange(vdot, offsetMin, offsetMax);
      }
      // Offset yoksa easy pace göster
      return formatPaceRange(vdot, 45, 75);
    }

    return null;
  }

  /// Segment türüne göre pace aralığı (sn/km tuple).
  /// Apple Watch ve export için kullanılır.
  static (int paceMinSec, int paceMaxSec)? getPaceRangeForSegmentType(
    double vdot,
    String segmentType,
    int? offsetMin,
    int? offsetMax,
  ) {
    if (vdot <= 0) return null;

    final lowerSegmentType = segmentType.toLowerCase();

    if (lowerSegmentType == 'warmup' ||
        lowerSegmentType == 'recovery' ||
        lowerSegmentType == 'cooldown') {
      return getPaceRangeFromOffsets(vdot, 45, 75);
    }

    if (lowerSegmentType == 'main') {
      if (offsetMin != null && offsetMax != null) {
        return getPaceRangeFromOffsets(vdot, offsetMin, offsetMax);
      }
      return getPaceRangeFromOffsets(vdot, 45, 75);
    }

    return null;
  }

  /// VDOT ve yoğunluk yüzdesinden pace hesapla (saniye/km)
  static double _calculatePaceFromVdot(double vdot, double intensityPercent) {
    // VO2 from VDOT
    final vo2 = vdot * intensityPercent;

    // Velocity from VO2 (ters formül)
    // VO2 = -4.60 + 0.182258 * v + 0.000104 * v^2
    // 0.000104 * v^2 + 0.182258 * v + (-4.60 - VO2) = 0
    final a = 0.000104;
    final b = 0.182258;
    final c = -4.60 - vo2;

    final discriminant = b * b - 4 * a * c;
    if (discriminant < 0) return 0;

    final velocity = (-b + sqrt(discriminant)) / (2 * a); // m/min

    if (velocity <= 0) return 0;

    // Pace = 1000 / velocity * 60 (saniye/km)
    final paceSecondsPerKm = (1000 / velocity) * 60;

    return paceSecondsPerKm;
  }

  /// Cooper testinden VDOT hesapla
  /// [distanceMeters] - 12 dakikada koşulan mesafe
  static double calculateFromCooperTest(double distanceMeters) {
    // Cooper test 12 dakikadır
    return calculateFromRace(distanceMeters, 12 * 60);
  }

  /// VDOT'tan tahmini yarış süresi hesapla
  /// [vdot] - VDOT değeri
  /// [distanceMeters] - Hedef mesafe
  /// Dönen değer saniye cinsindendir
  static int predictRaceTime(double vdot, double distanceMeters) {
    if (vdot <= 0 || distanceMeters <= 0) return 0;

    // Binary search ile süre tahmin et
    int lowSeconds = 1;
    int highSeconds = 36000; // 10 saat max

    while (lowSeconds < highSeconds) {
      final midSeconds = (lowSeconds + highSeconds) ~/ 2;
      final calculatedVdot = calculateFromRace(distanceMeters, midSeconds);

      if (calculatedVdot < vdot) {
        highSeconds = midSeconds;
      } else {
        lowSeconds = midSeconds + 1;
      }
    }

    return lowSeconds;
  }

  /// Pace'i formatla (saniye -> "mm:ss")
  static String formatPace(int paceSeconds) {
    if (paceSeconds <= 0) return '--:--';
    final minutes = paceSeconds ~/ 60;
    final seconds = paceSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Süreyi formatla (saniye -> "hh:mm:ss" veya "mm:ss")
  static String formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '--:--';
    
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
