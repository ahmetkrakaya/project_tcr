import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../notifications/constants/notification_types.dart';
import '../../../notifications/presentation/providers/notification_provider.dart';
import 'webview_page.dart';

/// Settings Page
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _appVersion = 'Yükleniyor...';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    Future.microtask(() =>
        ref.read(notificationSettingsProvider.notifier).load());
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // About Section
          _buildSectionHeader('Hakkında'),
          AppCard(
            child: Column(
              children: [
                _buildListTile(
                  leading: const Icon(Icons.info_outline),
                  title: 'Uygulama Sürümü',
                  subtitle: _appVersion,
                  trailing: const SizedBox.shrink(),
                  onTap: () {},
                ),
                const Divider(height: 1),
                _buildListTile(
                  leading: const Icon(Icons.group_outlined),
                  title: 'TCR Hakkında',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const WebViewPage(
                          url: 'https://www.rivlus.com/about',
                          title: 'TCR Hakkında',
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                _buildListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: 'Kullanım Koşulları',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const WebViewPage(
                          url: 'https://www.rivlus.com/terms',
                          title: 'Kullanım Koşulları',
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                _buildListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: 'Gizlilik Politikası',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const WebViewPage(
                          url: 'https://www.rivlus.com/privacy',
                          title: 'Gizlilik Politikası',
                        ),
                      ),
                    );
                  },
                ),
                
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Bildirimler (kategori bazlı: Etkinlik, Ortak Yolculuk, Sohbet, Post, Market)
          _buildSectionHeader('Bildirimler'),
          _buildNotificationSettings(ref),
          const SizedBox(height: 24),

          // Logout Button
          AppCard(
            onTap: () => _showLogoutDialog(context, ref),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout, color: AppColors.error),
                const SizedBox(width: 8),
                Text(
                  'Çıkış Yap',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: AppTypography.labelLarge.copyWith(
          color: AppColors.neutral500,
        ),
      ),
    );
  }

  bool _categoryEnabled(Map<String, bool> settings, String categoryId) {
    final types = NotificationCategories.typesForCategory(categoryId);
    if (types.isEmpty) return true;
    for (final t in types) {
      if (settings[t] != true) return false;
    }
    return true;
  }

  Widget _buildNotificationSettings(WidgetRef ref) {
    final settingsState = ref.watch(notificationSettingsProvider);
    return settingsState.when(
      data: (settings) {
        if (settings.isEmpty) {
          return const SizedBox.shrink();
        }
        return AppCard(
          child: Column(
            children: [
              for (int i = 0; i < NotificationCategories.all.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _buildNotificationCategoryTile(
                  ref,
                  settings,
                  NotificationCategories.all[i],
                ),
              ],
            ],
          ),
        );
      },
      loading: () => AppCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Text('Bildirim ayarları yükleniyor...', style: AppTypography.bodyMedium),
            ],
          ),
        ),
      ),
      error: (_, __) => AppCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bildirim ayarları yüklenemedi', style: AppTypography.titleSmall),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => ref.read(notificationSettingsProvider.notifier).load(),
                child: const Text('Tekrar dene'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCategoryTile(
    WidgetRef ref,
    Map<String, bool> settings,
    String categoryId,
  ) {
    final enabled = _categoryEnabled(settings, categoryId);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          try {
            await ref
                .read(notificationSettingsProvider.notifier)
                .setCategoryEnabled(categoryId, !enabled);
          } catch (_) {
            // Hata durumunda state provider tarafından eski haline döner
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (enabled ? AppColors.primary : AppColors.neutral300)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  NotificationCategories.icon(categoryId),
                  size: 22,
                  color: enabled ? AppColors.primary : AppColors.neutral500,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  NotificationCategories.label(categoryId),
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch.adaptive(
                value: enabled,
                onChanged: (value) async {
                  try {
                    await ref
                        .read(notificationSettingsProvider.notifier)
                        .setCategoryEnabled(categoryId, value);
                  } catch (_) {}
                },
                activeColor: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListTile({
    Widget? leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: leading,
      title: Text(title, style: AppTypography.titleSmall),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
            )
          : null,
      trailing: trailing ?? const Icon(Icons.chevron_right, color: AppColors.neutral400),
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Hesabından çıkış yapmak istediğine emin misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authNotifierProvider.notifier).signOut();
              context.go('/login');
            },
            child: const Text(
              'Çıkış Yap',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
