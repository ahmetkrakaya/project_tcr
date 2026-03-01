/// Tüm kullanıcılar için toplu rapor satırı modeli
class UserAggregateStatModel {
  final String userId;
  final String userName;
  final String? avatarUrl;
  final double totalDistanceMeters;
  final int totalDurationSeconds;
  final double? averagePaceSecondsPerKm;
  final int totalRuns;

  const UserAggregateStatModel({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    required this.averagePaceSecondsPerKm,
    required this.totalRuns,
  });

  factory UserAggregateStatModel.fromJson(Map<String, dynamic> json) {
    return UserAggregateStatModel(
      userId: json['user_id'] as String,
      userName: json['user_name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      totalDistanceMeters: (json['total_distance_meters'] as num).toDouble(),
      totalDurationSeconds: json['total_duration_seconds'] as int,
      averagePaceSecondsPerKm:
          (json['average_pace_seconds_per_km'] as num?)?.toDouble(),
      totalRuns: json['total_runs'] as int? ?? 0,
    );
  }
}

/// Kullanıcı bazlı raporun üst özet + liste modeli
class UserReportSummaryModel {
  final int totalUsers;
  final int totalRuns;
  final double totalDistanceMeters;
  final double? averagePaceSecondsPerKm;
  final List<UserAggregateStatModel> users;

  const UserReportSummaryModel({
    required this.totalUsers,
    required this.totalRuns,
    required this.totalDistanceMeters,
    required this.averagePaceSecondsPerKm,
    required this.users,
  });

  double get totalDistanceKm => totalDistanceMeters / 1000.0;

  factory UserReportSummaryModel.fromJson(Map<String, dynamic> json) {
    final usersJson = json['users'] as List<dynamic>? ?? const [];
    final users = usersJson
        .map((e) => UserAggregateStatModel.fromJson(e as Map<String, dynamic>))
        .toList();

    return UserReportSummaryModel(
      totalUsers: json['total_users'] as int? ?? users.length,
      totalRuns: json['total_runs'] as int? ?? 0,
      totalDistanceMeters:
          (json['total_distance_meters'] as num?)?.toDouble() ?? 0.0,
      averagePaceSecondsPerKm:
          (json['average_pace_seconds_per_km'] as num?)?.toDouble(),
      users: users,
    );
  }
}

