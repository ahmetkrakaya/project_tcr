import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserPointsEntry {
  final String userId;
  final String fullName;
  final String? avatarUrl;
  final int points;

  const UserPointsEntry({
    required this.userId,
    required this.fullName,
    required this.avatarUrl,
    required this.points,
  });

  @override
  bool operator ==(Object other) =>
      other is UserPointsEntry && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;
}

/// Tek bir puan kaydı (etkinlik veya market siparişi).
class UserPointsDetailItem {
  final String id;
  final int points;
  final String sourceType;
  final String title;
  final String? subtitle;
  final DateTime? date;
  final double? distanceKm;

  const UserPointsDetailItem({
    required this.id,
    required this.points,
    required this.sourceType,
    required this.title,
    this.subtitle,
    this.date,
    this.distanceKm,
  });

  bool get isEvent => sourceType == 'event_participation';
  bool get isOrder => sourceType == 'marketplace_order';
}

class UserPointsDetail {
  final String userId;
  final String fullName;
  final int totalPoints;
  final int eventPoints;
  final int orderPoints;
  final List<UserPointsDetailItem> items;

  const UserPointsDetail({
    required this.userId,
    required this.fullName,
    required this.totalPoints,
    required this.eventPoints,
    required this.orderPoints,
    required this.items,
  });
}

final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Admin ekranı için: aktif kullanıcıları toplam puana göre azalan sıralar.
final userPointsLeaderboardProvider =
    FutureProvider<List<UserPointsEntry>>((ref) async {
  final supabase = ref.watch(_supabaseProvider);

  final usersRaw = await supabase
      .from('users')
      .select('id, first_name, last_name, avatar_url, is_active')
      .eq('is_active', true);

  final pointsRaw =
      await supabase.from('user_points').select('user_id, points');

  final pointsByUserId = <String, int>{};
  for (final row in (pointsRaw as List<dynamic>)) {
    final map = row as Map<String, dynamic>;
    final userId = map['user_id'] as String?;
    final points = (map['points'] as num?)?.toInt();
    if (userId == null) continue;
    pointsByUserId[userId] = (pointsByUserId[userId] ?? 0) + (points ?? 0);
  }

  String buildFullName(Map<String, dynamic> u) {
    final first = (u['first_name'] as String?)?.trim();
    final last = (u['last_name'] as String?)?.trim();
    final name = [first, last]
        .where((x) => x != null && x.isNotEmpty)
        .map((x) => x!)
        .join(' ');
    if (name.isNotEmpty) return name;
    return 'İsimsiz Kullanıcı';
  }

  final entries = <UserPointsEntry>[];
  for (final row in (usersRaw as List<dynamic>)) {
    final u = row as Map<String, dynamic>;
    final userId = u['id'] as String?;
    if (userId == null) continue;

    entries.add(
      UserPointsEntry(
        userId: userId,
        fullName: buildFullName(u),
        avatarUrl: u['avatar_url'] as String?,
        points: pointsByUserId[userId] ?? 0,
      ),
    );
  }

  entries.sort((a, b) {
    final byPoints = b.points.compareTo(a.points);
    if (byPoints != 0) return byPoints;
    return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
  });

  return entries;
});

/// Belirli bir kullanıcının puan kırılımı (nereden ne kadar).
final userPointsDetailProvider =
    FutureProvider.family<UserPointsDetail, UserPointsEntry>((ref, entry) async {
  final supabase = ref.watch(_supabaseProvider);

  final raw = await supabase
      .from('user_points')
      .select('''
        id,
        points,
        source_type,
        distance_km,
        note,
        created_at,
        events (
          title,
          start_time,
          event_type
        ),
        marketplace_orders (
          total_price,
          marketplace_listings (
            title
          )
        )
      ''')
      .eq('user_id', entry.userId)
      .order('created_at', ascending: false);

  final items = <UserPointsDetailItem>[];
  var eventPoints = 0;
  var orderPoints = 0;

  for (final row in (raw as List<dynamic>)) {
    final map = row as Map<String, dynamic>;
    final points = (map['points'] as num?)?.toInt() ?? 0;
    final sourceType = map['source_type'] as String? ?? '';
    final note = map['note'] as String?;
    final distanceKm = (map['distance_km'] as num?)?.toDouble();
    final createdAt = DateTime.tryParse(map['created_at'] as String? ?? '');

    if (sourceType == 'event_participation') {
      eventPoints += points;
      final event = map['events'] as Map<String, dynamic>?;
      final eventTitle = (event?['title'] as String?)?.trim();
      final eventType = event?['event_type'] as String?;
      final startAt = DateTime.tryParse(event?['start_time'] as String? ?? '');

      final subtitleParts = <String>[
        if (eventType != null && eventType.isNotEmpty) _eventTypeLabel(eventType),
        if (distanceKm != null) '${_formatKm(distanceKm)} km',
      ];

      items.add(
        UserPointsDetailItem(
          id: map['id'] as String,
          points: points,
          sourceType: sourceType,
          title: (eventTitle != null && eventTitle.isNotEmpty)
              ? eventTitle
              : (note?.isNotEmpty == true ? note! : 'Etkinlik katılımı'),
          subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' · '),
          date: startAt ?? createdAt,
          distanceKm: distanceKm,
        ),
      );
    } else if (sourceType == 'marketplace_order') {
      orderPoints += points;
      final order = map['marketplace_orders'] as Map<String, dynamic>?;
      final listing = order?['marketplace_listings'] as Map<String, dynamic>?;
      final listingTitle = (listing?['title'] as String?)?.trim();
      final totalPrice = (order?['total_price'] as num?)?.toDouble();

      items.add(
        UserPointsDetailItem(
          id: map['id'] as String,
          points: points,
          sourceType: sourceType,
          title: (listingTitle != null && listingTitle.isNotEmpty)
              ? listingTitle
              : (note?.isNotEmpty == true ? note! : 'Market siparişi'),
          subtitle: totalPrice != null
              ? '${totalPrice.toStringAsFixed(0)} TL · %5'
              : null,
          date: createdAt,
        ),
      );
    }
  }

  return UserPointsDetail(
    userId: entry.userId,
    fullName: entry.fullName,
    totalPoints: entry.points,
    eventPoints: eventPoints,
    orderPoints: orderPoints,
    items: items,
  );
});

String _eventTypeLabel(String type) {
  return switch (type) {
    'race' => 'Yarış',
    'training' => 'Antrenman',
    'social' => 'Sosyal',
    'workshop' => 'Workshop',
    _ => type,
  };
}

String _formatKm(double km) {
  if (km == km.roundToDouble()) return km.toInt().toString();
  return km.toStringAsFixed(1);
}
