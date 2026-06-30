import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/vdot_calculator.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../coaching/data/models/training_load_models.dart';
import '../../../coaching/presentation/providers/training_load_provider.dart';
import '../../../events/presentation/providers/event_provider.dart';
import '../../../integrations/presentation/providers/strava_connection_report_provider.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';
import '../providers/admin_reports_provider.dart';

const _kCardGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1E3A5F), Color(0xFF2D5C8F)],
);

/// Raporlar: Dashboard (sayisal ozet) + Raporlar (drill-down liste) sekmeleri.
class AdminReportsDashboardPage extends ConsumerWidget {
  const AdminReportsDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Raporlar')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Bu sayfaya erişim yetkiniz yok.',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.neutral500),
                textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: const Text('Raporlar'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Raporlar'),
              Tab(text: 'Dashboard'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ReportsTab(),
            _DashboardTab(),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DASHBOARD TAB - sayisal ozet
// ============================================================

class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: const [
        _SectionCard(
          title: 'Üyeler',
          icon: Icons.people_alt_rounded,
          child: _MembersSection(),
        ),
        SizedBox(height: 14),
        _SectionCard(
          title: 'Etkinlikler',
          icon: Icons.event_available_rounded,
          child: _EventsSection(),
        ),
        SizedBox(height: 14),
        _SectionCard(
          title: 'Form & Performans',
          icon: Icons.monitor_heart_rounded,
          child: _PerformanceSection(),
        ),
        SizedBox(height: 14),
        _SectionCard(
          title: 'VDOT & Tempo',
          icon: Icons.speed_rounded,
          child: _VdotSection(),
        ),
        SizedBox(height: 14),
        _SectionCard(
          title: 'Gruplar',
          icon: Icons.workspaces_rounded,
          child: _GroupsSection(),
        ),
        SizedBox(height: 14),
        _SectionCard(
          title: 'Strava',
          icon: Icons.directions_run_rounded,
          child: _StravaSection(),
        ),
      ],
    );
  }
}

class _MembersSection extends ConsumerWidget {
  const _MembersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeUsersProvider);
    final pending = ref.watch(pendingUsersProvider);
    final unassigned = ref.watch(unassignedUsersProvider);
    final banned = ref.watch(rejectedBannedUsersProvider);
    final engagement = ref.watch(userEngagementReportsProvider);

    return _StatGrid(tiles: [
      _Stat(_countStr(active), 'Toplam Üye', Icons.badge_rounded),
      _Stat(_countStr(pending), 'Onay Bekleyen', Icons.hourglass_top_rounded),
      _Stat(_countStr(unassigned), 'Grupsuz', Icons.group_off_rounded),
      _Stat(
        banned.maybeWhen(
            data: (u) => '${u.where((e) => e.isBanned).length}',
            orElse: () => '…'),
        'Engelli',
        Icons.block_rounded,
      ),
      _Stat(
        banned.maybeWhen(
            data: (u) => '${u.where((e) => e.isRejected).length}',
            orElse: () => '…'),
        'Reddedilen',
        Icons.person_off_rounded,
      ),
      _Stat(
        engagement.maybeWhen(
            data: (r) => '${r.inactiveAppUsers.length}', orElse: () => '…'),
        'Pasif (30g)',
        Icons.bedtime_rounded,
      ),
      _Stat(
        engagement.maybeWhen(
            data: (r) => '${r.inactiveEventUsers.length}', orElse: () => '…'),
        'Gelmeyen',
        Icons.event_busy_rounded,
      ),
    ]);
  }
}

class _EventsSection extends ConsumerWidget {
  const _EventsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thisWeek = ref.watch(thisWeekEventsProvider);
    final active = ref.watch(activeUsersProvider);
    final now = DateTime.now();
    final range = (
      start: DateTime(now.year, now.month - 5, 1),
      end: DateTime(now.year, now.month, now.day),
    );
    final trend = ref.watch(eventTypeTrendProvider(range));

    int typeCount(String type) => trend.maybeWhen(
        data: (items) => items
            .where((i) => i.eventType == type)
            .fold<int>(0, (s, i) => s + i.events),
        orElse: () => -1);

    String typeStr(String type) {
      final c = typeCount(type);
      return c < 0 ? '…' : '$c';
    }

