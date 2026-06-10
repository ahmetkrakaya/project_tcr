import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../../features/notifications/constants/notification_types.dart';
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
  final target = data['target'] as String?;
  final activityId = data['activity_id'] as String?;

  // Strava watch: Ahmet/Ayça koştu, RunningViewerPage'e git
  if (type == 'strava_watch_run') {
    final queryParams = activityId != null ? {'activityId': activityId} : <String, String>{};
    router.goNamed(RouteNames.runningViewer, queryParameters: queryParams);
    return;
  }

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
  if (listingId != null &&
      (type == 'listing_created' ||
          type == 'listing_back_in_stock' ||
          type == 'listing_stock_updated' ||
          type == 'listing_discount')) {
    router.goNamed(RouteNames.listingDetail,
        pathParameters: {'listingId': listingId});
    return;
  }
  // Yeni üye başvurusu (admin) → Üyeler/Gruplar sayfası
  if (type == 'new_member_pending') {
    router.goNamed(RouteNames.groups);
    return;
  }
  // Mazaret bildirimi: uygulama açılsın, engel popup otomatik gösterilir
  if (type == NotificationTypes.engagementExcuseRequest) {
    router.goNamed(RouteNames.home);
    return;
  }
  // Admin manuel bildirimler: generic target bazlı yönlendirme
  if (type == NotificationTypes.adminManual && target != null) {
    if (target == 'integrations') {
      router.goNamed(RouteNames.integrations);
      return;
    }
    if (target == 'pace_calculator') {
      router.goNamed(RouteNames.paceCalculator);
      return;
    }
    if (target == 'groups') {
      router.goNamed(RouteNames.groups);
      return;
    }
    if (target == 'notifications') {
      router.goNamed(RouteNames.notifications);
      return;
    }
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

// Strava watch için özel yüksek öncelikli kanal
// v2: çoklu ses desteği (kanal ayarı değişince yeni id gerekir)
const String _stravaWatchChannelId = 'strava_watch_channel_v2';
const String _stravaWatchChannelName = 'Koşu Takip';
const String _stravaWatchChannelDescription = 'Ahmet ve Ayça\'nın koşu bildirimleri';

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  _channelId,
  _channelName,
  description: _channelDescription,
  importance: Importance.high,
  playSound: true,
);

const AndroidNotificationChannel _stravaWatchChannel = AndroidNotificationChannel(
  _stravaWatchChannelId,
  _stravaWatchChannelName,
  description: _stravaWatchChannelDescription,
  importance: Importance.max,
  playSound: true,
);

/// FCM data.sound → Android raw kaynağı (strava_alarm_1 … strava_alarm_5)
String _stravaWatchSoundResource(Map<String, dynamic> data) {
  final fromPayload = StravaWatchConstants.alarmSoundFromPayload(
    data['sound'] as String?,
  );
  return fromPayload ?? StravaWatchConstants.alarmSoundResource(0);
}

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

bool _initialized = false;

/// Foreground'da gelen FCM mesajını yerel bildirim olarak gösterir.
Future<void> showForegroundNotification(RemoteMessage message) async {
  if (!_initialized) return;
  final notification = message.notification;
  final title = notification?.title ?? message.data['title'] ?? 'Bildirim';
  final body = notification?.body ?? message.data['body'] ?? '';

  // Sohbet bildirimlerini (event_chat_message) aynı etkinlik için tek bildirim
  // olacak şekilde gruplayabilmek için notificationId'yi sabitliyoruz.
  final data = message.data;
  final type = data['type'] as String?;
  int notificationId = message.hashCode;

  if (type == NotificationTypes.eventChatMessage) {
    final eventId = data['event_id'] as String?;
    if (eventId != null) {
      notificationId = eventId.hashCode;
    }
  }

  final isStravaWatch = type == 'strava_watch_run';
  final stravaSoundRes = isStravaWatch
      ? _stravaWatchSoundResource(data)
      : null;

  final androidDetails = isStravaWatch
      ? AndroidNotificationDetails(
          _stravaWatchChannelId,
          _stravaWatchChannelName,
          channelDescription: _stravaWatchChannelDescription,
          importance: Importance.max,
          priority: Priority.max,
          sound: RawResourceAndroidNotificationSound(stravaSoundRes!),
        )
      : const AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        );

  final iosDetails = isStravaWatch
      ? DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: '$stravaSoundRes.wav',
        )
      : const DarwinNotificationDetails(
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
    notificationId,
    title,
    body,
    NotificationDetails(
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

  // Android bildirim kanalları
  if (defaultTargetPlatform == TargetPlatform.android) {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);
    await androidPlugin?.createNotificationChannel(_stravaWatchChannel);
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
