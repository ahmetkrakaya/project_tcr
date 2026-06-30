import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/models/partner_campaign_model.dart';
import '../providers/partner_campaign_provider.dart';

class PartnerPerksHomeBanner extends ConsumerWidget {
  const PartnerPerksHomeBanner({super.key});

  Color _parseColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return const Color(0xFF1B4332);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignsAsync = ref.watch(activePartnerCampaignsProvider);

    return campaignsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (campaigns) {
        if (campaigns.isEmpty) return const SizedBox.shrink();

        final featured = campaigns.first;
        final brandColor = _parseColor(featured.brandColor);

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Material(
            color: brandColor,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (campaigns.length == 1) {
                  context.pushNamed(
                    RouteNames.partnerPerkDetail,
                    pathParameters: {'campaignId': featured.id},
                  );
                } else {
                  context.pushNamed(RouteNames.partnerPerks);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    _BannerLogo(campaign: featured),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Üye Avantajı',
                            style: AppTypography.labelSmall.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            featured.partnerName,
                            style: AppTypography.titleSmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            featured.discountLabel,
                            style: AppTypography.bodySmall.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BannerLogo extends StatelessWidget {
  const _BannerLogo({required this.campaign});

  final PartnerCampaignModel campaign;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(6),
      child: campaign.logoUrl != null
          ? CachedNetworkImage(
              imageUrl: campaign.logoUrl!,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const Icon(
                Icons.local_offer,
                color: Colors.white,
                size: 22,
              ),
            )
          : const Icon(
              Icons.local_offer,
              color: Colors.white,
              size: 22,
            ),
    );
  }
}
