import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/report_info_button.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/admin_reports_models.dart';
import '../providers/admin_reports_provider.dart';

const _info = ReportInfo(
  title: 'Grup Durum Panosu',
  summary:
      'Her grubun üye sayısı, aktiflik ve bekleyen taleplerini tek bakışta '
      'gösterir; hangi grup canlı, hangisi ilgi bekliyor görürsünüz.',
  terms: [
    ReportInfoTerm('Üye', 'Gruptaki toplam üye sayısı.'),
    ReportInfoTerm('7g Aktif', 'Son 7 günde koşu kaydı olan üye sayısı.'),
    ReportInfoTerm('30g Pasif', 'Son 30 günde uygulama/aktivite hareketi olmayan üye.'),
    ReportInfoTerm('Bekleyen', 'Onay bekleyen katılım talebi sayısı.'),
  ],
  takeaways: [
    'Düşük aktiflik oranı olan grupları motive edici içerikle canlandırın.',
    'Bekleyen talepleri zamanında yanıtlayın.',
    'Gruba dokununca performans detayına gidebilirsiniz.',
  ],
);

class GroupStatusDashboardPage extends ConsumerWidget {
  const GroupStatusDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
    final groupsAsync = ref.watch(groupStatusOverviewProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grup Durum Panosu'),
        actions: const [ReportInfoButton(info: _info)],
      ),
      body: !isAdminOrCoach
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Bu sayfaya erişim yetkiniz yok.',
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.neutral500),
                    textAlign: TextAlign.center),
              ),
            )
          : groupsAsync.when(
              loading: () => const Center(child: LoadingWidget()),
              error: (e, _) => _ErrorView(
                error: e,
                onRetry: () => ref.invalidate(groupStatusOverviewProvider),
              ),
              data: (groups) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(groupStatusOverviewProvider);
                  await ref.read(groupStatusOverviewProvider.future);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    if (groups.isEmpty)
                      const EmptyStateWidget(
                        icon: Icons.groups_outlined,
                        title: 'Grup yok',
                        description: 'Aktif grup bulunamadı.',
                      )
                    else ...[
                      _OverallBand(groups: groups),
                      const SizedBox(height: 16),
                      ...groups.map((g) => _GroupCard(group: g)),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _OverallBand extends StatelessWidget {
  const _OverallBand({required this.groups});
  final List<GroupStatusItem> groups;

  @override
  Widget build(BuildContext context) {
    final totalMembers =
        groups.fold<int>(0, (s, g) => s + g.memberCount);
    final totalActive7d =
        groups.fold<int>(0, (s, g) => s + g.activeMembers7d);
    final totalPending =
        groups.fold<int>(0, (s, g) => s + g.pendingRequests);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _stat('${groups.length}', 'Grup', AppColors.info),
          _stat('$totalMembers', 'Üye', AppColors.primary),
          _stat('$totalActive7d', '7g Aktif', AppColors.success),
          _stat('$totalPending', 'Bekleyen', AppColors.warning),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, Color color) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: AppTypography.titleLarge
                    .copyWith(fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.neutral500)),
          ],
        ),
      );
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});
  final GroupStatusItem group;

  @override
  Widget build(BuildContext context) {
    final activeRatio = group.memberCount == 0
        ? 0.0
        : group.activeMembers7d / group.memberCount;
    final ratioColor = activeRatio >= 0.5
        ? AppColors.success
        : activeRatio >= 0.25
            ? AppColors.warning
            : AppColors.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.pushNamed(
          RouteNames.adminTrainingLoad,
          extra: group.id,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(group.name,
                      style: AppTypography.titleSmall
                          .copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (group.isPerformance)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Performans',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.info)),
                  ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AppColors.neutral400),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metric('${group.memberCount}', 'Üye', AppColors.neutral600),
                _metric('${group.activeMembers7d}', '7g Aktif', ratioColor),
                _metric('${group.passiveMembers30d}', '30g Pasif',
                    AppColors.neutral500),
                _metric(group.distance7dKm.toStringAsFixed(0), '7g km',
                    AppColors.info),
                _metric('${group.pendingRequests}', 'Bekleyen',
                    group.pendingRequests > 0
                        ? AppColors.warning
                        : AppColors.neutral500),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: activeRatio.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppColors.neutral200,
                valueColor: AlwaysStoppedAnimation(ratioColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String value, String label, Color color) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: AppTypography.titleSmall
                    .copyWith(fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.neutral500),
                textAlign: TextAlign.center),
          ],
        ),
      );
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
            Text(error.toString(),
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.neutral500),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Tekrar Dene')),
          ],
        ),
      ),
    );
  }
}
