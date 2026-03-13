import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../apple_watch/apple_watch_provider.dart';
import '../../apple_watch/apple_watch_workout_sync_service.dart';
import '../../garmin/garmin_provider.dart';
import '../../health_connect/health_connect_provider.dart';
import '../../health_connect/health_connect_workout_sync_service.dart';
import '../providers/strava_provider.dart';

/// Integrations Page - Harici servis bağlantıları
class IntegrationsPage extends ConsumerWidget {
  const IntegrationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bağlantılar'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(stravaNotifierProvider.notifier).loadIntegration();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aktivite Kaynakları',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Koşu ve antrenman verilerinizi otomatik olarak senkronize etmek için harici uygulamalarınızı bağlayın.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.neutral500,
                ),
              ),
              const SizedBox(height: 24),
              _buildStravaSection(context, ref),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
                const SizedBox(height: 16),
                _buildAppleWatchSection(context, ref),
              ],
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
                const SizedBox(height: 16),
                _buildHealthConnectSection(context, ref),
              ],
              const SizedBox(height: 16),
              _buildGarminSection(context, ref),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStravaSection(BuildContext context, WidgetRef ref) {
    final stravaState = ref.watch(stravaNotifierProvider);
    final notifier = ref.read(stravaNotifierProvider.notifier);
    final isConnected = stravaState.isConnected;
    final integration = stravaState.integration;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isConnected ? AppColors.success.withValues(alpha: 0.3) : AppColors.neutral200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFC4C02).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SvgPicture.asset(
                    AssetPaths.stravaIcon,
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                    placeholderBuilder: (context) => const Icon(
                      Icons.directions_run,
                      color: Color(0xFFFC4C02),
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Strava',
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isConnected ? 'Bağlı' : 'Bağlı Değil',
                            style: AppTypography.labelSmall.copyWith(
                              color: isConnected ? AppColors.success : AppColors.neutral500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Koşu, bisiklet ve yüzme aktiviteleri',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral500,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: !isConnected || stravaState.isSyncing
                          ? null
                          : () async {
                              final success = await notifier.syncActivities();
                              if (success && context.mounted) {
                                final syncCount =
                                    ref.read(stravaNotifierProvider).lastSyncCount;
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
                      icon: stravaState.isSyncing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      tooltip: 'Senkronize Et',
                    ),
                    IconButton(
                      onPressed: stravaState.isLoading
                          ? null
                          : () async {
                              if (isConnected) {
                                await _showDisconnectDialog(context, ref);
                              } else {
                                final success = await notifier.connectStrava();
                                if (success && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Strava başarıyla bağlandı!'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            },
                      icon: Icon(
                        isConnected ? Icons.link_off : Icons.link,
                        color: isConnected ? AppColors.error : null,
                      ),
                      tooltip: isConnected ? 'Bağlantıyı Kaldır' : 'Bağlan',
                    ),
                    IconButton(
                      onPressed: !isConnected
                          ? null
                          : () {
                              context.pushNamed(RouteNames.stravaActivityList);
                            },
                      icon: const Icon(Icons.list),
                      tooltip: 'Aktiviteleri Görüntüle',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            _buildInfoRow(
              'Son Senkronizasyon',
              integration?.formattedLastSync ?? 'Henüz senkronize edilmedi',
              Icons.schedule,
            ),
            if (stravaState.error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stravaState.error!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        ref.read(stravaNotifierProvider.notifier).clearError();
                      },
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: AppColors.neutral400,
          ),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.neutral500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAppleWatchLastSync(DateTime? dt) {
    if (dt == null) return 'Henüz senkronize edilmedi';
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  Widget _buildAppleWatchSection(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appleWatchIntegrationProvider);
    final notifier = ref.read(appleWatchIntegrationProvider.notifier);
    final syncService = ref.read(appleWatchWorkoutSyncServiceProvider);

    final isSupported = state.isSupported;
    final auth = state.authorizationStatus;
    final isConnected = isSupported && auth == 'authorized';
    final enabled = state.settings.enabled;
    final isSyncing = state.isSyncing;

    String statusText;
    Color statusColor;
    if (!isSupported) {
      statusText = 'Desteklenmiyor';
      statusColor = AppColors.neutral500;
    } else if (isConnected) {
      statusText = 'Bağlı';
      statusColor = AppColors.success;
    } else {
      statusText = 'Bağlı Değil';
      statusColor = AppColors.neutral500;
    }

    Color borderColor;
    if (!isSupported) {
      borderColor = AppColors.neutral200;
    } else if (isConnected) {
      borderColor = AppColors.success.withValues(alpha: 0.3);
    } else {
      borderColor = AppColors.warning.withValues(alpha: 0.35);
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.apple,
                    size: 26,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Apple Watch',
                            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            statusText,
                            style: AppTypography.labelSmall.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Antrenmanları Apple Watch Workout uygulamasına gönder',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
                      ),
                    ],
                  ),
                ),
                if (isSupported)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: !enabled || !isConnected || isSyncing
                            ? null
                            : () async {
                                await notifier.setSyncing(true);
                                try {
                                  await syncService.syncNext7Days();
                                  await notifier.setLastSyncNow();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Apple Watch senkronizasyonu tamamlandı'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Senkronizasyon hatası: $e'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } finally {
                                  await notifier.setSyncing(false);
                                }
                              },
                        icon: isSyncing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        tooltip: 'Şimdi Senkronla',
                      ),
                      IconButton(
                        onPressed: () async {
                          if (isConnected) {
                            await _showAppleWatchDisconnectInfoDialog(context);
                          } else {
                            await notifier.connectAndAuthorize();
                            await notifier.refreshPlatformState();
                          }
                        },
                        icon: Icon(
                          isConnected ? Icons.link_off : Icons.link,
                          color: isConnected ? AppColors.error : null,
                        ),
                        tooltip:
                            isConnected ? 'Bağlantıyı Kaldır (Ayarlar üzerinden)' : 'Bağla / Yetki Ver',
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!isSupported) ...[
              Text(
                'Bu özellik iOS 17+ gerektirir. Cihazınız desteklemiyorsa antrenmanları FIT/TCX/JSON ile manuel export edebilirsiniz.',
                style: AppTypography.bodySmall.copyWith(color: AppColors.neutral600),
              ),
            ] else ...[
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Bu bağlantı Apple Health / HealthKit API\'lerini kullanır ve oluşturduğunuz antrenman programlarını Apple Fitness / Health uygulamalarına planlı antrenman olarak aktarır.',
                style: AppTypography.bodySmall.copyWith(color: AppColors.neutral600),
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                'Son Senkronizasyon',
                _formatAppleWatchLastSync(state.settings.lastSyncAt),
                Icons.schedule,
              ),
              if (state.error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.error!,
                          style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                        ),
                      ),
                      IconButton(
                        onPressed: notifier.clearError,
                        icon: const Icon(Icons.close, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }



  Widget _buildHealthConnectSection(BuildContext context, WidgetRef ref) {
    final state = ref.watch(healthConnectIntegrationProvider);
    final notifier = ref.read(healthConnectIntegrationProvider.notifier);
    final syncService = ref.read(healthConnectWorkoutSyncServiceProvider);

    final isSupported = state.isSupported;
    final auth = state.authorizationStatus;
    final isConnected = isSupported && auth == 'authorized';
    final isSyncing = state.isSyncing;

    String statusText;
    Color statusColor;
    if (!isSupported) {
      statusText = 'Desteklenmiyor';
      statusColor = AppColors.neutral500;
    } else if (isConnected) {
      statusText = 'Bağlı';
      statusColor = AppColors.success;
    } else {
      statusText = 'Bağlı Değil';
      statusColor = AppColors.neutral500;
    }

    Color borderColor;
    if (!isSupported) {
      borderColor = AppColors.neutral200;
    } else if (isConnected) {
      borderColor = AppColors.success.withValues(alpha: 0.3);
    } else {
      borderColor = AppColors.warning.withValues(alpha: 0.35);
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3DDC84)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.android,
                    size: 26,
                    color: const Color(0xFF3DDC84),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Health Connect',
                            style: AppTypography.titleMedium
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            statusText,
                            style: AppTypography.labelSmall.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Antrenmanları Android fitness uygulamalarına gönder',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.neutral500),
                      ),
                    ],
                  ),
                ),
                if (isSupported)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: !isConnected || isSyncing
                            ? null
                            : () async {
                                await notifier.setSyncing(true);
                                try {
                                  await syncService.syncNext7Days();
                                  await notifier.setLastSyncNow();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Health Connect senkronizasyonu tamamlandı',
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Senkronizasyon hatası: $e',
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } finally {
                                  await notifier.setSyncing(false);
                                }
                              },
                        icon: isSyncing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        tooltip: 'Şimdi Senkronla',
                      ),
                      IconButton(
                        onPressed: () async {
                          if (isConnected) {
                            await _showHealthConnectDisconnectInfoDialog(
                                context);
                          } else {
                            await notifier.connectAndAuthorize();
                            await notifier.refreshPlatformState();
                          }
                        },
                        icon: Icon(
                          isConnected ? Icons.link_off : Icons.link,
                          color: isConnected ? AppColors.error : null,
                        ),
                        tooltip: isConnected
                            ? 'Bağlantıyı Kaldır (Ayarlar üzerinden)'
                            : 'Bağla / Yetki Ver',
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!isSupported) ...[
              Text(
                'Bu özellik Health Connect uygulamasını gerektirir. '
                'Health Connect\'i yükleyip güncelleyin.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.neutral600),
              ),
            ] else ...[
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Bu bağlantı Google Health Connect API\'sini kullanır ve '
                'oluşturduğunuz antrenman programlarını Android fitness '
                'uygulamalarına (Samsung Health, Pixel Fit vb.) planlı '
                'antrenman olarak aktarır.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.neutral600),
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                'Son Senkronizasyon',
                _formatHealthConnectLastSync(state.lastSyncAt),
                Icons.schedule,
              ),
              if (state.error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.error!,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.error),
                        ),
                      ),
                      IconButton(
                        onPressed: notifier.clearError,
                        icon: const Icon(Icons.close, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatHealthConnectLastSync(DateTime? dt) {
    if (dt == null) return 'Henüz senkronize edilmedi';
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  Future<void> _showHealthConnectDisconnectInfoDialog(
      BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Health Connect Bağlantısı'),
        content: const Text(
          'Health Connect izinleri sistem tarafından yönetilir ve '
          'uygulama içinden doğrudan kaldırılamaz.\n\n'
          'İzni kaldırmak için Ayarlar > Uygulamalar > Health Connect '
          'bölümünden TCR için izinleri düzenleyebilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Widget _buildGarminSection(BuildContext context, WidgetRef ref) {
    final garminState = ref.watch(garminNotifierProvider);
    final notifier = ref.read(garminNotifierProvider.notifier);
    final isConnected = garminState.isConnected;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isConnected
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.neutral200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      AssetPaths.garminConnectIcon,
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.watch,
                        size: 36,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Garmin Connect',
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isConnected ? 'Bağlı' : 'Bağlı Değil',
                            style: AppTypography.labelSmall.copyWith(
                              color: isConnected
                                  ? AppColors.success
                                  : AppColors.neutral500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Antrenmanları Garmin saatine otomatik gönder',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: garminState.isLoading || garminState.isConnecting
                      ? null
                      : () async {
                          if (isConnected) {
                            await _showGarminDisconnectDialog(context, ref);
                          } else {
                            final success = await notifier.connectGarmin();
                            if (success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Garmin Connect başarıyla bağlandı!'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  icon: garminState.isConnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isConnected ? Icons.link_off : Icons.link,
                          color: isConnected ? AppColors.error : null,
                        ),
                  tooltip: isConnected ? 'Bağlantıyı Kaldır' : 'Bağlan',
                ),
              ],
            ),
            if (isConnected) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              _buildInfoRow(
                'Son Senkronizasyon',
                garminState.lastSyncAt != null
                    ? '${garminState.lastSyncAt!.day}.${garminState.lastSyncAt!.month}.${garminState.lastSyncAt!.year}'
                    : 'Henüz senkronize edilmedi',
                Icons.schedule,
              ),
              if (garminState.sentWorkoutsCount != null &&
                  garminState.sentWorkoutsCount! > 0)
                _buildInfoRow(
                  'Gönderilen Antrenman',
                  '${garminState.sentWorkoutsCount}',
                  Icons.fitness_center,
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_mode,
                      size: 18,
                      color: AppColors.success.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Antrenmanlar her gün otomatik olarak Garmin\'e gönderilir',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (garminState.error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        garminState.error!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: notifier.clearError,
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showGarminDisconnectDialog(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Garmin Connect Bağlantısını Kaldır'),
        content: const Text(
          'Garmin Connect bağlantısını kaldırmak istediğinizden emin misiniz?\n\n'
          'Bağlantı kaldırıldığında antrenmanlar artık Garmin saatinize otomatik gönderilmeyecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Bağlantıyı Kaldır'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success =
          await ref.read(garminNotifierProvider.notifier).disconnectGarmin();
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Garmin Connect bağlantısı kaldırıldı'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showAppleWatchDisconnectInfoDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apple Watch Bağlantısı'),
        content: const Text(
          'Apple Watch Workout izinleri sistem (iOS) tarafından yönetilir ve uygulama içinden doğrudan kaldırılamaz.\n\n'
          'İzni kaldırmak için Watch > Antrenman > Bağlı Uygulamalar bölümünden TCR için izinleri düzenleyebilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDisconnectDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
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

    if (confirmed == true) {
      final success =
          await ref.read(stravaNotifierProvider.notifier).disconnectStrava();
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Strava bağlantısı kaldırıldı'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
