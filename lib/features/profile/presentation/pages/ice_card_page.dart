import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// ICE Card Page
class IceCardPage extends ConsumerStatefulWidget {
  final String? userId; // Başka kullanıcının ICE kartını görmek için
  
  const IceCardPage({super.key, this.userId});

  @override
  ConsumerState<IceCardPage> createState() => _IceCardPageState();
}

class _IceCardPageState extends ConsumerState<IceCardPage> {
  bool _isEditing = false;
  bool _isLoading = false;

  final _chronicDiseasesController = TextEditingController();
  final _medicationsController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _emergencyRelationController = TextEditingController();
  final _additionalNotesController = TextEditingController();

  @override
  void dispose() {
    _chronicDiseasesController.dispose();
    _medicationsController.dispose();
    _allergiesController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyRelationController.dispose();
    _additionalNotesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);

    final targetUserId = widget.userId ?? ref.read(userIdProvider);
    if (targetUserId == null) return;

    try {
      await ref.read(iceCardNotifierProvider(targetUserId).notifier).update(
            chronicDiseases: _chronicDiseasesController.text.trim().isNotEmpty
                ? _chronicDiseasesController.text.trim()
                : null,
            medications: _medicationsController.text.trim().isNotEmpty
                ? _medicationsController.text.trim()
                : null,
            allergies: _allergiesController.text.trim().isNotEmpty
                ? _allergiesController.text.trim()
                : null,
            emergencyContactName: _emergencyNameController.text.trim().isNotEmpty
                ? _emergencyNameController.text.trim()
                : null,
            emergencyContactPhone: _emergencyPhoneController.text.trim().isNotEmpty
                ? _emergencyPhoneController.text.trim()
                : null,
            emergencyContactRelation:
                _emergencyRelationController.text.trim().isNotEmpty
                    ? _emergencyRelationController.text.trim()
                    : null,
            additionalNotes: _additionalNotesController.text.trim().isNotEmpty
                ? _additionalNotesController.text.trim()
                : null,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ICE kartı güncellendi')),
        );
        setState(() => _isEditing = false);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Eğer userId parametresi verilmişse onu kullan, yoksa kendi userId'yi kullan
    final targetUserId = widget.userId ?? ref.watch(userIdProvider);
    final isViewingOtherUser = widget.userId != null;
    final iceCardAsync =
        targetUserId != null ? ref.watch(iceCardNotifierProvider(targetUserId)) : null;
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Acil Durum Kartı'),
        actions: [
          // Sadece kendi ICE kartında ve düzenleme modunda değilken edit butonu göster
          if (!_isEditing && !isViewingOtherUser)
            IconButton(
              icon: Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning Card
            AppCard(
              backgroundColor: isDark
                  ? AppColors.warning.withValues(alpha: 0.14)
                  : AppColors.warningContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.privacy_tip,
                    color: isDark ? AppColors.warningLight : AppColors.warning,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gizlilik Bildirimi',
                          style: AppTypography.titleSmall.copyWith(
                            color: isDark ? AppColors.warningLight : AppColors.warning,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bu bilgiler sadece acil durumlarda yetkili kişiler tarafından görüntülenebilir. Tüm erişimler loglanır.',
                          style: AppTypography.bodySmall.copyWith(
                            color: isDark
                                ? cs.onSurfaceVariant
                                : ThemeBrightnessHolder.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (_isEditing && !isViewingOtherUser) ...[
              _buildEditForm(),
            ] else ...[
              _buildViewMode(iceCardAsync, isViewingOtherUser),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _isEditing && !isViewingOtherUser
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: 'İptal',
                        variant: AppButtonVariant.outlined,
                        onPressed: () => setState(() => _isEditing = false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        text: 'Kaydet',
                        isLoading: _isLoading,
                        onPressed: _save,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildViewMode(AsyncValue<IceCardEntity?>? iceCardAsync, bool isViewingOtherUser) {
    final cs = Theme.of(context).colorScheme;

    return iceCardAsync?.when(
          data: (iceCard) {
            if (iceCard == null || !iceCard.hasEmergencyInfo) {
              return _buildEmptyState(isViewingOtherUser);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (iceCard.emergencyContactName != null) ...[
                  _buildInfoSection(
                    'Acil Durumda Aranacak Kişi',
                    [
                      _buildInfoItem('Ad', iceCard.emergencyContactName!),
                      if (iceCard.emergencyContactPhone != null)
                        _buildInfoItem('Telefon', iceCard.emergencyContactPhone!),
                      if (iceCard.emergencyContactRelation != null)
                        _buildInfoItem('Yakınlık', iceCard.emergencyContactRelation!),
                    ],
                    icon: Icons.contact_phone,
                    iconColor: cs.primary,
                  ),
                  const SizedBox(height: 20),
                ],
                if (iceCard.chronicDiseases != null) ...[
                  _buildInfoSection(
                    'Kronik Hastalıklar',
                    [_buildInfoItem('', iceCard.chronicDiseases!)],
                    icon: Icons.medical_information,
                    iconColor: AppColors.error,
                  ),
                  const SizedBox(height: 20),
                ],
                if (iceCard.medications != null) ...[
                  _buildInfoSection(
                    'Kullanılan İlaçlar',
                    [_buildInfoItem('', iceCard.medications!)],
                    icon: Icons.medication,
                    iconColor: AppColors.warning,
                  ),
                  const SizedBox(height: 20),
                ],
                if (iceCard.allergies != null) ...[
                  _buildInfoSection(
                    'Alerjiler',
                    [_buildInfoItem('', iceCard.allergies!)],
                    icon: Icons.warning_amber,
                    iconColor: AppColors.error,
                  ),
                  const SizedBox(height: 20),
                ],
                if (iceCard.additionalNotes != null) ...[
                  _buildInfoSection(
                    'Ek Notlar',
                    [_buildInfoItem('', iceCard.additionalNotes!)],
                    icon: Icons.note,
                    iconColor: cs.onSurfaceVariant,
                  ),
                ],
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _buildEmptyState(isViewingOtherUser),
        ) ??
        _buildEmptyState(isViewingOtherUser);
  }

  Widget _buildEmptyState(bool isViewingOtherUser) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.medical_services_outlined,
            size: 64,
            color: ThemeBrightnessHolder.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'Henüz ICE kartı oluşturulmadı',
            style: AppTypography.titleMedium.copyWith(
              color: ThemeBrightnessHolder.onSurfaceVariant,
            ),
          ),
          if (!isViewingOtherUser) ...[
            const SizedBox(height: 8),
            Text(
              'Acil durum bilgilerini eklemek için düzenle butonuna bas.',
              style: AppTypography.bodySmall.copyWith(
                color: ThemeBrightnessHolder.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            AppButton(
              text: 'ICE Kartı Oluştur',
              icon: Icons.add,
              onPressed: () => setState(() => _isEditing = true),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoSection(
    String title,
    List<Widget> children, {
    required IconData icon,
    required Color iconColor,
  }) {
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTypography.titleSmall.copyWith(color: cs.onSurface),
              ),
            ],
          ),
          const Divider(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(color: cs.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Acil Durumda Aranacak Kişi',
          style: AppTypography.titleMedium.copyWith(color: cs.onSurface),
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _emergencyNameController,
          label: 'Ad Soyad',
          prefixIcon: Icons.person_outline,
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _emergencyPhoneController,
          label: 'Telefon',
          keyboardType: TextInputType.phone,
          prefixIcon: Icons.phone_outlined,
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _emergencyRelationController,
          label: 'Yakınlık Derecesi',
          hint: 'Örn: Eş, Anne, Kardeş',
          prefixIcon: Icons.group_outlined,
        ),
        const SizedBox(height: 24),
        Text(
          'Sağlık Bilgileri',
          style: AppTypography.titleMedium.copyWith(color: cs.onSurface),
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _chronicDiseasesController,
          label: 'Kronik Hastalıklar',
          hint: 'Örn: Diyabet, Astım',
          maxLines: 2,
          prefixIcon: Icons.medical_information_outlined,
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _medicationsController,
          label: 'Kullanılan İlaçlar',
          hint: 'Örn: Metformin 500mg',
          maxLines: 2,
          prefixIcon: Icons.medication_outlined,
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _allergiesController,
          label: 'Alerjiler',
          hint: 'Örn: Penisilin, Arı sokması',
          maxLines: 2,
          prefixIcon: Icons.warning_amber_outlined,
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _additionalNotesController,
          label: 'Ek Notlar',
          hint: 'Diğer önemli bilgiler...',
          maxLines: 3,
          prefixIcon: Icons.note_outlined,
        ),
        const SizedBox(height: 100),
      ],
    );
  }
}
