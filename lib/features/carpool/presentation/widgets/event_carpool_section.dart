import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../events/domain/entities/event_entity.dart';
import '../../../events/presentation/providers/event_provider.dart';
import '../../domain/entities/carpool_entity.dart';
import '../providers/carpool_provider.dart';
import 'create_carpool_offer_sheet.dart';
import 'carpool_request_sheet.dart';

/// Ortak yolculuk aksiyon butonu — dolu, outline yok, aynı köşe kıvrımı
Widget carpoolFilledActionButton({
  required VoidCallback? onPressed,
  required IconData icon,
  required String label,
  required Color backgroundColor,
  Color foregroundColor = Colors.white,
}) {
  return FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: FilledButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      disabledBackgroundColor: backgroundColor.withValues(alpha: 0.38),
      disabledForegroundColor: foregroundColor.withValues(alpha: 0.72),
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Etkinlik için carpool bölümü
class EventCarpoolSection extends ConsumerStatefulWidget {
  final String eventId;

  const EventCarpoolSection({
    super.key,
    required this.eventId,
  });

  @override
  ConsumerState<EventCarpoolSection> createState() =>
      EventCarpoolSectionState();
}

/// Dışarıdan (alt bar, katılım sonrası) ortak yolculuk açmak için
typedef EventCarpoolSectionState = _EventCarpoolSectionState;

class _EventCarpoolSectionState extends ConsumerState<EventCarpoolSection> {
  String get eventId => widget.eventId;

  /// İlan listesi sheet'ini aç
  Future<void> openOffersSheet() async {
    final offers =
        await ref.read(eventCarpoolOffersProvider(eventId).future);
    if (!mounted) return;
    final currentUser = ref.read(currentUserProfileProvider);
    final participants =
        await ref.read(eventParticipantsProvider(eventId).future);
    final event = await ref.read(eventByIdProvider(eventId).future);

    final isParticipating = currentUser != null &&
        participants.any(
          (p) => p.userId == currentUser.id && p.status == RsvpStatus.going,
        );
    final eventEndTime = event.startTime.add(const Duration(hours: 2));
    final isEventFinished = DateTime.now().isAfter(eventEndTime);
    final currentUserId = currentUser?.id;
    final hasAcceptedRequest = offers.any(
      (offer) => offer.requests.any(
        (req) =>
            req.passengerId == currentUserId && req.isAccepted,
      ),
    );
    final hasActiveOffer = offers.any(
      (offer) => offer.driverId == currentUserId && offer.isActive,
    );

    if (!mounted) return;
    _showCarpoolListSheet(
      context,
      ref,
      offers,
      currentUserId,
      isParticipating: isParticipating,
      isEventFinished: isEventFinished,
      hasAcceptedRequest: hasAcceptedRequest,
      hasActiveOffer: hasActiveOffer,
    );
  }

  void openCreateOfferSheet() {
    CreateCarpoolOfferSheet.show(context, eventId);
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final eventAsync = ref.watch(eventByIdProvider(eventId));
    
    // Geçmiş etkinliklerde veya katılım aksiyonuna izin verilmeyen etkinliklerde hiçbir şey gösterme
    final isPastEvent = eventAsync.maybeWhen(
      data: (event) => event.isPast,
      orElse: () => false,
    );
    final isParticipationAllowed = eventAsync.maybeWhen(
      data: (event) => event.canUserParticipate,
      orElse: () => true,
    );
    
    if (isPastEvent || !isParticipationAllowed) {
      return const SizedBox.shrink();
    }
    
    final offersAsync = ref.watch(eventCarpoolOffersProvider(eventId));
    final participantsAsync = ref.watch(eventParticipantsProvider(eventId));
    final currentUser = ref.watch(currentUserProfileProvider);
    final currentUserId = currentUser?.id;
    
    // Helper: Kullanıcı etkinliğe katılıyor mu?
    final isParticipating = participantsAsync.maybeWhen(
      data: (participants) {
        if (currentUserId == null) return false;
        return participants.any(
          (p) => p.userId == currentUserId && p.status == RsvpStatus.going,
        );
      },
      orElse: () => false,
    );
    
    // Helper: Etkinlik bitti mi? (başlangıç + 2 saat geçmişse)
    final isEventFinished = eventAsync.maybeWhen(
      data: (event) {
        final eventEndTime = event.startTime.add(const Duration(hours: 2));
        return DateTime.now().isAfter(eventEndTime);
      },
      orElse: () => false,
    );
    
    // Helper: Kullanıcı bir araca onaylanmış mı?
    final hasAcceptedRequest = offersAsync.maybeWhen(
      data: (offers) {
        if (currentUserId == null) return false;
        return offers.any(
          (offer) => offer.requests.any(
            (req) => req.passengerId == currentUserId && req.isAccepted,
          ),
        );
      },
      orElse: () => false,
    );
    
    // Helper: Kullanıcının aktif bir ilanı var mı?
    final hasActiveOffer = offersAsync.maybeWhen(
      data: (offers) {
        if (currentUserId == null) return false;
        return offers.any(
          (offer) => offer.driverId == currentUserId && offer.isActive,
        );
      },
      orElse: () => false,
    );

    final canCreateOffer = !isEventFinished &&
        isParticipating &&
        !hasAcceptedRequest &&
        !hasActiveOffer;

    return offersAsync.when(
      data: (offers) => _buildProminentCard(
        context,
        ref,
        offers: offers,
        isParticipating: isParticipating,
        isEventFinished: isEventFinished,
        hasAcceptedRequest: hasAcceptedRequest,
        hasActiveOffer: hasActiveOffer,
        canCreateOffer: canCreateOffer,
      ),
      loading: () => _buildProminentCardSkeleton(),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Ortak yolculuk bilgileri yüklenemedi',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProminentCardSkeleton() {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: AppColors.neutral100,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildProminentCard(
    BuildContext context,
    WidgetRef ref, {
    required List<CarpoolOfferEntity> offers,
    required bool isParticipating,
    required bool isEventFinished,
    required bool hasAcceptedRequest,
    required bool hasActiveOffer,
    required bool canCreateOffer,
  }) {
    final offerCount = offers.length;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.1),
            AppColors.tertiary.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.directions_car,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ortak Yolculuk',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Arabanı paylaş veya etkinliğe giden yol arkadaşlarını bul',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.neutral600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (offerCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$offerCount ilan',
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (!isParticipating)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Katıldıktan sonra yolculuk ilanı verebilir veya mevcut ilanlara başvurabilirsin.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
            )
          else if (hasActiveOffer)
            _buildStatusBanner(
              'Aktif araç ilanın var. İlanını listeden yönetebilirsin.',
              Icons.check_circle,
              AppColors.success,
            )
          else if (hasAcceptedRequest)
            _buildStatusBanner(
              'Onaylanmış bir yolculuğun var.',
              Icons.check_circle,
              AppColors.success,
            )
          else
            Row(
              children: [
                Expanded(
                  child: carpoolFilledActionButton(
                    onPressed: isParticipating ? openOffersSheet : null,
                    icon: Icons.search,
                    label: offerCount > 0
                        ? '$offerCount İlan Gör'
                        : 'İlanlara Bak',
                    backgroundColor: AppColors.tertiary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: carpoolFilledActionButton(
                    onPressed: canCreateOffer ? openCreateOfferSheet : null,
                    icon: Icons.add_road,
                    label: 'İlan Ver',
                    backgroundColor: AppColors.primary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(String text, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(color: AppColors.neutral700),
            ),
          ),
          TextButton(
            onPressed: openOffersSheet,
            child: const Text('Görüntüle'),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferCard(
    BuildContext context,
    WidgetRef ref,
    CarpoolOfferEntity offer,
    String? currentUserId, {
    required bool isParticipating,
    required bool isEventFinished,
    required bool hasAcceptedRequest,
    required bool hasActiveOffer,
  }) {
    final isDriver = offer.driverId == currentUserId;
    final hasRequest = offer.requests.any(
      (r) => r.passengerId == currentUserId && r.isPending,
    );
    final isAccepted = offer.requests.any(
      (r) => r.passengerId == currentUserId && r.isAccepted,
    );
    
    // İlan açan kişi diğer araçlara istek atamaz
    final canRequest = !isDriver && 
        !isEventFinished && 
        isParticipating && 
        !hasAcceptedRequest && 
        !hasActiveOffer;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header - Sürücü bilgisi
            Row(
              children: [
                UserAvatar(
                  size: 44,
                  name: offer.driverName,
                  imageUrl: offer.driverAvatarUrl,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            offer.driverName,
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isDriver) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Sen',
                                style: AppTypography.labelSmall.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        offer.carInfo,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Koltuk durumu - 0/3 formatında göster
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: offer.isFull
                        ? AppColors.errorContainer
                        : AppColors.neutral100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${offer.occupiedSeats}/${offer.totalSeats}',
                    style: AppTypography.labelMedium.copyWith(
                      color: offer.isFull
                          ? AppColors.error
                          : AppColors.neutral700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Bilgiler - Güzergah
            if (offer.waypoints.isNotEmpty) ...[
              _buildInfoRow(
                icon: Icons.route,
                label: 'Güzergah',
                value: offer.waypoints
                    .map((w) => w.locationName)
                    .join(' → '),
              ),
            ] else ...[
              _buildInfoRow(
                icon: Icons.location_on_outlined,
                label: 'Kalkış',
                value: offer.pickupLocationDisplay,
              ),
            ],
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.calendar_today,
              label: 'Kalkış Tarihi',
              value: DateFormat('d MMMM yyyy', 'tr_TR').format(offer.departureTime),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.access_time,
              label: 'Kalkış Saati',
              value: DateFormat('HH:mm').format(offer.departureTime),
            ),
            if (offer.notes != null && offer.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildInfoRow(
                icon: Icons.note_outlined,
                label: 'Not',
                value: offer.notes!,
              ),
            ],

            // Sürücü: İlanı Sil butonu
            if (isDriver && !isEventFinished) ...[
              const SizedBox(height: 16),
              AppButton(
                text: 'İlanı Sil',
                variant: AppButtonVariant.outlined,
                icon: Icons.delete_outline,
                isFullWidth: true,
                onPressed: () => _showDeleteOfferDialog(
                  context,
                  ref,
                  offer,
                ),
              ),
            ],

            // Yolcu: istek gönderme / iptal / yolculuktan ayrılma
            if (!isDriver) ...[
              const SizedBox(height: 16),
              if (isAccepted) ...[
                // Onaylanmış yolcu: yolculuktan ayrıl
                AppButton(
                  text: 'Yolculuktan Ayrıl',
                  variant: AppButtonVariant.outlined,
                  icon: Icons.logout,
                  isFullWidth: true,
                  onPressed: () {
                    final req = offer.requests.firstWhere(
                      (r) => r.passengerId == currentUserId && r.isAccepted,
                    );
                    _showCancelRequestDialog(
                      context,
                      ref,
                      req,
                      offer,
                      isAccepted: true,
                    );
                  },
                ),
              ] else if (hasRequest) ...[
                // Bekleyen istek: isteği kaldır
                AppButton(
                  text: 'İsteği Kaldır',
                  variant: AppButtonVariant.outlined,
                  icon: Icons.close,
                  isFullWidth: true,
                  onPressed: () {
                    final req = offer.requests.firstWhere(
                      (r) => r.passengerId == currentUserId && r.isPending,
                    );
                    _showCancelRequestDialog(
                      context,
                      ref,
                      req,
                      offer,
                      isAccepted: false,
                    );
                  },
                ),
              ] else if (canRequest && !offer.isFull) ...[
                AppButton(
                  text: 'Katıl',
                  icon: Icons.person_add,
                  isFullWidth: true,
                  onPressed: () => _showRequestSheet(
                    context,
                    ref,
                    offer,
                  ),
                ),
              ] else if (canRequest && offer.isFull) ...[
                AppButton(
                  text: 'Dolu',
                  variant: AppButtonVariant.outlined,
                  isFullWidth: true,
                  onPressed: null,
                ),
              ],
            ],

            // Sürücü için request listesi
            if (isDriver && offer.requests.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                'İstekler (${offer.requests.where((r) => r.isPending).length})',
                style: AppTypography.labelMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ...offer.requests.where((r) => r.isPending).map((request) =>
                  _buildRequestItem(context, ref, request, offer)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.neutral500),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.neutral500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTypography.bodySmall.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestItem(
    BuildContext context,
    WidgetRef ref,
    CarpoolRequestEntity request,
    CarpoolOfferEntity offer,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.neutral100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          UserAvatar(
            size: 36,
            name: request.passengerName ?? '',
            imageUrl: request.passengerAvatarUrl,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.passengerName ?? 'Anonim',
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (request.message != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    request.message!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.neutral600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.check, color: AppColors.success),
                onPressed: () => _acceptRequest(context, ref, request, offer),
                tooltip: 'Kabul Et',
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.error),
                onPressed: () => _rejectRequest(context, ref, request, offer),
                tooltip: 'Reddet',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCarpoolListSheet(
    BuildContext context,
    WidgetRef ref,
    List<CarpoolOfferEntity> offers,
    String? currentUserId, {
    required bool isParticipating,
    required bool isEventFinished,
    required bool hasAcceptedRequest,
    required bool hasActiveOffer,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutral300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.directions_car,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ortak Yolculuk İlanları',
                            style: AppTypography.titleLarge,
                          ),
                          Text(
                            '${offers.length} yolculuk ilanı',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.neutral500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // İlan Ver butonu (eğer uygunsa)
              if (!isEventFinished && isParticipating && !hasAcceptedRequest && !hasActiveOffer)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: AppButton(
                    text: 'İlan Ver',
                    icon: Icons.add,
                    isFullWidth: true,
                    onPressed: () {
                      Navigator.pop(context);
                      openCreateOfferSheet();
                    },
                  ),
                ),
              // Araç listesi
              Expanded(
                child: offers.isEmpty
                    ? ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                        children: [
                          Icon(
                            Icons.directions_car_outlined,
                            size: 56,
                            color: AppColors.neutral300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz yolculuk ilanı yok',
                            textAlign: TextAlign.center,
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.neutral700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Şu an paylaşılan bir araç bulunmuyor. '
                            'Daha sonra tekrar bakabilirsin.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.neutral500,
                              height: 1.4,
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: offers.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildOfferCard(
                              context,
                              ref,
                              offers[index],
                              currentUserId,
                              isParticipating: isParticipating,
                              isEventFinished: isEventFinished,
                              hasAcceptedRequest: hasAcceptedRequest,
                              hasActiveOffer: hasActiveOffer,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRequestSheet(
    BuildContext context,
    WidgetRef ref,
    CarpoolOfferEntity offer,
  ) {
    CarpoolRequestSheet.show(context, ref, offer, eventId);
  }

  Future<void> _acceptRequest(
    BuildContext context,
    WidgetRef ref,
    CarpoolRequestEntity request,
    CarpoolOfferEntity offer,
  ) async {
    await ref.read(carpoolNotifierProvider.notifier).updateRequestStatus(
          request.id,
          offer.id,
          eventId,
          CarpoolRequestStatus.accepted,
        );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('İstek kabul edildi'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _rejectRequest(
    BuildContext context,
    WidgetRef ref,
    CarpoolRequestEntity request,
    CarpoolOfferEntity offer,
  ) async {
    await ref.read(carpoolNotifierProvider.notifier).updateRequestStatus(
          request.id,
          offer.id,
          eventId,
          CarpoolRequestStatus.rejected,
        );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('İstek reddedildi'),
        ),
      );
    }
  }

  void _showDeleteOfferDialog(
    BuildContext context,
    WidgetRef ref,
    CarpoolOfferEntity offer,
  ) {
    final acceptedCount = offer.requests.where((r) => r.isAccepted).length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('İlanı Sil'),
        content: Text(
          acceptedCount > 0
              ? '$acceptedCount onaylı yolcunuz var. İlanı sildiğinizde yolcularınıza bildirim gönderilecek. Devam etmek istiyor musunuz?'
              : 'Bu ilanı silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(carpoolNotifierProvider.notifier).deleteOffer(
                    offer.id,
                    eventId,
                  );
              if (context.mounted) {
                // Bottom sheet'i kapat
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('İlan silindi'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  void _showCancelRequestDialog(
    BuildContext context,
    WidgetRef ref,
    CarpoolRequestEntity request,
    CarpoolOfferEntity offer, {
    required bool isAccepted,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAccepted ? 'Yolculuktan Ayrıl' : 'İsteği Kaldır'),
        content: Text(
          isAccepted
              ? 'Onaylanmış yolculuğunuzdan ayrılmak istediğinize emin misiniz?'
              : 'Yolculuk isteğinizi kaldırmak istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(carpoolNotifierProvider.notifier).cancelRequest(
                    request.id,
                    offer.id,
                    eventId,
                  );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isAccepted
                          ? 'Yolculuktan ayrıldınız'
                          : 'İstek kaldırıldı',
                    ),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(isAccepted ? 'Ayrıl' : 'Kaldır'),
          ),
        ],
      ),
    );
  }
}

/// Ortak yolculuk tanıtımı ve dış erişim (etkinlik detayı alt bar vb.)
class EventCarpoolActions {
  EventCarpoolActions._();

  static final Set<String> _introShownEventIds = {};

  static void scrollToSection(GlobalKey<EventCarpoolSectionState> key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.08,
    );
  }

  static Future<void> openBrowse(
    BuildContext context,
    GlobalKey<EventCarpoolSectionState> key,
  ) async {
    final state = key.currentState;
    if (state != null) {
      await state.openOffersSheet();
      return;
    }
    scrollToSection(key);
  }

  static void openCreate(
    BuildContext context,
    GlobalKey<EventCarpoolSectionState> key,
    String eventId,
  ) {
    final state = key.currentState;
    if (state != null) {
      state.openCreateOfferSheet();
      return;
    }
    CreateCarpoolOfferSheet.show(context, eventId);
  }

  /// Katılım sonrası bir kez tanıtım sheet'i göster
  static Future<void> showIntroAfterJoin(
    BuildContext context,
    GlobalKey<EventCarpoolSectionState> carpoolKey,
    String eventId,
  ) async {
    if (_introShownEventIds.contains(eventId)) return;
    _introShownEventIds.add(eventId);
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.paddingOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutral300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.directions_car,
                  size: 36,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ortak Yolculuk',
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Etkinliğe katıldın! Arabanı paylaşabilir veya diğer '
                'katılımcıların araç ilanlarına başvurabilirsin.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.neutral600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: carpoolFilledActionButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    final state = carpoolKey.currentState;
                    state?.openCreateOfferSheet();
                  },
                  icon: Icons.add_road,
                  label: 'İlan Ver',
                  backgroundColor: AppColors.primary,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: carpoolFilledActionButton(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await openBrowse(context, carpoolKey);
                  },
                  icon: Icons.search,
                  label: 'İlanlara Bak',
                  backgroundColor: AppColors.tertiary,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Sonra'),
              ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
