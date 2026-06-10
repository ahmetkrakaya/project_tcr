import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../providers/app_versions_admin_provider.dart';

class AdminAppVersionsPage extends ConsumerStatefulWidget {
  const AdminAppVersionsPage({super.key});

  @override
  ConsumerState<AdminAppVersionsPage> createState() =>
      _AdminAppVersionsPageState();
}

class _AdminAppVersionsPageState extends ConsumerState<AdminAppVersionsPage> {
  final _iosVersionController = TextEditingController();
  final _iosStoreUrlController = TextEditingController();
  final _iosMessageController = TextEditingController();
  final _androidVersionController = TextEditingController();
  final _androidStoreUrlController = TextEditingController();
  final _androidMessageController = TextEditingController();

  bool _iosForceUpdate = false;
  bool _androidForceUpdate = false;
  bool _formsInitialized = false;
  bool _iosSaving = false;
  bool _androidSaving = false;

  @override
  void dispose() {
    _iosVersionController.dispose();
    _iosStoreUrlController.dispose();
    _iosMessageController.dispose();
    _androidVersionController.dispose();
    _androidStoreUrlController.dispose();
    _androidMessageController.dispose();
    super.dispose();
  }

  void _initForms(Map<String, AppVersionRow> data) {
    if (_formsInitialized) return;

    final ios = data['ios'];
    final android = data['android'];

    if (ios != null) {
      _iosVersionController.text = ios.minimumVersion;
      _iosStoreUrlController.text = ios.appStoreUrl ?? '';
      _iosMessageController.text = ios.message ?? '';
      _iosForceUpdate = ios.isForceUpdate;
    }

    if (android != null) {
      _androidVersionController.text = android.minimumVersion;
      _androidStoreUrlController.text = android.playStoreUrl ?? '';
      _androidMessageController.text = android.message ?? '';
      _androidForceUpdate = android.isForceUpdate;
    }

    _formsInitialized = true;
  }

  bool _isValidVersion(String value) =>
      RegExp(r'^\d+(\.\d+)*$').hasMatch(value.trim());

  Future<void> _saveIos() async {
    final version = _iosVersionController.text.trim();
    if (!_isValidVersion(version)) {
      _showError('Geçerli bir iOS sürüm numarası girin (örn. 1.2026.2)');
      return;
    }

    setState(() => _iosSaving = true);
    try {
      await ref.read(appVersionsAdminRepositoryProvider).upsertIos(
            minimumVersion: version,
            isForceUpdate: _iosForceUpdate,
            message: _iosMessageController.text,
            appStoreUrl: _iosStoreUrlController.text,
          );
      ref.invalidate(appVersionsAdminProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('iOS sürüm bilgileri kaydedildi')),
        );
      }
    } catch (e) {
      _showError('Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _iosSaving = false);
    }
  }

  Future<void> _saveAndroid() async {
    final version = _androidVersionController.text.trim();
    if (!_isValidVersion(version)) {
      _showError('Geçerli bir Android sürüm numarası girin (örn. 1.2026.2)');
      return;
    }

    setState(() => _androidSaving = true);
    try {
      await ref.read(appVersionsAdminRepositoryProvider).upsertAndroid(
            minimumVersion: version,
            isForceUpdate: _androidForceUpdate,
            message: _androidMessageController.text,
            playStoreUrl: _androidStoreUrlController.text,
          );
      ref.invalidate(appVersionsAdminProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Android sürüm bilgileri kaydedildi')),
        );
      }
    } catch (e) {
      _showError('Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _androidSaving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final versionsAsync = ref.watch(appVersionsAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Versiyon'),
      ),
      body: !isAdmin
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Bu sayfaya erişim yetkiniz yok.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.neutral500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : versionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sürüm bilgileri yüklenemedi',
                        style: AppTypography.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$e',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(appVersionsAdminProvider),
                        child: const Text('Tekrar dene'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (data) {
                _initForms(data);
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Kullanıcıların uygulama açılışında gördüğü güncelleme kontrolü bu değerlerle yapılır.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildPlatformCard(
                      title: 'iOS',
                      icon: Icons.phone_iphone,
                      iconColor: AppColors.primary,
                      versionController: _iosVersionController,
                      storeUrlController: _iosStoreUrlController,
                      storeUrlLabel: 'App Store linki',
                      storeUrlHint: 'https://apps.apple.com/app/id...',
                      messageController: _iosMessageController,
                      isForceUpdate: _iosForceUpdate,
                      onForceUpdateChanged: (v) =>
                          setState(() => _iosForceUpdate = v),
                      isSaving: _iosSaving,
                      onSave: _saveIos,
                      updatedAt: data['ios']?.updatedAt,
                    ),
                    const SizedBox(height: 16),
                    _buildPlatformCard(
                      title: 'Android',
                      icon: Icons.android,
                      iconColor: const Color(0xFF3DDC84),
                      versionController: _androidVersionController,
                      storeUrlController: _androidStoreUrlController,
                      storeUrlLabel: 'Play Store linki',
                      storeUrlHint:
                          'https://play.google.com/store/apps/details?id=...',
                      messageController: _androidMessageController,
                      isForceUpdate: _androidForceUpdate,
                      onForceUpdateChanged: (v) =>
                          setState(() => _androidForceUpdate = v),
                      isSaving: _androidSaving,
                      onSave: _saveAndroid,
                      updatedAt: data['android']?.updatedAt,
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildPlatformCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required TextEditingController versionController,
    required TextEditingController storeUrlController,
    required String storeUrlLabel,
    required String storeUrlHint,
    required TextEditingController messageController,
    required bool isForceUpdate,
    required ValueChanged<bool> onForceUpdateChanged,
    required bool isSaving,
    required VoidCallback onSave,
    required DateTime? updatedAt,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.titleMedium),
                    if (updatedAt != null)
                      Text(
                        'Son güncelleme: ${_formatDate(updatedAt)}',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: versionController,
            decoration: const InputDecoration(
              labelText: 'Güncel minimum sürüm',
              hintText: 'Örn: 1.2026.2',
              helperText:
                  'Bu sürümün altındaki kullanıcılara güncelleme uyarısı gösterilir',
            ),
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('Zorunlu güncelleme', style: AppTypography.titleSmall),
            subtitle: Text(
              isForceUpdate
                  ? 'Kullanıcı güncellemeden uygulamayı kullanamaz'
                  : 'Kullanıcı uyarıyı kapatabilir',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.neutral500,
              ),
            ),
            value: isForceUpdate,
            onChanged: onForceUpdateChanged,
            activeColor: AppColors.primary,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: storeUrlController,
            decoration: InputDecoration(
              labelText: storeUrlLabel,
              hintText: storeUrlHint,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: messageController,
            decoration: const InputDecoration(
              labelText: 'Güncelleme mesajı (isteğe bağlı)',
              hintText: 'Yeni sürümde neler var?',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isSaving ? null : onSave,
              child: isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('$title kaydet'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d.$m.${local.year} $h:$min';
  }
}
