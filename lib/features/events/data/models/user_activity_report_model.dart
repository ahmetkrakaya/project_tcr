/// Kullanıcı Aktivite Raporu Modeli
///
/// Belirli bir tarih aralığında, bir kullanıcının yaptığı
/// tüm aktiviteleri (etkinlik eşleşmesi olsa da olmasa da) temsil eder.
class UserActivityReportModel {
  /// Aktivite ID
  final String activityId;

  /// Aktivitenin bağlı olduğu etkinlik ID'si (varsa)
  final String? eventId;

  /// Aktivitenin bağlı olduğu etkinlik başlığı (varsa)
  final String? eventTitle;

  /// Aktivitenin başlangıç zamanı
  final DateTime startTime;

  /// Toplam mesafe (metre)
  final double distanceMeters;

  /// Toplam süre (saniye)
  final int durationSeconds;

  /// Ortalama pace (saniye / km) - null olabilir
  final double? averagePaceSecondsPerKm;

  const UserActivityReportModel({
    required this.activityId,
    required this.eventId,
    required this.eventTitle,
    required this.startTime,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.averagePaceSecondsPerKm,
  });

  factory UserActivityReportModel.fromJson(Map<String, dynamic> json) {
    return UserActivityReportModel(
      activityId: json['activity_id'] as String,
      eventId: json['event_id'] as String?,
      eventTitle: json['event_title'] as String?,
      startTime: DateTime.parse(json['start_time'] as String),
      distanceMeters: (json['distance_meters'] as num).toDouble(),
      durationSeconds: json['duration_seconds'] as int,
      averagePaceSecondsPerKm:
          (json['average_pace_seconds_per_km'] as num?)?.toDouble(),
    );
  }
}

