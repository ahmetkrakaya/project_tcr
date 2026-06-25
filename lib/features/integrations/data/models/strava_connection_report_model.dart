class StravaConnectionUserItemModel {
  const StravaConnectionUserItemModel({
    required this.userId,
    required this.fullName,
    this.avatarUrl,
  });

  final String userId;
  final String fullName;
  final String? avatarUrl;

  factory StravaConnectionUserItemModel.fromJson(Map<String, dynamic> json) {
    final fullName = (json['full_name'] as String?)?.trim();
    return StravaConnectionUserItemModel(
      userId: json['user_id'] as String,
      fullName: fullName != null && fullName.isNotEmpty ? fullName : 'İsimsiz',
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class StravaConnectionReportModel {
  const StravaConnectionReportModel({
    required this.connectedCount,
    required this.notConnectedCount,
    required this.notConnectedUsers,
  });

  final int connectedCount;
  final int notConnectedCount;
  final List<StravaConnectionUserItemModel> notConnectedUsers;

  int get totalActiveUsers => connectedCount + notConnectedCount;

  double get connectedPercentage =>
      totalActiveUsers == 0 ? 0 : connectedCount / totalActiveUsers * 100;

  factory StravaConnectionReportModel.fromJson(Map<String, dynamic> json) {
    final usersJson = json['not_connected_users'] as List<dynamic>? ?? [];
    return StravaConnectionReportModel(
      connectedCount: json['connected_count'] as int? ?? 0,
      notConnectedCount: json['not_connected_count'] as int? ?? 0,
      notConnectedUsers: usersJson
          .map(
            (item) => StravaConnectionUserItemModel.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}
