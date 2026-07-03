import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/report_info_button.dart';
import '../../data/models/training_load_models.dart';
import '../providers/training_load_provider.dart';
import '../widgets/training_load_format.dart';
import '../widgets/training_load_report_info.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

class AthleteTrainingLoadDetailPage extends ConsumerStatefulWidget {
  const AthleteTrainingLoadDetailPage({
    super.key,
    required this.userId,
    this.athleteName,
  });

  final String userId;
  final String? athleteName;

  @override
  ConsumerState<AthleteTrainingLoadDetailPage> createState() =>
      _AthleteTrainingLoadDetailPageState();
}

class _AthleteTrainingLoadDetailPageState
    extends ConsumerState<AthleteTrainingLoadDetailPage> {
  int _days = 90;

  static const _ranges = <int, String>{28: '4 Hafta', 90: '3 Ay', 365: '1 Yıl'};

  @override
  Widget build(BuildContext context) {
    final params = AthleteLoadParams(userId: widget.userId, days: _days);
    final loadAsync = ref.watch(athleteTrainingLoadProvider(params));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.athleteName ?? 'Antrenman Yükü'),
        actions: const [ReportInfoButton(info: athleteTrainingLoadReportInfo)],
      ),
      body: loadAsync.when(
        loading: () => const Center(child: LoadingWidget()),
        error: (error, _) => _ErrorView(
          error: error,
          onRetry: () => ref.invalidate(athleteTrainingLoadProvider(params)),
        ),
        data: (points) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(athleteTrainingLoadProvider(params));
              await ref.read(athleteTrainingLoadProvider(params).future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _buildRangeSelector(),
                const SizedBox(height: 16),
                if (points.isEmpty)
                  const EmptyStateWidget(
                    icon: Icons.show_chart,
                    title: 'Veri yok',
                    description: 'Bu aralıkta hesaplanabilir koşu yükü yok.',
                  )
                else ...[
                  _buildSummary(points),
                  const SizedBox(height: 16),
                  _PmcChartCard(points: points),
                  const SizedBox(height: 16),
                  _WeeklyLoadCard(points: points),
                  const SizedBox(height: 16),
                  _buildLegend(context),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRangeSelector() {
    final cs = Theme.of(context).colorScheme;
    return SegmentedButton<int>(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: cs.primary.withValues(alpha: 0.2),
        selectedForegroundColor: cs.primary,
        foregroundColor: cs.onSurfaceVariant,
        side: BorderSide(color: cs.outlineVariant),
      ),
      segments: _ranges.entries
          .map((e) => ButtonSegment(value: e.key, label: Text(e.value)))
          .toList(),
      selected: {_days},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _days = s.first),
    );
  }

  Widget _buildSummary(List<TrainingLoadPointModel> points) {
    final last = points.last;

    // ACWR'yi gunluk seriden hesapla (akut 7g / kronik 28g haftalik ort.)
    double sumLast(int n) {
      final slice = points.length <= n
          ? points
          : points.sublist(points.length - n);
      return slice.fold<double>(0, (sum, p) => sum + p.tss);
    }

    final acute = sumLast(7);
    final chronic28 = sumLast(28);
    final acwr = chronic28 > 0 ? acute / (chronic28 / 4.0) : null;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryTile(
                label: 'Fitness (CTL)',
                value: last.ctl.round().toString(),
                color: AppColors.info,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryTile(
                label: 'Yorgunluk (ATL)',
                value: last.atl.round().toString(),
                color: AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryTile(
                label: 'Form (TSB)',
                value: TrainingLoadFormat.formatSigned(last.tsb),
                color: last.tsb >= 0 ? AppColors.success : AppColors.error,
                subtitle: TrainingLoadFormat.tsbInterpretation(last.tsb),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryTile(
                label: 'ACWR',
                value: acwr?.toStringAsFixed(2) ?? '-',
                color: TrainingLoadFormat.acwrColor(acwr),
                subtitle: 'Tatlı nokta 0.8 - 1.3',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegend(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget item(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 14, height: 3, color: c),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        );

    return Wrap(
      spacing: 18,
      runSpacing: 6,
      children: [
        item(AppColors.info, 'CTL (Fitness)'),
        item(AppColors.warning, 'ATL (Yorgunluk)'),
        item(AppColors.success, 'TSB (Form)'),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
  });

  final String label;
  final String value;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.labelSmall
                .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.headlineSmall
                .copyWith(fontWeight: FontWeight.w700, color: color),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: AppTypography.labelSmall
                  .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _PmcChartCard extends StatelessWidget {
  const _PmcChartCard({required this.points});

  final List<TrainingLoadPointModel> points;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    double minY = 0;
    double maxY = 0;
    for (final p in points) {
      minY = [minY, p.tsb, p.atl, p.ctl].reduce((a, b) => a < b ? a : b);
      maxY = [maxY, p.tsb, p.atl, p.ctl].reduce((a, b) => a > b ? a : b);
    }
    minY = (minY - 5).floorToDouble();
    maxY = (maxY + 5).ceilToDouble();

    final n = points.length;
    final labelStep = (n / 4).ceil().clamp(1, n);

    List<FlSpot> spots(double Function(TrainingLoadPointModel) sel) => [
          for (var i = 0; i < n; i++) FlSpot(i.toDouble(), sel(points[i])),
        ];

    LineChartBarData bar(
      List<FlSpot> data,
      Color color, {
      bool fill = false,
    }) =>
        LineChartBarData(
          spots: data,
          isCurved: true,
          color: color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: fill,
            color: color.withValues(alpha: 0.12),
          ),
        );

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performans Yönetim Grafiği (PMC)',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                minX: 0,
                maxX: (n - 1).toDouble(),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => cs.inverseSurface,
                    getTooltipItems: (spots) {
                      if (spots.isEmpty) return [];
                      final idx = spots.first.x.toInt();
                      final p = points[idx.clamp(0, n - 1)];
                      final dateStr =
                          DateFormat('d MMM', 'tr_TR').format(p.date);
                      return spots.map((s) {
                        if (s.barIndex != 0) {
                          return null;
                        }
                        return LineTooltipItem(
                          '$dateStr\nCTL ${p.ctl.round()}  ATL ${p.atl.round()}\nTSB ${TrainingLoadFormat.formatSigned(p.tsb)}',
                          AppTypography.labelSmall
                              .copyWith(color: cs.onInverseSurface),
                        );
                      }).toList();
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max || value == meta.min) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          value.toInt().toString(),
                          style: AppTypography.labelSmall
                              .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: labelStep.toDouble(),
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= n) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            DateFormat('d/M').format(points[idx].date),
                            style: AppTypography.labelSmall
                                .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: ThemeBrightnessHolder.outlineVariant, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: ThemeBrightnessHolder.outline,
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ],
                ),
                lineBarsData: [
                  bar(spots((p) => p.ctl), AppColors.info, fill: true),
                  bar(spots((p) => p.atl), AppColors.warning),
                  bar(spots((p) => p.tsb), AppColors.success),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyLoadCard extends StatelessWidget {
  const _WeeklyLoadCard({required this.points});

  final List<TrainingLoadPointModel> points;

  List<_WeekBucket> _buckets() {
    final buckets = <_WeekBucket>[];
    // Sondan basa 7'serli grupla, son hafta en sagda olacak sekilde.
    final reversed = points.reversed.toList();
    for (var i = 0; i < reversed.length; i += 7) {
      final end = (i + 7).clamp(0, reversed.length);
      final slice = reversed.sublist(i, end);
      final total = slice.fold<double>(0, (sum, p) => sum + p.tss);
      buckets.add(_WeekBucket(weekStart: slice.last.date, totalTss: total));
    }
    return buckets.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final buckets = _buckets();
    final maxTss = buckets.fold<double>(
      0,
      (m, b) => b.totalTss > m ? b.totalTss : m,
    );

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Haftalık Yük (TSS)',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxTss > 0 ? maxTss * 1.2 : 10,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => cs.inverseSurface,
                    getTooltipItem: (group, _, rod, __) {
                      final b = buckets[group.x.toInt()];
                      final label = DateFormat('d MMM', 'tr_TR').format(b.weekStart);
                      return BarTooltipItem(
                        '$label haftası\n${rod.toY.round()} TSS',
                        AppTypography.labelSmall
                            .copyWith(color: cs.onInverseSurface),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max) return const SizedBox.shrink();
                        return Text(
                          value.toInt().toString(),
                          style: AppTypography.labelSmall
                              .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= buckets.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            DateFormat('d/M').format(buckets[idx].weekStart),
                            style: AppTypography.labelSmall
                                .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: ThemeBrightnessHolder.outlineVariant, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (var i = 0; i < buckets.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: buckets[i].totalTss,
                          color: cs.primary.withValues(alpha: 0.85),
                          width: 14,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekBucket {
  const _WeekBucket({required this.weekStart, required this.totalTss});

  final DateTime weekStart;
  final double totalTss;
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Veri yüklenemedi', style: AppTypography.titleSmall),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: AppTypography.bodySmall
                  .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Tekrar Dene')),
          ],
        ),
      ),
    );
  }
}
