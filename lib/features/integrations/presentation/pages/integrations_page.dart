import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/platform_utils.dart';
import '../../apple_watch/apple_watch_provider.dart';
import '../../apple_watch/apple_watch_workout_sync_service.dart';
import '../pages/strava_oauth_webview_page.dart';
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
                                bool success = false;
                                if (isAndroid) {
                                  success = await _connectStravaViaWebView(
                                    context,
                                    ref,
                                  );
                                } else {
                                  success = await notifier.connectStrava();
                                }
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

  /// Android'de Strava OAuth'u in-app WebView ile açar (Chrome Custom Tabs restart sorununu önler).
  Future<bool> _connectStravaViaWebView(BuildContext context, WidgetRef ref) async {
    final authUrl = ref.read(stravaRepositoryProvider).getAuthorizationUrl();
    final redirectUrl = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => StravaOAuthWebViewPage(
          initialUrl: authUrl,
          callbackScheme: 'tcr',
        ),
      ),
    );
    if (!context.mounted) return false;
    if (redirectUrl == null) return false;
    final uri = Uri.parse(redirectUrl);
    final code = uri.queryParameters['code'];
    final error = uri.queryParameters['error'];
    final notifier = ref.read(stravaNotifierProvider.notifier);
    if (error != null) {
      notifier.setAuthError('Strava yetkilendirme hatası: $error');
      return false;
    }
    if (code == null || code.isEmpty) {
      notifier.setAuthError('Yetkilendirme kodu alınamadı');
      return false;
    }
    return notifier.connectStravaWithCode(code);
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
