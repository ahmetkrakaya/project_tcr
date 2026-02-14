import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';

/// Bildirim açılışında yönlendirme için kullanılacak callback.
/// TCRApp ilk build'de set eder.
void Function(RemoteMessage)? _navigateFromNotificationCallback;

void setNotificationNavigationCallback(void Function(RemoteMessage) callback) {
  _navigateFromNotificationCallback = callback;
}

/// initNotificationHandler'a verilecek callback; main'den çağrılır.
void invokeNotificationNavigation(RemoteMessage message) {
  _navigateFromNotificationCallback?.call(message);
}

/// Uygulama kapalıyken bildirimle açıldıysa ilk mesajı döndürür.
Future<RemoteMessage?> getInitialMessage() =>
    FirebaseMessaging.instance.getInitialMessage();

/// Cold start'ta auth henüz hazır olmadığı için yönlendirme yapmıyoruz; mesajı saklıyoruz.
/// Splash auth kontrolü bittikten sonra [getPendingInitialMessage] ile alınıp yönlendirme yapılır.
RemoteMessage? _pendingInitialMessage;

/// İlk açılışta getInitialMessage varsa mesajı saklar (cold start). Yönlendirme splash auth
/// tamamlandıktan sonra SplashPage tarafından [getPendingInitialMessage] ile yapılır;
/// böylece router redirect auth hazır olmadan login'e atmaz.
Future<void> handleInitialMessage() async {
  final message = await getInitialMessage();
  if (message == null) return;
  _pendingInitialMessage = message;
}

/// Cold start bildirim mesajını döndürür ve temizler. Auth tamamlandıktan sonra
/// (örn. splash'ten /home'a gittikten sonra) tek seferlik çağrılmalı.
RemoteMessage? getPendingInitialMessage() {
  final message = _pendingInitialMessage;
  _pendingInitialMessage = null;
  return message;
}

/// RemoteMessage data'sına göre GoRouter ile ilgili sayfaya gider.
/// Kurallar: bildirim sayfasındaki tıklama yönlendirmesi ile aynı.
void navigateFromNotification(GoRouter router, RemoteMessage message) {
  final data = message.data;
  if (data.isEmpty) {
    router.goNamed(RouteNames.notifications);
    return;
  }
  final type = data['type'] as String?;
  final eventId = data['event_id'] as String?;
  final postId = data['post_id'] as String?;
  final listingId = data['listing_id'] as String?;
  final roomId = data['room_id'] as String?;

  // Etkinlik oluşturuldu/güncellendi, ortak araç başvurusu/yanıtı → etkinlik detay
  if (eventId != null &&
      (type == 'event_created' ||
          type == 'event_updated' ||
          type == 'carpool_application' ||
          type == 'carpool_application_response')) {
    router.goNamed(RouteNames.eventDetail, pathParameters: {'eventId': eventId});
    return;
  }
  // Etkinlik sohbeti → o etkinliğin chat sayfası
  if (eventId != null && type == 'event_chat_message') {
    router.goNamed(RouteNames.eventChat, pathParameters: {'eventId': eventId});
    return;
  }
  // Yeni duyuru / duyuru güncelleme → post detay
  if (postId != null &&
      (type == 'post_created' || type == 'post_updated')) {
    router.goNamed(RouteNames.postDetail, pathParameters: {'postId': postId});
    return;
  }
  // Yeni ürün → ürün detay
  if (listingId != null && type == 'listing_created') {
    router.goNamed(RouteNames.listingDetail,
        pathParameters: {'listingId': listingId});
    return;
  }
  // Yeni sipariş → sipariş yönetimi
  if (type == 'order_created') {
    router.goNamed(RouteNames.ordersManagement);
    return;
  }
  // Sipariş durumu → siparişlerim (sipariş durumu sayfası)
  if (type == 'order_status_changed') {
    router.goNamed(RouteNames.myOrders);
    return;
  }
  // Yeni üye başvurusu (admin) → Üyeler/Gruplar sayfası
  if (type == 'new_member_pending') {
    router.goNamed(RouteNames.groups);
    return;
  }
  // Fallback: room_id ile genel chat room
  if (roomId != null) {
    router.goNamed(RouteNames.chatRoom, pathParameters: {'roomId': roomId});
    return;
  }
  router.goNamed(RouteNames.notifications);
}

// --- Flutter Local Notifications (foreground bildirim) ---

const String _channelId = 'tcr_notifications';
const String _channelName = 'TCR Bildirimleri';
const String _channelDescription = 'Etkinlik, duyuru ve mesaj bildirimleri';

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  _channelId,
  _channelName,
  description: _channelDescription,
  importance: Importance.high,
  playSound: true,
);

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

bool _initialized = false;

/// Foreground'da gelen FCM mesajını yerel bildirim olarak gösterir.
Future<void> showForegroundNotification(RemoteMessage message) async {
  if (!_initialized) return;
  final notification = message.notification;
  final title = notification?.title ?? message.data['title'] ?? 'Bildirim';
  final body =
      notification?.body ?? message.data['body'] ?? '';
  const androidDetails = AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: _channelDescription,
    importance: Importance.high,
    priority: Priority.high,
  );
  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );
  // Payload: değerlerde = veya & olabilir; encode ederek tap'te doğru parse ederiz
  final payload = message.data.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
  await _localNotifications.show(
    message.hashCode,
    title,
    body,
    const NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    ),
    payload: payload,
  );
}

/// Arka planda gelen FCM (isolate). Sadece return; bildirim backend'den notification ile gidiyor.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Arka planda sistem bildirimi backend'den gönderildiği için ek iş yok.
}

/// Notification handler'ı başlatır: local notifications init, FCM dinleyicileri.
/// Web'de çağrılmaz (main.dart'ta kIsWeb guard var).
Future<void> initNotificationHandler(void Function(RemoteMessage) onTap) async {
  if (_initialized) return;
  if (kIsWeb) return;

  // Android bildirim kanalı
  if (defaultTargetPlatform == TargetPlatform.android) {
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings(
    requestAlertPermission: false, // Firebase.requestPermission kullanıyoruz
  );
  await _localNotifications.initialize(
    const InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    ),
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload == null || response.payload!.isEmpty) return;
      // payload "key=value&key2=value2" (encode edilmiş); decode ile parse
      final data = <String, String>{};
      for (final part in response.payload!.split('&')) {
        final idx = part.indexOf('=');
        if (idx > 0) {
          final key = Uri.decodeComponent(part.substring(0, idx));
          final value = Uri.decodeComponent(part.substring(idx + 1));
          data[key] = value;
        }
      }
      final fakeMessage = RemoteMessage(
        senderId: null,
        data: data,
        messageId: null,
        sentTime: null,
        ttl: null,
        notification: null,
      );
      onTap(fakeMessage);
    },
  );

  _initialized = true;

  // Foreground mesajı -> yerel bildirim göster
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    showForegroundNotification(message);
  });

  // Arka planda / kapalıyken bildirime tıklanınca
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    onTap(message);
  });

  // Arka plan handler (top-level)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
}