    double? avgPerEvent() => trend.maybeWhen(
        data: (items) {
          final ev = items.fold<int>(0, (s, i) => s + i.events);
          final pa = items.fold<int>(0, (s, i) => s + i.participants);
          return ev > 0 ? pa / ev : 0.0;
        },
        orElse: () => null);

    final avg = avgPerEvent();
    final members = active.maybeWhen(data: (d) => d.length, orElse: () => null);
    final avgStr = avg == null ? '…' : avg.toStringAsFixed(1);
    final rateStr = (avg == null || members == null || members == 0)
        ? '…'
        : '%${(avg / members * 100).round()}';

    return Column(
      children: [
        _StatGrid(tiles: [
          _Stat(
            thisWeek.maybeWhen(data: (e) => '${e.length}', orElse: () => '…'),
            'Bu Hafta',
            Icons.today_rounded,
          ),
          _Stat(
            thisWeek.maybeWhen(
                data: (e) =>
                    '${e.fold<int>(0, (s, x) => s + x.participantCount)}',
                orElse: () => '…'),
            'Hafta Katılım',
            Icons.how_to_reg_rounded,
          ),
          _Stat(avgStr, 'Ort./Etkinlik', Icons.functions_rounded),
          _Stat(
            trend.maybeWhen(
                data: (items) =>
                    '${items.fold<int>(0, (s, i) => s + i.events)}',
                orElse: () => '…'),
            '6 Ay Etkinlik',
            Icons.event_rounded,
          ),
          _Stat(
            trend.maybeWhen(
                data: (items) =>
                    '${items.fold<int>(0, (s, i) => s + i.participants)}',
                orElse: () => '…'),
            '6 Ay Katılım',
            Icons.groups_2_rounded,
          ),
          _Stat(rateStr, 'Katılım Oranı', Icons.percent_rounded),
        ]),
        const SizedBox(height: 14),
        const _SubLabel('Etkinlik Türü · son 6 ay'),
        const SizedBox(height: 10),
        _StatGrid(tiles: [
          _Stat(typeStr('training'), 'Antrenman', Icons.fitness_center_rounded),
          _Stat(typeStr('race'), 'Yarış', Icons.flag_rounded),
          _Stat(typeStr('social'), 'Sosyal', Icons.celebration_rounded),
          _Stat(typeStr('workshop'), 'Workshop', Icons.school_rounded),
          _Stat(typeStr('other'), 'Diğer', Icons.more_horiz_rounded),
        ]),
      ],
    );
  }
}

class _PerformanceSection extends ConsumerWidget {
  const _PerformanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(coachTrainingLoadOverviewProvider(null));

    return overview.when(
      loading: () => const _SectionLoading(),
      error: (_, __) => const _StatGrid(tiles: [
        _Stat('–', 'Veri yok', Icons.error_outline),
      ]),
      data: (athletes) {
        final total = athletes.length;
        final risk = athletes
            .where((a) => a.status == TrainingLoadStatus.risk)
            .length;
        final warning = athletes
            .where((a) => a.status == TrainingLoadStatus.warning)
            .length;
        final ok = athletes
            .where((a) => a.status == TrainingLoadStatus.ok)
            .length;
        final avgCtl = total == 0
            ? 0
            : athletes.map((a) => a.ctl).reduce((x, y) => x + y) / total;
        final avgTsb = total == 0
            ? 0
            : athletes.map((a) => a.tsb).reduce((x, y) => x + y) / total;
        final acwrs = athletes
            .where((a) => a.acwr != null)
            .map((a) => a.acwr!)
            .toList();
        final avgAcwr = acwrs.isEmpty
            ? null
            : acwrs.reduce((x, y) => x + y) / acwrs.length;
        final totalKm7 = athletes.isEmpty
            ? 0
            : athletes.map((a) => a.distance7dKm).reduce((x, y) => x + y);

        return _StatGrid(tiles: [
          _Stat('$total', 'Sporcu', Icons.directions_run_rounded),
          _Stat('$risk', 'Risk', Icons.warning_rounded),
          _Stat('$warning', 'Dikkat', Icons.priority_high_rounded),
          _Stat('$ok', 'Güvenli', Icons.check_circle_rounded),
          _Stat('${avgCtl.round()}', 'Ort. CTL', Icons.trending_up_rounded),
          _Stat('${avgTsb >= 0 ? '+' : ''}${avgTsb.round()}', 'Ort. TSB',
              Icons.balance_rounded),
          _Stat(avgAcwr?.toStringAsFixed(2) ?? '–', 'Ort. ACWR',
              Icons.speed_rounded),
          _Stat(totalKm7.toStringAsFixed(0), '7g km', Icons.route_rounded),
        ]);
      },
    );
  }
}

