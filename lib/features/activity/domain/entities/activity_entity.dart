/// Activity Entity
class ActivityEntity {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final ActivityType activityType;
  final ActivitySource source;
  final String? title;
  final String? description;
  final DateTime startTime;
  final DateTime? endTime;
  final int? durationSeconds;
  final double? distanceMeters;
  final double? elevationGain;
  final int? caloriesBurned;
  final int? averagePaceSeconds;
  final int? bestPaceSeconds;
  final int? averageHeartRate;
  final int? maxHeartRate;
  final int? averageCadence;
  final String? routePolyline;
  final int? feelingRating;
  final String? notes;
  final bool isPublic;
  final String? eventId;
  final String? externalId; // Strava, Garmin vb. harici servis ID'si
  final DateTime createdAt;

  const ActivityEntity({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.activityType,
    required this.source,
    this.title,
    this.description,
    required this.startTime,
    this.endTime,
    this.durationSeconds,
    this.distanceMeters,
    this.elevationGain,
    this.caloriesBurned,
    this.averagePaceSeconds,
    this.bestPaceSeconds,
    this.averageHeartRate,
    this.maxHeartRate,
    this.averageCadence,
    this.routePolyline,
    this.feelingRating,
    this.notes,
    this.isPublic = true,
    this.eventId,
    this.externalId,
    required this.createdAt,
  });

  /// Mesafeyi km olarak döndür
  double get distanceKm => (distanceMeters ?? 0) / 1000;

  /// Süreyi formatla (mm:ss veya hh:mm:ss)
  String get formattedDuration {
    if (durationSeconds == null) return '--:--';
    final hours = durationSeconds! ~/ 3600;
    final minutes = (durationSeconds! % 3600) ~/ 60;
    final seconds = durationSeconds! % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }

  /// Pace'i formatla (mm:ss /km)
  String get formattedPace {
    if (averagePaceSeconds == null) return '--:--';
    final minutes = averagePaceSeconds! ~/ 60;
    final seconds = averagePaceSeconds! % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Best pace'i formatla (mm:ss /km)
  String get formattedBestPace {
    if (bestPaceSeconds == null) return '--:--';
    final minutes = bestPaceSeconds! ~/ 60;
    final seconds = bestPaceSeconds! % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Aktivite tipine göre ikon adı
  String get activityIcon {
    switch (activityType) {
      case ActivityType.running:
        return 'run';
      case ActivityType.walking:
        return 'walk';
      case ActivityType.cycling:
        return 'cycle';
      case ActivityType.swimming:
        return 'swim';
      case ActivityType.strength:
        return 'weight';
      case ActivityType.yoga:
        return 'yoga';
      case ActivityType.other:
        return 'other';
    }
  }

  /// Kaynak cihaz/uygulama adı
  String get sourceName {
    switch (source) {
      case ActivitySource.manual:
        return 'Manuel';
      case ActivitySource.healthConnect:
        return 'Health Connect';
      case ActivitySource.healthkit:
        return 'Apple Health';
      case ActivitySource.strava:
        return 'Strava';
      case ActivitySource.garmin:
        return 'Garmin';
      case ActivitySource.appleWatch:
        return 'Apple Watch';
      case ActivitySource.other:
        return 'Diğer';
    }
  }
}

/// Aktivite türleri
enum ActivityType {
  running,
  walking,
  cycling,
  swimming,
  strength,
  yoga,
  other;

  static ActivityType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'running':
        return ActivityType.running;
      case 'walking':
        return ActivityType.walking;
      case 'cycling':
        return ActivityType.cycling;
      case 'swimming':
        return ActivityType.swimming;
      case 'strength':
        return ActivityType.strength;
      case 'yoga':
        return ActivityType.yoga;
      default:
        return ActivityType.other;
    }
  }
}

/// Aktivite kaynakları
enum ActivitySource {
  manual,
  healthConnect,
  healthkit,
  strava,
  garmin,
  appleWatch,
  other;

  static ActivitySource fromString(String value) {
    switch (value.toLowerCase()) {
      case 'manual':
        return ActivitySource.manual;
      case 'health_connect':
        return ActivitySource.healthConnect;
      case 'healthkit':
        return ActivitySource.healthkit;
      case 'strava':
        return ActivitySource.strava;
      case 'garmin':
        return ActivitySource.garmin;
      case 'apple_watch':
        return ActivitySource.appleWatch;
      default:
        return ActivitySource.other;
    }
  }
}

/// Kullanıcı istatistikleri
class UserStatisticsEntity {
  final String userId;
  final double totalDistanceMeters;
  final int totalDurationSeconds;
  final int totalActivities;
  final double totalElevationGain;
  final double longestRunMeters;
  final int? best5kSeconds;
  final int? best10kSeconds;
  final int? bestHalfMarathonSeconds;
  final int? bestMarathonSeconds;
  final int currentStreakDays;
  final int longestStreakDays;
  final DateTime? lastActivityAt;
  final double thisWeekDistance;
  final double thisMonthDistance;

  const UserStatisticsEntity({
    required this.userId,
    this.totalDistanceMeters = 0,
    this.totalDurationSeconds = 0,
    this.totalActivities = 0,
    this.totalElevationGain = 0,
    this.longestRunMeters = 0,
    this.best5kSeconds,
    this.best10kSeconds,
    this.bestHalfMarathonSeconds,
    this.bestMarathonSeconds,
    this.currentStreakDays = 0,
    this.longestStreakDays = 0,
    this.lastActivityAt,
    this.thisWeekDistance = 0,
    this.thisMonthDistance = 0,
  });

  double get totalDistanceKm => totalDistanceMeters / 1000;
  double get thisWeekDistanceKm => thisWeekDistance / 1000;
  double get thisMonthDistanceKm => thisMonthDistance / 1000;
  
  /// Ortalama pace hesapla (saniye/km)
  int? get averagePaceSeconds {
    if (totalDistanceMeters <= 0 || totalDurationSeconds <= 0) return null;
    final km = totalDistanceMeters / 1000;
    return (totalDurationSeconds / km).round();
  }
  
  /// Pace formatla
  String get formattedAveragePace {
    final pace = averagePaceSeconds;
    if (pace == null) return '--:--';
    final minutes = pace ~/ 60;
    final seconds = pace % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Lider tablosu girişi
class LeaderboardEntryEntity {
  final int rank;
  final String userId;
  final String userName;
  final String? avatarUrl;
  final double totalDistanceMeters;
  final int activityCount;

  const LeaderboardEntryEntity({
    required this.rank,
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.totalDistanceMeters = 0,
    this.activityCount = 0,
  });

  double get totalDistanceKm => totalDistanceMeters / 1000;
}
