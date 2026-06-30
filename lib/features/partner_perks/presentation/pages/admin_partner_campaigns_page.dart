import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/partner_campaign_model.dart';
import '../providers/partner_campaign_provider.dart';

class AdminPartnerCampaignsPage extends ConsumerWidget {
  const AdminPartnerCampaignsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminOrCoachProvider);
    final campaignsAsync = ref.watch(allPartnerCampaignsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Üye Avantajları'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Yeni kampanya',
              onPressed: () => _openCreatePage(context),
            ),
        ],
      ),
      body: !isAdmin
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Bu sayfaya erişim yetkiniz yok.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.neutral500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : campaignsAsync.when(
              loading: () => const LoadingWidget(),
              error: (e, _) => Center(child: Text('Yüklenemedi: $e')),
              data: (campaigns) {
                if (campaigns.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_offer_outlined,
                            size: 48,
                            color: AppColors.neutral400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz kampanya yok',
                            style: AppTypography.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Partner işletmeler için indirim kampanyası ekleyin.',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.neutral500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () => _openCreatePage(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Kampanya Ekle'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  itemCount: campaigns.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final campaign = campaigns[index];
                    return _AdminCampaignTile(
                      campaign: campaign,
                      onEdit: () => _openEditPage(context, ref, campaign.id),
                      onToggleActive: () =>
                          _toggleActive(context, ref, campaign),
                      onDelete: () => _confirmDelete(context, ref, campaign),
                    );
                  },
                );
              },
            ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => _openCreatePage(context),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Future<void> _openCreatePage(BuildContext context) async {
    final saved = await context.pushNamed<bool>(
      RouteNames.adminPartnerCampaignCreate,
    );
    if (saved == true && context.mounted) {
      // Liste provider'ı form sayfasında invalidate ediliyor.
    }
  }

  Future<void> _openEditPage(
    BuildContext context,
    WidgetRef ref,
    String campaignId,
  ) async {
    ref.invalidate(partnerCampaignByIdProvider(campaignId));
    await context.pushNamed<bool>(
      RouteNames.adminPartnerCampaignEdit,
      pathParameters: {'campaignId': campaignId},
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    PartnerCampaignModel campaign,
  ) async {
    final nextActive = !campaign.isActive;
    try {
      await ref.read(partnerCampaignRepositoryProvider).setCampaignActive(
            campaign.id,
            nextActive,
          );
      ref.invalidate(allPartnerCampaignsProvider);
      ref.invalidate(activePartnerCampaignsProvider);
      ref.invalidate(partnerCampaignByIdProvider(campaign.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nextActive ? 'Kampanya aktif edildi' : 'Kampanya pasif edildi',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Durum güncellenemedi: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PartnerCampaignModel campaign,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kampanyayı sil'),
        content: Text(
          '"${campaign.partnerName}" kampanyasını silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(partnerCampaignRepositoryProvider)
          .deleteCampaign(campaign.id);
      ref.invalidate(allPartnerCampaignsProvider);
      ref.invalidate(activePartnerCampaignsProvider);
      ref.invalidate(partnerCampaignByIdProvider(campaign.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kampanya silindi')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silinemedi: $e')),
        );
      }
    }
  }
}

class _AdminCampaignTile extends StatelessWidget {
  const _AdminCampaignTile({
    required this.campaign,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final PartnerCampaignModel campaign;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  Color _parseColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return const Color(0xFF1B4332);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final isLive = campaign.isCurrentlyActive();
    final brandColor = _parseColor(campaign.brandColor);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.surfaceVariantDark : AppColors.neutral300,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: brandColor,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: campaign.logoUrl != null
              ? CachedNetworkImage(
                  imageUrl: campaign.logoUrl!,
                  fit: BoxFit.contain,
                )
              : const Icon(Icons.local_offer, color: Colors.white),
        ),
        title: Text(
          campaign.partnerName,
          style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(campaign.discountLabel),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isLive
                        ? AppColors.success.withValues(alpha: 0.15)
                        : AppColors.neutral300.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isLive ? 'Aktif' : 'Pasif',
                    style: AppTypography.labelSmall.copyWith(
                      color: isLive ? AppColors.success : AppColors.neutral600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!campaign.isActive) ...[
                  const SizedBox(width: 6),
                  Text(
                    'Kapalı',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.neutral500,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'toggle') onToggleActive();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(campaign.isActive ? 'Pasif yap' : 'Aktif yap'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Sil')),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}
