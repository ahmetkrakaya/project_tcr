import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../events/domain/entities/event_entity.dart';
import '../../../events/presentation/providers/event_provider.dart';
import '../../domain/entities/carpool_entity.dart';
import '../providers/carpool_provider.dart';

/// Carpool request gönderme bottom sheet
class CarpoolRequestSheet extends ConsumerStatefulWidget {
  final CarpoolOfferEntity offer;
  final String eventId;

  const CarpoolRequestSheet({
    super.key,
    required this.offer,
    required this.eventId,
  });

  static Future<void> show(
    BuildContext context,
    WidgetRef ref,
    CarpoolOfferEntity offer,
    String eventId,
  ) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: CarpoolRequestSheet(offer: offer, eventId: eventId),
        ),
      ),
    );
  }

  @override
  ConsumerState<CarpoolRequestSheet> createState() =>
      _CarpoolRequestSheetState();
}

class _CarpoolRequestSheetState extends ConsumerState<CarpoolRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  int _seatsRequested = 1;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(carpoolNotifierProvider).isLoading;

    return Column(
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
                  Icons.person_add,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Katılım İsteği Gönder',
                      style: AppTypography.titleLarge,
                    ),
                    Text(
                      widget.offer.driverName,
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

        // Form
        Expanded(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Offer Info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.neutral100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 18,
                              color: AppColors.neutral600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.offer.pickupLocationDisplay,
                                style: AppTypography.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 18,
                              color: AppColors.neutral600,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Kalkış: ${widget.offer.departureTime.hour.toString().padLeft(2, '0')}:${widget.offer.departureTime.minute.toString().padLeft(2, '0')}',
                              style: AppTypography.bodyMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.directions_car,
                              size: 18,
                              color: AppColors.neutral600,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.offer.carInfo,
                              style: AppTypography.bodyMedium,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Seats Requested
                  Text('Koltuk Sayısı', style: AppTypography.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (int i = 1;
                          i <= widget.offer.availableSeats && i <= 4;
                          i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text('$i'),
                              selected: _seatsRequested == i,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _seatsRequested = i);
                                }
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Message
                  AppTextField(
                    controller: _messageController,
                    label: 'Mesaj (Opsiyonel)',
                    hint: 'Sürücüye iletmek istediğiniz bir şey var mı?',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  AppButton(
                    text: 'İstek Gönder',
                    icon: Icons.send,
                    isLoading: isLoading,
                    isFullWidth: true,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı giriş yapmamış')),
      );
      return;
    }

    // Kontrol 1: Etkinlik bitmiş mi?
    final eventAsync = ref.read(eventByIdProvider(widget.eventId));
    final event = eventAsync.when(
      data: (e) => e,
      loading: () => null,
      error: (_, __) => null,
    );

    if (event == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Etkinlik bilgileri alınamadı')),
      );
      return;
    }

    final eventEndTime = event.startTime.add(const Duration(hours: 2));
    if (DateTime.now().isAfter(eventEndTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Etkinlik bitmiş, istek gönderilemez'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Kontrol 2: Kullanıcı etkinliğe katılıyor mu?
    final participantsAsync = ref.read(eventParticipantsProvider(widget.eventId));
    final participants = participantsAsync.when(
      data: (list) => list,
      loading: () => <EventParticipantEntity>[],
      error: (_, __) => <EventParticipantEntity>[],
    );
    
    final isParticipating = participants.any(
      (p) => p.userId == userId && p.status == RsvpStatus.going,
    );
    
    if (!isParticipating) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Etkinliğe katılıyorum demeniz gerekiyor'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Kontrol 3: İlan açan kişi mi?
    if (widget.offer.driverId == userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kendi ilanınıza istek gönderemezsiniz'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Kontrol 4: Bir araca onaylanmış mı?
    final offersAsync = ref.read(eventCarpoolOffersProvider(widget.eventId));
    final offers = offersAsync.when(
      data: (list) => list,
      loading: () => <CarpoolOfferEntity>[],
      error: (_, __) => <CarpoolOfferEntity>[],
    );
    
    final hasAcceptedRequest = offers.any(
      (offer) => offer.requests.any(
        (req) => req.passengerId == userId && req.isAccepted,
      ),
    );
    
    if (hasAcceptedRequest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bir araca onaylandınız, başka istek gönderemezsiniz'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final created = await ref.read(carpoolNotifierProvider.notifier).createRequest(
          widget.offer.id,
          widget.eventId,
          _seatsRequested,
          message: _messageController.text.isEmpty
              ? null
              : _messageController.text,
        );

    if (mounted) {
      if (created != null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İstek başarıyla gönderildi'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İstek gönderilemedi'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
