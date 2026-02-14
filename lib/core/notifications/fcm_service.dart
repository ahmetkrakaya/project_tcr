import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// FCM token yönetimi ve Supabase'e kaydetme.
class FcmService {
  FcmService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Bildirim izni: iOS'ta FCM, Android 13+ ta permission_handler ile POST_NOTIFICATIONS.
  /// Web'de çağrılmaz (main.dart'ta kIsWeb guard var).
  static Future<void> requestPermission() async {
    if (kIsWeb) return;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android 13+ (API 33+) bildirim göstermek için runtime izni gerekli
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    }
  }

  /// Mevcut FCM token'ı alır.
  static Future<String?> getToken() => _messaging.getToken();

  /// Token değiştiğinde (refresh) tetiklenir.
  static Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  /// Token'ı Supabase `users.fcm_token` alanına yazar. Giriş yapmış kullanıcı gerekir.
  static Future<void> saveTokenToSupabase(String token) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('users')
          .update({'fcm_token': token}).eq('id', userId);
    } catch (_) {
      // RLS veya ağ hatası; sessizce bırak
    }
  }

  /// Giriş yapılmış kullanıcı için token alıp Supabase'e yazar.
  static Future<void> refreshAndSaveToken() async {
    final token = await getToken();
    if (token != null) await saveTokenToSupabase(token);
  }
}
