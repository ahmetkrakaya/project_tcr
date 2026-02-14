/// Integration Entity
class IntegrationEntity {
  final String id;
  final String userId;
  final IntegrationProvider provider;
  final String? providerUserId;
  final String? athleteName;
  final String? athleteAvatarUrl;
  final DateTime connectedAt;
  final DateTime? lastSyncAt;
  final bool syncEnabled;

  const IntegrationEntity({
    required this.id,
    required this.userId,
    required this.provider,
    this.providerUserId,
    this.athleteName,
    this.athleteAvatarUrl,
    required this.connectedAt,
    this.lastSyncAt,
    this.syncEnabled = true,
  });

  /// Provider adını döndür
  String get providerName {
    switch (provider) {
      case IntegrationProvider.strava:
        return 'Strava';
      case IntegrationProvider.garmin:
        return 'Garmin';
      case IntegrationProvider.appleHealth:
        return 'Apple Health';
      case IntegrationProvider.googleFit:
        return 'Google Fit';
    }
  }

  /// Son senkronizasyon tarihini formatla
  String get formattedLastSync {
    if (lastSyncAt == null) return 'Henüz senkronize edilmedi';
    final now = DateTime.now();
    final diff = now.difference(lastSyncAt!);
    
    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dakika önce';
    if (diff.inHours < 24) return '${diff.inHours} saat önce';
    if (diff.inDays < 7) return '${diff.inDays} gün önce';
    
    return '${lastSyncAt!.day}.${lastSyncAt!.month}.${lastSyncAt!.year}';
  }

  IntegrationEntity copyWith({
    String? id,
    String? userId,
    IntegrationProvider? provider,
    String? providerUserId,
    String? athleteName,
    String? athleteAvatarUrl,
    DateTime? connectedAt,
    DateTime? lastSyncAt,
    bool? syncEnabled,
  }) {
    return IntegrationEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      provider: provider ?? this.provider,
      providerUserId: providerUserId ?? this.providerUserId,
      athleteName: athleteName ?? this.athleteName,
      athleteAvatarUrl: athleteAvatarUrl ?? this.athleteAvatarUrl,
      connectedAt: connectedAt ?? this.connectedAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      syncEnabled: syncEnabled ?? this.syncEnabled,
    );
  }
}

/// Entegrasyon sağlayıcıları
enum IntegrationProvider {
  strava,
  garmin,
  appleHealth,
  googleFit;

  static IntegrationProvider fromString(String value) {
    switch (value.toLowerCase()) {
      case 'strava':
        return IntegrationProvider.strava;
      case 'garmin':
        return IntegrationProvider.garmin;
      case 'apple_health':
        return IntegrationProvider.appleHealth;
      case 'google_fit':
        return IntegrationProvider.googleFit;
      default:
        return IntegrationProvider.strava;
    }
  }

  String toDbString() {
    switch (this) {
      case IntegrationProvider.strava:
        return 'strava';
      case IntegrationProvider.garmin:
        return 'garmin';
      case IntegrationProvider.appleHealth:
        return 'apple_health';
      case IntegrationProvider.googleFit:
        return 'google_fit';
    }
  }
}

/// Strava Athlete Entity
class StravaAthleteEntity {
  final int id;
  final String? firstName;
  final String? lastName;
  final String? profileMedium;
  final String? profile;
  final String? city;
  final String? country;

  const StravaAthleteEntity({
    required this.id,
    this.firstName,
    this.lastName,
    this.profileMedium,
    this.profile,
    this.city,
    this.country,
  });

  String get fullName {
    final parts = <String>[];
    if (firstName != null && firstName!.isNotEmpty) parts.add(firstName!);
    if (lastName != null && lastName!.isNotEmpty) parts.add(lastName!);
    return parts.isEmpty ? 'Strava Kullanıcısı' : parts.join(' ');
  }

  String? get avatarUrl => profile ?? profileMedium;
}

/// Strava Activity Entity (Strava'dan gelen aktivite)
class StravaActivityEntity {
  final int id;
  final String name;
  final String type;
  final double distance; // meters
  final int movingTime; // seconds
  final int elapsedTime; // seconds
  final double totalElevationGain; // meters
  final DateTime startDate;
  final String? mapPolyline;
  final double? averageSpeed; // meters per second
  final double? maxSpeed;
  final double? averageHeartrate;
  final double? maxHeartrate;
  final double? averageCadence;
  final double? calories;
  final double? startLatlng; // Başlangıç enlemi (lat)
  final double? endLatlng; // Bitiş enlemi (lat)
  // Not: Strava [lat, lng] formatında döndürür, şimdilik sadece lat'i alıyoruz
  // İleride tam koordinat çifti için ayrı alanlar eklenebilir

  const StravaActivityEntity({
    required this.id,
    required this.name,
    required this.type,
    required this.distance,
    required this.movingTime,
    required this.elapsedTime,
    required this.totalElevationGain,
    required this.startDate,
    this.mapPolyline,
    this.averageSpeed,
    this.maxSpeed,
    this.averageHeartrate,
    this.maxHeartrate,
    this.averageCadence,
    this.calories,
    this.startLatlng,
    this.endLatlng,
  });

  /// Mesafeyi km olarak döndür
  double get distanceKm => distance / 1000;

  /// Ortalama pace hesapla (saniye/km)
  int? get averagePaceSeconds {
    if (distance <= 0 || movingTime <= 0) return null;
    final km = distance / 1000;
    return (movingTime / km).round();
  }

