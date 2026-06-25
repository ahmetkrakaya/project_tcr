import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/report_info_button.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../events/domain/entities/event_entity.dart';
import '../../../events/presentation/providers/event_provider.dart';
import '../../data/models/training_load_models.dart';
import '../providers/training_load_provider.dart';
import '../widgets/training_load_format.dart';

const _info = ReportInfo(
  title: 'Etkinlik Yarış Formu',
  summary:
      'Yaklaşan bir yarışa katılacak sporcuların yarış öncesi form durumunu '
      'gösterir; kim hazır, kim yorgun hızlıca görülür.',
  terms: [
    ReportInfoTerm('TSB (Form)', 'CTL − ATL. Pozitif = dinç/hazır, negatif = yorgun.'),
    ReportInfoTerm('ACWR', 'Akut/Kronik oran. >1.5 yüksek sakatlık riski.'),
    ReportInfoTerm('Taze → Yorgun', 'Liste forma göre sıralı (en dinçten en yorguna).'),
  ],
  takeaways: [
    'Yarış öncesi pozitif TSB hedeflenir.',
    'Yorgun (negatif TSB) sporcular için yükü azaltmayı değerlendirin.',
    'Yüksek ACWR olan sporcuyu yakından takip edin.',
  ],
);

class EventTrainingLoadPage extends ConsumerStatefulWidget {
  const EventTrainingLoadPage({super.key, this.initialEventId});

  final String? initialEventId;

  @override
  ConsumerState<EventTrainingLoadPage> createState() =>
      _EventTrainingLoadPageState();
}

class _EventTrainingLoadPageState extends ConsumerState<EventTrainingLoadPage> {
  String? _eventId;

  @override
  void initState() {
    super.initState();
    _eventId = widget.initialEventId;
  }

  @override
  Widget build(BuildContext context) {
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
    final eventsAsync = ref.watch(allEventsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Etkinlik Yarış Formu'),
        actions: const [ReportInfoButton(info: _info)],
      ),
      body: !isAdminOrCoach
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Bu sayfaya erişim yetkiniz yok.',
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.neutral500),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                eventsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text(
                    'Etkinlikler yüklenemedi: $e',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.error),
                  ),
                  data: (events) => _buildEventPicker(events),
                ),
                const SizedBox(height: 16),
                if (_eventId == null)
                  const EmptyStateWidget(
                    icon: Icons.flag_outlined,
                    title: 'Yaklaşan yarış yok',
                    description:
                        'Gelecek tarihli bir yarış etkinliği bulunamadı.',
                  )
                else
                  _buildRoster(_eventId!),
              ],
            ),
    );
  }

  Widget _buildEventPicker(List<EventEntity> events) {
    final now = DateTime.now();
    // Yalnizca yaklasan yarislar, en yakindan uzaga
    final upcoming = events
        .where((e) =>
            e.eventType == EventType.race && e.startTime.isAfter(now))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    if (upcoming.isEmpty) {
      return Text(
        'Yaklaşan yarış bulunamadı.',
        style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
      );
    }

    // En yakin yarisi otomatik sec
    final validId =
        upcoming.any((e) => e.id == _eventId) ? _eventId : upcoming.first.id;
    if (validId != _eventId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _eventId = validId);
      });
    }

    return DropdownButtonFormField<String>(
      value: validId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Yaklaşan Yarış',
        isDense: true,
      ),
      items: upcoming.map((e) {
        final date = DateFormat('d MMM yyyy', 'tr_TR').format(e.startTime);
        return DropdownMenuItem<String>(
          value: e.id,
          child: Text('${e.title} - $date', overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (value) => setState(() => _eventId = value),
    );
  }

  Widget _buildRoster(String eventId) {
    final rosterAsync = ref.watch(eventTrainingLoadProvider(eventId));

    return rosterAsync.when(
      loading: () => const Center(child: LoadingWidget()),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text('Rapor yüklenemedi', style: AppTypography.titleSmall),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.neutral500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  ref.invalidate(eventTrainingLoadProvider(eventId)),
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
      data: (athletes) {
        if (athletes.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.directions_run,
            title: 'Veri yok',
            description:
                'Bu etkinliğe katılacak ve hesaplanabilir yükü olan sporcu bulunamadı.',
          );
        }
        final sorted = [...athletes]..sort((a, b) => b.tsb.compareTo(a.tsb));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${sorted.length} katılımcı - forma göre sıralı (taze → yorgun)',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.neutral500),
            ),
            const SizedBox(height: 12),
            ...sorted.map(
              (a) => _RosterTile(
                athlete: a,
                onTap: () => context.pushNamed(
                  RouteNames.adminTrainingLoadDetail,
                  pathParameters: {'userId': a.userId},
                  extra: a.fullName,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({required this.athlete, required this.onTap});

  final AthleteLoadOverviewModel athlete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final statusColor = TrainingLoadFormat.statusColor(athlete.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                UserAvatar(
                  imageUrl: athlete.avatarUrl,
                  name: athlete.fullName,
                  size: 42,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        athlete.fullName,
                        style: AppTypography.titleSmall
                            .copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        TrainingLoadFormat.tsbInterpretation(athlete.tsb),
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.neutral500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'TSB ${TrainingLoadFormat.formatSigned(athlete.tsb)}',
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: athlete.tsb >= 0
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ACWR ${athlete.acwr?.toStringAsFixed(2) ?? '-'}',
                      style: AppTypography.labelSmall.copyWith(
                        color: TrainingLoadFormat.acwrColor(athlete.acwr),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
