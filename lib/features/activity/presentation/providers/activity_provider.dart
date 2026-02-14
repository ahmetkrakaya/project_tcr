import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/activity_remote_datasource.dart';
import '../../domain/entities/activity_entity.dart';

/// Supabase client provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Activity datasource provider
final activityDataSourceProvider = Provider<ActivityRemoteDataSource>((ref) {
  return ActivityRemoteDataSourceImpl(ref.watch(_supabaseProvider));
});

/// Activity Feed State (kullanıcı aktivite listesi için kullanılıyor; TCR feed'de aktivite gösterilmez)
class ActivityFeedState {
  final List<ActivityEntity> activities;
  final bool isLoading;
  final bool hasMore;
  final String? error;
  final int offset;

  const ActivityFeedState({
    this.activities = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
    this.offset = 0,
  });

  ActivityFeedState copyWith({
    List<ActivityEntity>? activities,
    bool? isLoading,
    bool? hasMore,
    String? error,
    int? offset,
  }) {
    return ActivityFeedState(
      activities: activities ?? this.activities,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      offset: offset ?? this.offset,
    );
  }
}

/// User Statistics Provider
final userStatisticsProvider = FutureProvider.family<UserStatisticsEntity?, String>((ref, userId) async {
  final dataSource = ref.watch(activityDataSourceProvider);
  final model = await dataSource.getUserStatistics(userId);
  return model?.toEntity();
});

/// Current User Statistics Provider
final currentUserStatisticsProvider = FutureProvider<UserStatisticsEntity?>((ref) async {
  final supabase = ref.watch(_supabaseProvider);
  final user = supabase.auth.currentUser;
  if (user == null) return null;

  final dataSource = ref.watch(activityDataSourceProvider);
  final model = await dataSource.getUserStatistics(user.id);
  return model?.toEntity();
});

/// Weekly Leaderboard Provider
final weeklyLeaderboardProvider = FutureProvider<List<LeaderboardEntryEntity>>((ref) async {
  final dataSource = ref.watch(activityDataSourceProvider);
  final models = await dataSource.getWeeklyLeaderboard();
  return models.map((m) => m.toEntity()).toList();
});

/// Monthly Leaderboard Provider  
final monthlyLeaderboardProvider = FutureProvider<List<LeaderboardEntryEntity>>((ref) async {
  final dataSource = ref.watch(activityDataSourceProvider);
  final models = await dataSource.getMonthlyLeaderboard();
  return models.map((m) => m.toEntity()).toList();
});

/// User Activities Provider (sadece koşu aktiviteleri)
final userActivitiesProvider = FutureProvider.family<List<ActivityEntity>, String>((ref, userId) async {
  final dataSource = ref.watch(activityDataSourceProvider);
  final models = await dataSource.getUserActivities(userId, activityType: 'running');
  return models.map((m) => m.toEntity()).toList();
});

/// User Running Activities Count Provider
final userRunningActivitiesCountProvider = FutureProvider.family<int, String>((ref, userId) async {
  final supabase = ref.watch(_supabaseProvider);
  final response = await supabase
      .from('activities')
      .select('id')
      .eq('user_id', userId)
      .eq('activity_type', 'running');
  return response.length;
});

/// Current User Running Activities Count Provider
final currentUserRunningActivitiesCountProvider = FutureProvider<int>((ref) async {
  final supabase = ref.watch(_supabaseProvider);
  final user = supabase.auth.currentUser;
  if (user == null) return 0;
  
  final response = await supabase
      .from('activities')
      .select('id')
      .eq('user_id', user.id)
      .eq('activity_type', 'running');
  return response.length;
});

/// Current User Activities Notifier (with pagination)
class CurrentUserActivitiesNotifier extends StateNotifier<ActivityFeedState> {
  final ActivityRemoteDataSource _dataSource;
  final String _userId;

  CurrentUserActivitiesNotifier(this._dataSource, this._userId) : super(const ActivityFeedState());

  /// İlk yükleme
  Future<void> loadActivities() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final models = await _dataSource.getUserActivities(_userId, limit: 20, offset: 0, activityType: 'running');
      final activities = models.map((m) => m.toEntity()).toList();

      state = state.copyWith(
        activities: activities,
        isLoading: false,
        hasMore: activities.length >= 20,
        offset: activities.length,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Daha fazla yükle
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final models = await _dataSource.getUserActivities(
        _userId,
        limit: 20,
        offset: state.offset,
        activityType: 'running',
      );
      final newActivities = models.map((m) => m.toEntity()).toList();

      state = state.copyWith(
        activities: [...state.activities, ...newActivities],
        isLoading: false,
        hasMore: newActivities.length >= 20,
        offset: state.offset + newActivities.length,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Yenile
  Future<void> refresh() async {
    state = const ActivityFeedState();
    await loadActivities();
  }
}

/// Current User Activities Provider (with pagination)
final currentUserActivitiesProvider = StateNotifierProvider<CurrentUserActivitiesNotifier, ActivityFeedState>((ref) {
  final supabase = ref.watch(_supabaseProvider);
  final user = supabase.auth.currentUser;
  if (user == null) {
    // Return a notifier that won't work, but won't crash
    final dataSource = ref.watch(activityDataSourceProvider);
    return CurrentUserActivitiesNotifier(dataSource, '');
  }
  
  final dataSource = ref.watch(activityDataSourceProvider);
  return CurrentUserActivitiesNotifier(dataSource, user.id);
});

/// User Activities Notifier Provider (with pagination, by userId)
final userActivitiesNotifierProvider = StateNotifierProvider.family<CurrentUserActivitiesNotifier, ActivityFeedState, String>((ref, userId) {
  final dataSource = ref.watch(activityDataSourceProvider);
  return CurrentUserActivitiesNotifier(dataSource, userId);
});