class _GroupsSection extends ConsumerWidget {
  const _GroupsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupStatusOverviewProvider);

    return groups.when(
      loading: () => const _SectionLoading(),
      error: (_, __) => const _StatGrid(tiles: [
        _Stat('–', 'Veri yok', Icons.error_outline),
      ]),
      data: (list) {
        final members = list.fold<int>(0, (s, g) => s + g.memberCount);
        final active7 = list.fold<int>(0, (s, g) => s + g.activeMembers7d);
        final pending = list.fold<int>(0, (s, g) => s + g.pendingRequests);
        return _StatGrid(tiles: [
          _Stat('${list.length}', 'Grup', Icons.workspaces_rounded),
          _Stat('$members', 'Gruplu Üye', Icons.people_rounded),
          _Stat('$active7', '7g Aktif', Icons.bolt_rounded),
          _Stat('$pending', 'Bekleyen', Icons.mark_email_unread_rounded),
        ]);
      },
    );
  }
}

class _VdotSection extends ConsumerWidget {
  const _VdotSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeUsersProvider);

    return active.when(
      loading: () => const _SectionLoading(),
      error: (_, __) => const _StatGrid(tiles: [
        _Stat('–', 'Veri yok', Icons.error_outline),
      ]),
      data: (users) {
        final total = users.length;
        final withVdot =
            users.where((u) => u.vdot != null && u.vdot! > 0).toList();
        final n = withVdot.length;

        if (n == 0) {
          return const _StatGrid(tiles: [
            _Stat('0', 'VDOT’lu Üye', Icons.speed_rounded),
          ]);
        }

        final vdots = withVdot.map((u) => u.vdot!).toList();
        final avgVdot = vdots.reduce((a, b) => a + b) / n;
        final maxVdot = vdots.reduce((a, b) => a > b ? a : b);
        final paces =
            withVdot.map((u) => VdotCalculator.getThresholdPace(u.vdot!)).toList();
        final avgPace = (paces.reduce((a, b) => a + b) / n).round();
        final fastestPace = paces.reduce((a, b) => a < b ? a : b);
        final coverage = total > 0 ? (n / total * 100).round() : 0;

        return _StatGrid(tiles: [
          _Stat('$n', 'VDOT’lu Üye', Icons.badge_rounded),
          _Stat('%$coverage', 'Kapsam', Icons.percent_rounded),
          _Stat(avgVdot.toStringAsFixed(1), 'Ort. VDOT',
              Icons.show_chart_rounded),
          _Stat(maxVdot.toStringAsFixed(1), 'En İyi VDOT',
              Icons.emoji_events_rounded),
          _Stat(VdotCalculator.formatPace(avgPace), 'Ort. Eşik',
              Icons.timer_rounded),
          _Stat(VdotCalculator.formatPace(fastestPace), 'En Hızlı Eşik',
              Icons.bolt_rounded),
        ]);
      },
    );
  }
}

class _StravaSection extends ConsumerWidget {
  const _StravaSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strava = ref.watch(stravaConnectionReportProvider);
    return strava.when(
      loading: () => const _SectionLoading(),
      error: (_, __) => const _StatGrid(tiles: [
        _Stat('–', 'Veri yok', Icons.error_outline),
      ]),
      data: (r) => _StatGrid(tiles: [
        _Stat('${r.connectedCount}', 'Bağlı', Icons.link_rounded),
        _Stat('${r.notConnectedCount}', 'Bağlı Değil', Icons.link_off_rounded),
        _Stat('%${r.connectedPercentage.round()}', 'Oran',
            Icons.percent_rounded),
      ]),
    );
  }
}

String _countStr(AsyncValue<List<dynamic>> v) =>
    v.maybeWhen(data: (d) => '${d.length}', orElse: () => '…');

class _Stat {
  const _Stat(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});
  final List<_Stat> tiles;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.95,
      children: tiles.map((t) => _StatTile(stat: t)).toList(),
    );
  }
}

