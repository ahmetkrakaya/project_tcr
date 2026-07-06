import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Ana ekran uygulama ikonu rozeti (iOS + destekleyen Android launcher'lar).
class AppIconBadgeService {
  AppIconBadgeService._();

  static Future<void> update(int count) async {
    if (kIsWeb) return;
    try {
      final supported = await AppBadgePlus.isSupported();
      if (!supported) return;
      await AppBadgePlus.updateBadge(count <= 0 ? 0 : count);
    } catch (_) {
      // Launcher desteklemiyorsa veya izin yoksa sessizce bırak
    }
  }
}
