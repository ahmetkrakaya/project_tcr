import '../../domain/entities/integration_entity.dart';

/// Strava Token Response Model
class StravaTokenResponse {
  final String tokenType;
  final int expiresAt;
  final int expiresIn;
  final String refreshToken;
  final String accessToken;
  final StravaAthleteModel athlete;

  const StravaTokenResponse({
    required this.tokenType,
    required this.expiresAt,
    required this.expiresIn,
    required this.refreshToken,
    required this.accessToken,
    required this.athlete,
  });

  factory StravaTokenResponse.fromJson(Map<String, dynamic> json) {
    return StravaTokenResponse(
      tokenType: json['token_type'] as String,
      expiresAt: json['expires_at'] as int,
      expiresIn: json['expires_in'] as int,
      refreshToken: json['refresh_token'] as String,
      accessToken: json['access_token'] as String,
      athlete: StravaAthleteModel.fromJson(json['athlete'] as Map<String, dynamic>),
    );
  }

  DateTime get expiresAtDateTime =>
      DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
}

/// Strava Refresh Token Response Model
class StravaRefreshTokenResponse {
  final String tokenType;
  final int expiresAt;
  final int expiresIn;
  final String refreshToken;
  final String accessToken;

  const StravaRefreshTokenResponse({
    required this.tokenType,
    required this.expiresAt,
    required this.expiresIn,
    required this.refreshToken,
    required this.accessToken,
  });

  factory StravaRefreshTokenResponse.fromJson(Map<String, dynamic> json) {
    return StravaRefreshTokenResponse(
      tokenType: json['token_type'] as String,
      expiresAt: json['expires_at'] as int,
      expiresIn: json['expires_in'] as int,
      refreshToken: json['refresh_token'] as String,
      accessToken: json['access_token'] as String,
    );
  }

  DateTime get expiresAtDateTime =>
      DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
}

/// Strava Athlete Model
class StravaAthleteModel {
  final int id;
  final String? username;
  final String? firstname;
  final String? lastname;
  final String? bio;
  final String? city;
  final String? state;
  final String? country;
  final String? sex;
  final bool? premium;
  final bool? summit;
  final String? profileMedium;
  final String? profile;

  const StravaAthleteModel({
    required this.id,
    this.username,
    this.firstname,
    this.lastname,
    this.bio,
    this.city,
    this.state,
    this.country,
    this.sex,
    this.premium,
    this.summit,
    this.profileMedium,
    this.profile,
  });

