import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/full_screen_image_viewer.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';

/// Admin için başka kullanıcının profil bilgilerini salt okunur gösterir.
class ProfileDetailsPage extends ConsumerWidget {
  final String userId;

  const ProfileDetailsPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final currentUserId = ref.watch(userIdProvider);
    final isOwnProfile = userId == currentUserId;

    if (!isAdmin && !isOwnProfile) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil Bilgileri')),
        body: const Center(child: Text('Bu sayfaya erişim yetkiniz yok.')),
      );
    }

    final userAsync = ref.watch(userProfileProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: Text(isOwnProfile ? 'Profil Bilgilerim' : 'Profil Bilgileri'),
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Kullanıcı bulunamadı.'));
          }
          return _ProfileDetailsBody(user: user);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Profil yüklenemedi.')),
      ),
    );
  }
}

class _ProfileDetailsBody extends StatelessWidget {
  final UserEntity user;

  const _ProfileDetailsBody({required this.user});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Center(
            child: UserAvatar(
              imageUrl: user.avatarUrl,
              name: user.fullName,
              size: 100,
              showBorder: true,
              borderColor: AppColors.primary,
              borderWidth: 2,
              onTap: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                  ? () => showFullScreenImage(context, user.avatarUrl!)
                  : null,
            ),
          ),
          const SizedBox(height: 24),
          AppCard(
            child: Column(
              children: [
                _InfoRow(label: 'Ad', value: user.firstName),
                _InfoRow(label: 'Soyad', value: user.lastName),
                _InfoRow(label: 'E-posta', value: user.email),
                _InfoRow(label: 'Telefon', value: _formatPhone(user.phone)),
                _InfoRow(label: 'Cinsiyet', value: _formatGender(user.gender)),
                _InfoRow(
                  label: 'Doğum Tarihi',
                  value: user.birthDate != null ? _formatDate(user.birthDate!) : null,
                ),
                _InfoRow(
                  label: 'Kilo',
                  value: user.weight != null ? '${user.weight!.toStringAsFixed(1)} kg' : null,
                ),
                _InfoRow(label: 'Hakkımda', value: user.bio),
                _InfoRow(label: 'Kan Grubu', value: _formatBloodType(user.bloodType)),
                _InfoRow(label: 'Tişört Bedeni', value: _formatTShirtSize(user.tshirtSize)),
                _InfoRow(label: 'Ayakkabı No', value: user.shoeSize),
                _InfoRow(label: 'Rol', value: _formatRoles(user.roles)),
                _InfoRow(label: 'Üyelik Durumu', value: _formatUserStatus(user.userStatus)),
                _InfoRow(
                  label: 'VDOT',
                  value: user.hasVdot ? user.vdot!.toStringAsFixed(1) : null,
                  isLast: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _formatPhone(String? phone) {
    if (phone == null || phone.isEmpty) return null;
    if (phone.startsWith('+')) return phone;
    return '+90 $phone';
  }

  String? _formatGender(Gender? gender) {
    switch (gender) {
      case Gender.female:
        return 'Kadın';
      case Gender.male:
        return 'Erkek';
      case Gender.unknown:
        return 'Belirtmek istemiyorum';
      case null:
        return null;
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  String? _formatBloodType(BloodType bloodType) {
    switch (bloodType) {
      case BloodType.aPositive:
        return 'A+';
      case BloodType.aNegative:
        return 'A-';
      case BloodType.bPositive:
        return 'B+';
      case BloodType.bNegative:
        return 'B-';
      case BloodType.abPositive:
        return 'AB+';
      case BloodType.abNegative:
        return 'AB-';
      case BloodType.oPositive:
        return 'O+';
      case BloodType.oNegative:
        return 'O-';
      case BloodType.unknown:
        return null;
    }
  }

  String? _formatTShirtSize(TShirtSize? size) {
    return size?.name.toUpperCase();
  }

  String? _formatRoles(List<UserRole> roles) {
    final labels = <String>[];
    if (roles.contains(UserRole.superAdmin)) labels.add('Yönetici');
    if (roles.contains(UserRole.coach)) labels.add('Antrenör');
    if (roles.contains(UserRole.member)) labels.add('Üye');
    return labels.isEmpty ? null : labels.join(', ');
  }

  String? _formatUserStatus(UserStatus status) {
    switch (status) {
      case UserStatus.pending:
        return 'Onay Bekliyor';
      case UserStatus.active:
        return 'Aktif';
      case UserStatus.rejected:
        return 'Reddedildi';
      case UserStatus.banned:
        return 'Yasaklı';
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool isLast;

  const _InfoRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = (value == null || value!.trim().isEmpty) ? '—' : value!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  displayValue,
                  style: AppTypography.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1),
      ],
    );
  }
}
