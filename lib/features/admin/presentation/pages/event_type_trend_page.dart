import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/report_info_button.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/admin_reports_models.dart';
import '../providers/admin_reports_provider.dart';

const _eventTypeLabels = <String, String>{
  'training': 'Antrenman',
  'race': 'Yarış',
  'social': 'Sosyal',
  'workshop': 'Atölye',
  'other': 'Diğer',
};

const _eventTypeColors = <String, Color>{
  'training': AppColors.info,
  'race': AppColors.error,
  'social': AppColors.success,
  'workshop': AppColors.warning,
  'other': AppColors.neutral500,
};

const _info = ReportInfo(
  title: 'Etkinlik Türü Trendi',
  summary:
      'Aylar içinde etkinlik türlerine göre katılımın nasıl değiştiğini gösterir; '
      'hangi tür zamanla büyüyor ya da düşüyor görürsünüz.',
  terms: [
    ReportInfoTerm('Türe Göre Toplam', 'Seçilen dönemde her türün etkinlik ve katılım toplamı.'),
    ReportInfoTerm('Aylık Katılım', 'Her ayın toplam katılımcı sayısı.'),
    ReportInfoTerm('Tür', 'Antrenman, Yarış, Sosyal, Workshop, Diğer.'),
  ],
  takeaways: [
    'Yükselen türlere daha fazla, düşenlere yenileyici içerik planlayın.',
    'Mevsimsel dalgalanmaları görmek için 12 ay aralığını kullanın.',
    'Ani düşüşler bir sorunun (takvim, hava, motivasyon) işareti olabilir.',
  ],
);

class EventTypeTrendPage extends ConsumerStatefulWidget {
  const EventTypeTrendPage({super.key});

  @override
  ConsumerState<EventTypeTrendPage> createState() => _EventTypeTrendPageState();
}

class _EventTypeTrendPageState extends ConsumerState<EventTypeTrendPage> {
  int _months = 6;

  @override
  Widget build(BuildContext context) {
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
    final now = DateTime.now();
    // Gune yuvarla: family anahtari rebuild'lerde sabit kalsin (aksi halde
    // 'end: now' her build'de degisip sonsuz yeniden yuklemeye yol acar).
    final range = (
      start: DateTime(now.year, now.month - (_months - 1), 1),
      end: DateTime(now.year, now.month, now.day),
    );
    final trendAsync = ref.watch(eventTypeTrendProvider(range));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Etkinlik Türü Trendi'),
        actions: const [ReportInfoButton(info: _info)],
      ),
      body: !isAdminOrCoach
          ? _noAccess()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _rangeSelector(),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: trendAsync.when(
                    loading: () => const Center(child: LoadingWidget()),
                    error: (e, _) => _error(e, () =>
                        ref.invalidate(eventTypeTrendProvider(range))),
                    data: (items) => RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(eventTypeTrendProvider(range));
                        await ref.read(eventTypeTrendProvider(range).future);
                      },
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        children: [
                          if (items.isEmpty)
                            const EmptyStateWidget(
                              icon: Icons.insights_outlined,
                              title: 'Veri yok',
                              description:
                                  'Seçilen aralıkta etkinlik bulunamadı.',
                            )
                          else ...[
                            _typeTotals(items),
                            const SizedBox(height: 16),
                            _monthlyChart(items),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _rangeSelector() {
    final cs = Theme.of(context).colorScheme;
    return SegmentedButton<int>(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: cs.primary.withValues(alpha: 0.2),
        selectedForegroundColor: cs.primary,
        foregroundColor: cs.onSurfaceVariant,
        side: BorderSide(color: cs.outlineVariant),
      ),
      segments: const [
        ButtonSegment(value: 3, label: Text('3 Ay')),
        ButtonSegment(value: 6, label: Text('6 Ay')),
        ButtonSegment(value: 12, label: Text('12 Ay')),
      ],
      selected: {_months},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _months = s.first),
    );
  }

  Widget _typeTotals(List<EventTypeTrendItem> items) {
    final cs = Theme.of(context).colorScheme;
    final byType = <String, ({int events, int participants})>{};
    for (final i in items) {
      final cur = byType[i.eventType] ?? (events: 0, participants: 0);
      byType[i.eventType] = (
        events: cur.events + i.events,
        participants: cur.participants + i.participants,
      );
    }
    final entries = byType.entries.toList()
      ..sort((a, b) => b.value.participants.compareTo(a.value.participants));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Türe Göre Toplam',
          style: AppTypography.titleSmall.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        ...entries.map((e) {
          final color = _eventTypeColors[e.key] ?? cs.onSurfaceVariant;
          final label = _eventTypeLabels[e.key] ?? e.key;
          final displayColor = cs.brightness == Brightness.dark &&
                  color.computeLuminance() < 0.45
              ? Color.lerp(color, Colors.white, 0.45)!
              : color;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: displayColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    '${e.value.events} etkinlik',
                    style: AppTypography.labelMedium.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${e.value.participants} katılım',
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: displayColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _monthlyChart(List<EventTypeTrendItem> items) {
    final cs = Theme.of(context).colorScheme;
    // Ay bazinda toplam katilim
    final months = <String>{for (final i in items) i.month}.toList()..sort();
    final monthTotals = <String, int>{};
    for (final m in months) {
      monthTotals[m] = items
          .where((i) => i.month == m)
          .fold<int>(0, (s, i) => s + i.participants);
    }
    final maxY = monthTotals.values.isEmpty
        ? 10.0
        : monthTotals.values.reduce((a, b) => a > b ? a : b).toDouble();

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aylık Katılım',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY > 0 ? maxY * 1.2 : 10,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => cs.inverseSurface,
                    getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                      '${months[group.x.toInt()]}\n${rod.toY.round()} katılım',
                      AppTypography.labelSmall.copyWith(
                        color: cs.onInverseSurface,
                      ),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max) return const SizedBox.shrink();
                        return Text(value.toInt().toString(),
                            style: AppTypography.labelSmall
                                .copyWith(color: cs.onSurfaceVariant));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= months.length) {
                          return const SizedBox.shrink();
                        }
                        // 'YYYY-MM' -> 'MM'
                        final parts = months[idx].split('-');
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(parts.length > 1 ? parts[1] : months[idx],
                              style: AppTypography.labelSmall
                                  .copyWith(color: cs.onSurfaceVariant)),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: cs.outlineVariant, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (var i = 0; i < months.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: monthTotals[months[i]]!.toDouble(),
                          color: cs.primary.withValues(alpha: 0.85),
                          width: 16,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
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

  Widget _noAccess() {
    final cs = Theme.of(context).colorScheme;
    return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            style: AppTypography.bodyMedium.copyWith(
              color: cs.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
  }

  Widget _error(Object e, VoidCallback onRetry) {
    final cs = Theme.of(context).colorScheme;
    return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rapor yüklenemedi',
                style: AppTypography.titleSmall.copyWith(color: cs.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                e.toString(),
                style: AppTypography.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
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
