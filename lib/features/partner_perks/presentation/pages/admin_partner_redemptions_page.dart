import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/partner_campaign_model.dart';
import '../../data/models/partner_redemption_models.dart';
import '../providers/partner_campaign_provider.dart';

class AdminPartnerRedemptionsPage extends ConsumerStatefulWidget {
  const AdminPartnerRedemptionsPage({super.key});

  @override
  ConsumerState<AdminPartnerRedemptionsPage> createState() =>
      _AdminPartnerRedemptionsPageState();
}

class _AdminPartnerRedemptionsPageState
    extends ConsumerState<AdminPartnerRedemptionsPage> {
  String? _selectedCampaignId;

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminOrCoachProvider);
    final campaignsAsync = ref.watch(allPartnerCampaignsProvider);
    final reportAsync =
        ref.watch(partnerRedemptionReportProvider(_selectedCampaignId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Avantaj Kullanımları')),
        body: const Center(child: Text('Bu sayfaya erişim yetkiniz yok.')),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Avantaj Kullanımları'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: () {
              ref.invalidate(partnerRedemptionReportProvider(_selectedCampaignId));
              ref.invalidate(allPartnerCampaignsProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: campaignsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Kampanyalar yüklenemedi: $e')),
        data: (campaigns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _CampaignFilter(
                  campaigns: campaigns,
                  selectedCampaignId: _selectedCampaignId,
                  onChanged: (id) => setState(() => _selectedCampaignId = id),
                ),
              ),
              const SizedBox(height: 12),
              reportAsync.when(
                loading: () => const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Expanded(
                  child: Center(child: Text('Rapor yüklenemedi: $e')),
                ),
                data: (report) => Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    children: [
                      _SummaryCards(summary: report.summary),
                      const SizedBox(height: 20),
                      if (report.items.isEmpty)
                        Text(
                          'Henüz kayıt yok.',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.neutral500,
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
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CampaignFilter extends StatelessWidget {
  const _CampaignFilter({
    required this.campaigns,
    required this.selectedCampaignId,
    required this.onChanged,
  });

  final List<PartnerCampaignModel> campaigns;
  final String? selectedCampaignId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      value: selectedCampaignId,
      decoration: const InputDecoration(
        labelText: 'Kampanya filtresi',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Tüm kampanyalar'),
        ),
        ...campaigns.map(
          (c) => DropdownMenuItem<String?>(
            value: c.id,
            child: Text(c.partnerName),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.summary});

  final PartnerRedemptionReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            color: cardColor,
            label: 'Başarılı kullanım',
            value: '${summary.totalSuccess}',
            icon: Icons.check_circle_outline,
            iconColor: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            color: cardColor,
            label: 'Tekil üye',
            value: '${summary.uniqueUsers}',
            icon: Icons.people_outline,
            iconColor: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.color,
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  final Color color;
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: AppTypography.headlineSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.neutral500,
            ),
          ),
        ],
      ),
    );
  }
}

class _RedemptionTile extends StatelessWidget {
  const _RedemptionTile({required this.item});

  final PartnerRedemptionReportItem item;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
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
                    color: AppColors.neutral500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  dateText,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.neutral500,
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
