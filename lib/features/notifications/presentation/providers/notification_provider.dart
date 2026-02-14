import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/presentation/providers/auth_notifier.dart' as auth;
import '../../../../shared/providers/auth_provider.dart';
import '../../constants/notification_types.dart';
import '../../data/datasources/notification_remote_datasource.dart';
import '../../data/models/notification_model.dart';

final notificationDataSourceProvider = Provider<NotificationRemoteDataSource>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return NotificationRemoteDataSourceImpl(supabase);
});

/// Bildirim listesi (sayfalı)
final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, AsyncValue<List<NotificationModel>>>((ref) {
  final dataSource = ref.watch(notificationDataSourceProvider);
  return NotificationsNotifier(dataSource, ref);
});

class NotificationsNotifier extends StateNotifier<AsyncValue<List<NotificationModel>>> {
  final NotificationRemoteDataSource _dataSource;
  final Ref _ref;

  NotificationsNotifier(this._dataSource, this._ref) : super(const AsyncValue.data([]));

  static const int _pageSize = 20;
  int _offset = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  Future<void> load() async {
    state = const AsyncValue.loading();
    _offset = 0;
    _hasMore = true;
    try {
      final list = await _dataSource.getNotifications(limit: _pageSize, offset: 0);
      _hasMore = list.length >= _pageSize;
      _offset = list.length;
      state = AsyncValue.data(list);
      _ref.invalidate(unreadNotificationCountProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    final current = state.valueOrNull ?? [];
    if (current.isEmpty) return;
    _isLoadingMore = true;
    try {
      final list = await _dataSource.getNotifications(limit: _pageSize, offset: _offset);
      _hasMore = list.length >= _pageSize;
      _offset += list.length;
      state = AsyncValue.data([...current, ...list]);
    } catch (_) {
      // Sessiz
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> refresh() async {
    await load();
  }

  Future<void> markAsRead(String notificationId) async {
    await _dataSource.markAsRead(notificationId);
    state.whenData((list) {
      state = AsyncValue.data(list.map((n) {
        if (n.id == notificationId) {
          return NotificationModel(
            id: n.id,
            userId: n.userId,
            type: n.type,
            title: n.title,
            body: n.body,
            data: n.data,
            readAt: DateTime.now(),
            createdAt: n.createdAt,
          );
        }
        return n;
      }).toList());
    });
    _ref.invalidate(unreadNotificationCountProvider);
  }

  Future<void> markAllAsRead() async {
    await _dataSource.markAllAsRead();
    state.whenData((list) {
      state = AsyncValue.data(list.map((n) {
        return NotificationModel(
          id: n.id,
          userId: n.userId,
          type: n.type,
          title: n.title,
          body: n.body,
          data: n.data,
          readAt: DateTime.now(),
          createdAt: n.createdAt,
        );
      }).toList());
    });
    _ref.invalidate(unreadNotificationCountProvider);
  }
}

/// Okunmamış bildirim sayısı
final unreadNotificationCountProvider = FutureProvider<int>((ref) async {
  final dataSource = ref.watch(notificationDataSourceProvider);
  return dataSource.getUnreadCount();
});

/// Realtime: Yeni bildirim geldiğinde badge güncellenir
final notificationRealtimeProvider =
    StateNotifierProvider<NotificationRealtimeNotifier, void>((ref) {
  final dataSource = ref.watch(notificationDataSourceProvider);
  final supabase = ref.watch(supabaseClientProvider);
  return NotificationRealtimeNotifier(ref, dataSource, supabase);
});

class NotificationRealtimeNotifier extends StateNotifier<void> {
  final Ref _ref;
  final NotificationRemoteDataSource _dataSource;
  final SupabaseClient _supabase;
  bool _started = false;

  NotificationRealtimeNotifier(this._ref, this._dataSource, this._supabase)
      : super(null) {
    _ref.listen<auth.AuthState>(auth.authNotifierProvider, (_, next) {
      if (next is! auth.AuthAuthenticated) stop();
    });
  }

  void start() {
    if (_started) return;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    _started = true;
    _dataSource.subscribeToNewNotifications(userId, () {
      _ref.invalidate(unreadNotificationCountProvider);
    });
  }

  void stop() {
    if (!_started) return;
    _dataSource.unsubscribeFromNewNotifications();
    _started = false;
  }
}

/// Bildirim ayarları (tür bazlı aç/kapa)
final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsNotifier, AsyncValue<Map<String, bool>>>((ref) {
  final dataSource = ref.watch(notificationDataSourceProvider);
  return NotificationSettingsNotifier(dataSource);
});

class NotificationSettingsNotifier extends StateNotifier<AsyncValue<Map<String, bool>>> {
  final NotificationRemoteDataSource _dataSource;

  NotificationSettingsNotifier(this._dataSource)
      : super(const AsyncValue.data({}));

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final settings = await _dataSource.getNotificationSettings();
      state = AsyncValue.data(settings);
    } catch (e, _) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> setEnabled(String type, bool enabled) async {
    final current = Map<String, bool>.from(state.valueOrNull ?? {});
    state = AsyncValue.data({...current, type: enabled});
    try {
      await _dataSource.updateNotificationSetting(type, enabled);
    } catch (e, _) {
      state = AsyncValue.data(current);
      rethrow;
    }
  }

  /// Kategori bazlı aç/kapa (tek switch). İlgili tüm türler aynı değere set edilir.
  /// Tüm bildirim listesi yeniden yüklenmez, sadece state güncellenir.
  Future<void> setCategoryEnabled(String categoryId, bool enabled) async {
    final types = NotificationCategories.typesForCategory(categoryId);
    if (types.isEmpty) return;
    final current = Map<String, bool>.from(state.valueOrNull ?? {});
    final next = Map<String, bool>.from(current);
    for (final t in types) {
      next[t] = enabled;
    }
    state = AsyncValue.data(next);
    try {
      await _dataSource.updateNotificationSettings(
        {for (final t in types) t: enabled},
      );
    } catch (e, _) {
      state = AsyncValue.data(current);
      rethrow;
    }
  }
}
