import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../data/models/recurring_event_series_model.dart';
import '../../utils/recurrence_rule_formatter.dart';
import '../providers/event_provider.dart';

/// Admin: tekrarlayan etkinlik serileri listesi
class RecurringEventsPage extends ConsumerWidget {
  const RecurringEventsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seriesAsync = ref.watch(recurringEventSeriesProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tekrar Eden Etkinlikler'),
      ),
      body: seriesAsync.when(
        data: (series) => RefreshIndicator(
          color: cs.primary,
          onRefresh: () async {
            ref.invalidate(recurringEventSeriesProvider);
            await ref.read(recurringEventSeriesProvider.future);
          },
          child: series.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 120),
                    EmptyStateWidget(
                      icon: Icons.repeat,
                      title: 'Tekrarlayan etkinlik yok',
                      description:
                          'Henüz tekrarlayan bir etkinlik serisi oluşturulmamış.',
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: series.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _RecurringSeriesCard(series: series[index]);
                  },
                ),
        ),
        loading: () => const Center(child: LoadingWidget()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Liste yüklenemedi', style: AppTypography.titleMedium),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: AppTypography.bodySmall.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(recurringEventSeriesProvider),
                  child: const Text('Tekrar Dene'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecurringSeriesCard extends ConsumerStatefulWidget {
  final RecurringEventSeriesModel series;

  const _RecurringSeriesCard({required this.series});

  @override
  ConsumerState<_RecurringSeriesCard> createState() => _RecurringSeriesCardState();
}

class _RecurringSeriesCardState extends ConsumerState<_RecurringSeriesCard> {
  bool _isStopping = false;
  bool _isDeleting = false;

  Future<void> _stopRecurrence() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tekrarlamayı durdur'),
        content: Text(
          '"${widget.series.title}" etkinliği artık otomatik olarak tekrarlanmayacak. '
          'Mevcut oluşturulmuş etkinlikler silinmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Durdur'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isStopping = true);
    try {
      final ds = ref.read(eventDataSourceProvider);
      await ds.stopRecurringEventSeries(widget.series.latestEventId);
      ref.invalidate(recurringEventSeriesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tekrarlama durduruldu')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
  }

  Future<void> _deleteSeries() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seriyi kaldır'),
        content: Text(
          '"${widget.series.title}" tekrarlayan seri listeden kaldırılacak ve '
          'yeni tekrarlar oluşturulmayacak.\n\n'
          'Geçmiş ve gelecekte zaten oluşturulmuş etkinlikler etkilenmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final ds = ref.read(eventDataSourceProvider);
      await ds.deleteRecurringEventSeries(widget.series.rootEventId);
      ref.invalidate(recurringEventSeriesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tekrarlayan seri kaldırıldı')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final cs = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('d MMM yyyy', 'tr_TR');
    final timeFormat = DateFormat('HH:mm', 'tr_TR');
    final frequency = formatRecurrenceRule(series.recurrenceRule);

    final description = series.description?.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        series.title,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _Chip(
                            label: series.eventType.displayName,
                            color: cs.primary.withValues(alpha: 0.12),
                            textColor: cs.primary,
                          ),
                          _Chip(
                            label: series.isActive ? 'Aktif' : 'Durduruldu',
                            color: series.isActive
                                ? AppColors.success.withValues(alpha: 0.12)
                                : cs.surfaceContainerHighest,
                            textColor: series.isActive
                                ? AppColors.success
                                : cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.repeat,
                  color: series.isActive ? cs.primary : cs.outline,
                ),
              ],
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Açıklama',
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: AppTypography.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.person_outline,
              label: 'Oluşturan',
              value: series.createdByName,
            ),
            const SizedBox(height: 6),
            _InfoRow(
              icon: Icons.route_outlined,
              label: 'Rotalar',
              value: series.routes.isEmpty
                  ? 'Rota tanımlı değil'
                  : series.routes.map((route) => route.displayText).join(', '),
            ),
            const SizedBox(height: 6),
            _InfoRow(
              icon: Icons.schedule_outlined,
              label: 'Tekrar',
              value: frequency,
            ),
            const SizedBox(height: 6),
            _InfoRow(
              icon: Icons.event_outlined,
              label: 'Son etkinlik',
              value:
                  '${dateFormat.format(series.latestStartTime)} · ${timeFormat.format(series.latestStartTime)}',
            ),
            const SizedBox(height: 6),
            _InfoRow(
              icon: Icons.history,
              label: 'İlk etkinlik',
              value: dateFormat.format(series.firstStartTime),
            ),
            const SizedBox(height: 6),
            _InfoRow(
              icon: Icons.format_list_numbered,
              label: 'Oluşturulan',
              value: '${series.occurrenceCount} etkinlik',
            ),
            if (series.recurrenceEndDate != null) ...[
              const SizedBox(height: 6),
              _InfoRow(
                icon: Icons.event_busy_outlined,
                label: 'Bitiş tarihi',
                value: dateFormat.format(series.recurrenceEndDate!),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (series.isActive)
                  IconButton(
                    onPressed: _isStopping || _isDeleting ? null : _stopRecurrence,
                    tooltip: 'Tekrarlamayı durdur',
                    icon: _isStopping
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.stop_circle_outlined, color: cs.onSurfaceVariant),
                  ),
                IconButton(
                  onPressed: _isStopping || _isDeleting
                      ? null
                      : () {
                          context.pushNamed(
                            RouteNames.editEvent,
                            pathParameters: {'eventId': series.latestEventId},
                            queryParameters: {
                              'scope': 'series',
                              'seriesRoot': series.rootEventId,
                            },
                          );
                        },
                  tooltip: 'Düzenle',
                  icon: Icon(Icons.edit_outlined, color: cs.onSurfaceVariant),
                ),
                IconButton(
                  onPressed: _isStopping || _isDeleting ? null : _deleteSeries,
                  tooltip: 'Seriyi kaldır',
                  icon: _isDeleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.delete_outline, color: AppColors.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppTypography.bodySmall.copyWith(color: cs.onSurface),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _Chip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