  /// Pace formatla (mm:ss /km)
  String get formattedPace {
    final pace = averagePaceSeconds;
    if (pace == null) return '--:--';
    final minutes = pace ~/ 60;
    final seconds = pace % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Süreyi formatla
  String get formattedDuration {
    final hours = movingTime ~/ 3600;
    final minutes = (movingTime % 3600) ~/ 60;
    final seconds = movingTime % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }
}

/// Strava Activity Detail Entity
class StravaActivityDetailEntity {
  final StravaActivityEntity activity;
  final List<StravaSplitEntity> splits;
  final List<StravaBestEffortEntity> bestEfforts;
  final List<StravaSegmentEffortEntity> segmentEfforts;
  final String? description;

  const StravaActivityDetailEntity({
    required this.activity,
    this.splits = const [],
    this.bestEfforts = const [],
    this.segmentEfforts = const [],
    this.description,
  });
}

/// Strava Split Entity
class StravaSplitEntity {
  final int split;
  final double distance; // meters
  final int elapsedTime; // seconds
  final int movingTime; // seconds
  final double? averageSpeed; // m/s
  final double? elevationDifference; // meters
  final double? averageHeartrate;
  final double? maxHeartrate;
  final int? paceZone;

  const StravaSplitEntity({
    required this.split,
    required this.distance,
    required this.elapsedTime,
    required this.movingTime,
    this.averageSpeed,
    this.elevationDifference,
    this.averageHeartrate,
    this.maxHeartrate,
    this.paceZone,
  });

  /// Pace hesapla (saniye/km)
  int? get paceSeconds {
    if (distance <= 0 || movingTime <= 0) return null;
    final km = distance / 1000;
    return (movingTime / km).round();
  }

  /// Pace formatla (mm:ss /km)
  String get formattedPace {
    final pace = paceSeconds;
    if (pace == null) return '--:--';
    final minutes = pace ~/ 60;
    final seconds = pace % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Strava Best Effort Entity
class StravaBestEffortEntity {
  final int id;
  final String name; // "400m", "1km", "5km", "10km", "Half Marathon", "Marathon" vb.
  final double distance; // meters
  final int movingTime; // seconds
  final int elapsedTime; // seconds
  final double? averageSpeed; // m/s
  final double? maxSpeed; // m/s
  final double? averageHeartrate;
  final double? maxHeartrate;
  final int? prRank; // Personal record rank (null if not a PR)
  final bool isPersonalRecord;

  const StravaBestEffortEntity({
    required this.id,
    required this.name,
    required this.distance,
    required this.movingTime,
    required this.elapsedTime,
    this.averageSpeed,
    this.maxSpeed,
    this.averageHeartrate,
    this.maxHeartrate,
    this.prRank,
    this.isPersonalRecord = false,
  });

  /// Pace hesapla (saniye/km)
  int? get paceSeconds {
    if (distance <= 0 || movingTime <= 0) return null;
    final km = distance / 1000;
    return (movingTime / km).round();
  }

  /// Pace formatla (mm:ss /km)
  String get formattedPace {
    final pace = paceSeconds;
    if (pace == null) return '--:--';
    final minutes = pace ~/ 60;
    final seconds = pace % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Süreyi formatla
  String get formattedTime {
    final hours = movingTime ~/ 3600;
    final minutes = (movingTime % 3600) ~/ 60;
    final seconds = movingTime % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Strava Segment Effort Entity
class StravaSegmentEffortEntity {
  final int id;
  final String name;
  final double distance; // meters
  final int movingTime; // seconds
  final int elapsedTime; // seconds
  final double? averageSpeed; // m/s
  final double? maxSpeed; // m/s
  final double? averageHeartrate;
  final double? maxHeartrate;
  final int? prRank;
  final int? komRank; // King of the Mountain rank
  final int? qomRank; // Queen of the Mountain rank

  const StravaSegmentEffortEntity({
    required this.id,
    required this.name,
    required this.distance,
    required this.movingTime,
    required this.elapsedTime,
    this.averageSpeed,
    this.maxSpeed,
    this.averageHeartrate,
    this.maxHeartrate,
    this.prRank,
    this.komRank,
    this.qomRank,
  });

  /// Pace hesapla (saniye/km)
  int? get paceSeconds {
    if (distance <= 0 || movingTime <= 0) return null;
    final km = distance / 1000;
    return (movingTime / km).round();
  }

  /// Pace formatla (mm:ss /km)
  String get formattedPace {
    final pace = paceSeconds;
    if (pace == null) return '--:--';
    final minutes = pace ~/ 60;
    final seconds = pace % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Strava Heart Zone Entity
class StravaHeartZoneEntity {
  final int min;
  final int max;
  final int time; // seconds spent in this zone

  const StravaHeartZoneEntity({
    required this.min,
    required this.max,
    required this.time,
  });

  /// Zone adı (index'e göre belirlenir, bu getter artık kullanılmıyor)
  /// UI'da zone index'i kullanılarak doğru isimlendirme yapılıyor
  @Deprecated('Use zone index from list instead')
  String get zoneName {
    // Bu getter artık kullanılmıyor, zone index'i kullanılıyor
    return 'Zone';
  }

  /// Süreyi formatla (dakika)
  String get formattedTime {
    final minutes = time ~/ 60;
    return '$minutes dk';
  }

  /// Süreyi formatla (saat:dakika)
  String get formattedTimeDetailed {
    final hours = time ~/ 3600;
    final minutes = (time % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}s ${minutes}dk';
    }
    return '${minutes}dk';
  }
}
