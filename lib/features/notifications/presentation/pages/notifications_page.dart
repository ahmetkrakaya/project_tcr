import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../data/models/notification_model.dart';
import '../providers/notification_provider.dart';

/// Bildirimler sayfası
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('tr', timeago.TrMessages());
    Future.microtask(() => ref.read(notificationsProvider.notifier).load());
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      ref.read(notificationsProvider.notifier).loadMore();
    }
  }

  void _navigateFromNotification(NotificationModel n) {
    final data = n.data;
    if (data == null) return;
    final type = n.type;

    // Etkinlik oluşturuldu / güncellendi → etkinlik detay
    if (data['event_id'] != null &&
        (type == 'event_created' ||
            type == 'event_updated' ||
            type == 'carpool_application' ||
            type == 'carpool_application_response')) {
      context.goNamed(RouteNames.eventDetail, pathParameters: {
        'eventId': data['event_id'] as String,
      });
      return;
    }
    // Etkinlik sohbeti → o etkinliğin chat sayfası
    if (data['event_id'] != null && type == 'event_chat_message') {
      context.goNamed(RouteNames.eventChat, pathParameters: {
        'eventId': data['event_id'] as String,
      });
      return;
    }
    // Yeni duyuru / duyuru güncelleme → post detay
    if (data['post_id'] != null &&
        (type == 'post_created' || type == 'post_updated')) {
      context.goNamed(RouteNames.postDetail, pathParameters: {
        'postId': data['post_id'] as String,
      });
      return;
    }
    // Yeni ürün → ürün detay
    if (data['listing_id'] != null && type == 'listing_created') {
      context.goNamed(RouteNames.listingDetail, pathParameters: {
        'listingId': data['listing_id'] as String,
      });
      return;
    }
    // Yeni sipariş → sipariş yönetimi
    if (type == 'order_created') {
      context.goNamed(RouteNames.ordersManagement);
      return;
    }
    // Sipariş durumu → siparişlerim (sipariş durumu sayfası)
    if (type == 'order_status_changed') {
      context.goNamed(RouteNames.myOrders);
      return;
    }
    // Fallback: room_id ile genel chat room (diğer sohbet bildirimleri)
    if (data['room_id'] != null) {
      context.goNamed(RouteNames.chatRoom, pathParameters: {
        'roomId': data['room_id'] as String,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.neutral200,
      appBar: AppBar(
        title: Text(
          'Bildirimler',
          style: AppTypography.titleLarge.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceLight,
          ),
        ),
        backgroundColor: AppColors.surfaceLight,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          Builder(
            builder: (context) {
              final list = state.valueOrNull ?? [];
              final hasUnread = list.any((n) => n.readAt == null);
              if (!hasUnread) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: () async {
                    await ref.read(notificationsProvider.notifier).markAllAsRead();
                  },
                  icon: Icon(Icons.done_all, size: 18, color: AppColors.primary),
                  label: Text(
                    'Tümünü okundu',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: state.when(
        data: (list) {
          if (list.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.notifications_none_outlined,
              title: 'Henüz bildirim yok',
              description: 'Yeni bildirimler burada görünecek.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
            color: AppColors.primary,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final n = list[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _NotificationTile(
                    notification: n,
                    onTap: () {
                      ref.read(notificationsProvider.notifier).markAsRead(n.id);
                      _navigateFromNotification(n);
                    },
                  ),
                );
              },
            ),
          );
        },
        loading: () => ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: 8,
          itemBuilder: (_, index) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: const NotificationTileShimmer(),
          ),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.cloud_off_outlined,
                    size: 48,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Bildirimler yüklenemedi',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.neutral800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString(),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.neutral500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(notificationsProvider.notifier).load(),
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text('Tekrar dene'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = notification.readAt == null;
    final iconColor = _colorForType(notification.type);

    return Material(
      color: AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isUnread
                  ? AppColors.primary.withValues(alpha: 0.25)
                  : AppColors.neutral300.withValues(alpha: 0.5),
              width: isUnread ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isUnread)
                Padding(
                  padding: const EdgeInsets.only(right: 10, top: 6),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _iconForType(notification.type),
                  color: iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight:
                            isUnread ? FontWeight.w600 : FontWeight.w500,
                        color: AppColors.neutral800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (notification.body != null &&
                        notification.body!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notification.body!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral500,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_outlined,
                          size: 12,
                          color: AppColors.neutral400,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeago.format(notification.createdAt, locale: 'tr'),
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.neutral400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.neutral400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'event_created':
      case 'event_updated':
        return AppColors.primary;
      case 'carpool_application':
      case 'carpool_application_response':
        return AppColors.tertiary;
      case 'event_chat_message':
        return AppColors.secondary;
      case 'post_created':
      case 'post_updated':
        return AppColors.info;
      case 'listing_created':
        return AppColors.warning;
      case 'order_created':
      case 'order_status_changed':
        return AppColors.success;
      default:
        return AppColors.primary;
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'event_created':
      case 'event_updated':
        return Icons.event;
      case 'carpool_application':
      case 'carpool_application_response':
        return Icons.directions_car;
      case 'event_chat_message':
        return Icons.chat_bubble_outline;
      case 'post_created':
      case 'post_updated':
        return Icons.article_outlined;
      case 'listing_created':
        return Icons.shopping_bag_outlined;
      case 'order_created':
      case 'order_status_changed':
        return Icons.receipt_long_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }
}
