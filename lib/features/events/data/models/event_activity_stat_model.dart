/// Event Activity Stat Model
///
/// Belirli bir etkinliğe ait aktivitelerden kullanıcı bazında
/// özet istatistikleri tutar.
class EventActivityStatModel {
  final String userId;
  final String userName;
  final String? avatarUrl;
  /// Toplam mesafe (metre)
  final double totalDistanceMeters;
  /// Toplam süre (saniye)
  final int totalDurationSeconds;
  /// Ortalama pace (saniye / km) - null olabilir
  final double? averagePaceSecondsPerKm;

  const EventActivityStatModel({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    required this.averagePaceSecondsPerKm,
  });
}