/// Navy kart uzerinde yari saydam istatistik chip'i (hero stiliyle ayni).
class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});
  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(stat.icon,
                color: Colors.white.withValues(alpha: 0.95), size: 17),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              stat.value,
              style: AppTypography.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stat.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall
                .copyWith(color: Colors.white.withValues(alpha: 0.72)),
          ),
        ],
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: AppTypography.labelSmall.copyWith(
          color: Colors.white.withValues(alpha: 0.75),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Navy gradient bolum karti - hero stiliyle ayni gorunum.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        gradient: _kCardGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// RAPORLAR TAB - drill-down liste
// ============================================================

class _ReportsTab extends StatelessWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _ReportCard(
          icon: Icons.monitor_heart_outlined,
          title: 'Performans Raporları',
          subtitle: 'Kulüp/grup özeti, form/yorgunluk (CTL/ATL/TSB) ve risk',
          iconColor: AppColors.info,
          onTap: () => context.pushNamed(RouteNames.adminTrainingLoad),
        ),
        const SizedBox(height: 12),
        _ReportCard(
          icon: Icons.person_search_outlined,
          title: 'Kişi 360',
          subtitle: 'Tek üyenin birleşik profili (performans, puan, Strava)',
          iconColor: AppColors.tertiary,
          onTap: () => context.pushNamed(RouteNames.adminPerson360),
        ),
        const SizedBox(height: 12),
        _ReportCard(
          icon: Icons.speed,
          title: 'VDOT & Eşik Pace',
          subtitle: 'Üyelerin VDOT ve eşik pace değerleri',
          iconColor: AppColors.success,
          onTap: () => context.pushNamed(RouteNames.adminVdotThresholdList),
        ),
        const SizedBox(height: 12),
        _ReportCard(
          icon: Icons.flag_outlined,
          title: 'Etkinlik Yarış Formu',
          subtitle: 'Yaklaşan yarış katılımcılarının form durumu',
          iconColor: AppColors.tertiary,
          onTap: () => context.pushNamed(RouteNames.adminEventTrainingLoad),
        ),
        const SizedBox(height: 12),
        _ReportCard(
          icon: Icons.bar_chart_rounded,
          title: 'Katılım Raporları',
          subtitle:
              'Etkinlik türüne göre katılım, KPI özeti ve etkinlik listesi',
          iconColor: AppColors.tertiary,
          onTap: () => context.pushNamed(RouteNames.adminParticipationReports),
        ),
        const SizedBox(height: 12),
        _ReportCard(
          icon: Icons.dashboard_customize_outlined,
          title: 'Grup Durum Panosu',
          subtitle: 'Grup başına üye, aktiflik ve bekleyen talepler',
          iconColor: AppColors.primary,
          onTap: () => context.pushNamed(RouteNames.adminGroupStatus),
        ),
        const SizedBox(height: 12),
        _ReportCard(
          icon: Icons.insights_outlined,
          title: 'Etkinlik Türü Trendi',
          subtitle: 'Aylık etkinlik türlerine göre katılım trendi',
          iconColor: AppColors.info,
          onTap: () => context.pushNamed(RouteNames.adminEventTypeTrend),
        ),
        const SizedBox(height: 12),
        _ReportCard(
          icon: Icons.groups_outlined,
          title: 'Kullanıcı Analizleri',
          subtitle: 'Uygulama açılışı ve etkinlik katılım analizleri',
          iconColor: AppColors.info,
          onTap: () => context.pushNamed(RouteNames.userEngagementReports),
        ),
        const SizedBox(height: 12),
        _ReportCard(
          icon: Icons.emoji_events_outlined,
          title: 'Kullanıcı Puanları',
          subtitle: 'Puan sıralaması ve liderlik tablosu',
          iconColor: const Color(0xFFFF8F00),
          onTap: () => context.pushNamed(RouteNames.userPointsLeaderboard),
        ),
        const SizedBox(height: 12),
        _ReportCard(
          icon: Icons.directions_run,
          title: 'Strava Bağlantı Raporu',
          subtitle: 'Bağlayan / bağlamayan sayısı ve kullanıcı listesi',
          iconColor: const Color(0xFFFC4C02),
          onTap: () =>
              context.pushNamed(RouteNames.adminStravaConnectionReport),
        ),
        const SizedBox(height: 12),
        _ReportCard(
          icon: Icons.qr_code_scanner_outlined,
          title: 'Avantaj Kullanımları',
          subtitle: 'QR doğrulama kayıtları ve özet',
          iconColor: const Color(0xFF1B4332),
          onTap: () => context.pushNamed(RouteNames.adminPartnerRedemptions),
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.neutral400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
