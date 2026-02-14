import '../../domain/entities/activity_entity.dart';

/// Activity Model - Supabase JSON mapping
class ActivityModel {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String activityType;
  final String source;
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

  const ActivityModel({
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

  factory ActivityModel.fromJson(Map<String, dynamic> json) {
    // Handle joined user data
    final userData = json['users'] as Map<String, dynamic>?;
    final userName = userData != null 
        ? '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''}'.trim()
        : 'Anonim';

    return ActivityModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      userName: userName.isEmpty ? 'Anonim' : userName,
      userAvatarUrl: userData?['avatar_url'] as String?,
      activityType: json['activity_type'] as String? ?? 'running',
      source: json['source'] as String? ?? 'manual',
      title: json['title'] as String?,
      description: json['description'] as String?,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time'] as String) : null,
      durationSeconds: json['duration_seconds'] as int?,
      distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
      elevationGain: (json['elevation_gain'] as num?)?.toDouble(),
      caloriesBurned: json['calories_burned'] as int?,
      averagePaceSeconds: json['average_pace_seconds'] as int?,
      bestPaceSeconds: json['best_pace_seconds'] as int?,
      averageHeartRate: json['average_heart_rate'] as int?,
      maxHeartRate: json['max_heart_rate'] as int?,
      averageCadence: json['average_cadence'] as int?,
      routePolyline: json['route_polyline'] as String?,
      feelingRating: json['feeling_rating'] as int?,
      notes: json['notes'] as String?,
      isPublic: json['is_public'] as bool? ?? true,
      eventId: json['event_id'] as String?,
      externalId: json['external_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Feed'den gelen veriyi parse et
  factory ActivityModel.fromFeedJson(Map<String, dynamic> json) {
    return ActivityModel(
      id: json['activity_id'] as String,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String? ?? 'Anonim',
      userAvatarUrl: json['avatar_url'] as String?,
      activityType: json['activity_type'] as String? ?? 'running',
      source: json['source'] as String? ?? 'manual',
      title: json['title'] as String?,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time'] as String) : null,
      durationSeconds: json['duration_seconds'] as int?,
      distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
      elevationGain: (json['elevation_gain'] as num?)?.toDouble(),
      caloriesBurned: json['calories_burned'] as int?,
      averagePaceSeconds: json['pace_seconds'] as int?,
      bestPaceSeconds: json['best_pace_seconds'] as int?,
      averageHeartRate: json['average_heart_rate'] as int?,
      maxHeartRate: json['max_heart_rate'] as int?,
      averageCadence: json['average_cadence'] as int?,
      feelingRating: json['feeling_rating'] as int?,
      isPublic: true,
      externalId: null, // Feed'de external_id yok
      createdAt: DateTime.parse(json['start_time'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'activity_type': activityType,
      'source': source,
      'title': title,
      'description': description,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'duration_seconds': durationSeconds,
      'distance_meters': distanceMeters,
      'elevation_gain': elevationGain,
      'calories_burned': caloriesBurned,
      'average_pace_seconds': averagePaceSeconds,
      'best_pace_seconds': bestPaceSeconds,
      'average_heart_rate': averageHeartRate,
      'max_heart_rate': maxHeartRate,
      'average_cadence': averageCadence,
      'route_polyline': routePolyline,
      'feeling_rating': feelingRating,
      'notes': notes,
      'is_public': isPublic,
      'event_id': eventId,
    };
  }

  ActivityEntity toEntity() {
    return ActivityEntity(
      id: id,
      userId: userId,
      userName: userName,
      userAvatarUrl: userAvatarUrl,
      activityType: ActivityType.fromString(activityType),
      source: ActivitySource.fromString(source),
      title: title,
      description: description,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: durationSeconds,
      distanceMeters: distanceMeters,
      elevationGain: elevationGain,
      caloriesBurned: caloriesBurned,
      averagePaceSeconds: averagePaceSeconds,
      bestPaceSeconds: bestPaceSeconds,
      averageHeartRate: averageHeartRate,
      maxHeartRate: maxHeartRate,
      averageCadence: averageCadence,
      routePolyline: routePolyline,
      feelingRating: feelingRating,
      notes: notes,
      isPublic: isPublic,
      eventId: eventId,
      externalId: externalId,
      createdAt: createdAt,
    );
  }
}

/// User Statistics Model
class UserStatisticsModel {
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

  const UserStatisticsModel({
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

  factory UserStatisticsModel.fromJson(Map<String, dynamic> json) {
    return UserStatisticsModel(
      userId: json['user_id'] as String,
      totalDistanceMeters: (json['total_distance_meters'] as num?)?.toDouble() ?? 0,
      totalDurationSeconds: (json['total_duration_seconds'] as num?)?.toInt() ?? 0,
      totalActivities: json['total_activities'] as int? ?? 0,
      totalElevationGain: (json['total_elevation_gain'] as num?)?.toDouble() ?? 0,
      longestRunMeters: (json['longest_run_meters'] as num?)?.toDouble() ?? 0,
      best5kSeconds: json['best_5k_seconds'] as int?,
      best10kSeconds: json['best_10k_seconds'] as int?,
      bestHalfMarathonSeconds: json['best_half_marathon_seconds'] as int?,
      bestMarathonSeconds: json['best_marathon_seconds'] as int?,
      currentStreakDays: json['current_streak_days'] as int? ?? 0,
      longestStreakDays: json['longest_streak_days'] as int? ?? 0,
      lastActivityAt: json['last_activity_at'] != null 
          ? DateTime.parse(json['last_activity_at'] as String) 
          : null,
      thisWeekDistance: (json['this_week_distance'] as num?)?.toDouble() ?? 0,
      thisMonthDistance: (json['this_month_distance'] as num?)?.toDouble() ?? 0,
    );
  }

  UserStatisticsEntity toEntity() {
    return UserStatisticsEntity(
      userId: userId,
      totalDistanceMeters: totalDistanceMeters,
      totalDurationSeconds: totalDurationSeconds,
      totalActivities: totalActivities,
      totalElevationGain: totalElevationGain,
      longestRunMeters: longestRunMeters,
      best5kSeconds: best5kSeconds,
      best10kSeconds: best10kSeconds,
      bestHalfMarathonSeconds: bestHalfMarathonSeconds,
      bestMarathonSeconds: bestMarathonSeconds,
      currentStreakDays: currentStreakDays,
      longestStreakDays: longestStreakDays,
      lastActivityAt: lastActivityAt,
      thisWeekDistance: thisWeekDistance,
      thisMonthDistance: thisMonthDistance,
    );
  }
}

/// Leaderboard Entry Model
class LeaderboardEntryModel {
  final int rank;
  final String userId;
  final String userName;
  final String? avatarUrl;
  final double totalDistanceMeters;
  final int activityCount;

  const LeaderboardEntryModel({
    required this.rank,
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.totalDistanceMeters = 0,
    this.activityCount = 0,
  });

  factory LeaderboardEntryModel.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntryModel(
      rank: (json['rank'] as num).toInt(),
      userId: json['user_id'] as String,
      userName: json['user_name'] as String? ?? 'Anonim',
      avatarUrl: json['avatar_url'] as String?,
      totalDistanceMeters: (json['total_distance'] as num?)?.toDouble() ?? 0,
      activityCount: (json['activity_count'] as num?)?.toInt() ?? 0,
    );
  }

  LeaderboardEntryEntity toEntity() {
    return LeaderboardEntryEntity(
      rank: rank,
      userId: userId,
      userName: userName,
      avatarUrl: avatarUrl,
      totalDistanceMeters: totalDistanceMeters,
      activityCount: activityCount,
    );
  }
}
