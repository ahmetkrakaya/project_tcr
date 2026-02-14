import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/carpool_remote_datasource.dart';
import '../../data/models/carpool_model.dart';
import '../../domain/entities/carpool_entity.dart';

/// Supabase client provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Carpool datasource provider
final carpoolDataSourceProvider = Provider<CarpoolRemoteDataSource>((ref) {
  return CarpoolRemoteDataSourceImpl(ref.watch(_supabaseProvider));
});

/// Event carpool offers provider
final eventCarpoolOffersProvider =
    FutureProvider.family<List<CarpoolOfferEntity>, String>((ref, eventId) async {
  final dataSource = ref.watch(carpoolDataSourceProvider);
  final models = await dataSource.getEventCarpoolOffers(eventId);
  return models.map((m) => m.toEntity()).toList();
});

/// Single carpool offer provider
final carpoolOfferByIdProvider =
    FutureProvider.family<CarpoolOfferEntity, String>((ref, offerId) async {
  final dataSource = ref.watch(carpoolDataSourceProvider);
  final model = await dataSource.getCarpoolOfferById(offerId);
  return model.toEntity();
});

/// Pickup locations provider
final pickupLocationsProvider =
    FutureProvider<List<PickupLocationModel>>((ref) async {
  final dataSource = ref.watch(carpoolDataSourceProvider);
  return await dataSource.getPickupLocations();
});

/// Carpool Notifier - CRUD işlemleri
class CarpoolNotifier extends StateNotifier<AsyncValue<void>> {
  final CarpoolRemoteDataSource _dataSource;
  final Ref _ref;

  CarpoolNotifier(this._dataSource, this._ref) : super(const AsyncValue.data(null));

  /// Carpool offer oluştur
  Future<CarpoolOfferEntity?> createOffer(
    String eventId,
    CarpoolOfferEntity offer,
  ) async {
    state = const AsyncValue.loading();
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      final model = CarpoolOfferModel(
        id: '',
        eventId: eventId,
        driverId: userId,
        pickupLocationId: offer.pickupLocationId,
        customPickupLocation: offer.customPickupLocation,
        pickupLat: offer.pickupLat,
        pickupLng: offer.pickupLng,
        departureTime: offer.departureTime,
        totalSeats: offer.totalSeats,
        availableSeats: offer.availableSeats,
        carModel: offer.carModel,
        carColor: offer.carColor,
        notes: offer.notes,
        status: offer.status.toDbString(),
        createdAt: DateTime.now(),
      );

      final created = await _dataSource.createCarpoolOffer(model);
      
      // Waypoints'i kaydet
      if (offer.waypoints.isNotEmpty) {
        final waypointModels = offer.waypoints
            .map((w) => CarpoolWaypointModel(
                  id: '',
                  offerId: created.id,
                  pickupLocationId: w.pickupLocationId,
                  customLocationName: w.customLocationName,
                  lat: w.lat,
                  lng: w.lng,
                  sortOrder: w.sortOrder,
                  estimatedArrivalTime: w.estimatedArrivalTime,
                ))
            .toList();
        await _dataSource.createCarpoolWaypoints(created.id, waypointModels);
      }

      state = const AsyncValue.data(null);

      // Provider'ları güncelle
      _ref.invalidate(eventCarpoolOffersProvider(eventId));

      // Waypoints ile birlikte tam offer'ı getir
      final fullOffer = await _dataSource.getCarpoolOfferById(created.id);
      return fullOffer.toEntity();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Carpool request oluştur
  Future<CarpoolRequestEntity?> createRequest(
    String offerId,
    String eventId,
    int seatsRequested,
    {String? message}
  ) async {
    state = const AsyncValue.loading();
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      final model = CarpoolRequestModel(
        id: '',
        offerId: offerId,
        passengerId: userId,
        seatsRequested: seatsRequested,
        message: message,
        status: 'pending',
        createdAt: DateTime.now(),
      );

      final created = await _dataSource.createCarpoolRequest(model);
      state = const AsyncValue.data(null);

      // Provider'ları güncelle
      _ref.invalidate(eventCarpoolOffersProvider(eventId));
      _ref.invalidate(carpoolOfferByIdProvider(offerId));

      return created.toEntity();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Carpool request durumunu güncelle (sürücü)
  Future<void> updateRequestStatus(
    String requestId,
    String offerId,
    String eventId,
    CarpoolRequestStatus status,
    {String? responseMessage}
  ) async {
    state = const AsyncValue.loading();
    try {
      // Request bilgisini al
      final offer = await _dataSource.getCarpoolOfferById(offerId);
      final request = offer.requests.firstWhere((r) => r.id == requestId);
      
      await _dataSource.updateCarpoolRequestStatus(
        requestId,
        status.toDbString(),
        responseMessage: responseMessage,
      );
      
      // Eğer request accept edildiyse, aynı kullanıcının diğer pending request'lerini iptal et
      if (status == CarpoolRequestStatus.accepted) {
        // Tüm event offer'larını al
        final allOffers = await _dataSource.getEventCarpoolOffers(eventId);
        
        // Aynı kullanıcının diğer pending request'lerini bul ve iptal et
        for (final otherOffer in allOffers) {
          for (final otherRequest in otherOffer.requests) {
            if (otherRequest.passengerId == request.passengerId &&
                otherRequest.id != requestId &&
                otherRequest.status == 'pending') {
              await _dataSource.cancelCarpoolRequest(otherRequest.id);
            }
          }
        }
      }
      
      state = const AsyncValue.data(null);

      // Provider'ları güncelle
      _ref.invalidate(eventCarpoolOffersProvider(eventId));
      _ref.invalidate(carpoolOfferByIdProvider(offerId));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Carpool request iptal et (yolcu)
  Future<void> cancelRequest(String requestId, String offerId, String eventId) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.cancelCarpoolRequest(requestId);
      state = const AsyncValue.data(null);

      // Provider'ları güncelle
      _ref.invalidate(eventCarpoolOffersProvider(eventId));
      _ref.invalidate(carpoolOfferByIdProvider(offerId));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Carpool offer sil
  Future<void> deleteOffer(String offerId, String eventId) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.deleteCarpoolOffer(offerId);
      state = const AsyncValue.data(null);

      // Provider'ı güncelle
      _ref.invalidate(eventCarpoolOffersProvider(eventId));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Carpool Notifier Provider
final carpoolNotifierProvider =
    StateNotifierProvider<CarpoolNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(carpoolDataSourceProvider);
  return CarpoolNotifier(dataSource, ref);
});
