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

/// Etkinlik için carpool bölümü
class EventCarpoolSection extends ConsumerWidget {
  final String eventId;

  const EventCarpoolSection({
    super.key,
    required this.eventId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventByIdProvider(eventId));
    
    // Geçmiş etkinliklerde hiçbir şey gösterme ve sorgu yapma
    final isPastEvent = eventAsync.maybeWhen(
      data: (event) => event.isPast,
      orElse: () => false,
    );
    
    if (isPastEvent) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.directions_car,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Ortak Yolculuk',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            // Yeni offer oluştur butonu
            // Kontroller: katılıyor mu, etkinlik bitmiş mi, onaylanmış mı, aktif ilanı var mı
            if (!isEventFinished && isParticipating && !hasAcceptedRequest && !hasActiveOffer)
              TextButton.icon(
                onPressed: () => _showCreateOfferSheet(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('İlan Ver'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        offersAsync.when(
          data: (offers) {
            if (offers.isEmpty) {
              return _buildEmptyState(context, ref);
            }
            // Araçları göster butonu
            return InkWell(
              onTap: () => _showCarpoolListSheet(
                context,
                ref,
                offers,
                currentUserId,
                isParticipating: isParticipating,
                isEventFinished: isEventFinished,
                hasAcceptedRequest: hasAcceptedRequest,
                hasActiveOffer: hasActiveOffer,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.neutral100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.neutral200),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.directions_car,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${offers.length} Araç İlanı',
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Araçları görüntülemek için tıklayın',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.neutral500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: AppColors.neutral400,
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (error, _) => Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Carpool bilgileri yüklenemedi',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.error,
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

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.neutral100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 48,
            color: AppColors.neutral400,
          ),
          const SizedBox(height: 12),
          Text(
            'Henüz ortak yolculuk ilanı yok',
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.neutral600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'İlk ilanı sen vererek diğer katılımcılara yardımcı olabilirsin',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.neutral500,
            ),
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
                    '${offer.availableSeats}/${offer.totalSeats}',
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

            // Action buttons
            // Kontroller: sürücü değil, onaylanmamış, etkinlik bitmemiş, katılıyor, başka araca onaylanmamış, ilan açmamış
            if (!isDriver && !isAccepted && canRequest) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  if (hasRequest)
                    Expanded(
                      child: AppButton(
                        text: 'İstek Gönderildi',
                        variant: AppButtonVariant.outlined,
                        icon: Icons.check,
                        onPressed: null,
                      ),
                    )
                  else if (!offer.isFull)
                    Expanded(
                      child: AppButton(
                        text: 'Katıl',
                        icon: Icons.person_add,
                        onPressed: () => _showRequestSheet(
                          context,
                          ref,
                          offer,
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: AppButton(
                        text: 'Dolu',
                        variant: AppButtonVariant.outlined,
                        onPressed: null,
                      ),
                    ),
                ],
              ),
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

  void _showCreateOfferSheet(BuildContext context, WidgetRef ref) {
    CreateCarpoolOfferSheet.show(context, eventId);
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
                      _showCreateOfferSheet(context, ref);
                    },
                  ),
                ),
              // Araç listesi
              Expanded(
                child: ListView.builder(
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
}
