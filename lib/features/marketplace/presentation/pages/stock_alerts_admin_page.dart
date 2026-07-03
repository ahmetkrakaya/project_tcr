import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/stock_alert_model.dart';
import '../providers/marketplace_provider.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

class StockAlertsAdminPage extends ConsumerWidget {
  const StockAlertsAdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stok Talepleri')),
        body: const Center(child: Text('Bu sayfaya erişim yetkiniz yok')),
      );
    }

    final alertsAsync = ref.watch(pendingStockAlertGroupsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok Talepleri'),
      ),
      body: alertsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 40, color: AppColors.error),
                const SizedBox(height: 12),
                Text(
                  'Talepler yüklenemedi',
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: ThemeBrightnessHolder.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(pendingStockAlertGroupsProvider),
                  child: const Text('Tekrar Dene'),
                ),
              ],
            ),
          ),
        ),
        data: (groups) {
          if (groups.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 56,
                    color: ThemeBrightnessHolder.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Bekleyen stok talebi yok',
                    style: AppTypography.titleMedium.copyWith(
                      color: ThemeBrightnessHolder.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Kullanıcılar stokta olmayan ürünler için\n“Gelince Haber Ver” dediğinde burada görünür.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: ThemeBrightnessHolder.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          final totalRequests =
              groups.fold<int>(0, (sum, group) => sum + group.alertCount);

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(pendingStockAlertGroupsProvider);
              await ref.read(pendingStockAlertGroupsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '$totalRequests talep · ${groups.length} ürün',
                          style: AppTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...groups.map((group) => _StockAlertGroupCard(group: group)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StockAlertGroupCard extends StatelessWidget {
  final ListingStockAlertGroup group;

  const _StockAlertGroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.pushNamed(
          RouteNames.listingDetail,
          pathParameters: {'listingId': group.listingId},
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: group.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: group.imageUrl!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 56,
                            height: 56,
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              Icons.image_outlined,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.listingTitle,
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${group.alertCount} kullanıcı bekliyor',
                          style: AppTypography.bodySmall.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: ThemeBrightnessHolder.outline),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              ...group.requests.take(4).map(
                    (request) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundImage: request.avatarUrl != null
                                ? CachedNetworkImageProvider(request.avatarUrl!)
                                : null,
                            child: request.avatarUrl == null
                                ? Text(
                                    request.userName.isNotEmpty
                                        ? request.userName[0].toUpperCase()
                                        : '?',
                                    style: AppTypography.labelSmall,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  request.userName.isEmpty
                                      ? 'Kullanıcı'
                                      : request.userName,
                                  style: AppTypography.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${request.scopeLabel} · ${dateFormat.format(request.createdAt.toLocal())}',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: ThemeBrightnessHolder.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (group.requests.length > 4)
                Text(
                  '+${group.requests.length - 4} talep daha',
                  style: AppTypography.bodySmall.copyWith(
                    color: ThemeBrightnessHolder.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
