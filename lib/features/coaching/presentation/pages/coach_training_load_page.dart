import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/report_info_button.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';
import '../../data/models/training_load_models.dart';
import '../providers/training_load_provider.dart';
import '../widgets/training_load_format.dart';
import '../widgets/training_load_report_info.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

enum _SortBy { tsb, acwr, acute }

class CoachTrainingLoadPage extends ConsumerStatefulWidget {
  const CoachTrainingLoadPage({super.key, this.initialGroupId});

  final String? initialGroupId;

  @override
  ConsumerState<CoachTrainingLoadPage> createState() =>
      _CoachTrainingLoadPageState();
}

class _CoachTrainingLoadPageState extends ConsumerState<CoachTrainingLoadPage> {
  final _searchController = TextEditingController();
  String? _selectedGroupId;
  _SortBy _sortBy = _SortBy.tsb;

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.initialGroupId;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AthleteLoadOverviewModel> _applyFilters(
    List<AthleteLoadOverviewModel> athletes,
  ) {
    final query = _searchController.text.toLowerCase().trim();
    final filtered = query.isEmpty
        ? [...athletes]
        : athletes
            .where((a) => a.fullName.toLowerCase().contains(query))
            .toList();

    filtered.sort((a, b) {
      switch (_sortBy) {
        case _SortBy.tsb:
          return a.tsb.compareTo(b.tsb); // dusuk TSB (yorgun) once
        case _SortBy.acwr:
          return (b.acwr ?? -1).compareTo(a.acwr ?? -1); // yuksek ACWR once
        case _SortBy.acute:
          return b.acute7d.compareTo(a.acute7d); // yuksek 7g yuk once
      }
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
    final overviewAsync =
        ref.watch(coachTrainingLoadOverviewProvider(_selectedGroupId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Performans Raporları'),
        actions: const [ReportInfoButton(info: coachTrainingLoadReportInfo)],
      ),
      body: !isAdminOrCoach
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Bu sayfaya erişim yetkiniz yok.',
                  style: AppTypography.bodyMedium
                      .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _buildFilters(),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: overviewAsync.when(
                    loading: () => const Center(child: LoadingWidget()),
                    error: (error, _) => _ErrorView(
                      error: error,
                      onRetry: () => ref.invalidate(
                        coachTrainingLoadOverviewProvider(_selectedGroupId),
                      ),
                    ),
                    data: (athletes) {
                      final filtered = _applyFilters(athletes);
                      return RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(
                            coachTrainingLoadOverviewProvider(_selectedGroupId),
                          );
                          await ref.read(
                            coachTrainingLoadOverviewProvider(_selectedGroupId)
                                .future,
                          );
                        },
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                          children: [
                            if (athletes.isNotEmpty) ...[
                              _SummaryBand(athletes: athletes),
                              const SizedBox(height: 12),
                            ],
                            _buildLegend(),
                            const SizedBox(height: 12),
                            if (athletes.isEmpty)
                              const EmptyStateWidget(
                                icon: Icons.monitor_heart_outlined,
                                title: 'Veri yok',
                                description:
                                    'Son 90 günde koşu aktivitesi olan sporcu bulunamadı.',
                              )
                            else if (filtered.isEmpty)
                              const EmptyStateWidget(
                                icon: Icons.search_off,
                                title: 'Sonuç bulunamadı',
                                description: 'Arama kriterine uyan sporcu yok.',
                              )
                            else
                              ...filtered.map(
                                (a) => _AthleteCard(
                                  athlete: a,
                                  onTap: () => context.pushNamed(
                                    RouteNames.adminTrainingLoadDetail,
                                    pathParameters: {'userId': a.userId},
                                    extra: a.fullName,
                                  ),
                                ),
                              ),
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

  Widget _buildFilters() {
    final groupsAsync = ref.watch(allGroupsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSearchField(
          controller: _searchController,
          hint: 'Sporcu ara...',
          onChanged: (_) => setState(() {}),
          onClear: () => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: groupsAsync.when(
                loading: () => const SizedBox(height: 48),
                error: (_, __) => const SizedBox.shrink(),
                data: (groups) {
                  return DropdownButtonFormField<String?>(
                    value: _selectedGroupId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Grup',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tüm sporcular'),
                      ),
                      ...groups.map(
                        (g) => DropdownMenuItem<String?>(
                          value: g.id,
                          child: Text(g.name, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedGroupId = value),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<_SortBy>(
                value: _sortBy,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Sırala',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: _SortBy.tsb,
                    child: Text('Form (TSB)'),
                  ),
                  DropdownMenuItem(
                    value: _SortBy.acwr,
                    child: Text('Risk (ACWR)'),
                  ),
                  DropdownMenuItem(
                    value: _SortBy.acute,
                    child: Text('7g Yük'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _sortBy = value ?? _SortBy.tsb),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegend() {
    Widget dot(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.labelSmall
                  .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
            ),
          ],
        );

    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        dot(AppColors.success, 'Güvenli'),
        dot(AppColors.warning, 'Dikkat'),
        dot(AppColors.error, 'Risk'),
      ],
    );
  }
}

class _SummaryBand extends StatelessWidget {
  const _SummaryBand({required this.athletes});

  final List<AthleteLoadOverviewModel> athletes;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = ThemeBrightnessHolder.surface;

    final total = athletes.length;
    final risk =
        athletes.where((a) => a.status == TrainingLoadStatus.risk).length;
    final warning =
        athletes.where((a) => a.status == TrainingLoadStatus.warning).length;
    final ok = athletes.where((a) => a.status == TrainingLoadStatus.ok).length;

    final avgCtl = total == 0
        ? 0.0
        : athletes.map((a) => a.ctl).reduce((x, y) => x + y) / total;
    final avgTsb = total == 0
        ? 0.0
        : athletes.map((a) => a.tsb).reduce((x, y) => x + y) / total;
    final acwrValues = athletes
        .where((a) => a.acwr != null)
        .map((a) => a.acwr!)
        .toList();
    final avgAcwr = acwrValues.isEmpty
        ? null
        : acwrValues.reduce((x, y) => x + y) / acwrValues.length;
    final totalKm7 = athletes.isEmpty
        ? 0.0
        : athletes.map((a) => a.distance7dKm).reduce((x, y) => x + y);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ThemeBrightnessHolder.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_2_outlined,
                  size: 18, color: ThemeBrightnessHolder.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '$total sporcu',
                style: AppTypography.titleSmall
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Form/risk dagilim cubugu
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                _segment(ok, total, AppColors.success),
                _segment(warning, total, AppColors.warning),
                _segment(risk, total, AppColors.error),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _countChip(AppColors.success, 'Güvenli', ok),
              const SizedBox(width: 8),
              _countChip(AppColors.warning, 'Dikkat', warning),
              const SizedBox(width: 8),
              _countChip(AppColors.error, 'Risk', risk),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              _stat('Ort. CTL', avgCtl.round().toString(), AppColors.info),
              _stat('Ort. TSB', TrainingLoadFormat.formatSigned(avgTsb),
                  avgTsb >= 0 ? AppColors.success : AppColors.error),
              _stat('Ort. ACWR', avgAcwr?.toStringAsFixed(2) ?? '-',
                  TrainingLoadFormat.acwrColor(avgAcwr)),
              _stat('7g Toplam km', totalKm7.toStringAsFixed(0),
                  AppColors.neutral600),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segment(int count, int total, Color color) {
    if (count == 0) return const SizedBox.shrink();
    return Expanded(
      flex: count,
      child: Container(height: 8, color: color),
    );
  }

  Widget _countChip(Color color, String label, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '$label $count',
          style: AppTypography.labelSmall.copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.titleSmall
                .copyWith(fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.labelSmall
                .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AthleteCard extends StatelessWidget {
  const _AthleteCard({required this.athlete, required this.onTap});

  final AthleteLoadOverviewModel athlete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = ThemeBrightnessHolder.surface;
    final statusColor = TrainingLoadFormat.statusColor(athlete.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    UserAvatar(
                      imageUrl: athlete.avatarUrl,
                      name: athlete.fullName,
                      size: 44,
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
                                .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    _StatusBadge(
                      status: athlete.status,
                      color: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Metric(
                      label: 'CTL',
                      value: athlete.ctl.round().toString(),
                      color: AppColors.info,
                    ),
                    _Metric(
                      label: 'ATL',
                      value: athlete.atl.round().toString(),
                      color: AppColors.warning,
                    ),
                    _Metric(
                      label: 'TSB',
                      value: TrainingLoadFormat.formatSigned(athlete.tsb),
                      color: athlete.tsb >= 0
                          ? AppColors.success
                          : AppColors.error,
                    ),
                    _Metric(
                      label: 'ACWR',
                      value: athlete.acwr?.toStringAsFixed(2) ?? '-',
                      color: TrainingLoadFormat.acwrColor(athlete.acwr),
                    ),
                    _Metric(
                      label: '7g km',
                      value: athlete.distance7dKm.toStringAsFixed(0),
                      color: ThemeBrightnessHolder.onSurfaceVariant,
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

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.titleSmall
                .copyWith(fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.labelSmall
                .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.color});

  final TrainingLoadStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        TrainingLoadFormat.statusLabel(status),
        style: AppTypography.labelSmall
            .copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
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
            Text('Rapor yüklenemedi', style: AppTypography.titleSmall),
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
