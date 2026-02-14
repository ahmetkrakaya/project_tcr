import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/carpool_model.dart';

/// Carpool Remote Data Source
abstract class CarpoolRemoteDataSource {
  /// Etkinlik için carpool offer'ları getir
  Future<List<CarpoolOfferModel>> getEventCarpoolOffers(String eventId);

  /// Tek bir carpool offer getir
  Future<CarpoolOfferModel> getCarpoolOfferById(String offerId);

  /// Carpool offer oluştur
  Future<CarpoolOfferModel> createCarpoolOffer(CarpoolOfferModel offer);

  /// Carpool offer güncelle
  Future<CarpoolOfferModel> updateCarpoolOffer(CarpoolOfferModel offer);

  /// Carpool offer sil
  Future<void> deleteCarpoolOffer(String offerId);

  /// Carpool request oluştur
  Future<CarpoolRequestModel> createCarpoolRequest(CarpoolRequestModel request);

  /// Carpool request durumunu güncelle (sürücü kabul/reddeder)
  Future<CarpoolRequestModel> updateCarpoolRequestStatus(
    String requestId,
    String status,
    {String? responseMessage}
  );

  /// Carpool request iptal et (yolcu)
  Future<void> cancelCarpoolRequest(String requestId);

  /// Pickup location'ları getir
  Future<List<PickupLocationModel>> getPickupLocations();

  /// Carpool offer waypoint'leri oluştur
  Future<void> createCarpoolWaypoints(
    String offerId,
    List<CarpoolWaypointModel> waypoints,
  );

  /// Carpool offer waypoint'lerini sil
  Future<void> deleteCarpoolWaypoints(String offerId);
}

/// Carpool Remote Data Source Implementation
class CarpoolRemoteDataSourceImpl implements CarpoolRemoteDataSource {
  final SupabaseClient _supabase;

  CarpoolRemoteDataSourceImpl(this._supabase);

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  @override
  Future<List<CarpoolOfferModel>> getEventCarpoolOffers(String eventId) async {
    try {
      final response = await _supabase
          .from('carpool_offers')
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url),
            pickup_locations(name),
            carpool_requests(
              *,
              users!inner(first_name, last_name, avatar_url)
            ),
            carpool_offer_waypoints(
              *,
              pickup_locations(name)
            )
          ''')
          .eq('event_id', eventId)
          .eq('status', 'active')
          .order('departure_time', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      return data
          .map((json) => CarpoolOfferModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Carpool offer\'lar alınamadı: $e');
    }
  }

  @override
  Future<CarpoolOfferModel> getCarpoolOfferById(String offerId) async {
    try {
      final response = await _supabase
          .from('carpool_offers')
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url),
            pickup_locations(name),
            carpool_requests(
              *,
              users!inner(first_name, last_name, avatar_url)
            ),
            carpool_offer_waypoints(
              *,
              pickup_locations(name)
            )
          ''')
          .eq('id', offerId)
          .single();

      return CarpoolOfferModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Carpool offer bulunamadı: $e');
    }
  }

  @override
  Future<CarpoolOfferModel> createCarpoolOffer(CarpoolOfferModel offer) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış');
      }

      // Kullanıcının bu etkinlikte aktif bir ilanı var mı kontrol et
      final existingOffers = await _supabase
          .from('carpool_offers')
          .select('id')
          .eq('event_id', offer.eventId)
          .eq('driver_id', userId)
          .eq('status', 'active');

      if ((existingOffers as List).isNotEmpty) {
        throw ServerException(
          message: 'Bu etkinlik için zaten aktif bir ilanınız var',
          code: 'DUPLICATE_OFFER',
        );
      }

      final response = await _supabase
          .from('carpool_offers')
          .insert(offer.toJson())
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url),
            pickup_locations(name)
          ''')
          .single();

      return CarpoolOfferModel.fromJson(response);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        // Unique constraint violation (migration'daki unique index)
        throw ServerException(
          message: 'Bu etkinlik için zaten aktif bir ilanınız var',
          code: e.code,
        );
      }
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException(message: 'Carpool offer oluşturulamadı: $e');
    }
  }

  @override
  Future<CarpoolOfferModel> updateCarpoolOffer(CarpoolOfferModel offer) async {
    try {
      final response = await _supabase
          .from('carpool_offers')
          .update(offer.toJson())
          .eq('id', offer.id)
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url),
            pickup_locations(name),
            carpool_requests(
              *,
              users!inner(first_name, last_name, avatar_url)
            )
          ''')
          .single();

      return CarpoolOfferModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Carpool offer güncellenemedi: $e');
    }
  }

  @override
  Future<void> deleteCarpoolOffer(String offerId) async {
    try {
      await _supabase.from('carpool_offers').delete().eq('id', offerId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Carpool offer silinemedi: $e');
    }
  }

  @override
  Future<CarpoolRequestModel> createCarpoolRequest(
      CarpoolRequestModel request) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış');
      }

      final response = await _supabase
          .from('carpool_requests')
          .insert(request.toJson())
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .single();

      return CarpoolRequestModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Carpool request oluşturulamadı: $e');
    }
  }

  @override
  Future<CarpoolRequestModel> updateCarpoolRequestStatus(
    String requestId,
    String status, {
    String? responseMessage,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'status': status,
        'responded_at': DateTime.now().toIso8601String(),
      };
      if (responseMessage != null) {
        updateData['response_message'] = responseMessage;
      }

      final response = await _supabase
          .from('carpool_requests')
          .update(updateData)
          .eq('id', requestId)
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .single();

      return CarpoolRequestModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Carpool request güncellenemedi: $e');
    }
  }

  @override
  Future<void> cancelCarpoolRequest(String requestId) async {
    try {
      await _supabase
          .from('carpool_requests')
          .update({
            'status': 'cancelled',
            'responded_at': DateTime.now().toIso8601String(),
          })
          .eq('id', requestId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Carpool request iptal edilemedi: $e');
    }
  }

  @override
  Future<List<PickupLocationModel>> getPickupLocations() async {
    try {
      final response = await _supabase
          .from('pickup_locations')
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      return data
          .map((json) => PickupLocationModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Pickup location\'lar alınamadı: $e');
    }
  }

  @override
  Future<void> createCarpoolWaypoints(
    String offerId,
    List<CarpoolWaypointModel> waypoints,
  ) async {
    try {
      if (waypoints.isEmpty) return;

      final waypointsToInsert = waypoints.map((w) => w.toJson()).toList();
      for (var waypoint in waypointsToInsert) {
        waypoint['offer_id'] = offerId;
      }

      await _supabase
          .from('carpool_offer_waypoints')
          .insert(waypointsToInsert);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Waypoint\'ler oluşturulamadı: $e');
    }
  }

  @override
  Future<void> deleteCarpoolWaypoints(String offerId) async {
    try {
      await _supabase
          .from('carpool_offer_waypoints')
          .delete()
          .eq('offer_id', offerId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Waypoint\'ler silinemedi: $e');
    }
  }
}

/// Pickup Location Model
class PickupLocationModel {
  final String id;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final bool isActive;
  final int sortOrder;

  const PickupLocationModel({
    required this.id,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory PickupLocationModel.fromJson(Map<String, dynamic> json) {
    return PickupLocationModel(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}
