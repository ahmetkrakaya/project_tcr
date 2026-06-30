import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';

class AdminReportsHubPage extends ConsumerWidget {
  const AdminReportsHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Yönetim'),
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
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'Araçlar, kullanıcı ve uygulama ayarlarına buradan ulaşabilirsiniz.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
                const SizedBox(height: 24),
                _SectionHeader(title: 'Araçlar'),
                _MenuCard(
                  icon: Icons.route_outlined,
                  title: 'Rotalar',
                  subtitle: 'GPX rotalarını görüntüle ve yönet',
                  iconColor: AppColors.tertiary,
                  onTap: () => context.pushNamed(RouteNames.routes),
                ),
                const SizedBox(height: 12),
                _MenuCard(
                  icon: Icons.notifications_active_outlined,
                  title: 'Bildirim Oluştur',
                  subtitle: 'Hedef kitle seçip manuel bildirim gönder',
                  iconColor: AppColors.warning,
                  onTap: () =>
                      context.pushNamed(RouteNames.adminCreateNotification),
                ),
                const SizedBox(height: 12),
                _MenuCard(
                  icon: Icons.local_offer_outlined,
                  title: 'Üye Avantajları',
                  subtitle: 'Partner kampanyalarını ekle ve yönet',
                  iconColor: const Color(0xFF1B4332),
                  onTap: () =>
                      context.pushNamed(RouteNames.adminPartnerCampaigns),
                ),
                const SizedBox(height: 24),
                _SectionHeader(title: 'Kullanıcı'),
                _MenuCard(
                  icon: Icons.person_off_outlined,
                  title: 'Engellenen ve Reddedilenler',
                  subtitle: 'Engellenen ve reddedilen kullanıcı listesi',
                  iconColor: AppColors.error,
                  onTap: () =>
                      context.pushNamed(RouteNames.adminBannedRejectedUsers),
                ),
                const SizedBox(height: 24),
                _SectionHeader(title: 'Uygulama'),
                _MenuCard(
                  icon: Icons.system_update_alt_outlined,
                  title: 'App Versiyon',
                  subtitle: 'iOS ve Android güncelleme ayarları',
                  iconColor: AppColors.primary,
                  onTap: () => context.pushNamed(RouteNames.adminAppVersions),
                ),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: AppTypography.titleMedium.copyWith(
          color: AppColors.neutral500,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.neutral400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
