import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../data/models/partner_campaign_model.dart';
import '../providers/partner_campaign_provider.dart';

class PartnerPerksPage extends ConsumerWidget {
  const PartnerPerksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignsAsync = ref.watch(activePartnerCampaignsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Üye Avantajları'),
      ),
      body: campaignsAsync.when(
        loading: () => const LoadingWidget(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Avantajlar yüklenemedi',
                  style: AppTypography.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '$e',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.neutral500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(activePartnerCampaignsProvider),
                  child: const Text('Tekrar Dene'),
                ),
              ],
            ),
          ),
        ),
        data: (campaigns) {
          if (campaigns.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.local_offer_outlined,
              title: 'Henüz aktif avantaj yok',
              description:
                  'Yeni partner kampanyaları eklendiğinde burada görünecek.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: campaigns.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _PartnerCampaignCard(campaign: campaigns[index]);
            },
          );
        },
      ),
    );
  }
}

class _PartnerCampaignCard extends StatelessWidget {
  const _PartnerCampaignCard({required this.campaign});

  final PartnerCampaignModel campaign;

  Color _parseColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return const Color(0xFF1B4332);
  }

  @override
  Widget build(BuildContext context) {
    final brandColor = _parseColor(campaign.brandColor);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => context.pushNamed(
          RouteNames.partnerPerkDetail,
          pathParameters: {'campaignId': campaign.id},
        ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: brandColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: campaign.logoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: campaign.logoUrl!,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Icon(
                          Icons.local_cafe,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      )
                    : Icon(
                        Icons.local_offer,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 28,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      campaign.partnerName,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (campaign.tagline != null &&
                        campaign.tagline!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        campaign.tagline!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      campaign.discountLabel,
                      style: AppTypography.labelMedium.copyWith(
                        color: brandColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
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
