import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/integration_entity.dart';
import '../providers/strava_provider.dart';

/// Strava Activity List Page - Liste görünümü ile aktiviteleri göster ve tek tek import et
class StravaActivityListPage extends ConsumerStatefulWidget {
  const StravaActivityListPage({super.key});

  @override
  ConsumerState<StravaActivityListPage> createState() => _StravaActivityListPageState();
}

class _StravaActivityListPageState extends ConsumerState<StravaActivityListPage> {
  final Map<String, bool> _importingActivities = {}; // activityId -> isImporting

  @override
  void initState() {
    super.initState();
    // Cache'den yükle veya ilk yükleme yap
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final listState = ref.read(stravaActivityListProvider);
      if (listState.activities.isEmpty && !listState.isLoading) {
        ref.read(stravaActivityListProvider.notifier).loadActivities();
      }
    });
  }

  Future<void> _importActivity(StravaActivityEntity activity) async {
    setState(() {
      _importingActivities[activity.id.toString()] = true;
    });

    try {
      final success = await ref.read(stravaActivityListProvider.notifier).importActivity(activity);

      if (mounted) {
        setState(() {
          _importingActivities[activity.id.toString()] = false;
        });

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${activity.name} başarıyla import edildi'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          final error = ref.read(stravaNotifierProvider).error;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Import başarısız: ${error ?? "Bilinmeyen hata"}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _importingActivities[activity.id.toString()] = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import hatası: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  bool _isImported(String activityId) {
    final listState = ref.watch(stravaActivityListProvider);
    return listState.importedIds.contains(activityId);
  }

  bool _isImporting(String activityId) {
    return _importingActivities[activityId] ?? false;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Bugün ${DateFormat('HH:mm').format(date)}';
    } else if (difference.inDays == 1) {
      return 'Dün ${DateFormat('HH:mm').format(date)}';
    } else if (difference.inDays < 7) {
      return timeago.format(date, locale: 'tr');
    } else {
      return DateFormat('d MMM yyyy HH:mm', 'tr_TR').format(date);
    }
  }

  String _formatActivityType(String type) {
    switch (type.toLowerCase()) {
      case 'run':
      case 'running':
      case 'virtualrun':
      case 'trailrun':
        return 'Koşu';
      case 'ride':
      case 'cycling':
      case 'virtualride':
      case 'ebikeride':
      case 'mountainbikeride':
      case 'gravelride':
        return 'Bisiklet';
      case 'walk':
      case 'walking':
        return 'Yürüyüş';
      case 'hike':
      case 'hiking':
        return 'Yürüyüş';
      case 'swim':
      case 'swimming':
        return 'Yüzme';
      case 'yoga':
        return 'Yoga';
      case 'weighttraining':
      case 'crossfit':
        return 'Güç Antrenmanı';
      default:
        return type;
    }
  }

  IconData _getActivityIcon(String type) {
    switch (type.toLowerCase()) {
      case 'run':
      case 'running':
      case 'virtualrun':
      case 'trailrun':
        return Icons.directions_run;
      case 'ride':
      case 'cycling':
      case 'virtualride':
      case 'ebikeride':
      case 'mountainbikeride':
      case 'gravelride':
        return Icons.directions_bike;
      case 'walk':
      case 'walking':
      case 'hike':
      case 'hiking':
        return Icons.directions_walk;
      case 'swim':
      case 'swimming':
        return Icons.pool;
      case 'yoga':
        return Icons.self_improvement;
      case 'weighttraining':
      case 'crossfit':
        return Icons.fitness_center;
      default:
        return Icons.sports;
    }
  }

  Color _getActivityIconColor(String type) {
    switch (type.toLowerCase()) {
      case 'run':
      case 'running':
      case 'virtualrun':
      case 'trailrun':
        return const Color(0xFFFC4C02); // Strava turuncu
      case 'ride':
      case 'cycling':
      case 'virtualride':
      case 'ebikeride':
      case 'mountainbikeride':
      case 'gravelride':
        return Colors.blue;
      case 'walk':
      case 'walking':
      case 'hike':
      case 'hiking':
        return Colors.green;
      case 'swim':
      case 'swimming':
        return Colors.cyan;
      case 'yoga':
        return Colors.purple;
      case 'weighttraining':
      case 'crossfit':
        return Colors.orange;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Strava Aktiviteleri'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(stravaActivityListProvider.notifier).refresh();
        },
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final listState = ref.watch(stravaActivityListProvider);
    
    // İlk yükleme sırasında daha hızlı görünüm için skeleton/placeholder göster
    if (listState.isLoading && listState.activities.isEmpty) {
      return ListView.builder(
        itemCount: 5, // Skeleton item sayısı
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.neutral100),
              ),
            ),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.neutral200,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              title: Container(
                height: 16,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.neutral200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: 100,
                      decoration: BoxDecoration(
                        color: AppColors.neutral200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 12,
                      width: 150,
                      decoration: BoxDecoration(
                        color: AppColors.neutral200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    if (listState.error != null && listState.activities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(listState.error!, style: AppTypography.bodyLarge),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref.read(stravaActivityListProvider.notifier).loadActivities(refresh: true);
              },
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }

    if (listState.activities.isEmpty && !listState.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fitness_center, size: 64, color: AppColors.neutral400),
            const SizedBox(height: 16),
            Text(
              'Aktivite bulunamadı',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.neutral500,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Başlık ve sayı
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.neutral100,
            border: Border(
              bottom: BorderSide(color: AppColors.neutral200),
            ),
          ),
          child: Row(
            children: [
              Text(
                'SON 90 GÜNDEKİ AKTİVİTELER',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.neutral600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${listState.activities.length}',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.neutral600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        // Liste
        Expanded(
          child: ListView.builder(
            itemCount: listState.activities.length + (listState.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == listState.activities.length) {
                // Load more - build sonrası çağır
                if (!listState.isLoadingMore && !listState.isLoading) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ref.read(stravaActivityListProvider.notifier).loadMoreActivities();
                  });
                }
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final activity = listState.activities[index];
              final activityId = activity.id.toString();
              final isImported = _isImported(activityId);
              final isImporting = _isImporting(activityId);

              return _buildActivityItem(activity, isImported, isImporting);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActivityItem(
    StravaActivityEntity activity,
    bool isImported,
    bool isImporting,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.neutral100),
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getActivityIconColor(activity.type).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getActivityIcon(activity.type),
            color: _getActivityIconColor(activity.type),
            size: 24,
          ),
        ),
        title: Text(
          activity.name,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              _formatActivityType(activity.type),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.neutral600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatDate(activity.startDate),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.neutral500,
              ),
            ),
            if (activity.distance > 0) ...[
              const SizedBox(height: 2),
              Text(
                '${(activity.distance / 1000).toStringAsFixed(2)} km',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.neutral500,
                ),
              ),
            ],
          ],
        ),
        trailing: isImported
            ? Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 24,
              )
            : isImporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : OutlinedButton(
                    onPressed: () => _importActivity(activity),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('Import'),
                  ),
      ),
    );
  }
}
