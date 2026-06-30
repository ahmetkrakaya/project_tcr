import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/map_directions_utils.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/partner_campaign_model.dart';
import '../../data/models/partner_redemption_models.dart';
import '../providers/partner_campaign_provider.dart';

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
  Timer? _tokenTimer;
  DateTime _now = DateTime.now();
  bool _qrEnabled = false;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  void _configureQrPolling(bool qrEnabled) {
    if (_qrEnabled == qrEnabled) return;
    _qrEnabled = qrEnabled;

    _entitlementTimer?.cancel();
    _tokenTimer?.cancel();

    if (!qrEnabled) return;

    _entitlementTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      ref.invalidate(partnerPerkEntitlementProvider(widget.campaignId));
    });
  }

  void _scheduleTokenRefresh(bool canRedeem) {
    _tokenTimer?.cancel();
    if (!canRedeem || !_qrEnabled) return;

    _tokenTimer = Timer.periodic(const Duration(seconds: 50), (_) {
      if (!mounted) return;
      ref.invalidate(partnerRedemptionTokenProvider(widget.campaignId));
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _entitlementTimer?.cancel();
    _tokenTimer?.cancel();
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

  @override
  Widget build(BuildContext context) {
    ref.listen(partnerCampaignByIdProvider(widget.campaignId), (prev, next) {
      next.whenData((campaign) {
        if (campaign != null) {
          _configureQrPolling(campaign.qrRedemptionEnabled);
        }
      });
    });

    final campaignAsync =
        ref.watch(partnerCampaignByIdProvider(widget.campaignId));
    final user = ref.watch(currentUserProfileProvider);
    final qrEnabled = campaignAsync.maybeWhen(
      data: (campaign) => campaign?.qrRedemptionEnabled == true,
      orElse: () => false,
    );

    if (qrEnabled) {
      ref.listen(
        partnerPerkEntitlementProvider(widget.campaignId),
        (prev, next) {
          next.whenData((e) => _scheduleTokenRefresh(e.canRedeem));
        },
      );
    }

    final entitlementAsync = qrEnabled
        ? ref.watch(partnerPerkEntitlementProvider(widget.campaignId))
        : null;
    final tokenAsync = entitlementAsync?.maybeWhen(
      data: (entitlement) => entitlement.canRedeem
          ? ref.watch(partnerRedemptionTokenProvider(widget.campaignId))
          : null,
      orElse: () => null,
    );

    return campaignAsync.when(
      loading: () => const Scaffold(body: LoadingWidget()),
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
        final timeText = DateFormat('HH:mm:ss').format(_now);
        final hasLocation = hasNavigableLocation(
          locationName: campaign.locationName,
          locationAddress: campaign.locationAddress,
          lat: campaign.locationLat,
          lng: campaign.locationLng,
        );

        final redemptionHint = campaign.qrRedemptionEnabled
            ? entitlementAsync?.maybeWhen(
                  data: (e) => e.statusMessage,
                  orElse: () => campaign.redemptionHint,
                ) ??
                campaign.redemptionHint
            : campaign.redemptionHint;

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
                    child: const Icon(
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
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                _CouponCard(
                                  campaign: campaign,
                                  brandColor: brandColor,
                                  notchColor: _darken(brandColor, 0.22),
                                  userName: user?.fullName ?? 'TCR Üyesi',
                                  avatarUrl: user?.avatarUrl,
                                  timeText: timeText,
                                ),
                                if (campaign.qrRedemptionEnabled) ...[
                                  const SizedBox(height: 20),
                                  _QrRedemptionSection(
                                    brandColor: brandColor,
                                    entitlementAsync: entitlementAsync,
                                    tokenAsync: tokenAsync,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        redemptionHint,
                        style: AppTypography.bodyMedium.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (campaign.terms != null &&
                          campaign.terms!.isNotEmpty) ...[
                        const SizedBox(height: 8),
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
                        const SizedBox(height: 16),
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

class _QrRedemptionSection extends StatelessWidget {
  const _QrRedemptionSection({
    required this.brandColor,
    required this.entitlementAsync,
    required this.tokenAsync,
  });

  final Color brandColor;
  final AsyncValue<PartnerPerkEntitlement>? entitlementAsync;
  final AsyncValue<PartnerRedemptionToken>? tokenAsync;

  @override
  Widget build(BuildContext context) {
    if (entitlementAsync == null) {
      return const SizedBox.shrink();
    }

    return entitlementAsync!.when(
      loading: () => const _QrPanel(
        child: SizedBox(
          height: 48,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (e, _) => _QrPanel(
        child: Text(
          'QR yüklenemedi',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.neutral600),
          textAlign: TextAlign.center,
        ),
      ),
      data: (entitlement) {
        if (!entitlement.canRedeem) {
          return _QrPanel(
            child: Column(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: brandColor,
                  size: 40,
                ),
                const SizedBox(height: 10),
                Text(
                  entitlement.statusMessage,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.neutral800,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (tokenAsync == null) {
          return const SizedBox.shrink();
        }

        return tokenAsync!.when(
          loading: () => const _QrPanel(
            child: SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
          error: (e, _) => _QrPanel(
            child: Text(
              'QR oluşturulamadı',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.neutral600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          data: (token) {
            final secondsLeft =
                token.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 60);

            return _QrPanel(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.neutral200),
                    ),
                    child: QrImageView(
                      data: token.redeemUrl,
                      version: QrVersions.auto,
                      size: 180,
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
                  const SizedBox(height: 12),
                  Text(
                    'Kasada okutulmasını isteyin',
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.neutral800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Kod $secondsLeft sn içinde yenilenir',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.neutral500,
                    ),
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

class _QrPanel extends StatelessWidget {
  const _QrPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({
    required this.campaign,
    required this.brandColor,
    required this.notchColor,
    required this.userName,
    required this.avatarUrl,
    required this.timeText,
  });

  final PartnerCampaignModel campaign;
  final Color brandColor;
  final Color notchColor;
  final String userName;
  final String? avatarUrl;
  final String timeText;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              children: [
                _LogoFrame(campaign: campaign, brandColor: brandColor),
                const SizedBox(height: 20),
                if (campaign.tagline != null &&
                    campaign.tagline!.isNotEmpty) ...[
                  Text(
                    campaign.tagline!.toUpperCase(),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.neutral500,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  campaign.partnerName,
                  style: AppTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.neutral900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Text(
                  '%${campaign.discountPercent}',
                  style: AppTypography.displaySmall.copyWith(
                    color: brandColor,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  campaign.discountLabel,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.neutral700,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          _TicketDivider(notchColor: notchColor),
          Container(
            width: double.infinity,
            color: const Color(0xFFF7F8FA),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              children: [
                Row(
                  children: [
                    UserAvatar(
                      imageUrl: avatarUrl,
                      name: userName,
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TCR Üyesi',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.neutral500,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            userName,
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF22C55E),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Geçerli · $timeText',
                        style: AppTypography.labelMedium.copyWith(
                          color: const Color(0xFF15803D),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoFrame extends StatelessWidget {
  const _LogoFrame({
    required this.campaign,
    required this.brandColor,
  });

  final PartnerCampaignModel campaign;
  final Color brandColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        color: brandColor.withValues(alpha: 0.08),
        shape: BoxShape.circle,
        border: Border.all(color: brandColor.withValues(alpha: 0.18), width: 2),
      ),
      padding: const EdgeInsets.all(18),
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
              painter: _DashedLinePainter(color: AppColors.neutral300),
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
                child: const Icon(
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
