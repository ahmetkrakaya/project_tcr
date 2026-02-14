import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../activity/presentation/providers/activity_provider.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../events/presentation/providers/event_provider.dart';
import '../../../integrations/presentation/providers/strava_provider.dart';
import '../../../integrations/apple_watch/apple_watch_provider.dart';
import '../../../../shared/providers/auth_provider.dart';

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
                icon: const Icon(Icons.arrow_back),
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
                    icon: const Icon(Icons.settings_outlined),
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
                      color: AppColors.neutral500,
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
    final userEventsAsync = ref.watch(currentUserEventsProvider);
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
                value: count.toString(),
                label: 'Koşu',
                icon: Icons.directions_run,
              ),
              loading: () => _buildStatCard(
                value: '...',
                label: 'Koşu',
                icon: Icons.directions_run,
              ),
              error: (_, __) => _buildStatCard(
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
                value: stats != null
                    ? stats.totalDistanceKm.toStringAsFixed(0)
                    : '--',
                label: 'KM',
                icon: Icons.straighten,
              ),
              loading: () => _buildStatCard(
                value: '...',
                label: 'KM',
                icon: Icons.straighten,
              ),
              error: (_, __) => _buildStatCard(
                value: '--',
                label: 'KM',
                icon: Icons.straighten,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: userEventsAsync.when(
              data: (events) => _buildStatCard(
                value: events.length.toString(),
                label: 'Etkinlik',
                icon: Icons.event,
              ),
              loading: () => _buildStatCard(
                value: '...',
                label: 'Etkinlik',
                icon: Icons.event,
              ),
              error: (_, __) => _buildStatCard(
                value: '--',
                label: 'Etkinlik',
                icon: Icons.event,
              ),
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
  
  Widget _buildVdotCard(
    BuildContext context, {
    double? vdot,
    required bool isOwnProfile,
  }) {
    final hasVdot = vdot != null && vdot > 0;

    final card = AppCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      backgroundColor: hasVdot ? AppColors.successContainer : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.speed,
            color: hasVdot ? AppColors.success : AppColors.primary,
            size: 22,
          ),
          const SizedBox(height: 6),
          Text(
            hasVdot ? vdot.toStringAsFixed(1) : '--',
            style: AppTypography.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: hasVdot ? AppColors.success : AppColors.neutral400,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'VDOT',
            style: AppTypography.labelSmall.copyWith(
              color: hasVdot ? AppColors.success : AppColors.neutral500,
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

  Widget _buildStatCard({
    required String value,
    required String label,
    required IconData icon,
  }) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.neutral500,
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
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: (iconColor ?? AppColors.primary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor ?? AppColors.primary, size: 22),
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

  List<Widget> _buildMenuItems(BuildContext context, WidgetRef ref, bool isOwnProfile) {
    final menuItems = <Widget>[];
    final viewingUserIsAdmin = ref.watch(isAdminProvider);
    final targetUserId = userId ?? ref.watch(userIdProvider);
    
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
      
      // Bağlantılar - Sadece kendisi görebilir
      menuItems.add(_buildIntegrationsMenuItem(context, ref));
      
      menuItems.add(const Divider(height: 32));
    } else {
      // Başka kullanıcının profilinde - Sadece admin ise Acil Durum Kartını göster
      if (viewingUserIsAdmin && targetUserId != null) {
        menuItems.add(
          _buildMenuItem(
            context,
            icon: Icons.medical_services_outlined,
            title: 'Acil Durum Kartı',
            subtitle: 'ICE bilgileri',
            iconColor: AppColors.error,
            onTap: () {
              // Başka kullanıcının ICE kartını göster
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
    menuItems.add(
      _buildMenuItem(
        context,
        icon: Icons.history,
        title: isOwnProfile ? 'Aktivite Geçmişim' : 'Aktivite Geçmişi',
        subtitle: isOwnProfile ? 'Tüm koşularım' : 'Tüm koşuları',
        onTap: () {
          // pushNamed kullan ki geri dönünce aynı profile sayfasına dönsün
          // Eğer başka kullanıcının profilindeyse, userId'yi geçir
          context.pushNamed(
            RouteNames.activityHistory,
            queryParameters: !isOwnProfile && targetUserId != null
                ? {'userId': targetUserId}
                : {},
          );
        },
      ),
    );
    
    // İstatistikler
    menuItems.add(
      _buildMenuItem(
        context,
        icon: Icons.bar_chart,
        title: 'İstatistikler',
        subtitle: 'Haftalık ve aylık istatistikler',
        iconColor: AppColors.tertiary,
        onTap: () {
          // pushNamed kullan ki geri dönünce aynı profile sayfasına dönsün
          // Eğer başka kullanıcının profilindeyse, userId'yi geçir
          context.pushNamed(
            RouteNames.statistics,
            queryParameters: !isOwnProfile && targetUserId != null
                ? {'userId': targetUserId}
                : {},
          );
        },
      ),
    );
    
    menuItems.add(const SizedBox(height: 100));
    
    return menuItems;
  }

  Widget _buildIntegrationsMenuItem(BuildContext context, WidgetRef ref) {
    final isStravaConnected = ref.watch(isStravaConnectedProvider);
    final appleWatchState = ref.watch(appleWatchIntegrationProvider);
    final isAppleWatchConnected =
        appleWatchState.isSupported && appleWatchState.authorizationStatus == 'authorized';

    final connectedNames = <String>[];
    if (isStravaConnected) connectedNames.add('Strava');
    if (isAppleWatchConnected) connectedNames.add('Apple Watch');

    String subtitle;
    if (connectedNames.isEmpty) {
      subtitle = 'Henüz bağlantı yok';
    } else if (connectedNames.length == 1) {
      subtitle = '${connectedNames.first} bağlı';
    } else {
      subtitle = '${connectedNames.join(', ')} bağlı';
    }
    
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFFC4C02).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.link, color: Color(0xFFFC4C02), size: 22),
      ),
      title: Text('Bağlantılar', style: AppTypography.titleSmall),
      subtitle: Text(
        subtitle,
        style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (connectedNames.isNotEmpty)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
            ),
          const Icon(Icons.chevron_right, color: AppColors.neutral400),
        ],
      ),
      onTap: () => context.pushNamed(RouteNames.integrations),
    );
  }
}
