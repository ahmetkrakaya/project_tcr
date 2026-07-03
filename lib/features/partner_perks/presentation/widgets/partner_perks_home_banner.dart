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

  static const double bannerHeight = 68;
  static const double cardGap = 8;

  @override
  ConsumerState<PartnerPerksHomeBanner> createState() =>
      _PartnerPerksHomeBannerState();
}

class _PartnerPerksHomeBannerState extends ConsumerState<PartnerPerksHomeBanner>
    with WidgetsBindingObserver {
  static const Duration _autoSlideInterval = Duration(seconds: 4);
  static const Duration _slideDuration = Duration(milliseconds: 550);

  PageController? _pageController;
  Timer? _autoSlideTimer;
  int _currentPage = 1;
  int _slideItemCount = 0;
  bool _isAutoWrapping = false;
  bool _isUserDragging = false;
  bool _routeIsCurrent = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRouteVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _onRouteHidden();
    } else if (state == AppLifecycleState.resumed) {
      _syncRouteVisibility();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseAutoSlide();
    _pageController?.dispose();
    super.dispose();
  }

  void _syncRouteVisibility() {
    if (!mounted) return;

    final route = ModalRoute.of(context);
    final isCurrent = route == null || route.isCurrent;
    if (isCurrent == _routeIsCurrent) return;

    _routeIsCurrent = isCurrent;
    if (isCurrent) {
      _onRouteVisible();
    } else {
      _onRouteHidden();
    }
  }

  void _onRouteHidden() {
    _pauseAutoSlide();
    _isUserDragging = false;
    _isAutoWrapping = false;
  }

  void _onRouteVisible() {
    if (_slideItemCount <= 1) return;
    _recenterClonePage(_slideItemCount);
    _ensureAutoSlideRunning(_slideItemCount);
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
    _isAutoWrapping = false;
    _isUserDragging = false;
    _pageController = PageController(initialPage: 1);
  }

  void _disposePageController() {
    _pauseAutoSlide();
    _pageController?.dispose();
    _pageController = null;
    _slideItemCount = 0;
    _currentPage = 1;
    _isAutoWrapping = false;
    _isUserDragging = false;
  }

  void _configureAutoSlide(int itemCount) {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = null;
    if (!_routeIsCurrent ||
        itemCount <= 1 ||
        _isAutoWrapping ||
        _isUserDragging) {
      return;
    }

    _autoSlideTimer = Timer.periodic(_autoSlideInterval, (_) {
      _advanceAutoSlide(itemCount);
    });
  }

  void _ensureAutoSlideRunning(int itemCount) {
    if (!_routeIsCurrent ||
        itemCount <= 1 ||
        _isAutoWrapping ||
        _isUserDragging) {
      return;
    }
    if (_autoSlideTimer == null || !_autoSlideTimer!.isActive) {
      _configureAutoSlide(itemCount);
    }
  }

  void _advanceAutoSlide(int itemCount) {
    if (!mounted ||
        !_routeIsCurrent ||
        itemCount <= 1 ||
        _isAutoWrapping ||
        _isUserDragging) {
      return;
    }

    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;

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

  void _releaseDragState(int itemCount) {
    if (!_isUserDragging) return;

    _isUserDragging = false;
    if (_isAutoWrapping || itemCount <= 1) return;

    _recenterClonePage(itemCount);
    _ensureAutoSlideRunning(itemCount);
  }

  void _syncControllerForCampaigns(List<PartnerCampaignModel> campaigns) {
    if (!mounted) return;

    if (campaigns.length <= 1) {
      if (_pageController != null) {
        _disposePageController();
        setState(() {});
      }
      return;
    }

    final needsController =
        _pageController == null || _slideItemCount != campaigns.length;
    if (!needsController) return;

    _ensurePageController(campaigns.length);
    if (_routeIsCurrent) {
      _ensureAutoSlideRunning(campaigns.length);
    }
    setState(() {});
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

    ref.listen(activePartnerCampaignsProvider, (previous, next) {
      next.whenData(_syncControllerForCampaigns);
    });

    return campaignsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (campaigns) {
        if (campaigns.isEmpty) return const SizedBox.shrink();

        if (campaigns.length > 1 &&
            (_pageController == null || _slideItemCount != campaigns.length)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncControllerForCampaigns(campaigns);
          });
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: campaigns.length == 1
              ? _buildBanner(context, campaigns.first)
              : _pageController == null
                  ? SizedBox(
                      height: PartnerPerksHomeBanner.bannerHeight,
                      child: _buildBanner(context, campaigns.first),
                    )
                  : SizedBox(
                      height: PartnerPerksHomeBanner.bannerHeight,
                      child: Listener(
                        onPointerUp: (_) =>
                            _releaseDragState(campaigns.length),
                        onPointerCancel: (_) =>
                            _releaseDragState(campaigns.length),
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            final itemCount = campaigns.length;

                            if (notification is ScrollStartNotification &&
                                notification.dragDetails != null) {
                              if (!_isUserDragging) {
                                _isUserDragging = true;
                                _pauseAutoSlide();
                              }
                            } else if (notification is ScrollEndNotification) {
                              if (_isAutoWrapping) return false;
                              _releaseDragState(itemCount);
                            }
                            return false;
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: PageView.builder(
                              controller: _pageController,
                              clipBehavior: Clip.hardEdge,
                              physics: const PageScrollPhysics(
                                parent: ClampingScrollPhysics(),
                              ),
                              itemCount: _extendedPageCount(campaigns.length),
                              onPageChanged: (index) =>
                                  _onPageChanged(index, campaigns.length),
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal:
                                        PartnerPerksHomeBanner.cardGap / 2,
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
      child: InkWell(
        onTap: onTap,
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
