import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/full_screen_image_viewer.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../activity/presentation/providers/activity_provider.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../providers/statistics_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// Profile Page
class ProfilePage extends ConsumerWidget {
  final String? userId;
  
  const ProfilePage({super.key, this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kendi profilinde mi yoksa başka kullanıcının profilinde mi olduğunu kontrol et
    final currentUserId = ref.watch(userIdProvider);
    final isOwnProfile = userId == null || userId == currentUserId;
    
    final screenHeight = MediaQuery.sizeOf(context).height;
    final appBarHeight = (screenHeight * 0.28).clamp(220.0, 320.0);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar with Profile Header
          SliverAppBar(
            expandedHeight: appBarHeight,
            pinned: true,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.goNamed(RouteNames.home);
                  }
                },
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildProfileHeader(context, ref),
            ),
            actions: [
              // Sadece kendi profilinde settings göster
              if (userId == null)
                Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.settings_outlined),
                    onPressed: () => context.pushNamed(RouteNames.settings),
                  ),
                ),
            ],
          ),

          // Stats Cards
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _buildStatsGrid(context, ref, isOwnProfile),
            ),
          ),

          // Menu Items Başlığı
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOwnProfile ? 'Profilim' : 'Profil',
                    style: AppTypography.titleMedium.copyWith(
                      color: ThemeBrightnessHolder.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Menu List
          SliverList(
            delegate: SliverChildListDelegate(
              _buildMenuItems(context, ref, isOwnProfile),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, WidgetRef ref) {
    // Profil verisini al - loading durumunu kontrol et
    if (userId != null) {
      final userAsync = ref.watch(userProfileProvider(userId!));
      return userAsync.when(
        data: (user) => _buildProfileHeaderContent(context, ref, user),
        loading: () => _buildProfileHeaderLoading(context),
        error: (_, __) => _buildProfileHeaderContent(context, ref, null),
      );
    } else {
      final user = ref.watch(currentUserProfileProvider);
      return _buildProfileHeaderContent(context, ref, user);
    }
  }

  Widget _buildProfileHeaderLoading(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: 150,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 80,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeaderContent(BuildContext context, WidgetRef ref, UserEntity? user) {
    // Rolleri al
    final roles = user?.roles ?? [UserRole.member];

    String roleText = 'Üye';
    Color roleColor = AppColors.member;
    if (roles.contains(UserRole.superAdmin)) {
      roleText = 'Yönetici';
      roleColor = AppColors.superAdmin;
    } else if (roles.contains(UserRole.coach)) {
      roleText = 'Antrenör';
      roleColor = AppColors.coach;
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final avatarSize = (screenWidth * 0.2).clamp(72.0, 96.0);

    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              UserAvatar(
                imageUrl: user?.avatarUrl,
                name: user?.fullName,
                size: avatarSize,
                showBorder: true,
                borderColor: Colors.white,
                borderWidth: 3,
                onTap: user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                    ? () => showFullScreenImage(context, user.avatarUrl!)
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                user?.fullName ?? 'TCR Üyesi',
                style: AppTypography.headlineSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  roleText,
                  style: AppTypography.labelMedium.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (user?.bio != null)
                Text(
                  user!.bio!,
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, WidgetRef ref, bool isOwnProfile) {
    // Eğer başka kullanıcının profilini görüyorsak, o kullanıcının istatistiklerini göster
    final targetUserId = userId ?? ref.watch(userIdProvider);
    
    final userVdot = userId != null 
        ? ref.watch(userProfileProvider(userId!)).valueOrNull?.vdot
        : ref.watch(userVdotProvider);
    final statsAsync = targetUserId != null
        ? ref.watch(userStatisticsProvider(targetUserId))
        : ref.watch(currentUserStatisticsProvider);
    final pointsAsync = targetUserId != null
        ? ref.watch(userTotalPointsProvider(targetUserId))
        : const AsyncValue<int>.data(0);
    final runningCountAsync = targetUserId != null
        ? ref.watch(userRunningActivitiesCountProvider(targetUserId))
        : ref.watch(currentUserRunningActivitiesCountProvider);
    
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: runningCountAsync.when(
              data: (count) => _buildStatCard(
                context,
                value: count.toString(),
                label: 'Koşu',
                icon: Icons.directions_run,
              ),
              loading: () => _buildStatCard(
                context,
                value: '...',
                label: 'Koşu',
                icon: Icons.directions_run,
              ),
              error: (_, __) => _buildStatCard(
                context,
                value: '--',
                label: 'Koşu',
                icon: Icons.directions_run,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: statsAsync.when(
              data: (stats) => _buildStatCard(
                context,
                value: stats != null
                    ? stats.totalDistanceKm.toStringAsFixed(0)
                    : '--',
                label: 'KM',
                icon: Icons.straighten,
              ),
              loading: () => _buildStatCard(
                context,
                value: '...',
                label: 'KM',
                icon: Icons.straighten,
              ),
              error: (_, __) => _buildStatCard(
                context,
                value: '--',
                label: 'KM',
                icon: Icons.straighten,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: pointsAsync.when(
              data: (points) => _buildPointsCard(context, points),
              loading: () => _buildPointsCard(context, null),
              error: (_, __) => _buildPointsCard(context, null),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildVdotCard(
              context,
              vdot: userVdot,
              isOwnProfile: isOwnProfile,
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatPoints(int points) {
    if (points >= 1000) {
      final thousands = points ~/ 1000;
      return '${thousands}K';
    }
    return points.toString();
  }

  Widget _buildPointsCard(BuildContext context, int? points) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final hasPoints = points != null && points > 0;
    const accent = Color(0xFFFF8F00);

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      backgroundColor: hasPoints
          ? (isDark ? accent.withValues(alpha: 0.14) : const Color(0xFFFFF8E1))
          : null,
      border: Border.all(
        color: hasPoints && isDark
            ? accent.withValues(alpha: 0.35)
            : cs.outlineVariant,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.emoji_events,
            color: hasPoints ? accent : cs.primary,
            size: 22,
          ),
          const SizedBox(height: 6),
          Text(
            hasPoints ? _formatPoints(points) : (points == null ? '...' : '0'),
            style: AppTypography.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: hasPoints
                  ? accent
                  : (isDark ? cs.onSurfaceVariant : AppColors.neutral400),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Puan',
            style: AppTypography.labelSmall.copyWith(
              color: hasPoints
                  ? accent
                  : (isDark ? cs.onSurfaceVariant : AppColors.neutral500),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildVdotCard(
    BuildContext context, {
    double? vdot,
    required bool isOwnProfile,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final hasVdot = vdot != null && vdot > 0;
    final successColor = isDark ? AppColors.secondaryLight : AppColors.success;

    final card = AppCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      backgroundColor: hasVdot
          ? (isDark
              ? successColor.withValues(alpha: 0.14)
              : AppColors.successContainer)
          : null,
      border: Border.all(
        color: hasVdot && isDark
            ? successColor.withValues(alpha: 0.35)
            : cs.outlineVariant,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.speed,
            color: hasVdot ? successColor : cs.primary,
            size: 22,
          ),
          const SizedBox(height: 6),
          Text(
            hasVdot ? vdot.toStringAsFixed(1) : '--',
            style: AppTypography.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: hasVdot
                  ? successColor
                  : (isDark ? cs.onSurfaceVariant : AppColors.neutral400),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'VDOT',
            style: AppTypography.labelSmall.copyWith(
              color: hasVdot
                  ? successColor
                  : (isDark ? cs.onSurfaceVariant : AppColors.neutral500),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (!isOwnProfile) {
      // Başkasının profilinde VDOT kartı sadece görüntülenir, tıklanamaz
      return card;
    }

    return GestureDetector(
      onTap: () => context.pushNamed(RouteNames.paceCalculator),
      child: card,
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String value,
    required String label,
    required IconData icon,
  }) {
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      border: Border.all(color: cs.outlineVariant),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: cs.primary, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final accent = iconColor ?? cs.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.28)),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              title: Text(
                title,
                style: AppTypography.titleSmall.copyWith(color: cs.onSurface),
              ),
              subtitle: Text(
                subtitle,
                style: AppTypography.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              trailing: Icon(Icons.chevron_right, color: cs.outline),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMenuItems(BuildContext context, WidgetRef ref, bool isOwnProfile) {
    final menuItems = <Widget>[];
    final viewingUserIsAdmin = ref.watch(isAdminProvider);
    final currentUserId = ref.watch(userIdProvider);
    final targetUserId = userId ?? currentUserId;
    
    // Kendi profilinde gösterilecek öğeler
    if (isOwnProfile) {
      // Profil Düzenle - Herkes görebilir (kendi profilinde)
      menuItems.add(
        _buildMenuItem(
          context,
          icon: Icons.person_outline,
          title: 'Profili Düzenle',
          subtitle: 'Ad, soyad, iletişim bilgileri',
          onTap: () => context.pushNamed(RouteNames.profileEdit),
        ),
      );
      
      // Acil Durum Kartı - Kendi profilinde ve admin ise görebilir
      if (viewingUserIsAdmin) {
        menuItems.add(
          _buildMenuItem(
            context,
            icon: Icons.medical_services_outlined,
            title: 'Acil Durum Kartı',
            subtitle: 'ICE bilgileri',
            iconColor: AppColors.error,
            onTap: () => context.pushNamed(
              RouteNames.iceCard,
              queryParameters: {},
            ),
          ),
        );
      }
      
      // VDOT Hesaplayıcı - Herkes görebilir (kendi profilinde)
      menuItems.add(
        _buildMenuItem(
          context,
          icon: Icons.speed,
          title: 'VDOT Hesaplayıcı',
          subtitle: 'Antrenman pace\'lerini hesapla',
          iconColor: AppColors.success,
          onTap: () => context.pushNamed(RouteNames.paceCalculator),
        ),
      );

      // Üye Avantajları
      menuItems.add(
        _buildMenuItem(
          context,
          icon: Icons.local_offer_outlined,
          title: 'Üye Avantajları',
          subtitle: 'Partner işletmelerde indirimler',
          iconColor: const Color(0xFF1B4332),
          onTap: () => context.pushNamed(RouteNames.partnerPerks),
        ),
      );
      
      // Bağlantılar - Sadece kendisi görebilir
      menuItems.add(_buildIntegrationsMenuItem(context, ref));

      // Aktivite Geçmişi
      menuItems.add(
        _buildMenuItem(
          context,
          icon: Icons.history,
          title: 'Aktivite Geçmişim',
          subtitle: 'Tüm koşularım',
          onTap: () {
            context.pushNamed(
              RouteNames.activityHistory,
              queryParameters: {},
            );
          },
        ),
      );

      // Strava Watch: sadece 3 kişi görebilir
      if (currentUserId != null &&
          StravaWatchConstants.allowedUserIds.contains(currentUserId)) {
        menuItems.add(
          _buildMenuItem(
            context,
            icon: Icons.visibility,
            title: 'Ahmet & Ayça\'nın Koşuları',
            subtitle: 'Deli mi bunlar, dur bir bak!',
            iconColor: const Color(0xFFFC4C02),
            onTap: () => context.pushNamed(RouteNames.runningViewer),
          ),
        );
      }

      // İstatistikler
      menuItems.add(
        _buildMenuItem(
          context,
          icon: Icons.bar_chart,
          title: 'İstatistikler',
          subtitle: 'Haftalık ve aylık istatistikler',
          iconColor: AppColors.tertiary,
          onTap: () {
            context.pushNamed(
              RouteNames.statistics,
              queryParameters: {},
            );
          },
        ),
      );

      final isCoachOnly = ref.watch(isCoachProvider) && !viewingUserIsAdmin;

      if (isCoachOnly) {
        menuItems.add(const Divider(height: 32));

        menuItems.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yönetim Araçları',
                  style: AppTypography.titleMedium.copyWith(
                    color: ThemeBrightnessHolder.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );

        menuItems.add(
          _buildMenuItem(
            context,
            icon: Icons.route_outlined,
            title: 'Rotalar',
            subtitle: 'GPX rotalarını görüntüle ve yönet',
            iconColor: AppColors.tertiary,
            onTap: () => context.pushNamed(RouteNames.routes),
          ),
        );
      }
    } else {
      // Başka kullanıcının profilinde - Admin profil bilgilerini görebilir
      if (viewingUserIsAdmin && targetUserId != null) {
        menuItems.add(
          _buildMenuItem(
            context,
            icon: Icons.person_outline,
            title: 'Profil Bilgileri',
            subtitle: 'Ad, soyad, iletişim bilgileri',
            onTap: () {
              context.pushNamed(
                RouteNames.profileDetails,
                queryParameters: {'userId': targetUserId},
              );
            },
          ),
        );
        menuItems.add(
          _buildMenuItem(
            context,
            icon: Icons.medical_services_outlined,
            title: 'Acil Durum Kartı',
            subtitle: 'ICE bilgileri',
            iconColor: AppColors.error,
            onTap: () {
              context.pushNamed(
                RouteNames.iceCard,
                queryParameters: {'userId': targetUserId},
              );
            },
          ),
        );
        menuItems.add(const Divider(height: 32));
      }
    }
    
    // Herkes görebilir (hem kendi hem başkalarının profilinde)
    // Aktivite Geçmişi
    if (!isOwnProfile) {
      menuItems.add(
        _buildMenuItem(
          context,
          icon: Icons.history,
          title: 'Aktivite Geçmişi',
          subtitle: 'Tüm koşuları',
          onTap: () {
            context.pushNamed(
              RouteNames.activityHistory,
              queryParameters: targetUserId != null ? {'userId': targetUserId} : {},
            );
          },
        ),
      );
    }
    
    // İstatistikler
    if (!isOwnProfile) {
      menuItems.add(
        _buildMenuItem(
          context,
          icon: Icons.bar_chart,
          title: 'İstatistikler',
          subtitle: 'Haftalık ve aylık istatistikler',
          iconColor: AppColors.tertiary,
          onTap: () {
            context.pushNamed(
              RouteNames.statistics,
              queryParameters: targetUserId != null ? {'userId': targetUserId} : {},
            );
          },
        ),
      );
    }

    // Strava Watch: sadece 3 kişinin profilinde ve sadece 3 kişiye görünür
    if (!isOwnProfile &&
        currentUserId != null &&
        StravaWatchConstants.allowedUserIds.contains(currentUserId) &&
        targetUserId != null &&
        StravaWatchConstants.allowedUserIds.contains(targetUserId)) {
      menuItems.add(
        _buildMenuItem(
          context,
          icon: Icons.directions_run,
          title: 'Koşuları Gör',
          subtitle: 'Ahmet & Ayça\'nın tüm koşuları',
          iconColor: const Color(0xFFFC4C02),
          onTap: () => context.pushNamed(RouteNames.runningViewer),
        ),
      );
    }

    menuItems.add(const SizedBox(height: 100));
    
    return menuItems;
  }

  Widget _buildIntegrationsMenuItem(BuildContext context, WidgetRef ref) {
    const subtitle = 'Koşu ve antrenman uygulamalarınızı buradan bağlayın.';
    const stravaColor = Color(0xFFFC4C02);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.pushNamed(RouteNames.integrations),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: stravaColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: stravaColor.withValues(alpha: 0.28)),
                ),
                child: const Icon(Icons.link, color: stravaColor, size: 22),
              ),
              title: Text(
                'Bağlantılar',
                style: AppTypography.titleSmall.copyWith(color: cs.onSurface),
              ),
              subtitle: Text(
                subtitle,
                style: AppTypography.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              trailing: Icon(Icons.chevron_right, color: cs.outline),
            ),
          ),
        ),
      ),
    );
  }
}