  factory StravaAthleteModel.fromJson(Map<String, dynamic> json) {
    return StravaAthleteModel(
      id: json['id'] as int,
      username: json['username'] as String?,
      firstname: json['firstname'] as String?,
      lastname: json['lastname'] as String?,
      bio: json['bio'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      country: json['country'] as String?,
      sex: json['sex'] as String?,
      premium: json['premium'] as bool?,
      summit: json['summit'] as bool?,
      profileMedium: json['profile_medium'] as String?,
      profile: json['profile'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'firstname': firstname,
      'lastname': lastname,
      'bio': bio,
      'city': city,
      'state': state,
      'country': country,
      'sex': sex,
      'premium': premium,
      'summit': summit,
      'profile_medium': profileMedium,
      'profile': profile,
    };
  }

  StravaAthleteEntity toEntity() {
    return StravaAthleteEntity(
      id: id,
      firstName: firstname,
      lastName: lastname,
      profileMedium: profileMedium,
      profile: profile,
      city: city,
      country: country,
    );
  }

  String get fullName {
    final parts = <String>[];
    if (firstname != null && firstname!.isNotEmpty) parts.add(firstname!);
    if (lastname != null && lastname!.isNotEmpty) parts.add(lastname!);
    return parts.isEmpty ? 'Strava Kullanıcısı' : parts.join(' ');
  }
}

/// Strava Activity Model
class StravaActivityModel {
  final int id;
  final String name;
  final double distance;
  final int movingTime;
  final int elapsedTime;
  final double totalElevationGain;
  final String type;
  final String sportType;
  final DateTime startDate;
  final DateTime startDateLocal;
  final String? timezone;
  final double? startLatlng;
  final double? endLatlng;
  final int? achievementCount;
  final int? kudosCount;
  final int? commentCount;
  final int? athleteCount;
  final int? photoCount;
  final StravaMapModel? map;
  final bool trainer;
  final bool commute;
  final bool manual;
  final bool private_;
  final double? averageSpeed;
  final double? maxSpeed;
  final double? averageCadence;
  final double? averageHeartrate;
  final double? maxHeartrate;
  final double? kilojoules;
  final double? calories;

  const StravaActivityModel({
    required this.id,
    required this.name,
    required this.distance,
    required this.movingTime,
    required this.elapsedTime,
    required this.totalElevationGain,
    required this.type,
    required this.sportType,
    required this.startDate,
    required this.startDateLocal,
    this.timezone,
    this.startLatlng,
    this.endLatlng,
    this.achievementCount,
    this.kudosCount,
    this.commentCount,
    this.athleteCount,
    this.photoCount,
    this.map,
    this.trainer = false,
    this.commute = false,
    this.manual = false,
    this.private_ = false,
    this.averageSpeed,
    this.maxSpeed,
    this.averageCadence,
    this.averageHeartrate,
    this.maxHeartrate,
    this.kilojoules,
    this.calories,
  });

  factory StravaActivityModel.fromJson(Map<String, dynamic> json) {
    return StravaActivityModel(
      id: json['id'] as int,
      name: json['name'] as String,
      distance: (json['distance'] as num).toDouble(),
      movingTime: json['moving_time'] as int,
      elapsedTime: json['elapsed_time'] as int,
      totalElevationGain: (json['total_elevation_gain'] as num).toDouble(),
      type: json['type'] as String,
      sportType: json['sport_type'] as String? ?? json['type'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      startDateLocal: DateTime.parse(json['start_date_local'] as String),
      timezone: json['timezone'] as String?,
      // start_latlng ve end_latlng [lat, lng] formatında liste olarak gelir
      startLatlng: json['start_latlng'] != null && (json['start_latlng'] as List).length >= 2
          ? (json['start_latlng'] as List)[0] as double?
          : null,
      endLatlng: json['end_latlng'] != null && (json['end_latlng'] as List).length >= 2
          ? (json['end_latlng'] as List)[0] as double?
          : null,
      achievementCount: json['achievement_count'] as int?,
      kudosCount: json['kudos_count'] as int?,
      commentCount: json['comment_count'] as int?,
      athleteCount: json['athlete_count'] as int?,
      photoCount: json['photo_count'] as int?,
      map: json['map'] != null
          ? StravaMapModel.fromJson(json['map'] as Map<String, dynamic>)
          : null,
      trainer: json['trainer'] as bool? ?? false,
      commute: json['commute'] as bool? ?? false,
      manual: json['manual'] as bool? ?? false,
      private_: json['private'] as bool? ?? false,
      averageSpeed: (json['average_speed'] as num?)?.toDouble(),
      maxSpeed: (json['max_speed'] as num?)?.toDouble(),
      averageCadence: (json['average_cadence'] as num?)?.toDouble(),
      averageHeartrate: (json['average_heartrate'] as num?)?.toDouble(),
      maxHeartrate: (json['max_heartrate'] as num?)?.toDouble(),
      kilojoules: (json['kilojoules'] as num?)?.toDouble(),
      calories: (json['calories'] as num?)?.toDouble(),
    );
  }

  StravaActivityEntity toEntity() {
    return StravaActivityEntity(
      id: id,
      name: name,
      type: type,
      distance: distance,
      movingTime: movingTime,
      elapsedTime: elapsedTime,
      totalElevationGain: totalElevationGain,
      startDate: startDateLocal,
      mapPolyline: map?.summaryPolyline,
      averageSpeed: averageSpeed,
      maxSpeed: maxSpeed,
      averageHeartrate: averageHeartrate,
      maxHeartrate: maxHeartrate,
      averageCadence: averageCadence,
      calories: calories,
      startLatlng: startLatlng,
      endLatlng: endLatlng,
    );
  }

  /// Strava aktivite tipini uygulama aktivite tipine dönüştür
  String get activityTypeForDb {
    switch (type.toLowerCase()) {
      case 'run':
      case 'virtualrun':
      case 'trailrun':
        return 'running';
      case 'walk':
      case 'hike':
        return 'walking';
      case 'ride':
      case 'virtualride':
      case 'ebikeride':
      case 'mountainbikeride':
      case 'gravelride':
        return 'cycling';
      case 'swim':
        return 'swimming';
      case 'weighttraining':
      case 'crossfit':
        return 'strength';
      case 'yoga':
        return 'yoga';
      default:
        return 'other';
    }
  }

  /// Pace hesapla (saniye/km)
  int? get paceSeconds {
    if (distance <= 0 || movingTime <= 0) return null;
    final km = distance / 1000;
    return (movingTime / km).round();
  }
}

/// Strava Map Model
class StravaMapModel {
  final String id;
  final String? summaryPolyline;
  final String? polyline;

  const StravaMapModel({
    required this.id,
    this.summaryPolyline,
    this.polyline,
  });

  factory StravaMapModel.fromJson(Map<String, dynamic> json) {
    return StravaMapModel(
      id: json['id'] as String,
      summaryPolyline: json['summary_polyline'] as String?,
      polyline: json['polyline'] as String?,
    );
  }
}

/// Strava Activity Detail Model (Detaylı aktivite bilgisi)
class StravaActivityDetailModel {
  final StravaActivityModel activity;
  final List<StravaSplitModel> splits;
  final List<StravaBestEffortModel> bestEfforts;
  final List<StravaSegmentEffortModel> segmentEfforts;
  final String? description;

  const StravaActivityDetailModel({
    required this.activity,
    this.splits = const [],
    this.bestEfforts = const [],
    this.segmentEfforts = const [],
    this.description,
  });

  factory StravaActivityDetailModel.fromJson(Map<String, dynamic> json) {
    return StravaActivityDetailModel(
      activity: StravaActivityModel.fromJson(json),
      splits: json['splits_metric'] != null
          ? (json['splits_metric'] as List)
              .map((s) => StravaSplitModel.fromJson(s as Map<String, dynamic>))
              .toList()
          : [],
      bestEfforts: json['best_efforts'] != null
          ? (json['best_efforts'] as List)
              .map((e) => StravaBestEffortModel.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      segmentEfforts: json['segment_efforts'] != null
          ? (json['segment_efforts'] as List)
              .map((e) => StravaSegmentEffortModel.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      description: json['description'] as String?,
    );
  }

  /// Entity'ye dönüştür
  StravaActivityDetailEntity toEntity() {
    return StravaActivityDetailEntity(
      activity: activity.toEntity(),
      splits: splits.map((s) => s.toEntity()).toList(),
      bestEfforts: bestEfforts.map((e) => e.toEntity()).toList(),
      segmentEfforts: segmentEfforts.map((e) => e.toEntity()).toList(),
      description: description,
    );
  }
}

/// Strava Split Model (Kilometre bazlı bölümler)
class StravaSplitModel {
  final int split;
  final double distance; // meters
  final int elapsedTime; // seconds
  final int movingTime; // seconds
  final double? averageSpeed; // m/s
  final double? averageGradeAdjustedSpeed; // m/s
  final double? elevationDifference; // meters
  final double? averageHeartrate;
  final double? maxHeartrate;
  final int? paceZone;

  const StravaSplitModel({
    required this.split,
    required this.distance,
    required this.elapsedTime,
    required this.movingTime,
    this.averageSpeed,
    this.averageGradeAdjustedSpeed,
    this.elevationDifference,
    this.averageHeartrate,
    this.maxHeartrate,
    this.paceZone,
  });

  factory StravaSplitModel.fromJson(Map<String, dynamic> json) {
    return StravaSplitModel(
      split: json['split'] as int,
      distance: (json['distance'] as num).toDouble(),
      elapsedTime: json['elapsed_time'] as int,
      movingTime: json['moving_time'] as int,
      averageSpeed: (json['average_speed'] as num?)?.toDouble(),
      averageGradeAdjustedSpeed: (json['average_grade_adjusted_speed'] as num?)?.toDouble(),
      elevationDifference: (json['elevation_difference'] as num?)?.toDouble(),
      averageHeartrate: (json['average_heartrate'] as num?)?.toDouble(),
      maxHeartrate: (json['max_heartrate'] as num?)?.toDouble(),
      paceZone: json['pace_zone'] as int?,
    );
  }

  /// Pace hesapla (saniye/km)
  int? get paceSeconds {
    if (distance <= 0 || movingTime <= 0) return null;
    final km = distance / 1000;
    return (movingTime / km).round();
  }

  /// Entity'ye dönüştür
  StravaSplitEntity toEntity() {
    return StravaSplitEntity(
      split: split,
      distance: distance,
      elapsedTime: elapsedTime,
      movingTime: movingTime,
      averageSpeed: averageSpeed,
      elevationDifference: elevationDifference,
      averageHeartrate: averageHeartrate,
      maxHeartrate: maxHeartrate,
      paceZone: paceZone,
    );
  }
}

/// Strava Best Effort Model (En iyi performanslar)
class StravaBestEffortModel {
  final int id;
  final int resourceState;
  final String name; // "400m", "1/2 mile", "1km", "1 mile", "5km", "10km", "15km", "20km", "Half Marathon", "25km", "30km", "Marathon", "50km", "100km"
  final double distance; // meters
  final int movingTime; // seconds
  final int elapsedTime; // seconds
  final double? averageSpeed; // m/s
  final double? maxSpeed; // m/s
  final double? averageHeartrate;
  final double? maxHeartrate;
  final int? prRank; // Personal record rank (null if not a PR)
  final int? achievements;

  const StravaBestEffortModel({
    required this.id,
    required this.resourceState,
    required this.name,
    required this.distance,
    required this.movingTime,
    required this.elapsedTime,
    this.averageSpeed,
    this.maxSpeed,
    this.averageHeartrate,
    this.maxHeartrate,
    this.prRank,
    this.achievements,
  });

  factory StravaBestEffortModel.fromJson(Map<String, dynamic> json) {
    // achievements bir liste olabilir, sayısını al
    int? achievementsCount;
    if (json['achievements'] != null) {
      if (json['achievements'] is List) {
        achievementsCount = (json['achievements'] as List).length;
      } else if (json['achievements'] is int) {
        achievementsCount = json['achievements'] as int;
      }
    }

    return StravaBestEffortModel(
      id: json['id'] as int,
      resourceState: json['resource_state'] as int? ?? 2,
      name: json['name'] as String,
      distance: (json['distance'] as num).toDouble(),
      movingTime: json['moving_time'] as int,
      elapsedTime: json['elapsed_time'] as int,
      averageSpeed: (json['average_speed'] as num?)?.toDouble(),
      maxSpeed: (json['max_speed'] as num?)?.toDouble(),
      averageHeartrate: (json['average_heartrate'] as num?)?.toDouble(),
      maxHeartrate: (json['max_heartrate'] as num?)?.toDouble(),
      prRank: json['pr_rank'] as int?,
      achievements: achievementsCount,
    );
  }

  /// Pace hesapla (saniye/km)
  int? get paceSeconds {
    if (distance <= 0 || movingTime <= 0) return null;
    final km = distance / 1000;
    return (movingTime / km).round();
  }

  /// Personal Record mu?
  bool get isPersonalRecord => prRank != null;

  /// Entity'ye dönüştür
  StravaBestEffortEntity toEntity() {
    return StravaBestEffortEntity(
      id: id,
      name: name,
      distance: distance,
      movingTime: movingTime,
      elapsedTime: elapsedTime,
      averageSpeed: averageSpeed,
      maxSpeed: maxSpeed,
      averageHeartrate: averageHeartrate,
      maxHeartrate: maxHeartrate,
      prRank: prRank,
      isPersonalRecord: isPersonalRecord,
    );
  }
}

/// Strava Segment Effort Model (Segment performansları)
class StravaSegmentEffortModel {
  final int id;
  final int resourceState;
  final String name;
  final double distance; // meters
  final int movingTime; // seconds
  final int elapsedTime; // seconds
  final double? averageSpeed; // m/s
  final double? maxSpeed; // m/s
  final double? averageHeartrate;
  final double? maxHeartrate;
  final int? prRank;
  final int? achievements;
  final int? komRank; // King of the Mountain rank
  final int? qomRank; // Queen of the Mountain rank

  const StravaSegmentEffortModel({
    required this.id,
    required this.resourceState,
    required this.name,
    required this.distance,
    required this.movingTime,
    required this.elapsedTime,
    this.averageSpeed,
    this.maxSpeed,
    this.averageHeartrate,
    this.maxHeartrate,
    this.prRank,
    this.achievements,
    this.komRank,
    this.qomRank,
  });

  factory StravaSegmentEffortModel.fromJson(Map<String, dynamic> json) {
    // achievements bir liste olabilir, sayısını al
    int? achievementsCount;
    if (json['achievements'] != null) {
      if (json['achievements'] is List) {
        achievementsCount = (json['achievements'] as List).length;
      } else if (json['achievements'] is int) {
        achievementsCount = json['achievements'] as int;
      }
    }

    return StravaSegmentEffortModel(
      id: json['id'] as int,
      resourceState: json['resource_state'] as int? ?? 2,
      name: json['name'] as String,
      distance: (json['distance'] as num).toDouble(),
      movingTime: json['moving_time'] as int,
      elapsedTime: json['elapsed_time'] as int,
      averageSpeed: (json['average_speed'] as num?)?.toDouble(),
      maxSpeed: (json['max_speed'] as num?)?.toDouble(),
      averageHeartrate: (json['average_heartrate'] as num?)?.toDouble(),
      maxHeartrate: (json['max_heartrate'] as num?)?.toDouble(),
      prRank: json['pr_rank'] as int?,
      achievements: achievementsCount,
      komRank: json['kom_rank'] as int?,
      qomRank: json['qom_rank'] as int?,
    );
  }

  /// Pace hesapla (saniye/km)
  int? get paceSeconds {
    if (distance <= 0 || movingTime <= 0) return null;
    final km = distance / 1000;
    return (movingTime / km).round();
  }

  /// Entity'ye dönüştür
  StravaSegmentEffortEntity toEntity() {
    return StravaSegmentEffortEntity(
      id: id,
      name: name,
      distance: distance,
      movingTime: movingTime,
      elapsedTime: elapsedTime,
      averageSpeed: averageSpeed,
      maxSpeed: maxSpeed,
      averageHeartrate: averageHeartrate,
      maxHeartrate: maxHeartrate,
      prRank: prRank,
      komRank: komRank,
      qomRank: qomRank,
    );
  }
}

/// Strava Heart Zone Model
class StravaHeartZoneModel {
  final int min;
  final int max;
  final int time; // seconds spent in this zone

  const StravaHeartZoneModel({
    required this.min,
    required this.max,
    required this.time,
  });

  factory StravaHeartZoneModel.fromJson(Map<String, dynamic> json) {
    // Strava zones distribution_buckets formatında geliyor
    // {min: 0, max: 124, time: 930.0} gibi
    // time double olarak gelebilir, int'e çeviriyoruz
    int minValue = 0;
    int maxValue = 0;
    int timeValue = 0;

    if (json['min'] != null) {
      minValue = (json['min'] as num).toInt();
    }
    if (json['max'] != null) {
      // max -1 olabilir (son zone için "ve üzeri" anlamına gelir)
      final maxNum = json['max'] as num;
      maxValue = maxNum.toInt();
    }
    if (json['time'] != null) {
      // time double olarak gelebilir (930.0 gibi)
      timeValue = (json['time'] as num).toInt();
    }

    return StravaHeartZoneModel(
      min: minValue,
      max: maxValue,
      time: timeValue,
    );
  }

  /// Zone adı (Zone 1, Zone 2, vb.)
  String get zoneName {
    if (max <= 60) return 'Zone 1 (Recovery)';
    if (max <= 70) return 'Zone 2 (Aerobic)';
    if (max <= 80) return 'Zone 3 (Tempo)';
    if (max <= 90) return 'Zone 4 (Threshold)';
    return 'Zone 5 (VO2 Max)';
  }

  /// Entity'ye dönüştür
  StravaHeartZoneEntity toEntity() {
    return StravaHeartZoneEntity(
      min: min,
      max: max,
      time: time,
    );
  }
}
