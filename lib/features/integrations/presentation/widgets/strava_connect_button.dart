import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/strava_provider.dart';

/// Strava Connect Button Widget
class StravaConnectButton extends ConsumerWidget {
  final VoidCallback? onConnected;
  final VoidCallback? onDisconnected;

  const StravaConnectButton({
    super.key,
    this.onConnected,
    this.onDisconnected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stravaState = ref.watch(stravaNotifierProvider);
    final isConnected = stravaState.isConnected;
    final isLoading = stravaState.isLoading;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading
            ? null
            : () async {
                if (isConnected) {
                  final confirmed = await _showDisconnectDialog(context);
                  if (confirmed == true) {
                    final success = await ref
                        .read(stravaNotifierProvider.notifier)
                        .disconnectStrava();
                    if (success) {
                      onDisconnected?.call();
                    }
                  }
                } else {
                  final success = await ref
                      .read(stravaNotifierProvider.notifier)
                      .connectStrava();
                  if (success) {
                    onConnected?.call();
                  }
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: isConnected ? AppColors.error : const Color(0xFFFC4C02),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStravaIcon(),
                  const SizedBox(width: 12),
                  Text(
                    isConnected ? 'Strava Bağlantısını Kaldır' : 'Strava ile Bağlan',
                    style: AppTypography.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStravaIcon() {
    // SVG dosyası varsa kullan, yoksa ikon kullan
    return SvgPicture.asset(
      AssetPaths.stravaIcon,
      width: 24,
      height: 24,
      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      placeholderBuilder: (context) => const Icon(
        Icons.directions_run,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  Future<bool?> _showDisconnectDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Strava Bağlantısını Kaldır'),
        content: const Text(
          'Strava bağlantısını kaldırmak istediğinizden emin misiniz?\n\n'
          'Mevcut aktiviteleriniz silinmeyecek, ancak yeni aktiviteler otomatik olarak senkronize edilmeyecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
            child: const Text('Bağlantıyı Kaldır'),
          ),
        ],
      ),
    );
  }
}

/// Strava Sync Button Widget
class StravaSyncButton extends ConsumerWidget {
  const StravaSyncButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stravaState = ref.watch(stravaNotifierProvider);
    final isConnected = stravaState.isConnected;
    final isSyncing = stravaState.isSyncing;

    if (!isConnected) return const SizedBox.shrink();

    return IconButton(
      onPressed: isSyncing
          ? null
          : () async {
              final success = await ref
                  .read(stravaNotifierProvider.notifier)
                  .syncActivities();
              if (success && context.mounted) {
                final syncCount = ref.read(stravaNotifierProvider).lastSyncCount;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      syncCount != null && syncCount > 0
                          ? '$syncCount aktivite senkronize edildi'
                          : 'Yeni aktivite bulunamadı',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
      icon: isSyncing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
      tooltip: 'Strava Senkronize Et',
    );
  }
}

/// Strava Status Card Widget
class StravaStatusCard extends ConsumerWidget {
  const StravaStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stravaState = ref.watch(stravaNotifierProvider);
    final integration = stravaState.integration;

    if (integration == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFC4C02).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SvgPicture.asset(
                    AssetPaths.stravaIcon,
                    width: 24,
                    height: 24,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFFFC4C02),
                      BlendMode.srcIn,
                    ),
                    placeholderBuilder: (context) => const Icon(
                      Icons.directions_run,
                      color: Color(0xFFFC4C02),
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Strava',
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (integration.athleteName != null)
                        Text(
                          integration.athleteName!,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Bağlı',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Son senkronizasyon:',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
                Text(
                  integration.formattedLastSync,
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
