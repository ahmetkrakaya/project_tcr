import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/report_info_button.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../integrations/data/models/strava_connection_report_model.dart';
import '../../../integrations/presentation/providers/strava_connection_report_provider.dart';

const _info = ReportInfo(
  title: 'Strava Bağlantı Raporu',
  summary:
      'Üyelerin Strava hesabını bağlama durumunu gösterir. Bağlantı, otomatik '
      'aktivite akışı ve performans verisi için gereklidir.',
  terms: [
    ReportInfoTerm('Bağlı', 'Strava hesabını bağlamış üye sayısı.'),
    ReportInfoTerm('Bağlı Değil', 'Henüz bağlamamış aktif üyeler.'),
    ReportInfoTerm('Bağlanma %', 'Aktif üyeler içinde bağlı olanların oranı.'),
  ],
  takeaways: [
    'Düşük oran, performans raporlarının eksik veriyle çalışması demektir.',
    'Bağlamamış üyeleri bağlanmaya yönlendirin.',
    'Yüksek oran daha sağlıklı analizler sağlar.',
  ],
);

class StravaConnectionReportPage extends ConsumerStatefulWidget {
  const StravaConnectionReportPage({super.key});

  @override
  ConsumerState<StravaConnectionReportPage> createState() =>
      _StravaConnectionReportPageState();
}

class _StravaConnectionReportPageState
    extends ConsumerState<StravaConnectionReportPage> {
  final _searchController = TextEditingController();

  static const _stravaColor = Color(0xFFFC4C02);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAdmin = ref.watch(isAdminProvider);
    final reportAsync = ref.watch(stravaConnectionReportProvider);
    final searchQuery = _searchController.text.toLowerCase().trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Strava Bağlantı Raporu'),
        actions: const [ReportInfoButton(info: _info)],
      ),
      body: !isAdmin
          ? Center(
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
            )
          : reportAsync.when(
              loading: () => const Center(child: LoadingWidget()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Rapor yüklenemedi',
                        style: AppTypography.titleSmall.copyWith(
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.toString(),
                        style: AppTypography.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(stravaConnectionReportProvider),
                        child: const Text('Tekrar Dene'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (report) {
                final filteredUsers = searchQuery.isEmpty
                    ? report.notConnectedUsers
                    : report.notConnectedUsers
                        .where(
                          (user) =>
                              user.fullName.toLowerCase().contains(searchQuery),
                        )
                        .toList();

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(stravaConnectionReportProvider);
                    await ref.read(stravaConnectionReportProvider.future);
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryCard(
                              label: 'Bağlayan',
                              value: report.connectedCount.toString(),
                              subtitle:
                                  '%${report.connectedPercentage.toStringAsFixed(0)}',
                              color: _stravaColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SummaryCard(
                              label: 'Bağlamayan',
                              value: report.notConnectedCount.toString(),
                              subtitle: 'aktif üye',
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Bağlamayanlar (${report.notConnectedCount})',
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Aktif üyeler arasında Strava hesabı bağlamamış kullanıcılar',
                        style: AppTypography.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppSearchField(
                        controller: _searchController,
                        hint: 'Ad soyad ara...',
                        onChanged: (_) => setState(() {}),
                        onClear: () => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      if (report.notConnectedUsers.isEmpty)
                        const EmptyStateWidget(
                          icon: Icons.link,
                          title: 'Herkes bağlamış',
                          description:
                              'Tüm aktif üyeler Strava hesabını bağlamış görünüyor',
                        )
                      else if (filteredUsers.isEmpty)
                        EmptyStateWidget(
                          icon: Icons.search_off,
                          title: 'Sonuç bulunamadı',
                          description: '"$searchQuery" için eşleşme yok',
                        )
                      else
                        ...filteredUsers.map(
                          (user) => _UserListTile(user: user),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  final String label;
  final String value;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTypography.headlineSmall.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTypography.labelSmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserListTile extends StatelessWidget {
  const _UserListTile({required this.user});

  final StravaConnectionUserItemModel user;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ListTile(
        leading: UserAvatar(
          imageUrl: user.avatarUrl,
          name: user.fullName,
          size: 44,
        ),
        title: Text(
          user.fullName,
          style: AppTypography.titleSmall.copyWith(color: cs.onSurface),
        ),
        subtitle: Text(
          'Strava bağlı değil',
          style: AppTypography.bodySmall.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
