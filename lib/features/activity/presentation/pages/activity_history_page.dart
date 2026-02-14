import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../domain/entities/activity_entity.dart';
import '../../presentation/providers/activity_provider.dart';

/// Activity History Page - Kullanıcının tüm aktiviteleri
class ActivityHistoryPage extends ConsumerStatefulWidget {
  final String? userId; // Başka kullanıcının aktivitelerini görmek için
  
  const ActivityHistoryPage({super.key, this.userId});

  @override
  ConsumerState<ActivityHistoryPage> createState() => _ActivityHistoryPageState();
}

class _ActivityHistoryPageState extends ConsumerState<ActivityHistoryPage> {
  final ScrollController _scrollController = ScrollController();
  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    // Türkçe timeago
    timeago.setLocaleMessages('tr', timeago.TrMessages());

    // Infinite scroll için scroll listener
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // İlk yükleme - sadece bir kez
    if (!_hasInitialized) {
      _hasInitialized = true;
      final targetUserId = widget.userId ?? ref.read(userIdProvider);
      if (targetUserId != null) {
        Future.microtask(() {
          if (mounted) {
            ref.read(userActivitiesNotifierProvider(targetUserId).notifier).loadActivities();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      // %80'e ulaştığında daha fazla yükle
      final targetUserId = widget.userId ?? ref.read(userIdProvider);
      if (targetUserId != null) {
        ref.read(userActivitiesNotifierProvider(targetUserId).notifier).loadMore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Eğer userId verilmişse o kullanıcının, yoksa kendi aktivitelerini göster
    final targetUserId = widget.userId ?? ref.read(userIdProvider);
    final isViewingOtherUser = widget.userId != null;
    
    final activitiesState = targetUserId != null
        ? ref.watch(userActivitiesNotifierProvider(targetUserId))
        : ref.watch(currentUserActivitiesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isViewingOtherUser ? 'Aktivite Geçmişi' : 'Aktivite Geçmişim'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (targetUserId != null) {
            await ref.read(userActivitiesNotifierProvider(targetUserId).notifier).refresh();
          } else {
            await ref.read(currentUserActivitiesProvider.notifier).refresh();
          }
        },
        child: _buildBody(context, activitiesState),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ActivityFeedState activitiesState) {
    if (activitiesState.isLoading && activitiesState.activities.isEmpty) {
      return const Center(child: LoadingWidget());
    }

    if (activitiesState.error != null && activitiesState.activities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Bir hata oluştu',
              style: AppTypography.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              activitiesState.error!,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.neutral500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final targetUserId = widget.userId ?? ref.read(userIdProvider);
                if (targetUserId != null) {
                  ref.read(userActivitiesNotifierProvider(targetUserId).notifier).refresh();
                } else {
                  ref.read(currentUserActivitiesProvider.notifier).refresh();
                }
              },
              child: const Text('Yeniden Dene'),
            ),
          ],
        ),
      );
    }

    if (activitiesState.activities.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.directions_run,
        title: 'Henüz aktivite yok',
        description: 'İlk koşunu paylaş ve topluluğu motive et!',
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: activitiesState.activities.length + (activitiesState.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= activitiesState.activities.length) {
          // Loading indicator at the bottom
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final activity = activitiesState.activities[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildActivityCard(context, activity),
        );
      },
    );
  }

  Widget _buildActivityCard(BuildContext context, ActivityEntity activity) {
    return InkWell(
      onTap: () => context.pushNamed(
        RouteNames.activityDetail,
        pathParameters: {'activityId': activity.id},
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Header
            Row(
              children: [
                UserAvatar(
                  size: 44,
                  name: activity.userName,
                  imageUrl: activity.userAvatarUrl,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.userName,
                        style: AppTypography.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            _getActivityIcon(activity.activityType),
                            size: 14,
                            color: AppColors.neutral500,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeago.format(activity.startTime, locale: 'tr'),
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.neutral500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '·',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.neutral500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          _buildSourceBadge(activity.source),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Activity Title
            Text(
              activity.title ?? _getDefaultTitle(activity.activityType),
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // Stats Row - Sadece temel bilgiler (Mesafe, Pace, Süre)
            Row(
              children: [
                if (activity.distanceMeters != null && activity.distanceMeters! > 0)
                  _buildStatItem(
                    icon: Icons.straighten,
                    value: '${activity.distanceKm.toStringAsFixed(2)} km',
                    label: 'Mesafe',
                  ),
                if (activity.averagePaceSeconds != null)
                  _buildStatItem(
                    icon: Icons.speed,
                    value: '${activity.formattedPace} /km',
                    label: 'Pace',
                  ),
                if (activity.durationSeconds != null)
                  _buildStatItem(
                    icon: Icons.timer_outlined,
                    value: activity.formattedDuration,
                    label: 'Süre',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getActivityIcon(ActivityType type) {
    switch (type) {
      case ActivityType.running:
        return Icons.directions_run;
      case ActivityType.walking:
        return Icons.directions_walk;
      case ActivityType.cycling:
        return Icons.directions_bike;
      case ActivityType.strength:
        return Icons.fitness_center;
      case ActivityType.swimming:
        return Icons.pool;
      case ActivityType.yoga:
        return Icons.self_improvement;
      case ActivityType.other:
        return Icons.sports;
    }
  }

  String _getDefaultTitle(ActivityType type) {
    switch (type) {
      case ActivityType.running:
        return 'Koşu';
      case ActivityType.walking:
        return 'Yürüyüş';
      case ActivityType.cycling:
        return 'Bisiklet';
      case ActivityType.strength:
        return 'Güç Antrenmanı';
      case ActivityType.swimming:
        return 'Yüzme';
      case ActivityType.yoga:
        return 'Yoga';
      case ActivityType.other:
        return 'Aktivite';
    }
  }

  Widget _buildSourceBadge(ActivitySource source) {
    if (source == ActivitySource.strava) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFC4C02).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              AssetPaths.stravaIcon,
              width: 12,
              height: 12,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 4),
            Text(
              'Strava',
              style: AppTypography.labelSmall.copyWith(
                color: const Color(0xFFFC4C02),
                fontWeight: FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.neutral500,
            ),
          ),
        ],
      ),
    );
  }
}
