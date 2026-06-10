class UserEngagementReportItemModel {
  final String userId;
  final String fullName;
  final int? openCount;
  final int? participationCount;
  final DateTime? lastOpenAt;
  final DateTime? lastActivityAt;
  final DateTime? lastParticipationAt;

  const UserEngagementReportItemModel({
    required this.userId,
    required this.fullName,
    this.openCount,
    this.participationCount,
    this.lastOpenAt,
    this.lastActivityAt,
    this.lastParticipationAt,
  });

  factory UserEngagementReportItemModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value as String);
    }

    return UserEngagementReportItemModel(
      userId: json['user_id'] as String,
      fullName: (json['full_name'] as String?)?.trim().isNotEmpty == true
          ? (json['full_name'] as String).trim()
          : 'İsimsiz',
      openCount: json['open_count'] as int?,
      participationCount: json['participation_count'] as int?,
      lastOpenAt: parseDate(json['last_open_at']),
      lastActivityAt: parseDate(json['last_activity_at']),
      lastParticipationAt: parseDate(json['last_participation_at']),
    );
  }
}

class UserEngagementReportsModel {
  final List<UserEngagementReportItemModel> topAppOpeners;
  final List<UserEngagementReportItemModel> inactiveAppUsers;
  final List<UserEngagementReportItemModel> topEventParticipants;
  final List<UserEngagementReportItemModel> inactiveEventUsers;

  const UserEngagementReportsModel({
    required this.topAppOpeners,
    required this.inactiveAppUsers,
    required this.topEventParticipants,
    required this.inactiveEventUsers,
  });

  factory UserEngagementReportsModel.fromJson(Map<String, dynamic> json) {
    List<UserEngagementReportItemModel> parseList(String key) {
      final raw = json[key];
      if (raw is! List) return [];
      return raw
          .map(
            (e) => UserEngagementReportItemModel.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList();
    }

    return UserEngagementReportsModel(
      topAppOpeners: parseList('top_app_openers'),
      inactiveAppUsers: parseList('inactive_app_users'),
      topEventParticipants: parseList('top_event_participants'),
      inactiveEventUsers: parseList('inactive_event_users'),
    );
  }
}
