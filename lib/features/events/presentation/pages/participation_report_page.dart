import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/report_info_button.dart';
import '../../data/models/event_report_model.dart';
import '../providers/event_provider.dart';

const _typeOrder = ['training', 'race', 'social', 'workshop', 'other'];

const _typeColors = <String, Color>{
  'training': AppColors.info,
  'race': AppColors.error,
  'social': AppColors.success,
  'workshop': AppColors.warning,
  'other': AppColors.neutral500,
};

String _typeLabel(String t) {
  switch (t) {
    case 'training':
      return 'Antrenman';
    case 'race':
      return 'Yarış';
    case 'social':
      return 'Sosyal';
    case 'workshop':
      return 'Workshop';
    default:
      return 'Diğer';
  }
}

const _info = ReportInfo(
  title: 'Katılım Raporu',
  summary:
      'Seçilen tarih aralığında etkinlik katılımını özetler; hangi etkinlik '
      'türünün ne kadar ilgi gördüğünü gösterir.',
  terms: [
    ReportInfoTerm('Toplam Katılım', 'Tüm etkinliklere katılan kişi sayısının toplamı.'),
    ReportInfoTerm('Ortalama', 'Etkinlik başına düşen ortalama katılımcı.'),
    ReportInfoTerm('En Aktif Gün', 'En çok katılımın olduğu hafta günü.'),
    ReportInfoTerm('Tür Dağılımı', 'Antrenman/Yarış/Sosyal vb. türlere göre katılım payı.'),
  ],
  takeaways: [
    'Düşük katılımlı türleri tespit edip planlamayı buna göre yapın.',
    'En aktif güne etkinlik koymak katılımı artırabilir.',
    'Tarih aralığını değiştirerek dönemsel değişimi karşılaştırın.',
  ],
);

/// Profesyonel katilim raporu: KPI ozeti + etkinlik turune gore katilim.
class ParticipationReportPage extends ConsumerStatefulWidget {
  const ParticipationReportPage({
    super.key,
    this.eventReportDetailRouteName = RouteNames.adminParticipationReportDetail,
  });

  final String eventReportDetailRouteName;

  @override
  ConsumerState<ParticipationReportPage> createState() =>
      _ParticipationReportPageState();
}

