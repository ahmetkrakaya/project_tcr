import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../providers/app_versions_admin_provider.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

class AdminAppVersionsPage extends ConsumerStatefulWidget {
  const AdminAppVersionsPage({super.key});

  @override
  ConsumerState<AdminAppVersionsPage> createState() =>
      _AdminAppVersionsPageState();
}

class _AdminAppVersionsPageState extends ConsumerState<AdminAppVersionsPage> {
  final _iosVersionController = TextEditingController();
  final _iosStoreUrlController = TextEditingController();
  final _androidVersionController = TextEditingController();
  final _androidStoreUrlController = TextEditingController();

  bool _iosForceUpdate = false;
  bool _androidForceUpdate = false;
  bool _formsInitialized = false;
  bool _iosSaving = false;
  bool _androidSaving = false;

  @override
  void dispose() {
    _iosVersionController.dispose();
    _iosStoreUrlController.dispose();
    _androidVersionController.dispose();
    _androidStoreUrlController.dispose();
    super.dispose();
  }

  void _initForms(Map<String, AppVersionRow> data) {
    if (_formsInitialized) return;

    final ios = data['ios'];
    final android = data['android'];

    if (ios != null) {
      _iosVersionController.text = ios.minimumVersion;
      _iosStoreUrlController.text = ios.appStoreUrl ?? '';
      _iosForceUpdate = ios.isForceUpdate;
    }

    if (android != null) {
      _androidVersionController.text = android.minimumVersion;
      _androidStoreUrlController.text = android.playStoreUrl ?? '';
      _androidForceUpdate = android.isForceUpdate;
    }

    _formsInitialized = true;
  }

  bool _isValidVersion(String value) =>
      RegExp(r'^\d+(\.\d+)*$').hasMatch(value.trim());

  Future<void> _saveIos() async {
    final version = _iosVersionController.text.trim();
    if (!_isValidVersion(version)) {
      _showError('Geçerli bir sürüm numarası girin (örn. 1.2026.2)');
      return;
    }

    setState(() => _iosSaving = true);
    try {
      await ref.read(appVersionsAdminRepositoryProvider).upsertIos(
            minimumVersion: version,
            isForceUpdate: _iosForceUpdate,
            appStoreUrl: _iosStoreUrlController.text,
          );
      ref.invalidate(appVersionsAdminProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('iOS ayarları kaydedildi')),
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
      _showError('Geçerli bir sürüm numarası girin (örn. 1.2026.2)');
      return;
    }

    setState(() => _androidSaving = true);
    try {
      await ref.read(appVersionsAdminRepositoryProvider).upsertAndroid(
            minimumVersion: version,
            isForceUpdate: _androidForceUpdate,
            playStoreUrl: _androidStoreUrlController.text,
          );
      ref.invalidate(appVersionsAdminProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Android ayarları kaydedildi')),
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
    final cs = Theme.of(context).colorScheme;

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
                    color: ThemeBrightnessHolder.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : versionsAsync.when(
              loading: () => const LoadingWidget(),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ayarlar yüklenemedi',
                        style: AppTypography.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$e',
                        style: AppTypography.bodySmall.copyWith(
                          color: ThemeBrightnessHolder.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(appVersionsAdminProvider),
                        child: const Text('Tekrar Dene'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (data) {
                _initForms(data);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    Text(
                      'Minimum sürümün altındaki kullanıcılara güncelleme uyarısı gösterilir.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: ThemeBrightnessHolder.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _PlatformSection(
                      title: 'iOS',
                      icon: Icons.phone_iphone_rounded,
                      iconColor: cs.primary,
                      updatedAt: data['ios']?.updatedAt,
                      versionController: _iosVersionController,
                      storeUrlController: _iosStoreUrlController,
                      storeUrlLabel: 'App Store linki',
                      storeUrlHint: 'https://apps.apple.com/app/id...',
                      isForceUpdate: _iosForceUpdate,
                      onForceUpdateChanged: (value) =>
                          setState(() => _iosForceUpdate = value),
                      isSaving: _iosSaving,
                      onSave: _saveIos,
                    ),
                    const SizedBox(height: 16),
                    _PlatformSection(
                      title: 'Android',
                      icon: Icons.android_rounded,
                      iconColor: const Color(0xFF3DDC84),
                      updatedAt: data['android']?.updatedAt,
                      versionController: _androidVersionController,
                      storeUrlController: _androidStoreUrlController,
                      storeUrlLabel: 'Play Store linki',
                      storeUrlHint:
                          'https://play.google.com/store/apps/details?id=...',
                      isForceUpdate: _androidForceUpdate,
                      onForceUpdateChanged: (value) =>
                          setState(() => _androidForceUpdate = value),
                      isSaving: _androidSaving,
                      onSave: _saveAndroid,
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _PlatformSection extends StatelessWidget {
  const _PlatformSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.updatedAt,
    required this.versionController,
    required this.storeUrlController,
    required this.storeUrlLabel,
    required this.storeUrlHint,
    required this.isForceUpdate,
    required this.onForceUpdateChanged,
    required this.isSaving,
    required this.onSave,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final DateTime? updatedAt;
  final TextEditingController versionController;
  final TextEditingController storeUrlController;
  final String storeUrlLabel;
  final String storeUrlHint;
  final bool isForceUpdate;
  final ValueChanged<bool> onForceUpdateChanged;
  final bool isSaving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    if (updatedAt != null)
                      Text(
                        'Son kayıt: ${DateFormat('d MMM yyyy, HH:mm').format(updatedAt!.toLocal())}',
                        style: AppTypography.bodySmall.copyWith(
                          color: ThemeBrightnessHolder.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SaveIconButton(
                isSaving: isSaving,
                onPressed: onSave,
              ),
            ],
          ),
          const SizedBox(height: 20),
          AppTextField(
            controller: versionController,
            label: 'Minimum sürüm',
            hint: '1.2026.2',
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: storeUrlController,
            label: storeUrlLabel,
            hint: storeUrlHint,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Zorunlu güncelleme',
              style: AppTypography.titleSmall.copyWith(color: cs.onSurface),
            ),
            value: isForceUpdate,
            onChanged: onForceUpdateChanged,
            activeTrackColor: cs.primary.withValues(alpha: 0.5),
            inactiveTrackColor: cs.surfaceContainerHighest,
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return cs.primary;
              return cs.outline;
            }),
          ),
        ],
      ),
    );
  }
}

class _SaveIconButton extends StatelessWidget {
  const _SaveIconButton({
    required this.isSaving,
    required this.onPressed,
  });

  final bool isSaving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'Kaydet',
      child: Material(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: isSaving ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 40,
            height: 40,
            child: isSaving
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : Icon(
                    Icons.check_rounded,
                    color: cs.primary,
                    size: 22,
                  ),
          ),
        ),
      ),
    );
  }
}