import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/models/user_activity_report_model.dart';
import '../providers/event_provider.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';

class UserActivityReportPage extends ConsumerWidget {
  final String userId;
  final String userName;
  final String? avatarUrl;
  final DateTime startDate;
  final DateTime endDate;

  const UserActivityReportPage({
    super.key,
    required this.userId,
    required this.userName,
    this.avatarUrl,
    required this.startDate,
    required this.endDate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(userActivityReportProvider((
      userId: userId,
      startDate: startDate,
      endDate: endDate,
    )));

    final dateRangeText =
        '${DateFormat('dd.MM.yyyy').format(startDate)} - ${DateFormat('dd.MM.yyyy').format(endDate)}';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              userName,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.neutral900,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              dateRangeText,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.neutral300,
              ),
            ),
          ],
        ),
      ),
      body: reportAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: EmptyStateWidget(
                icon: Icons.directions_run,
                title: 'Aktivite bulunamadı',
                description:
                    'Seçilen tarih aralığında bu kullanıcı için aktivite kaydı yok.',
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildActivityTile(item);
            },
          );
        },
        loading: () => const Center(child: LoadingWidget()),
        error: (e, _) => Center(
          child: Text(
            'Aktiviteler yüklenemedi: $e',
            style:
                AppTypography.bodySmall.copyWith(color: AppColors.error),
          ),
        ),
      ),
    );
  }

  Widget _buildActivityTile(UserActivityReportModel item) {
    final distanceKm = item.distanceMeters / 1000.0;
    final duration = Duration(seconds: item.durationSeconds);
    final paceSec = item.averagePaceSecondsPerKm;

    String durationStr =
        '${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
    String paceStr = paceSec != null && paceSec.isFinite
        ? _formatPace(paceSec)
        : '-';

    final isEventMatched = item.eventId != null;
    final title =
        isEventMatched ? (item.eventTitle ?? 'Etkinlik') : 'Kişisel Koşu';
    final subtitleDate = DateFormat('dd.MM.yyyy – HH:mm').format(item.startTime);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isEventMatched
                      ? Icons.event_available
                      : Icons.directions_run,
                  size: 18,
                  color: isEventMatched
                      ? AppColors.primary
                      : AppColors.neutral500,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitleDate,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.neutral500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.route, size: 14, color: AppColors.neutral500),
                const SizedBox(width: 4),
                Text(
                  '${distanceKm.toStringAsFixed(2)} km',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.timer_outlined,
                    size: 14, color: AppColors.neutral500),
                const SizedBox(width: 4),
                Text(
                  durationStr,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.speed, size: 14, color: AppColors.neutral500),
                const SizedBox(width: 4),
                Text(
                  '$paceStr dk/km',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatPace(double secondsPerKm) {
    final totalSeconds = secondsPerKm.round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

