import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/models/partner_campaign_model.dart';
import '../providers/partner_campaign_provider.dart';

class PartnerPerksHomeBanner extends ConsumerStatefulWidget {
  const PartnerPerksHomeBanner({super.key});

  static const double _bannerHeight = 68;
  static const double _cardGap = 8;

  @override
  ConsumerState<PartnerPerksHomeBanner> createState() =>
      _PartnerPerksHomeBannerState();
}

class _PartnerPerksHomeBannerState extends ConsumerState<PartnerPerksHomeBanner> {
  static const Duration _autoSlideInterval = Duration(seconds: 4);
  static const Duration _slideDuration = Duration(milliseconds: 550);

  PageController? _pageController;
  Timer? _autoSlideTimer;
  int _currentPage = 1;
  int _slideItemCount = 0;
  bool _isAutoWrapping = false;
  bool _isUserDragging = false;

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  int _extendedPageCount(int itemCount) => itemCount + 2;

  PartnerCampaignModel _campaignAt(
    int index,
    List<PartnerCampaignModel> campaigns,
  ) {
    final lastIndex = campaigns.length - 1;
    if (index == 0) return campaigns[lastIndex];
    if (index == campaigns.length + 1) return campaigns.first;
    return campaigns[index - 1];
  }

  void _ensurePageController(int itemCount) {
    if (_pageController != null && _slideItemCount == itemCount) return;

    _pageController?.dispose();
    _slideItemCount = itemCount;
    _currentPage = 1;
    _pageController = PageController(initialPage: 1);
  }

  void _configureAutoSlide(int itemCount) {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = null;
    if (itemCount <= 1 || _isAutoWrapping || _isUserDragging) return;

    _autoSlideTimer = Timer.periodic(_autoSlideInterval, (_) {
      _advanceAutoSlide(itemCount);
    });
  }

  void _ensureAutoSlideRunning(int itemCount) {
    if (itemCount <= 1 || _isAutoWrapping || _isUserDragging) return;
    if (_autoSlideTimer == null || !_autoSlideTimer!.isActive) {
      _configureAutoSlide(itemCount);
    }
  }

  void _advanceAutoSlide(int itemCount) {
    if (!mounted || itemCount <= 1 || _isAutoWrapping || _isUserDragging) {
      return;
    }
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    if (_currentPage >= itemCount) {
      _isAutoWrapping = true;
      controller.jumpToPage(0);
      _currentPage = 0;
      controller
          .animateToPage(
            1,
            duration: _slideDuration,
            curve: Curves.easeInOut,
          )
          .whenComplete(() {
            if (!mounted) return;
            _isAutoWrapping = false;
            _currentPage = 1;
            _ensureAutoSlideRunning(itemCount);
          });
      return;
    }

    controller.animateToPage(
      _currentPage + 1,
      duration: _slideDuration,
      curve: Curves.easeInOut,
    );
  }

  void _pauseAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = null;
  }

  void _recenterClonePage(int itemCount) {
    if (_isAutoWrapping) return;

    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;

    final page = controller.page?.round() ?? _currentPage;

    if (page == 0) {
      controller.jumpToPage(itemCount);
      _currentPage = itemCount;
    } else if (page == itemCount + 1) {
      controller.jumpToPage(1);
      _currentPage = 1;
    } else {
      _currentPage = page;
    }
  }

  void _onPageChanged(int index, int itemCount) {
    if (_isAutoWrapping) {
      _currentPage = index;
      return;
    }

    _currentPage = index;

    if (index != 0 && index != itemCount + 1) {
      _ensureAutoSlideRunning(itemCount);
    }
  }

  void _scheduleAutoSlideIfVisible(int itemCount) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || itemCount <= 1) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      _ensureAutoSlideRunning(itemCount);
    });
  }

  Color _parseColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return const Color(0xFF1B4332);
  }

  Widget _buildBanner(
    BuildContext context,
    PartnerCampaignModel campaign,
  ) {
    return _PartnerPerkBannerCard(
      key: ValueKey(campaign.id),
      campaign: campaign,
      brandColor: _parseColor(campaign.brandColor),
      onTap: () => context.pushNamed(
        RouteNames.partnerPerkDetail,
        pathParameters: {'campaignId': campaign.id},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final campaignsAsync = ref.watch(activePartnerCampaignsProvider);

    return campaignsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (campaigns) {
        if (campaigns.isEmpty) return const SizedBox.shrink();

        if (campaigns.length > 1) {
          _ensurePageController(campaigns.length);
          _scheduleAutoSlideIfVisible(campaigns.length);
        } else if (_slideItemCount != 1) {
          _slideItemCount = 1;
          _pauseAutoSlide();
          _pageController?.dispose();
          _pageController = null;
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: campaigns.length == 1
              ? _buildBanner(context, campaigns.first)
              : SizedBox(
                  height: PartnerPerksHomeBanner._bannerHeight,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      final itemCount = campaigns.length;

                      if (notification is ScrollUpdateNotification &&
                          notification.dragDetails != null) {
                        if (!_isUserDragging) {
                          _isUserDragging = true;
                          _pauseAutoSlide();
                        }
                      } else if (notification is ScrollEndNotification) {
                        if (_isAutoWrapping) return false;

                        _isUserDragging = false;
                        _recenterClonePage(itemCount);
                        _ensureAutoSlideRunning(itemCount);
                      }
                      return false;
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: PageView.builder(
                        controller: _pageController,
                        clipBehavior: Clip.hardEdge,
                        physics: const PageScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        itemCount: _extendedPageCount(campaigns.length),
                        onPageChanged: (index) =>
                            _onPageChanged(index, campaigns.length),
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal:
                                  PartnerPerksHomeBanner._cardGap / 2,
                            ),
                            child: _buildBanner(
                              context,
                              _campaignAt(index, campaigns),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _PartnerPerkBannerCard extends StatelessWidget {
  const _PartnerPerkBannerCard({
    super.key,
    required this.campaign,
    required this.brandColor,
    required this.onTap,
  });

  final PartnerCampaignModel campaign;
  final Color brandColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: brandColor,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              _BannerLogo(campaign: campaign),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      campaign.partnerName,
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      campaign.discountLabel,
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BannerLogo extends StatelessWidget {
  const _BannerLogo({required this.campaign});

  final PartnerCampaignModel campaign;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(5),
      child: campaign.logoUrl != null
          ? CachedNetworkImage(
              imageUrl: campaign.logoUrl!,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const Icon(
                Icons.local_offer,
                color: Colors.white,
                size: 18,
              ),
            )
          : const Icon(
              Icons.local_offer,
              color: Colors.white,
              size: 18,
            ),
    );
  }
}
