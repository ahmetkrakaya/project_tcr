import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../events/domain/entities/event_entity.dart';
import '../../../events/presentation/providers/event_provider.dart';
import '../../data/datasources/carpool_remote_datasource.dart';
import '../../domain/entities/carpool_entity.dart';
import '../providers/carpool_provider.dart';

/// Waypoint data class for form state
class _WaypointData {
  String? pickupLocationId;
  String? customLocationName;
  int sortOrder;

  _WaypointData({
    required this.sortOrder,
  });
}

/// Carpool offer oluşturma bottom sheet
class CreateCarpoolOfferSheet extends ConsumerStatefulWidget {
  final String eventId;

  const CreateCarpoolOfferSheet({
    super.key,
    required this.eventId,
  });

  static Future<void> show(BuildContext context, String eventId) {
    return showModalBottomSheet(
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
          child: CreateCarpoolOfferSheet(eventId: eventId),
        ),
      ),
    );
  }

  @override
  ConsumerState<CreateCarpoolOfferSheet> createState() =>
      _CreateCarpoolOfferSheetState();
}

class _CreateCarpoolOfferSheetState
    extends ConsumerState<CreateCarpoolOfferSheet> {
  final _formKey = GlobalKey<FormState>();
  final _carModelController = TextEditingController();
  final _carColorController = TextEditingController();
  final _notesController = TextEditingController();

  TimeOfDay? _departureTime;
  int _totalSeats = 4;
  
  // Güzergah noktaları
  final List<_WaypointData> _waypoints = [];
  
  // Her waypoint için custom location controller'ları
  final Map<int, TextEditingController> _waypointControllers = {};

  @override
  void initState() {
    super.initState();
    // İlk noktayı ekle
    _waypoints.add(_WaypointData(sortOrder: 0));
    _waypointControllers[0] = TextEditingController();
  }

  @override
  void dispose() {
    _carModelController.dispose();
    _carColorController.dispose();
    _notesController.dispose();
    // Tüm waypoint controller'larını dispose et
    for (final controller in _waypointControllers.values) {
      controller.dispose();
    }
    _waypointControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(pickupLocationsProvider);
    final isLoading = ref.watch(carpoolNotifierProvider).isLoading;
    final eventAsync = ref.watch(eventByIdProvider(widget.eventId));

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
                      'Ortak Yolculuk İlanı Ver',
                      style: AppTypography.titleLarge,
                    ),
                    Text(
                      'Diğer katılımcılara yardımcı ol',
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
                  // Güzergah Noktaları
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Güzergah', style: AppTypography.labelLarge),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            final newIndex = _waypoints.length;
                            _waypoints.add(_WaypointData(
                              sortOrder: newIndex,
                            ));
                            // Yeni waypoint için controller oluştur
                            _waypointControllers[newIndex] = TextEditingController();
                          });
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Nokta Ekle'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  locationsAsync.when(
                    data: (locations) => Column(
                      children: [
                        ..._waypoints.asMap().entries.map((entry) {
                          final index = entry.key;
                          final waypoint = entry.value;
                          return _buildWaypointItem(
                            context,
                            locations,
                            waypoint,
                            index,
                          );
                        }),
                      ],
                    ),
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: (_, __) => const Text('Konumlar yüklenemedi'),
                  ),
                  const SizedBox(height: 24),

                  // Departure Time (etkinlik saatine göre sınırlı)
                  eventAsync.when(
                    data: (event) {
                      // Etkinlik başlangıç saati
                      final eventStartTime = TimeOfDay.fromDateTime(event.startTime);
                      // En fazla 15 dakika geç seçilebilir
                      final maxTime = TimeOfDay(
                        hour: eventStartTime.hour,
                        minute: eventStartTime.minute + 15,
                      );
                      
                      // İlk yüklemede event başlangıç saatini kullan
                      _departureTime ??= eventStartTime;
                      
                      return _buildTimeField(
                        label: 'Kalkış Saati',
                        value: _departureTime!,
                        maxTime: maxTime,
                        onTap: () => _selectTime(maxTime),
                      );
                    },
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 24),

                  // Total Seats
                  Text('Toplam Koltuk Sayısı', style: AppTypography.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (int i = 2; i <= 8; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text('$i'),
                              selected: _totalSeats == i,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _totalSeats = i);
                                }
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Car Info
                  AppTextField(
                    controller: _carModelController,
                    label: 'Araç Modeli',
                    hint: 'Örn: Ford Focus',
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _carColorController,
                    label: 'Araç Rengi',
                    hint: 'Örn: Beyaz',
                  ),
                  const SizedBox(height: 24),

                  // Notes
                  AppTextField(
                    controller: _notesController,
                    label: 'Notlar (Opsiyonel)',
                    hint: 'Örn: Bagajda yer var, Sigara içilmez',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  AppButton(
                    text: 'İlanı Yayınla',
                    icon: Icons.check,
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

  Widget _buildTimeField({
    required String label,
    required TimeOfDay value,
    required TimeOfDay maxTime,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.neutral300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, size: 20, color: AppColors.neutral500),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.neutral500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value.format(context),
                    style: AppTypography.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectTime(TimeOfDay maxTime) async {
    // Async sonrasında context kullanmamak için referansları başta al
    final messenger = ScaffoldMessenger.of(context);
    final maxTimeText = maxTime.format(context);

    final picked = await showTimePicker(
      context: context,
      initialTime: _departureTime ?? const TimeOfDay(hour: 8, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              hourMinuteShape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      // Sadece max saat kontrolü (başlangıçtan önce sınırsız)
      final pickedMinutes = picked.hour * 60 + picked.minute;
      final maxMinutes = maxTime.hour * 60 + maxTime.minute;
      
      if (pickedMinutes > maxMinutes) {
        // Max saatten sonra seçilmişse max saati kullan
        setState(() => _departureTime = maxTime);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Kalkış saati etkinlik başlangıç saatinden en fazla 15 dakika geç olabilir ($maxTimeText)',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      } else {
        setState(() => _departureTime = picked);
      }
    }
  }

  Widget _buildWaypointItem(
    BuildContext context,
    List<PickupLocationModel> locations,
    _WaypointData waypoint,
    int index,
  ) {
    // Controller'ı state'ten al veya oluştur
    final customController = _waypointControllers.putIfAbsent(
      index,
      () => TextEditingController(text: waypoint.customLocationName ?? ''),
    );
    
    // Eğer waypoint dışarıdan değiştiyse (dropdown'dan) controller'ı güncelle
    // Ama sadece farklıysa ve waypoint null/boş ise, aksi halde cursor pozisyonu kaybolur
    if (waypoint.customLocationName == null || waypoint.customLocationName!.isEmpty) {
      if (customController.text.isNotEmpty) {
        customController.text = '';
      }
    } else if (customController.text != waypoint.customLocationName) {
      // Sadece dropdown'dan değiştiyse güncelle (kullanıcı yazmıyorsa)
      // Bu durumda cursor pozisyonunu korumak için sadece farklıysa güncelle
      final cursorPosition = customController.selection.base.offset;
      customController.text = waypoint.customLocationName!;
      if (cursorPosition != -1 && cursorPosition <= customController.text.length) {
        customController.selection = TextSelection.fromPosition(
          TextPosition(offset: cursorPosition),
        );
      }
    }
    
    // Dropdown için seçili değer
    String? selectedValue;
    if (waypoint.pickupLocationId != null) {
      selectedValue = waypoint.pickupLocationId;
    } else if (waypoint.customLocationName != null) {
      // Boş string olsa bile özel konum seçilmiş sayılır
      selectedValue = '__CUSTOM__';
    }
    
    // Özel konum textbox'ını göster/gizle
    final showCustomField = selectedValue == '__CUSTOM__';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutral200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  index == 0
                      ? 'Kalkış Noktası'
                      : '${index + 1}. Nokta',
                  style: AppTypography.titleSmall,
                ),
              ),
              if (_waypoints.length > 1)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () {
                    setState(() {
                      // Controller'ı dispose et ve kaldır
                      _waypointControllers[index]?.dispose();
                      _waypointControllers.remove(index);
                      _waypoints.removeAt(index);
                      // Sort order'ları yeniden düzenle
                      for (int i = 0; i < _waypoints.length; i++) {
                        _waypoints[i].sortOrder = i;
                      }
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Dropdown
          DropdownButtonFormField<String?>(
            value: selectedValue,
            decoration: InputDecoration(
              labelText: 'Konum Seçin',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'Konum seçin',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.neutral400,
                  ),
                ),
              ),
              ...locations.map((location) => DropdownMenuItem<String?>(
                    value: location.id,
                    child: Text(location.name),
                  )),
              DropdownMenuItem<String?>(
                value: '__CUSTOM__',
                child: Row(
                  children: [
                    Icon(
                      Icons.add_location,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Özel Konum Ekle',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                if (value == '__CUSTOM__') {
                  waypoint.pickupLocationId = null;
                  // Boş string yap ki selectedValue '__CUSTOM__' olarak algılansın
                  waypoint.customLocationName = '';
                  customController.text = '';
                } else if (value != null) {
                  waypoint.pickupLocationId = value;
                  waypoint.customLocationName = null;
                  customController.text = '';
                } else {
                  waypoint.pickupLocationId = null;
                  waypoint.customLocationName = null;
                  customController.text = '';
                }
              });
            },
            validator: (value) {
              if (value == null) {
                if (waypoint.customLocationName == null ||
                    waypoint.customLocationName!.isEmpty) {
                  return 'Konum seçin veya özel konum girin';
                }
              }
              return null;
            },
          ),
          // Özel konum textbox (sadece özel konum seçildiyse göster)
          if (showCustomField) ...[
            const SizedBox(height: 12),
            AppTextField(
              controller: customController,
              label: 'Özel Konum',
              hint: 'Örn: Teraspark, Forum Çamlık',
              onChanged: (value) {
                // Waypoint'i güncelle ama setState çağırma (performans için)
                waypoint.customLocationName = value;
              },
              validator: (value) {
                if (showCustomField &&
                    (value == null || value.isEmpty)) {
                  return 'Özel konum gerekli';
                }
                return null;
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);

    // Güzergah noktalarını kontrol et
    bool hasValidWaypoint = false;
    for (final waypoint in _waypoints) {
      if (waypoint.pickupLocationId != null ||
          (waypoint.customLocationName != null &&
              waypoint.customLocationName!.isNotEmpty)) {
        hasValidWaypoint = true;
        break;
      }
    }

    if (!hasValidWaypoint) {
      messenger.showSnackBar(
        const SnackBar(content: Text('En az bir güzergah noktası gerekli')),
      );
      return;
    }

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Kullanıcı giriş yapmamış')),
      );
      return;
    }

    // Event bilgilerini al
    final event = await ref.read(eventByIdProvider(widget.eventId).future);

    // Kontrol 1: Etkinlik bitmiş mi? (başlangıç + 2 saat geçmişse)
    final eventEndTime = event.startTime.add(const Duration(hours: 2));
    if (DateTime.now().isAfter(eventEndTime)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Etkinlik bitmiş, yeni ilan verilemez'),
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
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Etkinliğe katılıyorum demeniz gerekiyor'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Kontrol 3: Kullanıcı bir araca onaylanmış mı?
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
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Bir araca onaylandınız, yeni ilan veremezsiniz'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Etkinlik tarihini kullan, sadece saati değiştir
    if (_departureTime == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Lütfen kalkış saati seçin')),
      );
      return;
    }
    
    final departureDateTime = DateTime(
      event.startTime.year,
      event.startTime.month,
      event.startTime.day,
      _departureTime!.hour,
      _departureTime!.minute,
    );

    // Waypoints oluştur
    final waypoints = <CarpoolWaypointEntity>[];
    for (final w in _waypoints) {
      if (w.pickupLocationId != null ||
          (w.customLocationName != null && w.customLocationName!.isNotEmpty)) {
        waypoints.add(CarpoolWaypointEntity(
          id: '',
          offerId: '',
          pickupLocationId: w.pickupLocationId,
          customLocationName: w.customLocationName,
          sortOrder: w.sortOrder,
        ));
      }
    }

    final offer = CarpoolOfferEntity(
      id: '',
      eventId: widget.eventId,
      driverId: '', // Provider'da otomatik doldurulacak
      departureTime: departureDateTime,
      totalSeats: _totalSeats,
      availableSeats: _totalSeats,
      carModel: _carModelController.text.isEmpty
          ? null
          : _carModelController.text,
      carColor:
          _carColorController.text.isEmpty ? null : _carColorController.text,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
      status: CarpoolOfferStatus.active,
      createdAt: DateTime.now(),
      waypoints: waypoints,
    );

    final created = await ref
        .read(carpoolNotifierProvider.notifier)
        .createOffer(widget.eventId, offer);

    if (mounted) {
      if (created != null) {
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('İlan başarıyla oluşturuldu'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        // Hata mesajını provider'dan al
        final errorState = ref.read(carpoolNotifierProvider);
        final errorMessage = errorState.hasError
            ? errorState.error.toString().contains('zaten aktif')
                ? 'Bu etkinlik için zaten aktif bir ilanınız var'
                : 'İlan oluşturulamadı: ${errorState.error}'
            : 'İlan oluşturulamadı';
        
        messenger.showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
