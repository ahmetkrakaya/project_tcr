import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_notifier.dart' as auth;
import '../../features/notifications/presentation/providers/notification_provider.dart';
import 'app_icon_badge_service.dart';

/// Okunmamış bildirim sayısına göre uygulama ikonu rozetini senkronize eder.
/// [MainShell] içinde watch edilmeli.
final appIconBadgeSyncProvider = Provider<void>((ref) {
  ref.listen<auth.AuthState>(auth.authNotifierProvider, (_, next) {
    if (next is! auth.AuthAuthenticated) {
      AppIconBadgeService.update(0);
    } else {
      ref.invalidate(unreadNotificationCountProvider);
    }
  });

  ref.listen<AsyncValue<int>>(
    unreadNotificationCountProvider,
    (_, next) {
      next.when(
        data: AppIconBadgeService.update,
        loading: () {},
        error: (_, __) => AppIconBadgeService.update(0),
      );
    },
    fireImmediately: true,
  );
});

/// Okunmamış sayıyı DB'den alıp uygulama ikonu rozetine yazar.
Future<void> refreshAppIconBadge(WidgetRef ref) async {
  ref.invalidate(unreadNotificationCountProvider);
  try {
    final count = await ref.read(unreadNotificationCountProvider.future);
    await AppIconBadgeService.update(count);
  } catch (_) {
    await AppIconBadgeService.update(0);
  }
}
