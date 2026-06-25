import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../../shared/widgets/user_avatar.dart';

enum AdminMenuAction {
  profile,
  reports,
  management,
}

class AdminHomeMenuSheet extends StatelessWidget {
  const AdminHomeMenuSheet({super.key, required this.user});

  final UserEntity? user;

  static Future<AdminMenuAction?> show(BuildContext context, {UserEntity? user}) {
    return showModalBottomSheet<AdminMenuAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: false,
      builder: (context) => AdminHomeMenuSheet(user: user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.neutral400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  UserAvatar(
                    imageUrl: user?.avatarUrl,
                    name: user?.fullName,
                    size: 52,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.fullName ?? 'Yönetici',
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Yönetici',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 24),
            _MenuItem(
              icon: Icons.person_outline,
              title: 'Profil',
              subtitle: 'Profil bilgileri ve ayarlar',
              iconColor: AppColors.primary,
              onTap: () => Navigator.pop(context, AdminMenuAction.profile),
            ),
            _MenuItem(
              icon: Icons.assessment_outlined,
              title: 'Raporlar',
              subtitle: 'Dashboard ve tüm raporlar',
              iconColor: AppColors.tertiary,
              onTap: () => Navigator.pop(context, AdminMenuAction.reports),
            ),
            _MenuItem(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Yönetim',
              subtitle: 'Araçlar, kullanıcı ve uygulama ayarları',
              iconColor: AppColors.secondary,
              onTap: () => Navigator.pop(context, AdminMenuAction.management),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(title, style: AppTypography.titleSmall),
      subtitle: Text(
        subtitle,
        style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.neutral400),
      onTap: onTap,
    );
  }
}