class _ParticipationReportPageState
    extends ConsumerState<ParticipationReportPage> {
  late DateTime _startDate;
  late DateTime _endDate;
  int _rangeDays = 30;
  String? _typeFilter; // null = tum turler

  @override
  void initState() {
    super.initState();
    _applyRange(30);
  }

  void _applyRange(int days) {
    final now = DateTime.now();
    setState(() {
      _rangeDays = days;
      _endDate = DateTime(now.year, now.month, now.day);
      _startDate = _endDate.subtract(Duration(days: days - 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(eventReportProvider((
      startDate: _startDate,
      endDate: _endDate,
      eventType: null,
      groupId: null,
    )));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Katılım Raporu'),
        actions: const [ReportInfoButton(info: _info)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _rangeSelector(),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: reportAsync.when(
              loading: () => const Center(child: LoadingWidget()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Rapor yüklenemedi',
                          style: AppTypography.titleSmall),
                      const SizedBox(height: 8),
                      Text(e.toString(),
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.neutral500)),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref.invalidate(eventReportProvider((
                          startDate: _startDate,
                          endDate: _endDate,
                          eventType: null,
                          groupId: null,
                        ))),
                        child: const Text('Tekrar Dene'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (report) {
                final events = report.events;
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(eventReportProvider((
                      startDate: _startDate,
                      endDate: _endDate,
                      eventType: null,
                      groupId: null,
                    )));
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    children: [
                      if (events.isEmpty)
                        const EmptyStateWidget(
                          icon: Icons.bar_chart_outlined,
                          title: 'Veri yok',
                          description: 'Seçilen aralıkta etkinlik bulunamadı.',
                        )
                      else ...[
                        _kpiBand(events),
                        const SizedBox(height: 20),
                        _byTypeSection(events),
                        const SizedBox(height: 20),
                        _typeFilterChips(events),
                        const SizedBox(height: 8),
                        _eventList(events),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeSelector() {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 7, label: Text('7g')),
        ButtonSegment(value: 30, label: Text('30g')),
        ButtonSegment(value: 90, label: Text('90g')),
        ButtonSegment(value: 365, label: Text('1y')),
      ],
      selected: {_rangeDays},
      showSelectedIcon: false,
      onSelectionChanged: (s) => _applyRange(s.first),
    );
  }

  Widget _kpiBand(List<EventReportModel> events) {
    final totalEvents = events.length;
    final totalParticipants =
        events.fold<int>(0, (s, e) => s + e.participantCount);
    final avg = totalEvents == 0 ? 0.0 : totalParticipants / totalEvents;

    // En aktif gun (katilima gore)
    final byWeekday = <int, int>{};
    for (final e in events) {
      byWeekday[e.eventDate.weekday] =
          (byWeekday[e.eventDate.weekday] ?? 0) + e.participantCount;
    }
    String mostActive = '-';
    if (byWeekday.isNotEmpty) {
      final top = byWeekday.entries
          .reduce((a, b) => a.value >= b.value ? a : b);
      const days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
      mostActive = days[top.key - 1];
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _kpi('$totalEvents', 'Etkinlik', AppColors.primary),
          _kpi('$totalParticipants', 'Katılım', AppColors.success),
          _kpi(avg.toStringAsFixed(1), 'Ortalama', AppColors.info),
          _kpi(mostActive, 'En Aktif Gün', AppColors.warning),
        ],
      ),
    );
  }

  Widget _kpi(String value, String label, Color color) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: AppTypography.titleLarge
                    .copyWith(fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.neutral500)),
          ],
        ),
      );

  Widget _byTypeSection(List<EventReportModel> events) {
    final byType = <String, ({int events, int participants})>{};
    for (final e in events) {
      final key = _typeColors.containsKey(e.eventType) ? e.eventType : 'other';
      final cur = byType[key] ?? (events: 0, participants: 0);
      byType[key] = (
        events: cur.events + 1,
        participants: cur.participants + e.participantCount,
      );
    }
    final totalParticipants =
        byType.values.fold<int>(0, (s, v) => s + v.participants);
    final ordered = _typeOrder.where(byType.containsKey).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Etkinlik Türüne Göre Katılım',
            style: AppTypography.titleSmall
                .copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ...ordered.map((t) {
          final data = byType[t]!;
          final color = _typeColors[t]!;
          final ratio = totalParticipants == 0
              ? 0.0
              : data.participants / totalParticipants;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_typeLabel(t),
                          style: AppTypography.bodyMedium
                              .copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Text('${data.events} etkinlik · ',
                        style: AppTypography.labelMedium
                            .copyWith(color: AppColors.neutral500)),
                    Text('${data.participants} katılım',
                        style: AppTypography.labelMedium.copyWith(
                            color: color, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: AppColors.neutral200,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _typeFilterChips(List<EventReportModel> events) {
    final types = _typeOrder
        .where((t) => events.any(
            (e) => (_typeColors.containsKey(e.eventType) ? e.eventType : 'other') == t))
        .toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Tümü'),
          selected: _typeFilter == null,
          onSelected: (_) => setState(() => _typeFilter = null),
        ),
        ...types.map((t) => ChoiceChip(
              label: Text(_typeLabel(t)),
              selected: _typeFilter == t,
              onSelected: (_) => setState(() => _typeFilter = t),
            )),
      ],
    );
  }

  Widget _eventList(List<EventReportModel> events) {
    final filtered = (_typeFilter == null
        ? [...events]
        : events
            .where((e) =>
                (_typeColors.containsKey(e.eventType) ? e.eventType : 'other') ==
                _typeFilter)
            .toList())
      ..sort((a, b) => b.eventDate.compareTo(a.eventDate));

    if (filtered.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: EmptyStateWidget(
          icon: Icons.event_busy,
          title: 'Etkinlik yok',
          description: 'Bu türde etkinlik bulunamadı.',
        ),
      );
    }

    return Column(
      children: filtered.map((e) {
        final key =
            _typeColors.containsKey(e.eventType) ? e.eventType : 'other';
        final color = _typeColors[key]!;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AppCard(
            padding: const EdgeInsets.all(12),
            onTap: () => context.pushNamed(
              widget.eventReportDetailRouteName,
              pathParameters: {'eventId': e.eventId},
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    key == 'race'
                        ? Icons.emoji_events
                        : key == 'training'
                            ? Icons.directions_run
                            : Icons.event,
                    size: 18,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.eventTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMedium
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('d MMM yyyy', 'tr').format(e.eventDate),
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.neutral500),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people,
                        size: 15, color: AppColors.neutral500),
                    const SizedBox(width: 4),
                    Text('${e.participantCount}',
                        style: AppTypography.bodyMedium
                            .copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
