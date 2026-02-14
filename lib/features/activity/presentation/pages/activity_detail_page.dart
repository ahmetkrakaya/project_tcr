import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../domain/entities/activity_entity.dart';
import '../../presentation/providers/activity_provider.dart';
import '../../../integrations/domain/entities/integration_entity.dart';
import '../../../integrations/presentation/providers/strava_provider.dart' show stravaNotifierProvider;

/// Activity Detail Page
class ActivityDetailPage extends ConsumerWidget {
  final String activityId;

  const ActivityDetailPage({
    super.key,
    required this.activityId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(activityByIdProvider(activityId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Aktivite Detayı'),
      ),
      body: activityAsync.when(
        data: (activity) {
          if (activity == null) {
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
                    'Aktivite bulunamadı',
                    style: AppTypography.titleLarge,
                  ),
                ],
              ),
            );
          }
          return _buildContent(context, activity, ref);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
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
                error.toString(),
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.neutral500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Geri Dön'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ActivityEntity activity, WidgetRef ref) {
    // Strava aktivitesi ise detaylı verileri çek
    final isStravaActivity = activity.source == ActivitySource.strava && activity.externalId != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserAvatar(
                      size: 56,
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
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                _getActivityIcon(activity.activityType),
                                size: 16,
                                color: AppColors.neutral500,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                timeago.format(activity.startTime, locale: 'tr'),
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.neutral500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildSourceBadge(activity.source),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  activity.title ?? _getDefaultTitle(activity.activityType),
                  style: AppTypography.headlineSmall.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Primary Stats
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Temel Bilgiler',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatsGrid(activity),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Detailed Metrics
          if (_hasDetailedMetrics(activity))
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Detaylı Metrikler',
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailedMetrics(activity),
                ],
              ),
            ),

          // Strava Detaylı Veriler (Splits, Best Efforts, Heart Zones)
          if (isStravaActivity)
            _buildStravaDetailedData(context, ref, activity.externalId!),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(ActivityEntity activity) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: [
        if (activity.distanceMeters != null && activity.distanceMeters! > 0)
          _buildStatCard(
            icon: Icons.straighten,
            label: 'Mesafe',
            value: '${activity.distanceKm.toStringAsFixed(2)} km',
          ),
        if (activity.averagePaceSeconds != null)
          _buildStatCard(
            icon: Icons.speed,
            label: 'Pace',
            value: '${activity.formattedPace} /km',
          ),
        if (activity.durationSeconds != null)
          _buildStatCard(
            icon: Icons.timer,
            label: 'Süre',
            value: activity.formattedDuration,
          ),
        if (activity.caloriesBurned != null)
          _buildStatCard(
            icon: Icons.local_fire_department,
            label: 'Kalori',
            value: '${activity.caloriesBurned} Cal',
          ),
        if (activity.elevationGain != null && activity.elevationGain! > 0)
          _buildStatCard(
            icon: Icons.terrain,
            label: 'Yükseklik',
            value: '${activity.elevationGain!.toStringAsFixed(0)} m',
          ),
        if (activity.averageHeartRate != null)
          _buildStatCard(
            icon: Icons.favorite,
            label: 'Ort. KH',
            value: '${activity.averageHeartRate} bpm',
          ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 32, color: AppColors.primary),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.neutral500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildDetailedMetrics(ActivityEntity activity) {
    return Column(
      children: [
        if (activity.bestPaceSeconds != null)
          _buildMetricRow(
            icon: Icons.speed,
            label: 'En İyi Pace',
            value: '${activity.formattedBestPace} /km',
            color: AppColors.success,
          ),
        if (activity.maxHeartRate != null)
          _buildMetricRow(
            icon: Icons.favorite,
            label: 'Max Kalp Atışı',
            value: '${activity.maxHeartRate} bpm',
            color: AppColors.error,
          ),
        if (activity.averageCadence != null)
          _buildMetricRow(
            icon: Icons.trending_up,
            label: 'Ortalama Kadans',
            value: '${activity.averageCadence!.toStringAsFixed(0)} spm',
          ),
        if (activity.endTime != null)
          _buildMetricRow(
            icon: Icons.access_time,
            label: 'Bitiş Zamanı',
            value: '${activity.endTime!.hour.toString().padLeft(2, '0')}:${activity.endTime!.minute.toString().padLeft(2, '0')}',
          ),
        _buildMetricRow(
          icon: Icons.schedule,
          label: 'Başlangıç Zamanı',
          value: '${activity.startTime.hour.toString().padLeft(2, '0')}:${activity.startTime.minute.toString().padLeft(2, '0')}',
        ),
      ],
    );
  }

  Widget _buildMetricRow({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (color ?? AppColors.primary).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: color ?? AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyMedium,
            ),
          ),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: color ?? AppColors.neutral900,
            ),
          ),
        ],
      ),
    );
  }

  bool _hasDetailedMetrics(ActivityEntity activity) {
    return activity.bestPaceSeconds != null ||
        activity.maxHeartRate != null ||
        activity.averageCadence != null ||
        activity.endTime != null;
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

  Widget _buildSplitsTable(List<StravaSplitEntity> splits) {
    return Column(
      children: [
        // Header
        Row(
          children: [
            Expanded(
              flex: 1,
              child: Text(
                'KM',
                style: AppTypography.labelSmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.neutral600,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Pace',
                style: AppTypography.labelSmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.neutral600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Süre',
                style: AppTypography.labelSmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.neutral600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (splits.any((s) => s.averageHeartrate != null))
              Expanded(
                flex: 2,
                child: Text(
                  'KH',
                  style: AppTypography.labelSmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.neutral600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
        const Divider(height: 16),
        // Rows
        ...splits.map((split) {
          final minutes = split.movingTime ~/ 60;
          final seconds = split.movingTime % 60;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Text(
                    '${split.split}',
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    split.formattedPace,
                    style: AppTypography.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '$minutes:${seconds.toString().padLeft(2, '0')}',
                    style: AppTypography.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (splits.any((s) => s.averageHeartrate != null))
                  Expanded(
                    flex: 2,
                    child: Text(
                      split.averageHeartrate != null
                          ? '${split.averageHeartrate!.round()} bpm'
                          : '--',
                      style: AppTypography.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBestEffortsList(List<StravaBestEffortEntity> bestEfforts) {
    return Column(
      children: bestEfforts.map((effort) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: effort.isPersonalRecord
                ? AppColors.success.withValues(alpha: 0.1)
                : AppColors.neutral100,
            borderRadius: BorderRadius.circular(8),
            border: effort.isPersonalRecord
                ? Border.all(color: AppColors.success, width: 1)
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          effort.name,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (effort.isPersonalRecord) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'PR',
                              style: AppTypography.labelSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      effort.formattedTime,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.bold,
                        color: effort.isPersonalRecord
                            ? AppColors.success
                            : AppColors.neutral900,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    effort.formattedPace,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (effort.averageHeartrate != null)
                    Text(
                      '${effort.averageHeartrate!.round()} bpm',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHeartZonesChart(List<StravaHeartZoneEntity> zones) {
    final totalTime = zones.fold<int>(0, (sum, zone) => sum + zone.time);
    if (totalTime == 0) return const SizedBox.shrink();

    // Zone isimleri (Strava standardına göre)
    final zoneNames = [
      'Zone 1 (Recovery)',
      'Zone 2 (Aerobic)',
      'Zone 3 (Tempo)',
      'Zone 4 (Threshold)',
      'Zone 5 (VO2 Max)',
      'Zone 6 (Neuromuscular)',
    ];

    return Column(
      children: zones.asMap().entries.map((entry) {
        final index = entry.key;
        final zone = entry.value;
        final percentage = (zone.time / totalTime * 100);
        final zoneName = index < zoneNames.length 
            ? zoneNames[index] 
            : 'Zone ${index + 1}';
        
        // max -1 ise "ve üzeri" anlamına gelir
        final maxLabel = zone.max == -1 
            ? '${zone.min}+' 
            : '${zone.min}-${zone.max}';
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    zoneName,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${zone.formattedTime} (${percentage.toStringAsFixed(1)}%)',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percentage / 100,
                  minHeight: 8,
                  backgroundColor: AppColors.neutral200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getZoneColor(zone.max == -1 ? 999 : zone.max),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$maxLabel bpm',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.neutral500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _getZoneColor(int max) {
    // Kalp atış hızı zone'larına göre renkler (Strava standardı)
    // Zone 1 (Recovery): Mavi
    // Zone 2 (Aerobic): Yeşil
    // Zone 3 (Tempo): Sarı
    // Zone 4 (Threshold): Turuncu
    // Zone 5 (VO2 Max): Kırmızı
    // Zone 6 (Neuromuscular): Koyu kırmızı
    
    if (max <= 124) return Colors.blue.shade400; // Zone 1
    if (max <= 154) return Colors.green.shade500; // Zone 2
    if (max <= 169) return Colors.yellow.shade600; // Zone 3
    if (max <= 184) return Colors.orange.shade600; // Zone 4
    if (max <= 999) return Colors.red.shade600; // Zone 5
    return Colors.red.shade900; // Zone 6 veya üzeri
  }

  Widget _buildStravaDetailedData(BuildContext context, WidgetRef ref, String externalId) {
    final stravaId = int.tryParse(externalId);
    if (stravaId == null) return const SizedBox.shrink();

    // Detaylı verileri çek
    final detailFuture = Future(() async {
      final notifier = ref.read(stravaNotifierProvider.notifier);
      return await notifier.fetchActivityDetail(stravaId);
    });

    final zonesFuture = Future(() async {
      final notifier = ref.read(stravaNotifierProvider.notifier);
      return await notifier.fetchActivityZones(stravaId);
    });

    return FutureBuilder<StravaActivityDetailEntity?>(
      future: detailFuture,
      builder: (context, detailSnapshot) {
        return FutureBuilder<List<StravaHeartZoneEntity>>(
          future: zonesFuture,
          builder: (context, zonesSnapshot) {
            return Column(
              children: [
                const SizedBox(height: 16),
                // Splits
                if (detailSnapshot.hasData && detailSnapshot.data?.splits.isNotEmpty == true)
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kilometre Bölümleri',
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSplitsTable(detailSnapshot.data!.splits),
                      ],
                    ),
                  ),
                // Best Efforts
                if (detailSnapshot.hasData && detailSnapshot.data?.bestEfforts.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'En İyi Performanslar',
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildBestEffortsList(detailSnapshot.data!.bestEfforts),
                      ],
                    ),
                  ),
                ],
                // Heart Zones
                if (zonesSnapshot.hasData && zonesSnapshot.data?.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kalp Atışı Bölgeleri',
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildHeartZonesChart(zonesSnapshot.data!),
                      ],
                    ),
                  ),
                ],
                // Loading
                if (detailSnapshot.connectionState == ConnectionState.waiting ||
                    zonesSnapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Activity By ID Provider
final activityByIdProvider = FutureProvider.family<ActivityEntity?, String>((ref, activityId) async {
  final dataSource = ref.watch(activityDataSourceProvider);
  try {
    final model = await dataSource.getActivityById(activityId);
    return model.toEntity();
  } catch (e) {
    return null;
  }
});
