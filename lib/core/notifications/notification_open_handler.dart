import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notifications/presentation/providers/notification_provider.dart';
import 'app_icon_badge_sync.dart';

/// Push / yerel bildirim açıldığında DB'de okundu işaretle ve ikon rozetini güncelle.
Future<void> handleNotificationOpen(WidgetRef ref, RemoteMessage message) async {
  final notificationId = message.data['notification_id'];
  if (notificationId != null && notificationId.isNotEmpty) {
    try {
      await ref.read(notificationDataSourceProvider).markAsRead(notificationId);
      ref.invalidate(notificationsProvider);
    } catch (_) {
      // Okundu işaretlenemese bile rozet gerçek sayıya çekilsin
    }
  }
  await refreshAppIconBadge(ref);
}
