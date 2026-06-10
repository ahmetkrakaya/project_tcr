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
}

final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Admin ekranı için: aktif kullanıcıları toplam puana göre azalan sıralar.
final userPointsLeaderboardProvider = FutureProvider<List<UserPointsEntry>>((ref) async {
  final supabase = ref.watch(_supabaseProvider);

  final usersRaw = await supabase
      .from('users')
      .select('id, first_name, last_name, avatar_url, is_active')
      .eq('is_active', true);

  final pointsRaw = await supabase.from('user_race_points').select('user_id, points');

  final pointsByUserId = <String, int>{};
  for (final row in (pointsRaw as List<dynamic>)) {
    final map = row as Map<String, dynamic>;
    final userId = map['user_id'] as String?;
    final points = map['points'] as int?;
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

