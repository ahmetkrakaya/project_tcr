import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/partner_campaign_model.dart';
import '../../data/models/partner_redemption_models.dart';
import '../providers/partner_campaign_provider.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

class AdminPartnerRedemptionsPage extends ConsumerStatefulWidget {
  const AdminPartnerRedemptionsPage({super.key});

  @override
  ConsumerState<AdminPartnerRedemptionsPage> createState() =>
      _AdminPartnerRedemptionsPageState();
}

class _AdminPartnerRedemptionsPageState
    extends ConsumerState<AdminPartnerRedemptionsPage> {
  late PartnerRedemptionReportFilters _filters;
  bool _sinceCampaignStart = false;

  @override
  void initState() {
    super.initState();
    _filters = _defaultDateFilters();
  }

  PartnerRedemptionReportFilters _defaultDateFilters() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return PartnerRedemptionReportFilters(
      fromDate: today.subtract(const Duration(days: 29)),
      toDate: today,
    );
  }

  void _refresh() {
    ref.invalidate(partnerRedemptionReportProvider(_filters));
    ref.invalidate(partnerRedemptionDashboardProvider(_filters));
    ref.invalidate(allPartnerCampaignsProvider);
  }

  void _setCampaignFilter(
    String? campaignId, {
    required List<PartnerCampaignModel> campaigns,
  }) {
    setState(() {
      _filters = _filters.copyWith(
        campaignId: campaignId,
        clearCampaignId: campaignId == null,
      );

      if (campaignId == null && _sinceCampaignStart) {
        _sinceCampaignStart = false;
        _filters = _defaultDateFilters();
      } else if (_sinceCampaignStart && campaignId != null) {
        _applySinceCampaignStart(campaigns);
      }
    });
  }

  void _applySinceCampaignStart(List<PartnerCampaignModel> campaigns) {
    final campaignId = _filters.campaignId;
    if (campaignId == null) return;

    final campaign = campaigns.where((c) => c.id == campaignId);
    if (campaign.isEmpty) return;
    final start = campaign.first.startsAt.toLocal();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    _filters = _filters.copyWith(
      fromDate: DateTime(start.year, start.month, start.day),
      toDate: today,
    );
  }

  void _toggleSinceCampaignStart(
    bool value,
    List<PartnerCampaignModel> campaigns,
  ) {
    if (value && _filters.campaignId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kampanya başından beri için önce bir kampanya seçin.'),
        ),
      );
      return;
    }

    setState(() {
      _sinceCampaignStart = value;
      if (value) {
        _applySinceCampaignStart(campaigns);
      }
    });
  }

  Future<void> _pickFromDate() async {
    if (_sinceCampaignStart) return;

    final now = DateTime.now();
    final current = _filters.fromDate ?? now.subtract(const Duration(days: 29));

    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2024),
      lastDate: _filters.toDate ?? now,
      locale: const Locale('tr', 'TR'),
    );

    if (picked == null || !mounted) return;

    setState(() {
      var toDate = _filters.toDate ?? now;
      if (picked.isAfter(toDate)) toDate = picked;
      _filters = _filters.copyWith(fromDate: picked, toDate: toDate);
    });
  }

  Future<void> _pickToDate() async {
    if (_sinceCampaignStart) return;

    final now = DateTime.now();
    final current = _filters.toDate ?? now;
    final fromDate = _filters.fromDate ?? now.subtract(const Duration(days: 29));

    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(fromDate) ? fromDate : current,
      firstDate: fromDate,
      lastDate: now,
      locale: const Locale('tr', 'TR'),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _filters = _filters.copyWith(toDate: picked);
    });
  }

  Future<void> _pickCampaign(List<PartnerCampaignModel> campaigns) async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CampaignSearchSheet(
        campaigns: campaigns,
        selectedCampaignId: _filters.campaignId,
      ),
    );

    if (!mounted || selected == _filters.campaignId) return;
    _setCampaignFilter(selected, campaigns: campaigns);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminOrCoachProvider);
    final campaignsAsync = ref.watch(allPartnerCampaignsProvider);
    final reportAsync = ref.watch(partnerRedemptionReportProvider(_filters));
    final dashboardAsync =
        ref.watch(partnerRedemptionDashboardProvider(_filters));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        ThemeBrightnessHolder.scaffoldBackground;

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Avantaj Kullanımları')),
        body: const Center(child: Text('Bu sayfaya erişim yetkiniz yok.')),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: const Text('Avantaj Kullanımları'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Kayıtlar'),
              Tab(text: 'Dashboard'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Yenile',
              onPressed: _refresh,
              icon: Icon(Icons.refresh),
            ),
          ],
        ),
        body: campaignsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Kampanyalar yüklenemedi: $e')),
          data: (campaigns) {
            PartnerCampaignModel? selectedCampaign;
            if (_filters.campaignId != null) {
              final matches =
                  campaigns.where((c) => c.id == _filters.campaignId);
              if (matches.isNotEmpty) selectedCampaign = matches.first;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CampaignSearchField(
                        label: selectedCampaign?.partnerName ?? 'Tüm kampanyalar',
                        subtitle: selectedCampaign?.discountLabel,
                        onTap: () => _pickCampaign(campaigns),
                        onClear: _filters.campaignId == null
                            ? null
                            : () => _setCampaignFilter(
                                  null,
                                  campaigns: campaigns,
                                ),
                      ),
                      const SizedBox(height: 12),
                      _DateRangeFilterBar(
                        fromDate: _filters.fromDate,
                        toDate: _filters.toDate,
                        sinceCampaignStart: _sinceCampaignStart,
                        showSinceCampaignStart:
                            _filters.campaignId != null,
                        onFromDateTap: _pickFromDate,
                        onToDateTap: _pickToDate,
                        onSinceCampaignStartChanged: (value) =>
                            _toggleSinceCampaignStart(value, campaigns),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    children: [
                      reportAsync.when(
                        loading: () => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        error: (e, _) =>
                            Center(child: Text('Rapor yüklenemedi: $e')),
                        data: (report) => _RecordsTab(report: report),
                      ),
                      dashboardAsync.when(
                        loading: () => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        error: (e, _) =>
                            Center(child: Text('Dashboard yüklenemedi: $e')),
                        data: (dashboard) => _DashboardTab(
                          campaigns: campaigns,
                          dashboard: dashboard,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CampaignSearchField extends StatelessWidget {
  const _CampaignSearchField({
    required this.label,
    required this.onTap,
    this.subtitle,
    this.onClear,
  });

  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Kampanya filtresi',
          border: const OutlineInputBorder(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onClear != null)
                IconButton(
                  tooltip: 'Temizle',
                  onPressed: onClear,
                  icon: Icon(Icons.close, size: 20),
                ),
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.search, size: 20),
              ),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: AppTypography.bodySmall.copyWith(
                  color: ThemeBrightnessHolder.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CampaignSearchSheet extends StatefulWidget {
  const _CampaignSearchSheet({
    required this.campaigns,
    required this.selectedCampaignId,
  });

  final List<PartnerCampaignModel> campaigns;
  final String? selectedCampaignId;

  @override
  State<_CampaignSearchSheet> createState() => _CampaignSearchSheetState();
}

class _CampaignSearchSheetState extends State<_CampaignSearchSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PartnerCampaignModel> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.campaigns;
    return widget.campaigns.where((c) {
      return c.partnerName.toLowerCase().contains(q) ||
          c.discountLabel.toLowerCase().contains(q) ||
          c.slug.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        ThemeBrightnessHolder.surface;
    final filtered = _filtered;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeBrightnessHolder.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Kampanya ara...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: Icon(Icons.all_inclusive),
                    title: const Text('Tüm kampanyalar'),
                    trailing: widget.selectedCampaignId == null
                        ? Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.pop(context, null),
                  ),
                  ...filtered.map(
                    (campaign) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.1),
                        child: Text(
                          campaign.partnerName.isNotEmpty
                              ? campaign.partnerName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(campaign.partnerName),
                      subtitle: Text(
                        campaign.discountLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: widget.selectedCampaignId == campaign.id
                          ? Icon(Icons.check, color: AppColors.primary)
                          : null,
                      onTap: () => Navigator.pop(context, campaign.id),
                    ),
                  ),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Sonuç bulunamadı.',
                        style: AppTypography.bodyMedium.copyWith(
                          color: ThemeBrightnessHolder.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
          ],
        ),
      ),
    );
  }
}

class _DateRangeFilterBar extends StatelessWidget {
  const _DateRangeFilterBar({
    required this.fromDate,
    required this.toDate,
    required this.sinceCampaignStart,
    required this.showSinceCampaignStart,
    required this.onFromDateTap,
    required this.onToDateTap,
    required this.onSinceCampaignStartChanged,
  });

  final DateTime? fromDate;
  final DateTime? toDate;
  final bool sinceCampaignStart;
  final bool showSinceCampaignStart;
  final VoidCallback onFromDateTap;
  final VoidCallback onToDateTap;
  final ValueChanged<bool> onSinceCampaignStartChanged;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy', 'tr_TR');
    final enabled = !sinceCampaignStart;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Tarih aralığı',
                style: AppTypography.labelMedium.copyWith(
                  color: ThemeBrightnessHolder.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (showSinceCampaignStart)
              FilterChip(
                label: const Text('Baştan beri'),
                selected: sinceCampaignStart,
                onSelected: onSinceCampaignStartChanged,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                labelPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                selectedColor: AppColors.primary.withValues(alpha: 0.12),
                checkmarkColor: AppColors.primary,
                labelStyle: AppTypography.labelSmall.copyWith(
                  color: sinceCampaignStart
                      ? AppColors.primary
                      : AppColors.neutral600,
                  fontWeight:
                      sinceCampaignStart ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'Başlangıç',
                value: fromDate != null ? fmt.format(fromDate!) : '—',
                enabled: enabled,
                onTap: onFromDateTap,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.arrow_forward,
                size: 18,
                color: enabled
                    ? AppColors.neutral400
                    : AppColors.neutral300,
              ),
            ),
            Expanded(
              child: _DateField(
                label: 'Bitiş',
                value: toDate != null ? fmt.format(toDate!) : '—',
                enabled: enabled,
                onTap: onToDateTap,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          enabled: enabled,
          suffixIcon: Icon(
            Icons.calendar_today_outlined,
            size: 18,
            color: enabled ? AppColors.neutral500 : AppColors.neutral300,
          ),
        ),
        child: Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: enabled ? null : AppColors.neutral400,
          ),
        ),
      ),
    );
  }
}

