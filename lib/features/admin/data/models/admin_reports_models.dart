double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

double? _toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

/// Etkinlik turu trendi - ay x tur kirilimi tek satir
class EventTypeTrendItem {
  const EventTypeTrendItem({
    required this.month,
    required this.eventType,
    required this.events,
    required this.participants,
  });

  final String month; // 'YYYY-MM'
  final String eventType;
  final int events;
  final int participants;

  factory EventTypeTrendItem.fromJson(Map<String, dynamic> json) {
    return EventTypeTrendItem(
      month: json['month'] as String,
      eventType: json['event_type'] as String? ?? 'other',
      events: _toInt(json['events']),
      participants: _toInt(json['participants']),
    );
  }
}

/// Grup durum panosu satiri
class GroupStatusItem {
  const GroupStatusItem({
    required this.id,
    required this.name,
    required this.groupType,
    required this.color,
    required this.memberCount,
    required this.activeMembers7d,
    required this.passiveMembers30d,
    required this.pendingRequests,
    required this.distance7dKm,
  });

  final String id;
  final String name;
  final String groupType;
  final String? color;
  final int memberCount;
  final int activeMembers7d;
  final int passiveMembers30d;
  final int pendingRequests;
  final double distance7dKm;

  bool get isPerformance => groupType == 'performance';

  factory GroupStatusItem.fromJson(Map<String, dynamic> json) {
    return GroupStatusItem(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Grup',
      groupType: json['group_type'] as String? ?? 'normal',
      color: json['color'] as String?,
      memberCount: _toInt(json['member_count']),
      activeMembers7d: _toInt(json['active_members_7d']),
      passiveMembers30d: _toInt(json['passive_members_30d']),
      pendingRequests: _toInt(json['pending_requests']),
      distance7dKm: _toDouble(json['distance_7d_km']),
    );
  }
}

/// Kisi 360 - son aktivite ozeti
class Person360Activity {
  const Person360Activity({
    this.id,
    required this.title,
    required this.startTime,
    required this.distanceKm,
    required this.durationSeconds,
    required this.paceSeconds,
  });

  final String? id;
  final String? title;
  final DateTime? startTime;
  final double distanceKm;
  final int durationSeconds;
  final int? paceSeconds;

  factory Person360Activity.fromJson(Map<String, dynamic> json) {
    return Person360Activity(
      id: json['id'] as String?,
      title: json['title'] as String?,
      startTime: _toDate(json['start_time']),
      distanceKm: _toDouble(json['distance_km']),
      durationSeconds: _toInt(json['duration_seconds']),
      paceSeconds: json['average_pace_seconds'] == null
          ? null
          : _toInt(json['average_pace_seconds']),
    );
  }
}

/// Kisi 360 birlesik ozet
class Person360 {
  const Person360({
    required this.userId,
    required this.fullName,
    this.avatarUrl,
    this.vdot,
    this.groupName,
    this.lastAppOpenAt,
    required this.totalPoints,
    required this.stravaConnected,
    required this.totalDistanceKm,
    required this.totalActivities,
    required this.thisWeekKm,
    required this.thisMonthKm,
    this.ctl,
    this.atl,
    this.tsb,
    this.acwr,
    this.loadStatus,
    required this.recentActivities,
  });

  final String userId;
  final String fullName;
  final String? avatarUrl;
  final double? vdot;
  final String? groupName;
  final DateTime? lastAppOpenAt;
  final int totalPoints;
  final bool stravaConnected;
  final double totalDistanceKm;
  final int totalActivities;
  final double thisWeekKm;
  final double thisMonthKm;
  final double? ctl;
  final double? atl;
  final double? tsb;
  final double? acwr;
  final String? loadStatus;
  final List<Person360Activity> recentActivities;

  factory Person360.fromJson(Map<String, dynamic> json) {
    final profile = Map<String, dynamic>.from(json['profile'] as Map? ?? {});
    final stats = Map<String, dynamic>.from(json['statistics'] as Map? ?? {});
    final load = Map<String, dynamic>.from(json['training_load'] as Map? ?? {});
    final recent = (json['recent_activities'] as List<dynamic>? ?? []);
    final fullName = (profile['full_name'] as String?)?.trim();

    return Person360(
      userId: profile['user_id'] as String,
      fullName: fullName != null && fullName.isNotEmpty ? fullName : 'İsimsiz',
      avatarUrl: profile['avatar_url'] as String?,
      vdot: _toDoubleOrNull(profile['vdot']),
      groupName: json['group_name'] as String?,
      lastAppOpenAt: _toDate(json['last_app_open_at']),
      totalPoints: _toInt(json['total_points']),
      stravaConnected: json['strava_connected'] == true,
      totalDistanceKm: _toDouble(stats['total_distance_km']),
      totalActivities: _toInt(stats['total_activities']),
      thisWeekKm: _toDouble(stats['this_week_km']),
      thisMonthKm: _toDouble(stats['this_month_km']),
      ctl: _toDoubleOrNull(load['ctl']),
      atl: _toDoubleOrNull(load['atl']),
      tsb: _toDoubleOrNull(load['tsb']),
      acwr: _toDoubleOrNull(load['acwr']),
      loadStatus: load['status'] as String?,
      recentActivities: recent
          .map((e) =>
              Person360Activity.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
