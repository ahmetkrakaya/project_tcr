import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../notifications/constants/notification_types.dart';
import '../../../notifications/presentation/providers/notification_provider.dart';
import 'webview_page.dart';

final appVersionsProvider = FutureProvider<Map<String, String>>((ref) async {
  final supabase = Supabase.instance.client;
  final rows = await supabase
      .from('app_versions')
      .select('platform, minimum_version')
      .inFilter('platform', ['android', 'ios']);

  final map = <String, String>{};
  for (final row in rows as List<dynamic>) {
    final r = row as Map<String, dynamic>;
    final platform = (r['platform'] as String?)?.toLowerCase();
    final minVersion = r['minimum_version'] as String?;
    if (platform != null && minVersion != null) {
      map[platform] = minVersion;
    }
  }
  return map;
});

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
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
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

          // Account Section
          _buildSectionHeader('Hesap'),
          AppCard(
            child: Column(
              children: [
                _buildListTile(
                  leading: const Icon(
                    Icons.delete_forever_outlined,
                    color: AppColors.error,
                  ),
                  title: 'Hesabımı Sil',
                  subtitle:
                      'Hesabını silmek için talep oluştur. 15 gün içinde tekrar giriş yaparsan iptal edilir.',
                  onTap: () => _showDeleteAccountDialog(context, ref),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.neutral400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Bildirimler (kategori bazlı: Etkinlik, Ortak Yolculuk, Sohbet, Post, Market)
          _buildSectionHeader('Bildirimler'),
          _buildNotificationSettings(ref),
          const SizedBox(height: 24),

          if (isAdminOrCoach) ...[
            _buildSectionHeader('Admin'),
            _buildAdminVersionManagement(context, ref),
            const SizedBox(height: 24),
          ],

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

  Widget _buildAdminVersionManagement(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(appVersionsProvider);

    String subtitleFor(String platform) => versions.when(
          data: (data) => data[platform] ?? 'Kayıt yok',
          loading: () => 'Yükleniyor...',
          error: (_, __) => 'Yüklenemedi',
        );

    return AppCard(
      child: Column(
        children: [
          _buildListTile(
            leading: const Icon(Icons.android),
            title: 'Android minimum sürüm',
            subtitle: subtitleFor('android'),
            onTap: () => _showEditMinimumVersionDialog(
              context: context,
              ref: ref,
              platform: 'android',
              currentValue: versions.valueOrNull?['android'],
            ),
          ),
          const Divider(height: 1),
          _buildListTile(
            leading: const Icon(Icons.phone_iphone),
            title: 'iOS minimum sürüm',
            subtitle: subtitleFor('ios'),
            onTap: () => _showEditMinimumVersionDialog(
              context: context,
              ref: ref,
              platform: 'ios',
              currentValue: versions.valueOrNull?['ios'],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditMinimumVersionDialog({
    required BuildContext context,
    required WidgetRef ref,
    required String platform,
    String? currentValue,
  }) async {
    final controller = TextEditingController(text: currentValue ?? '');
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              platform == 'android'
                  ? 'Android minimum sürüm'
                  : 'iOS minimum sürüm',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    hintText: 'Örn: 1.2026.2',
                    errorText: errorText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bu değer, uygulamanın açılışta yaptığı güncelleme kontrolünde minimum sürüm olarak kullanılır.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('İptal'),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  final ok = RegExp(r'^\d+(\.\d+)*$').hasMatch(value);
                  if (!ok) {
                    setDialogState(() {
                      errorText = 'Geçersiz sürüm formatı';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(value);
                },
                child: const Text('Kaydet'),
              ),
            ],
          ),
        );
      },
    );

    if (result == null) return;
    if (!context.mounted) return;
    await _upsertMinimumVersion(
      context: context,
      platform: platform,
      minimumVersion: result,
      ref: ref,
    );
  }

  Future<void> _upsertMinimumVersion({
    required BuildContext context,
    required WidgetRef ref,
    required String platform,
    required String minimumVersion,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final supabase = Supabase.instance.client;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: SizedBox(
          height: 64,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );

    try {
      await supabase.from('app_versions').upsert(
        {
          'platform': platform,
          'minimum_version': minimumVersion,
        },
        onConflict: 'platform',
      );

      ref.invalidate(appVersionsProvider);

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${platform == 'android' ? 'Android' : 'iOS'} minimum sürüm güncellendi: $minimumVersion',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Kaydedilemedi: $e')),
      );
    }
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

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hesabımı Sil'),
        content: const Text(
          'Hesabını silmek için bir talep oluşturacaksın.\n\n'
          '• Silme talebi hemen işlenmez, 15 günlük bir bekleme süresi başlar.\n'
          '• Bu süre içinde tekrar giriş yaparsan talep otomatik olarak iptal edilir.\n'
          '• 15 gün sonunda hesabın geri dönüşsüz şekilde pasif hâle getirilir ve kişisel verilerin mümkün olduğunca silinir veya anonimleştirilir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _handleAccountDeletionRequest(context, ref);
            },
            child: const Text(
              'Silme Talebi Oluştur',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAccountDeletionRequest(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: SizedBox(
          height: 64,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );

    final error = await ref
        .read(authNotifierProvider.notifier)
        .requestAccountDeletion();

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (error != null && error.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Hesap silme talebin alındı. 15 gün içinde tekrar giriş yaparsan talep iptal edilecektir.',
        ),
      ),
    );

    ref.read(authNotifierProvider.notifier).signOut();
    if (context.mounted) {
      context.go('/login');
    }
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
