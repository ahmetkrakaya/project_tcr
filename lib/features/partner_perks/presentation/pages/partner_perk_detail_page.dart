import 'dart:async';
import 'dart:math' show pi;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/map_directions_utils.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/partner_campaign_model.dart';
import '../../data/models/partner_redemption_models.dart';
import '../providers/partner_campaign_provider.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// Beyaz kupon kartı sabit açık zemin — metin renkleri uygulama temasından bağımsız.
abstract final class _CouponCardPalette {
  static const onSurface = AppColors.neutral900;
  static const onSurfaceVariant = AppColors.neutral600;
  static const outline = AppColors.neutral400;
  static const outlineVariant = AppColors.neutral300;
  static const sectionBackground = Color(0xFFF7F8FA);
}

class PartnerPerkDetailPage extends ConsumerStatefulWidget {
  const PartnerPerkDetailPage({super.key, required this.campaignId});

  final String campaignId;

  @override
  ConsumerState<PartnerPerkDetailPage> createState() =>
      _PartnerPerkDetailPageState();
}

class _PartnerPerkDetailPageState extends ConsumerState<PartnerPerkDetailPage> {
  Timer? _clockTimer;
  Timer? _entitlementTimer;
  Timer? _tokenExpiryTimer;
  DateTime _now = DateTime.now();
  DateTime? _activeTokenExpiresAt;
  bool _qrEnabled = false;
  PartnerPerkEntitlement? _cachedEntitlement;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() => _now = now);
      _refreshTokenIfExpired(now);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final campaign =
          ref.read(partnerCampaignByIdProvider(widget.campaignId)).valueOrNull;
      _ensureQrPollingConfigured(campaign);

      if (campaign?.qrRedemptionEnabled == true) {
        _syncEntitlementFromProvider(
          ref.read(partnerPerkEntitlementProvider(widget.campaignId)),
        );
      }
    });
  }

  void _configureQrPolling(bool qrEnabled) {
    if (_qrEnabled == qrEnabled) return;
    _qrEnabled = qrEnabled;

    _entitlementTimer?.cancel();
    _tokenExpiryTimer?.cancel();
    _activeTokenExpiresAt = null;

    if (!qrEnabled) return;

    _entitlementTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      ref.invalidate(partnerPerkEntitlementProvider(widget.campaignId));
    });
  }

  void _scheduleTokenExpiryRefresh(PartnerRedemptionToken token) {
    if (_activeTokenExpiresAt == token.expiresAt && _tokenExpiryTimer != null) {
      return;
    }
    _scheduleTokenExpiryRefreshAt(token.expiresAt);
  }

  void _scheduleTokenExpiryRefreshAt(DateTime expiresAt) {
    _tokenExpiryTimer?.cancel();
    _activeTokenExpiresAt = expiresAt;

    final remaining = expiresAt.difference(DateTime.now());
    if (!remaining.isNegative && remaining.inMilliseconds > 0) {
      _tokenExpiryTimer = Timer(remaining, () {
        if (!mounted) return;
        _requestNewToken();
      });
    } else {
      _requestNewToken();
    }
  }

  void _refreshTokenIfExpired(DateTime now) {
    final expiresAt = _activeTokenExpiresAt;
    if (expiresAt == null || now.isBefore(expiresAt)) return;
    _requestNewToken();
  }

  void _requestNewToken() {
    _tokenExpiryTimer?.cancel();
    _activeTokenExpiresAt = null;
    ref.invalidate(partnerRedemptionTokenProvider(widget.campaignId));
  }

  void _syncTokenExpirySchedule(AsyncValue<PartnerRedemptionToken>? async) {
    async?.whenData((token) {
      if (_activeTokenExpiresAt == token.expiresAt) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scheduleTokenExpiryRefresh(token);
      });
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _entitlementTimer?.cancel();
    _tokenExpiryTimer?.cancel();
    super.dispose();
  }

  Color _parseColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return const Color(0xFF1B4332);
  }

  Color _darken(Color color, [double amount = 0.18]) {
    return Color.lerp(color, Colors.black, amount) ?? color;
  }

  void _openDirections(PartnerCampaignModel campaign) {
    openMapsForDirections(
      lat: campaign.locationLat,
      lng: campaign.locationLng,
      locationName: campaign.locationName,
      locationAddress: campaign.locationAddress,
    );
  }

  Future<void> _openWebsite(PartnerCampaignModel campaign) async {
    final raw = campaign.websiteUrl?.trim();
    if (raw == null || raw.isEmpty) return;

    final normalized = raw.startsWith('http://') || raw.startsWith('https://')
        ? raw
        : 'https://$raw';
    final uri = Uri.tryParse(normalized);
    if (uri == null) return;

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Web sitesi açılamadı')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Web sitesi açılamadı')),
        );
      }
    }
  }

  String? _websiteDisplayLabel(PartnerCampaignModel campaign) {
    final raw = campaign.websiteUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/$'), '');
  }

  String? _footerMessage(
    PartnerCampaignModel campaign,
    PartnerPerkEntitlement? entitlement,
  ) {
    if (campaign.qrRedemptionEnabled) {
      if (entitlement == null) return null;
      if (!entitlement.canRedeem) {
        if (entitlement.showRedemptionSuccess) return null;
        return entitlement.memberDisplayMessage;
      }
    }

    final hint = campaign.redemptionHint.trim();
    return hint.isEmpty ? null : hint;
  }

  void _onQrSideOpened() {
    ref.invalidate(partnerPerkEntitlementProvider(widget.campaignId));
  }

  void _syncEntitlementFromProvider(AsyncValue<PartnerPerkEntitlement>? async) {
    final current = async?.valueOrNull;
    if (current == null) return;

    if (_cachedEntitlement != current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _cachedEntitlement == current) return;
        setState(() => _cachedEntitlement = current);
      });
    }

    if (!current.canRedeem) {
      _tokenExpiryTimer?.cancel();
      _activeTokenExpiresAt = null;
    }
  }

  void _ensureQrPollingConfigured(PartnerCampaignModel? campaign) {
    if (campaign == null) return;
    if (_qrEnabled == campaign.qrRedemptionEnabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _configureQrPolling(campaign.qrRedemptionEnabled);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(partnerCampaignByIdProvider(widget.campaignId), (prev, next) {
      next.whenData((campaign) => _ensureQrPollingConfigured(campaign));
    });

    final campaignAsync =
        ref.watch(partnerCampaignByIdProvider(widget.campaignId));
    final user = ref.watch(currentUserProfileProvider);
    final qrEnabled = campaignAsync.maybeWhen(
      data: (campaign) => campaign?.qrRedemptionEnabled == true,
      orElse: () => false,
    );

    final entitlementAsync = qrEnabled
        ? ref.watch(partnerPerkEntitlementProvider(widget.campaignId))
        : null;

    _syncEntitlementFromProvider(entitlementAsync);

    final entitlement =
        entitlementAsync?.valueOrNull ?? _cachedEntitlement;
    final entitlementInitialLoading =
        entitlementAsync?.isLoading == true && entitlement == null;

    if (qrEnabled) {
      ref.listen(
        partnerPerkEntitlementProvider(widget.campaignId),
        (prev, next) {
          next.whenData((e) {
            final wasRedeemable = prev?.valueOrNull?.canRedeem ?? false;
            if (_cachedEntitlement != e) {
              setState(() => _cachedEntitlement = e);
            }
            if (!e.canRedeem) {
              _tokenExpiryTimer?.cancel();
              _activeTokenExpiresAt = null;
              if (wasRedeemable && e.showRedemptionSuccess) {
                HapticFeedback.mediumImpact();
              }
            }
          });
        },
      );

      ref.listen(
        partnerRedemptionTokenProvider(widget.campaignId),
        (prev, next) {
          next.whenData(_scheduleTokenExpiryRefresh);
        },
      );
    }

    final tokenAsync = qrEnabled && (entitlement?.canRedeem ?? false)
        ? ref.watch(partnerRedemptionTokenProvider(widget.campaignId))
        : null;

    if (qrEnabled) {
      _syncTokenExpirySchedule(tokenAsync);
    }

    return campaignAsync.when(
      loading: () => const _PartnerPerkDetailLoadingScaffold(),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Kampanya yüklenemedi: $e')),
      ),
      data: (campaign) {
        if (campaign == null || !campaign.isCurrentlyActive(at: _now)) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Text('Bu kampanya artık geçerli değil.'),
            ),
          );
        }

        final brandColor = _parseColor(campaign.brandColor);
        final footerMessage = _footerMessage(campaign, entitlement);
        final hasLocation = hasNavigableLocation(
          locationName: campaign.locationName,
          locationAddress: campaign.locationAddress,
          lat: campaign.locationLat,
          lng: campaign.locationLng,
        );
        final hasWebsite =
            campaign.websiteUrl != null && campaign.websiteUrl!.trim().isNotEmpty;
        final websiteLabel = _websiteDisplayLabel(campaign);

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            extendBodyBehindAppBar: true,
            backgroundColor: brandColor,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              title: const SizedBox.shrink(),
              leading: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    brandColor,
                    _darken(brandColor, 0.22),
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: _FlipCouponCard(
                                  campaign: campaign,
                                  brandColor: brandColor,
                                  notchColor: _darken(brandColor, 0.22),
                                  userName: user?.fullName ?? 'TCR Üyesi',
                                  avatarUrl: user?.avatarUrl,
                                  now: _now,
                                  qrEnabled: campaign.qrRedemptionEnabled,
                                  cachedEntitlement: entitlement,
                                  entitlementInitialLoading:
                                      entitlementInitialLoading,
                                  tokenAsync: tokenAsync,
                                  onQrSideOpened: _onQrSideOpened,
                                ),
                        ),
                      ),
                      if (footerMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          footerMessage,
                          style: AppTypography.bodyMedium.copyWith(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (campaign.terms != null &&
                          campaign.terms!.isNotEmpty) ...[
                        SizedBox(height: footerMessage != null ? 8 : 16),
                        Text(
                          campaign.terms!,
                          style: AppTypography.bodySmall.copyWith(
                            color: Colors.white.withValues(alpha: 0.65),
                            height: 1.35,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (hasLocation) ...[
                        const SizedBox(height: 12),
                        _LocationButton(
                          locationName: campaign.locationName ??
                              campaign.locationAddress ??
                              'Konum',
                          locationAddress: campaign.locationName != null
                              ? campaign.locationAddress
                              : null,
                          onTap: () => _openDirections(campaign),
                        ),
                      ],
                      if (hasWebsite && websiteLabel != null) ...[
                        const SizedBox(height: 12),
                        _WebsiteButton(
                          label: websiteLabel,
                          onTap: () => _openWebsite(campaign),
                        ),
                      ],
                    ],
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

class _FlipCouponCard extends StatefulWidget {
  const _FlipCouponCard({
    required this.campaign,
    required this.brandColor,
    required this.notchColor,
    required this.userName,
    required this.avatarUrl,
    required this.now,
    required this.qrEnabled,
    required this.cachedEntitlement,
    required this.entitlementInitialLoading,
    required this.tokenAsync,
    this.onQrSideOpened,
  });

  final PartnerCampaignModel campaign;
  final Color brandColor;
  final Color notchColor;
  final String userName;
  final String? avatarUrl;
  final DateTime now;
  final bool qrEnabled;
  final PartnerPerkEntitlement? cachedEntitlement;
  final bool entitlementInitialLoading;
  final AsyncValue<PartnerRedemptionToken>? tokenAsync;
  final VoidCallback? onQrSideOpened;

  @override
  State<_FlipCouponCard> createState() => _FlipCouponCardState();
}

class _FlipCouponCardState extends State<_FlipCouponCard>
    with TickerProviderStateMixin {
  static const double _cardHeightDefault = 400;
  static const double _cardHeightWithPromo = 460;

  static const int _hintCycles = 4;

  double get _cardHeight {
    final hasPromo = widget.campaign.promoCode != null &&
        widget.campaign.promoCode!.trim().isNotEmpty;
    return hasPromo ? _cardHeightWithPromo : _cardHeightDefault;
  }

  late final AnimationController _flipController;
  late final Animation<double> _flipAnimation;
  late final AnimationController _gestureHintController;
  bool _hintScheduled = false;
  bool _showGestureHint = false;
  bool _userInteracted = false;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _flipAnimation = CurvedAnimation(
      parent: _flipController,
      curve: Curves.easeInOutCubic,
    );
    _gestureHintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _flipController.addStatusListener(_onFlipStatusChanged);
    _scheduleSwipeHintIfNeeded();
  }

  void _onFlipStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_flipController.value >= 0.5) {
      widget.onQrSideOpened?.call();
    }
  }

  @override
  void dispose() {
    _flipController.removeStatusListener(_onFlipStatusChanged);
    _gestureHintController.removeStatusListener(_onGestureHintStatus);
    _flipController.dispose();
    _gestureHintController.dispose();
    super.dispose();
  }

  bool get _canSwipe =>
      widget.qrEnabled &&
      !widget.entitlementInitialLoading &&
      (widget.cachedEntitlement?.canRedeem ?? false);

  void _startGestureHint() {
    if (!mounted || _userInteracted) return;
    setState(() => _showGestureHint = true);
    _gestureHintController
      ..removeStatusListener(_onGestureHintStatus)
      ..addStatusListener(_onGestureHintStatus)
      ..repeat(count: _hintCycles, reverse: true);
  }

  void _onGestureHintStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      _stopGestureHint();
    }
  }

  void _stopGestureHint() {
    if (!_showGestureHint) return;
    _gestureHintController.removeStatusListener(_onGestureHintStatus);
    _gestureHintController.stop();
    _gestureHintController.reset();
    if (mounted) setState(() => _showGestureHint = false);
  }

  void _scheduleSwipeHintIfNeeded() {
    if (!_canSwipe || _hintScheduled || _userInteracted) return;
    _hintScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_canSwipe || _userInteracted) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted || !_canSwipe || _userInteracted) return;

      _startGestureHint();

      for (var i = 0; i < _hintCycles; i++) {
        if (!mounted || _userInteracted) break;
        await _flipController.animateTo(
          0.12,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
        if (!mounted || _userInteracted) break;
        await _flipController.animateTo(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInCubic,
        );
        if (i < _hintCycles - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 180));
        }
      }
    });
  }

  void _onUserInteraction() {
    if (_userInteracted) return;
    _userInteracted = true;
    _stopGestureHint();
  }

  @override
  void didUpdateWidget(_FlipCouponCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasRedeemable = oldWidget.cachedEntitlement?.canRedeem ?? false;
    final isRedeemable = widget.cachedEntitlement?.canRedeem ?? false;
    if (wasRedeemable && !isRedeemable && _flipController.value > 0) {
      _flipController.reverse();
    }
    final becameSwipeable = _canSwipe &&
        (!oldWidget.qrEnabled ||
            oldWidget.entitlementInitialLoading ||
            !(oldWidget.cachedEntitlement?.canRedeem ?? false));
    if (becameSwipeable) {
      _hintScheduled = false;
      _scheduleSwipeHintIfNeeded();
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_canSwipe) return;
    _onUserInteraction();
    final width = context.size?.width ?? 360;
    final delta = (-details.delta.dx / width) * 1.6;
    _flipController.value = (_flipController.value + delta).clamp(0.0, 1.0);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_canSwipe) return;
    final velocity = -(details.primaryVelocity ?? 0);
    if (_flipController.value >= 0.42 || velocity > 420) {
      _flipController.forward();
      HapticFeedback.lightImpact();
    } else {
      _flipController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: AnimatedBuilder(
        animation: _flipAnimation,
        builder: (context, _) {
          final angle = _flipAnimation.value * pi;
          final showBack = angle >= pi / 2;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: showBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(pi),
                    child: _CouponCardShell(
                      height: _cardHeight,
                      child: _CouponCardBack(
                        campaign: widget.campaign,
                        brandColor: widget.brandColor,
                        notchColor: widget.notchColor,
                        now: widget.now,
                        tokenAsync: widget.tokenAsync,
                      ),
                    ),
                  )
                : _CouponCardShell(
                    height: _cardHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _CouponCardFront(
                          campaign: widget.campaign,
                          brandColor: widget.brandColor,
                          notchColor: widget.notchColor,
                          userName: widget.userName,
                          avatarUrl: widget.avatarUrl,
                          entitlement: widget.cachedEntitlement,
                        ),
                        if (_showGestureHint)
                          _SwipeGestureHintOverlay(
                            animation: _gestureHintController,
                          ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _SwipeGestureHintOverlay extends StatelessWidget {
  const _SwipeGestureHintOverlay({
    required this.animation,
  });

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(animation.value);
          final breathe = 0.32 + 0.16 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
          // 0→1 sola, 1→0 sağa (reverse ile bir sola bir sağa)
          final rotation = (t - 0.5) * 0.34;

          return Align(
            alignment: const Alignment(0.72, 0),
            child: Opacity(
              opacity: breathe,
              child: Transform.rotate(
                angle: rotation,
                child: Icon(
                  Icons.swipe,
                  size: 100,
                  color: _CouponCardPalette.outline,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CouponCardShell extends StatelessWidget {
  const _CouponCardShell({
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

class _CouponCardFront extends StatelessWidget {
  const _CouponCardFront({
    required this.campaign,
    required this.brandColor,
    required this.notchColor,
    required this.userName,
    required this.avatarUrl,
    required this.entitlement,
  });

  final PartnerCampaignModel campaign;
  final Color brandColor;
  final Color notchColor;
  final String userName;
  final String? avatarUrl;
  final PartnerPerkEntitlement? entitlement;

  @override
  Widget build(BuildContext context) {
    final showSuccess = entitlement?.showRedemptionSuccess ?? false;
    final hasPromoCode =
        campaign.promoCode != null && campaign.promoCode!.trim().isNotEmpty;
    final logoSize = showSuccess ? 72.0 : 96.0;
    final topPadding = showSuccess ? 16.0 : 22.0;

    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, topPadding, 24, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LogoFrame(
                  campaign: campaign,
                  brandColor: brandColor,
                  size: logoSize,
                ),
                SizedBox(height: showSuccess ? 8 : 12),
                if (campaign.tagline != null && campaign.tagline!.isNotEmpty) ...[
                  Text(
                    campaign.tagline!.toUpperCase(),
                    style: AppTypography.labelSmall.copyWith(
                      color: _CouponCardPalette.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: showSuccess ? 2 : 4),
                ],
                Text(
                  campaign.partnerName,
                  style: (showSuccess
                          ? AppTypography.titleMedium
                          : AppTypography.titleLarge)
                      .copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.neutral900,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: showSuccess ? 8 : 12),
                Text(
                  '%${campaign.discountPercent}',
                  style: (showSuccess
                          ? AppTypography.displayMedium
                          : AppTypography.displaySmall)
                      .copyWith(
                    color: brandColor,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                SizedBox(height: showSuccess ? 2 : 4),
                Text(
                  campaign.discountLabel,
                  style: AppTypography.titleMedium.copyWith(
                    color: _CouponCardPalette.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: showSuccess ? 15 : null,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        _TicketDivider(notchColor: notchColor),
        if (showSuccess)
          Container(
            width: double.infinity,
            color: _CouponCardPalette.sectionBackground,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFECFDF3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    color: Color(0xFF15803D),
                    size: 26,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  entitlement!.memberDisplayMessage,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.neutral900,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          )
        else
          Container(
            width: double.infinity,
            color: _CouponCardPalette.sectionBackground,
            padding: EdgeInsets.fromLTRB(
              20,
              showSuccess ? 14 : (hasPromoCode ? 16 : 0),
              20,
              hasPromoCode ? 16 : 0,
            ),
            child: hasPromoCode
                ? _PromoCodeSection(
                    code: campaign.promoCode!.trim(),
                    brandColor: brandColor,
                  )
                : SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        UserAvatar(
                          imageUrl: avatarUrl,
                          name: userName,
                          size: 36,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TCR Üyesi',
                                style: AppTypography.labelSmall.copyWith(
                                  color: _CouponCardPalette.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                userName,
                                style: AppTypography.labelLarge.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: _CouponCardPalette.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
      ],
    );
  }
}

class _CouponCardBack extends StatelessWidget {
  const _CouponCardBack({
    required this.campaign,
    required this.brandColor,
    required this.notchColor,
    required this.now,
    required this.tokenAsync,
  });

  final PartnerCampaignModel campaign;
  final Color brandColor;
  final Color notchColor;
  final DateTime now;
  final AsyncValue<PartnerRedemptionToken>? tokenAsync;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                Text(
                  campaign.partnerName,
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.neutral900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Kasada okutulmasını isteyin',
                  style: AppTypography.bodySmall.copyWith(
                    color: _CouponCardPalette.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Center(
                    child: _QrBackContent(
                      brandColor: brandColor,
                      now: now,
                      tokenAsync: tokenAsync,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QrBackContent extends StatelessWidget {
  const _QrBackContent({
    required this.brandColor,
    required this.now,
    required this.tokenAsync,
  });

  final Color brandColor;
  final DateTime now;
  final AsyncValue<PartnerRedemptionToken>? tokenAsync;

  @override
  Widget build(BuildContext context) {
    if (tokenAsync == null) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return tokenAsync!.when(
      loading: () => const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: _CouponCardPalette.outline, size: 36),
          const SizedBox(height: 10),
          Text(
            'QR oluşturulamadı',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
              color: _CouponCardPalette.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: AppTypography.bodySmall.copyWith(
              color: _CouponCardPalette.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      data: (token) {
        final secondsLeft =
            token.expiresAt.difference(now).inSeconds.clamp(0, 60);

        if (secondsLeft <= 0) {
          return const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.neutral200),
                boxShadow: [
                  BoxShadow(
                    color: brandColor.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: QrImageView(
                data: token.redeemUrl,
                version: QrVersions.auto,
                size: 168,
                backgroundColor: Colors.white,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: brandColor,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.neutral900,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Kod $secondsLeft sn içinde yenilenir',
              style: AppTypography.labelMedium.copyWith(
                color: _CouponCardPalette.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LogoFrame extends StatelessWidget {
  const _LogoFrame({
    required this.campaign,
    required this.brandColor,
    this.size = 112,
  });

  final PartnerCampaignModel campaign;
  final Color brandColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: brandColor.withValues(alpha: 0.08),
        shape: BoxShape.circle,
        border: Border.all(color: brandColor.withValues(alpha: 0.18), width: 2),
      ),
      padding: EdgeInsets.all(size * 0.16),
      child: campaign.logoUrl != null
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: campaign.logoUrl!,
                fit: BoxFit.contain,
                placeholder: (_, __) => Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: brandColor,
                  ),
                ),
                errorWidget: (_, __, ___) => Icon(
                  Icons.local_offer_outlined,
                  color: brandColor,
                  size: 36,
                ),
              ),
            )
          : Icon(
              Icons.local_offer_outlined,
              color: brandColor,
              size: 36,
            ),
    );
  }
}

class _TicketDivider extends StatelessWidget {
  const _TicketDivider({required this.notchColor});

  final Color notchColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _DashedLinePainter(color: _CouponCardPalette.outlineVariant),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TicketNotch(color: notchColor, side: _NotchSide.left),
              _TicketNotch(color: notchColor, side: _NotchSide.right),
            ],
          ),
        ],
      ),
    );
  }
}

enum _NotchSide { left, right }

class _TicketNotch extends StatelessWidget {
  const _TicketNotch({required this.color, required this.side});

  final Color color;
  final _NotchSide side;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(side == _NotchSide.left ? -14 : 14, 0),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;

    const dashWidth = 6.0;
    const dashSpace = 5.0;
    var startX = 24.0;
    final y = size.height / 2;

    while (startX < size.width - 24) {
      canvas.drawLine(Offset(startX, y), Offset(startX + dashWidth, y), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WebsiteButton extends StatelessWidget {
  const _WebsiteButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.language_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Web sitesine git',
                      style: AppTypography.titleSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                color: Colors.white.withValues(alpha: 0.9),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromoCodeSection extends StatelessWidget {
  const _PromoCodeSection({
    required this.code,
    required this.brandColor,
  });

  final String code;
  final Color brandColor;

  Future<void> _copyCode(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.lightImpact();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$code" kopyalandı'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'İNDİRİM KODU',
          style: AppTypography.labelSmall.copyWith(
            color: _CouponCardPalette.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: brandColor.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: brandColor.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            code,
            style: AppTypography.headlineSmall.copyWith(
              fontWeight: FontWeight.w800,
              color: brandColor,
              letterSpacing: 2,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _copyCode(context),
            icon: Icon(Icons.copy_rounded, size: 18),
            label: const Text('Kodu kopyala'),
            style: OutlinedButton.styleFrom(
              foregroundColor: brandColor,
              side: BorderSide(color: brandColor.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationButton extends StatelessWidget {
  const _LocationButton({
    required this.locationName,
    required this.onTap,
    this.locationAddress,
  });

  final String locationName;
  final String? locationAddress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      locationName,
                      style: AppTypography.titleSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (locationAddress != null &&
                        locationAddress!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        locationAddress!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.navigation_rounded,
                color: Colors.white.withValues(alpha: 0.9),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartnerPerkDetailLoadingScaffold extends StatelessWidget {
  const _PartnerPerkDetailLoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: ThemeBrightnessHolder.scaffoldBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          leading: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ThemeBrightnessHolder.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: ThemeBrightnessHolder.onSurface,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                ThemeBrightnessHolder.scaffoldBackground,
                ThemeBrightnessHolder.surfaceContainerHighest,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: _CouponCardLoadingSkeleton(
                        notchColor: ThemeBrightnessHolder.scaffoldBackground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CouponCardLoadingSkeleton extends StatelessWidget {
  const _CouponCardLoadingSkeleton({required this.notchColor});

  static const double _cardHeight = 400;

  final Color notchColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: _cardHeight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Shimmer.fromColors(
                baseColor: AppColors.neutral300,
                highlightColor: AppColors.neutral100,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
                  child: Column(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 12,
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 28,
                        width: 160,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 48,
                        width: 88,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 18,
                        width: 200,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _TicketDivider(notchColor: notchColor),
            Container(
              width: double.infinity,
              height: 64,
              color: const Color(0xFFF7F8FA),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Shimmer.fromColors(
                baseColor: AppColors.neutral300,
                highlightColor: AppColors.neutral100,
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 10,
                            width: 56,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 14,
                            width: 120,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
