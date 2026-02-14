import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../domain/entities/period_statistics_entity.dart';
import '../providers/statistics_provider.dart';

/// İstatistikler Widget
/// Strava benzeri haftalık/aylık istatistik gösterimi
class StatisticsWidget extends ConsumerStatefulWidget {
  final String? userId; // Başka kullanıcının istatistiklerini görmek için
  
  const StatisticsWidget({super.key, this.userId});

  @override
  ConsumerState<StatisticsWidget> createState() => _StatisticsWidgetState();
}

class _StatisticsWidgetState extends ConsumerState<StatisticsWidget> {
  bool _isWeekly = true;

  @override
  Widget build(BuildContext context) {
    // Eğer userId verilmişse o kullanıcının, yoksa kendi istatistiklerini göster
    final targetUserId = widget.userId ?? ref.watch(userIdProvider);
    
    if (targetUserId == null) {
      return const Center(
        child: Text('Kullanıcı bulunamadı'),
      );
    }
    
    final statisticsAsync = _isWeekly
        ? ref.watch(weeklyStatisticsProvider(targetUserId))
        : ref.watch(monthlyStatisticsProvider(targetUserId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Haftalık/Aylık Toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.neutral200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildToggleButton(
                      label: 'Haftalık',
                      isSelected: _isWeekly,
                      onTap: () => setState(() => _isWeekly = true),
                    ),
                    _buildToggleButton(
                      label: 'Aylık',
                      isSelected: !_isWeekly,
                      onTap: () => setState(() => _isWeekly = false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // İstatistikler
        statisticsAsync.when(
          data: (stats) => _buildStatisticsContent(stats),
          loading: () => _buildLoadingState(),
          error: (error, stack) => _buildErrorState(error),
        ),
      ],
    );
  }

  Widget _buildToggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: isSelected ? Colors.white : AppColors.neutral600,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticsContent(PeriodStatisticsEntity stats) {
    return Column(
      children: [
        // Özet Kartlar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildSummaryCards(stats),
        ),
        const SizedBox(height: 20),

        // Grafik
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildChart(stats),
        ),
        const SizedBox(height: 20),

        // Detaylı İstatistikler
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildDetailedStats(stats),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(PeriodStatisticsEntity stats) {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.directions_run,
            value: stats.totalActivities.toString(),
            label: 'Aktivite',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.straighten,
            value: stats.totalDistanceKm.toStringAsFixed(1),
            label: 'KM',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.timer,
            value: _formatDuration(stats.totalDurationSeconds),
            label: 'Süre',
            color: AppColors.tertiary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.trending_up,
            value: stats.formattedAveragePace,
            label: 'Pace',
            color: AppColors.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
      ),
    );
  }

  Widget _buildChart(PeriodStatisticsEntity stats) {
    if (stats.dailyStats.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.bar_chart_outlined,
                size: 48,
                color: AppColors.neutral400,
              ),
              const SizedBox(height: 8),
              Text(
                'Henüz aktivite yok',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.neutral500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final maxDistance = stats.dailyStats
        .map((d) => d.distanceKm)
        .reduce((a, b) => a > b ? a : b);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isWeekly ? 'Haftalık Mesafe' : 'Aylık Mesafe',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxDistance > 0 ? maxDistance * 1.2 : 10,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.primary,
                    tooltipRoundedRadius: 8,
                    tooltipPadding: const EdgeInsets.all(8),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final dayStats = stats.dailyStats[groupIndex];
                      return BarTooltipItem(
                        '${dayStats.distanceKm.toStringAsFixed(1)} km\n${dayStats.activityCount} aktivite',
                        AppTypography.labelSmall.copyWith(
                          color: Colors.white,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= stats.dailyStats.length) {
                          return const SizedBox.shrink();
                        }
                        final dayStats = stats.dailyStats[value.toInt()];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _isWeekly ? dayStats.dayName : dayStats.dayOfMonth.toString(),
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.neutral500,
                            ),
                          ),
                        );
                      },
                      reservedSize: 30,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max) return const SizedBox.shrink();
                        return Text(
                          value.toStringAsFixed(0),
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxDistance > 0 ? maxDistance / 4 : 2.5,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: AppColors.neutral300,
                      strokeWidth: 1,
                    );
                  },
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.neutral300,
                      width: 1,
                    ),
                    left: BorderSide(
                      color: AppColors.neutral300,
                      width: 1,
                    ),
                  ),
                ),
                barGroups: stats.dailyStats.asMap().entries.map((entry) {
                  final index = entry.key;
                  final dayStats = entry.value;
                  final isToday = _isToday(dayStats.date);
                  
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: dayStats.distanceKm,
                        color: isToday
                            ? AppColors.primary
                            : (dayStats.distanceKm > 0
                                ? AppColors.primary.withValues(alpha: 0.6)
                                : AppColors.neutral300),
                        width: _isWeekly ? 20 : 8,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedStats(PeriodStatisticsEntity stats) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detaylı İstatistikler',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _buildStatRow(
            icon: Icons.straighten,
            label: 'Toplam Mesafe',
            value: '${stats.totalDistanceKm.toStringAsFixed(1)} km',
          ),
          const Divider(height: 24),
          _buildStatRow(
            icon: Icons.timer,
            label: 'Toplam Süre',
            value: _formatDuration(stats.totalDurationSeconds),
          ),
          const Divider(height: 24),
          _buildStatRow(
            icon: Icons.trending_up,
            label: 'Ortalama Pace',
            value: '${stats.formattedAveragePace} /km',
          ),
          if (stats.totalElevationGain > 0) ...[
            const Divider(height: 24),
            _buildStatRow(
              icon: Icons.terrain,
              label: 'Toplam Yükseklik',
              value: '${stats.totalElevationGain.toStringAsFixed(0)} m',
            ),
          ],
          if (!_isWeekly) ...[
            const Divider(height: 24),
            _buildStatRow(
              icon: Icons.calendar_today,
              label: 'Günlük Ortalama',
              value: '${stats.averageDailyDistanceKm.toStringAsFixed(1)} km',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
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
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.all(40),
      child: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: AppCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.error,
            ),
            const SizedBox(height: 8),
            Text(
              'İstatistikler yüklenemedi',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0d';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}s ${minutes}d';
    }
    return '${minutes}d';
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}
