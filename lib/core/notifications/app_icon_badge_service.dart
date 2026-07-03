import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_app_badger/flutter_app_badger.dart';

/// Ana ekran uygulama ikonu rozeti (iOS + destekleyen Android launcher'lar).
class AppIconBadgeService {
  AppIconBadgeService._();

  static Future<void> update(int count) async {
    if (kIsWeb) return;
    try {
      final supported = await FlutterAppBadger.isAppBadgeSupported();
      if (supported != true) return;
      if (count <= 0) {
        await FlutterAppBadger.removeBadge();
      } else {
        await FlutterAppBadger.updateBadgeCount(count);
      }
    } catch (_) {
      // Launcher desteklemiyorsa veya izin yoksa sessizce bırak
    }
  }
}