class _RecordsTab extends StatelessWidget {
  const _RecordsTab({required this.report});

  final PartnerRedemptionReport report;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        if (report.items.isEmpty)
          Text(
            'Seçili filtrelere uygun kayıt yok.',
            style: AppTypography.bodyMedium.copyWith(
              color: ThemeBrightnessHolder.onSurfaceVariant,
            ),
          )
        else
          ...report.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RedemptionTile(item: item),
            ),
          ),
      ],
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.campaigns,
    required this.dashboard,
  });

  final List<PartnerCampaignModel> campaigns;
  final PartnerRedemptionDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final activeCount =
        campaigns.where((c) => c.isCurrentlyActive(at: now)).length;
    final inactiveCount = campaigns.length - activeCount;
    final qrActiveCount = campaigns
        .where((c) => c.qrRedemptionEnabled && c.isCurrentlyActive(at: now))
        .length;
    final usage = dashboard.usage;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = ThemeBrightnessHolder.surface;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        _DashboardSection(
          title: 'Kampanyalar',
          icon: Icons.local_offer_outlined,
          child: _StatGrid(
            tiles: [
              _DashboardStat('${campaigns.length}', 'Toplam kampanya'),
              _DashboardStat('$activeCount', 'Aktif kampanya'),
              _DashboardStat('$inactiveCount', 'Pasif kampanya'),
              _DashboardStat('$qrActiveCount', 'QR aktif kampanya'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _DashboardSection(
          title: 'Kullanım özeti',
          icon: Icons.analytics_outlined,
          child: _StatGrid(
            tiles: [
              _DashboardStat('${usage.totalSuccess}', 'Başarılı kullanım'),
              _DashboardStat('${usage.totalAttempts}', 'Toplam deneme'),
              _DashboardStat('${usage.uniqueUsers}', 'Tekil üye'),
              _DashboardStat(
                usage.totalAttempts == 0
                    ? '—'
                    : '${usage.successRate.toStringAsFixed(0)}%',
                'Başarı oranı',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _DashboardSection(
          title: 'Reddedilenler',
          icon: Icons.block_outlined,
          child: _StatGrid(
            tiles: [
              _DashboardStat('${usage.totalRejected}', 'Toplam red'),
              _DashboardStat(
                '${usage.rejectedAlreadyUsed}',
                'Zaten kullanılmış',
              ),
              _DashboardStat('${usage.rejectedExpired}', 'Süresi dolmuş'),
              _DashboardStat('${usage.rejectedLimit}', 'Limit aşıldı'),
              _DashboardStat('${usage.rejectedInactive}', 'Kampanya pasif'),
            ],
          ),
        ),
        if (dashboard.byCampaign.isNotEmpty) ...[
          const SizedBox(height: 16),
          _DashboardSection(
            title: 'Kampanyaya göre',
            icon: Icons.leaderboard_outlined,
            child: Column(
              children: dashboard.byCampaign.map((item) {
                final maxCount = dashboard.byCampaign
                    .map((e) => e.successCount)
                    .fold(0, (a, b) => a > b ? a : b);
                final ratio = maxCount == 0
                    ? 0.0
                    : item.successCount / maxCount;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.partnerName,
                              style: AppTypography.titleSmall.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: (item.isActive
                                      ? AppColors.success
                                      : AppColors.neutral400)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              item.isActive ? 'Aktif' : 'Pasif',
                              style: AppTypography.labelSmall.copyWith(
                                color: item.isActive
                                    ? AppColors.success
                                    : AppColors.neutral600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                          backgroundColor: ThemeBrightnessHolder.surfaceContainerHighest,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${item.successCount} başarılı · ${item.totalCount} toplam',
                        style: AppTypography.bodySmall.copyWith(
                          color: ThemeBrightnessHolder.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = ThemeBrightnessHolder.surface;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _DashboardStat {
  const _DashboardStat(this.value, this.label);

  final String value;
  final String label;
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});

  final List<_DashboardStat> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 420 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.35,
          ),
          itemBuilder: (context, index) {
            final tile = tiles[index];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ThemeBrightnessHolder.scaffoldBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    tile.value,
                    style: AppTypography.titleLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tile.label,
                    style: AppTypography.labelSmall.copyWith(
                      color: ThemeBrightnessHolder.onSurfaceVariant,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RedemptionTile extends StatelessWidget {
  const _RedemptionTile({required this.item});

  final PartnerRedemptionReportItem item;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = ThemeBrightnessHolder.surface;
    final dateText =
        DateFormat('d MMM yyyy HH:mm', 'tr_TR').format(item.redeemedAt);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (item.isSuccess ? AppColors.success : AppColors.neutral400)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              item.isSuccess ? Icons.check : Icons.close,
              color: item.isSuccess ? AppColors.success : AppColors.neutral500,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.userName.isEmpty ? 'Üye' : item.userName,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.partnerName,
                  style: AppTypography.bodySmall.copyWith(
                    color: ThemeBrightnessHolder.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  dateText,
                  style: AppTypography.labelSmall.copyWith(
                    color: ThemeBrightnessHolder.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (item.isSuccess ? AppColors.success : AppColors.neutral400)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              item.statusLabel,
              style: AppTypography.labelSmall.copyWith(
                color: item.isSuccess
                    ? AppColors.success
                    : AppColors.neutral600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
