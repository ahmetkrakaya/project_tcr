import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/notification_model.dart';

/// Bildirim veri kaynağı
abstract class NotificationRemoteDataSource {
  /// Kullanıcının bildirimlerini getir (sayfalı)
  Future<List<NotificationModel>> getNotifications({
    int limit = 20,
    int offset = 0,
  });

  /// Okunmamış bildirim sayısı
  Future<int> getUnreadCount();

  /// Bildirimi okundu işaretle
  Future<void> markAsRead(String notificationId);

  /// Tüm bildirimleri okundu işaretle
  Future<void> markAllAsRead();

  /// Kullanıcının bildirim ayarlarını getir
  Future<Map<String, bool>> getNotificationSettings();

  /// Bildirim türü ayarını güncelle
  Future<void> updateNotificationSetting(String type, bool enabled);

  /// Birden fazla bildirim türünü tek seferde güncelle (kategori toggle için)
  Future<void> updateNotificationSettings(Map<String, bool> updates);

  /// Yeni bildirimler için Realtime aboneliği (INSERT)
  void subscribeToNewNotifications(String userId, void Function() onNewNotification);

  /// Realtime aboneliğini iptal et
  void unsubscribeFromNewNotifications();
}

class NotificationRemoteDataSourceImpl implements NotificationRemoteDataSource {
  final SupabaseClient _supabase;
  RealtimeChannel? _notificationsChannel;

  NotificationRemoteDataSourceImpl(this._supabase);

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  @override
  Future<List<NotificationModel>> getNotifications({
    int limit = 20,
    int offset = 0,
  }) async {
    if (_currentUserId == null) {
      throw ServerException(message: 'Oturum açılmamış', code: 'UNAUTHORIZED');
    }
    try {
      final response = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', _currentUserId!)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final List<dynamic> data = response as List<dynamic>;
      return data
          .map((json) => NotificationModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Bildirimler alınamadı: $e');
    }
  }

  @override
  Future<int> getUnreadCount() async {
    if (_currentUserId == null) return 0;
    try {
      final response = await _supabase
          .from('notifications')
          .select('id')
          .eq('user_id', _currentUserId!)
          .isFilter('read_at', null);
      final List<dynamic> data = response as List<dynamic>;
      return data.length;
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    if (_currentUserId == null) {
      throw ServerException(message: 'Oturum açılmamış', code: 'UNAUTHORIZED');
    }
    try {
      await _supabase
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', notificationId)
          .eq('user_id', _currentUserId!);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Bildirim güncellenemedi: $e');
    }
  }

  @override
  Future<void> markAllAsRead() async {
    if (_currentUserId == null) {
      throw ServerException(message: 'Oturum açılmamış', code: 'UNAUTHORIZED');
    }
    try {
      await _supabase
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', _currentUserId!)
          .isFilter('read_at', null);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Bildirimler güncellenemedi: $e');
    }
  }

  @override
  Future<Map<String, bool>> getNotificationSettings() async {
    if (_currentUserId == null) {
      throw ServerException(message: 'Oturum açılmamış', code: 'UNAUTHORIZED');
    }
    try {
      final response = await _supabase
          .from('user_notification_settings')
          .select('settings')
          .eq('user_id', _currentUserId!)
          .maybeSingle();

      if (response == null) {
        return _defaultSettings();
      }
      final settings = response['settings'] as Map<String, dynamic>?;
      if (settings == null) return _defaultSettings();
      final Map<String, bool> result = {};
      for (final entry in settings.entries) {
        result[entry.key] = _parseSettingValue(entry.value);
      }
      for (final key in _defaultSettings().keys) {
        result.putIfAbsent(key, () => true);
      }
      return result;
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Bildirim ayarları alınamadı: $e');
    }
  }

  /// JSONB'dan gelen değeri bool yorumla (true/1 -> true, false/0/null -> false)
  static bool _parseSettingValue(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return false;
  }

  Map<String, bool> _defaultSettings() {
    return {
      'event_created': true,
      'event_updated': true,
      'carpool_application': true,
      'carpool_application_response': true,
      'event_chat_message': true,
      'post_created': true,
      'post_updated': true,
      'listing_created': true,
      'order_created': true,
      'order_status_changed': true,
    };
  }

  @override
  Future<void> updateNotificationSetting(String type, bool enabled) async {
    await updateNotificationSettings({type: enabled});
  }

  @override
  Future<void> updateNotificationSettings(Map<String, bool> updates) async {
    if (_currentUserId == null) {
      throw ServerException(message: 'Oturum açılmamış', code: 'UNAUTHORIZED');
    }
    try {
      final current = await getNotificationSettings();
      for (final entry in updates.entries) {
        current[entry.key] = entry.value;
      }
      final defaults = _defaultSettings();
      final settingsToSave = <String, bool>{};
      for (final key in defaults.keys) {
        settingsToSave[key] = current[key] ?? true;
      }

      await _supabase.from('user_notification_settings').upsert(
            {
              'user_id': _currentUserId!,
              'settings': settingsToSave,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'user_id',
          );
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Ayar güncellenemedi: $e');
    }
  }

  @override
  void subscribeToNewNotifications(String userId, void Function() onNewNotification) {
    _notificationsChannel?.unsubscribe();
    _notificationsChannel = _supabase
        .channel('notifications_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => onNewNotification(),
        )
        .subscribe();
  }

  @override
  void unsubscribeFromNewNotifications() {
    _notificationsChannel?.unsubscribe();
    _notificationsChannel = null;
  }
}
