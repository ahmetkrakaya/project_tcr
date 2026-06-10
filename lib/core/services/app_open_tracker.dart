import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uygulama kullanımını kaydeder: soğuk başlatmada açılış sayacı,
/// ön plana dönüşte son kullanım zamanı güncellenir.
class AppOpenTracker {
  static bool _recordedOpenThisLaunch = false;
  static DateTime? _lastTouchAt;
  static const _touchCooldown = Duration(minutes: 15);

  /// Soğuk başlatma veya yeni oturum: açılış sayacına +1, last_app_open_at güncelle.
  static Future<void> recordIfNeeded() async {
    if (_recordedOpenThisLaunch) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _recordedOpenThisLaunch = true;
    _lastTouchAt = DateTime.now();

    try {
      await Supabase.instance.client.rpc('record_app_open');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppOpenTracker: record_app_open başarısız: $e');
      }
    }
  }

  /// Arka plandan dönüş: yalnızca last_app_open_at güncelle (15 dk throttle).
  static Future<void> touchActivityIfNeeded() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final now = DateTime.now();
    if (_lastTouchAt != null &&
        now.difference(_lastTouchAt!) < _touchCooldown) {
      return;
    }
    _lastTouchAt = now;

    try {
      await Supabase.instance.client.rpc('touch_last_app_activity');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppOpenTracker: touch_last_app_activity başarısız: $e');
      }
    }
  }
}
