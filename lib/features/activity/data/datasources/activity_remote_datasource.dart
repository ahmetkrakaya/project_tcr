import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/activity_model.dart';

/// Activity Remote Data Source
abstract class ActivityRemoteDataSource {
  /// Kullanıcının aktivitelerini getir (activityType null ise tümü, 'running' ise sadece koşu)
  Future<List<ActivityModel>> getUserActivities(String userId, {int limit = 20, int offset = 0, String? activityType});

  /// Tek bir aktivite getir
  Future<ActivityModel> getActivityById(String id);

  /// Yeni aktivite ekle
  Future<ActivityModel> createActivity(ActivityModel activity);

  /// Aktivite güncelle
  Future<ActivityModel> updateActivity(ActivityModel activity);

  /// Aktivite sil
  Future<void> deleteActivity(String id);

  /// Kullanıcı istatistiklerini getir
  Future<UserStatisticsModel?> getUserStatistics(String userId);

  /// Haftalık lider tablosunu getir
  Future<List<LeaderboardEntryModel>> getWeeklyLeaderboard();

  /// Aylık lider tablosunu getir
  Future<List<LeaderboardEntryModel>> getMonthlyLeaderboard();
}

/// Activity Remote Data Source Implementation
class ActivityRemoteDataSourceImpl implements ActivityRemoteDataSource {
  final SupabaseClient _supabase;

  ActivityRemoteDataSourceImpl(this._supabase);

  @override
  Future<List<ActivityModel>> getUserActivities(String userId, {int limit = 20, int offset = 0, String? activityType}) async {
    try {
      var query = _supabase
          .from('activities')
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .eq('user_id', userId);

      if (activityType != null && activityType.isNotEmpty) {
        query = query.eq('activity_type', activityType);
      }

      final response = await query
          .order('start_time', ascending: false)
          .range(offset, offset + limit - 1);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => ActivityModel.fromJson(json as Map<String, dynamic>)).toList();
    } on PostgrestException catch (e) {
      throw ServerException(
        message: e.message,
        code: e.code,
      );
    } catch (e) {
      throw ServerException(message: 'Aktiviteler alınamadı: $e');
    }
  }

  @override
  Future<ActivityModel> getActivityById(String id) async {
    try {
      final response = await _supabase
          .from('activities')
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .eq('id', id)
          .single();

      return ActivityModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(
        message: e.message,
        code: e.code,
      );
    } catch (e) {
      throw ServerException(message: 'Aktivite bulunamadı: $e');
    }
  }

  @override
  Future<ActivityModel> createActivity(ActivityModel activity) async {
    try {
      final response = await _supabase
          .from('activities')
          .insert(activity.toJson())
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .single();

      return ActivityModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(
        message: e.message,
        code: e.code,
      );
    } catch (e) {
      throw ServerException(message: 'Aktivite oluşturulamadı: $e');
    }
  }

  @override
  Future<ActivityModel> updateActivity(ActivityModel activity) async {
    try {
      final response = await _supabase
          .from('activities')
          .update(activity.toJson())
          .eq('id', activity.id)
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .single();

      return ActivityModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(
        message: e.message,
        code: e.code,
      );
    } catch (e) {
      throw ServerException(message: 'Aktivite güncellenemedi: $e');
    }
  }

  @override
  Future<void> deleteActivity(String id) async {
    try {
      await _supabase.from('activities').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerException(
        message: e.message,
        code: e.code,
      );
    } catch (e) {
      throw ServerException(message: 'Aktivite silinemedi: $e');
    }
  }

  @override
  Future<UserStatisticsModel?> getUserStatistics(String userId) async {
    try {
      final response = await _supabase
          .from('user_statistics')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;
      return UserStatisticsModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(
        message: e.message,
        code: e.code,
      );
    } catch (e) {
      throw ServerException(message: 'İstatistikler alınamadı: $e');
    }
  }

  @override
  Future<List<LeaderboardEntryModel>> getWeeklyLeaderboard() async {
    try {
      final response = await _supabase.rpc('get_weekly_leaderboard');

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => LeaderboardEntryModel.fromJson(json as Map<String, dynamic>)).toList();
    } on PostgrestException catch (e) {
      throw ServerException(
        message: e.message,
        code: e.code,
      );
    } catch (e) {
      throw ServerException(message: 'Lider tablosu alınamadı: $e');
    }
  }

  @override
  Future<List<LeaderboardEntryModel>> getMonthlyLeaderboard() async {
    try {
      // Ayın başı
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      
      final response = await _supabase
          .from('activities')
          .select('''
            user_id,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .eq('is_public', true)
          .eq('activity_type', 'running')
          .gte('start_time', monthStart.toIso8601String());

      // Manuel olarak aggregate et
      final Map<String, Map<String, dynamic>> userStats = {};
      
      for (final row in response) {
        final odaId = row['user_id'] as String;
        if (!userStats.containsKey(odaId)) {
          final user = row['users'] as Map<String, dynamic>;
          userStats[odaId] = {
            'user_id': odaId,
            'user_name': '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim(),
            'avatar_url': user['avatar_url'],
            'total_distance': 0.0,
            'activity_count': 0,
          };
        }
        userStats[odaId]!['total_distance'] = 
            (userStats[odaId]!['total_distance'] as double) + 
            ((row['distance_meters'] as num?)?.toDouble() ?? 0);
        userStats[odaId]!['activity_count'] = 
            (userStats[odaId]!['activity_count'] as int) + 1;
      }

      // Sırala ve rank ekle
      final sorted = userStats.values.toList()
        ..sort((a, b) => (b['total_distance'] as double).compareTo(a['total_distance'] as double));

      return sorted.asMap().entries.map((entry) {
        return LeaderboardEntryModel(
          rank: entry.key + 1,
          userId: entry.value['user_id'] as String,
          userName: entry.value['user_name'] as String? ?? 'Anonim',
          avatarUrl: entry.value['avatar_url'] as String?,
          totalDistanceMeters: entry.value['total_distance'] as double,
          activityCount: entry.value['activity_count'] as int,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw ServerException(
        message: e.message,
        code: e.code,
      );
    } catch (e) {
      throw ServerException(message: 'Aylık lider tablosu alınamadı: $e');
    }
  }
}
