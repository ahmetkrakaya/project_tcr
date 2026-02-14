import '../../domain/entities/carpool_entity.dart';

/// Carpool Offer Model
class CarpoolOfferModel {
  final String id;
  final String eventId;
  final String driverId;
  final String? driverName;
  final String? driverAvatarUrl;
  final String? pickupLocationId;
  final String? pickupLocationName;
  final String? customPickupLocation;
  final double? pickupLat;
  final double? pickupLng;
  final DateTime departureTime;
  final int totalSeats;
  final int availableSeats;
  final String? carModel;
  final String? carColor;
  final String? notes;
  final String status;
  final DateTime createdAt;
  final List<CarpoolRequestModel> requests;
  final List<CarpoolWaypointModel> waypoints;

  const CarpoolOfferModel({
    required this.id,
    required this.eventId,
    required this.driverId,
    this.driverName,
    this.driverAvatarUrl,
    this.pickupLocationId,
    this.pickupLocationName,
    this.customPickupLocation,
    this.pickupLat,
    this.pickupLng,
    required this.departureTime,
    required this.totalSeats,
    required this.availableSeats,
    this.carModel,
    this.carColor,
    this.notes,
    required this.status,
    required this.createdAt,
    this.requests = const [],
    this.waypoints = const [],
  });

  factory CarpoolOfferModel.fromJson(Map<String, dynamic> json) {
    final userData = json['users'] as Map<String, dynamic>?;
    final locationData = json['pickup_locations'] as Map<String, dynamic>?;
    final requestsData = json['carpool_requests'] as List<dynamic>?;
    final waypointsData = json['carpool_offer_waypoints'] as List<dynamic>?;

    return CarpoolOfferModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      driverId: json['driver_id'] as String,
      driverName: userData != null
          ? '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''}'.trim()
          : null,
      driverAvatarUrl: userData?['avatar_url'] as String?,
      pickupLocationId: json['pickup_location_id'] as String?,
      pickupLocationName: locationData?['name'] as String?,
      customPickupLocation: json['custom_pickup_location'] as String?,
      pickupLat: (json['pickup_lat'] as num?)?.toDouble(),
      pickupLng: (json['pickup_lng'] as num?)?.toDouble(),
      departureTime: DateTime.parse(json['departure_time'] as String),
      totalSeats: json['total_seats'] as int,
      availableSeats: json['available_seats'] as int,
      carModel: json['car_model'] as String?,
      carColor: json['car_color'] as String?,
      notes: json['notes'] as String?,
      status: json['status'] as String? ?? 'active',
      createdAt: DateTime.parse(json['created_at'] as String),
      requests: requestsData
              ?.map((r) => CarpoolRequestModel.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      waypoints: waypointsData
              ?.map((w) => CarpoolWaypointModel.fromJson(w as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'driver_id': driverId,
      'pickup_location_id': pickupLocationId,
      'custom_pickup_location': customPickupLocation,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'departure_time': departureTime.toIso8601String(),
      'total_seats': totalSeats,
      'available_seats': availableSeats,
      'car_model': carModel,
      'car_color': carColor,
      'notes': notes,
      'status': status,
    };
  }

  CarpoolOfferEntity toEntity() {
    return CarpoolOfferEntity(
      id: id,
      eventId: eventId,
      driverId: driverId,
      driverName: driverName ?? '',
      driverAvatarUrl: driverAvatarUrl,
      pickupLocationId: pickupLocationId,
      pickupLocationName: pickupLocationName,
      customPickupLocation: customPickupLocation,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      departureTime: departureTime,
      totalSeats: totalSeats,
      availableSeats: availableSeats,
      carModel: carModel,
      carColor: carColor,
      notes: notes,
      status: CarpoolOfferStatus.fromString(status),
      createdAt: createdAt,
      requests: requests.map((r) => r.toEntity()).toList(),
      waypoints: waypoints.map((w) => w.toEntity()).toList(),
    );
  }
}

/// Carpool Request Model
class CarpoolRequestModel {
  final String id;
  final String offerId;
  final String passengerId;
  final String? passengerName;
  final String? passengerAvatarUrl;
  final int seatsRequested;
  final String? message;
  final String status;
  final DateTime? respondedAt;
  final String? responseMessage;
  final DateTime createdAt;

  const CarpoolRequestModel({
    required this.id,
    required this.offerId,
    required this.passengerId,
    this.passengerName,
    this.passengerAvatarUrl,
    required this.seatsRequested,
    this.message,
    required this.status,
    this.respondedAt,
    this.responseMessage,
    required this.createdAt,
  });

  factory CarpoolRequestModel.fromJson(Map<String, dynamic> json) {
    final userData = json['users'] as Map<String, dynamic>?;

    return CarpoolRequestModel(
      id: json['id'] as String,
      offerId: json['offer_id'] as String,
      passengerId: json['passenger_id'] as String,
      passengerName: userData != null
          ? '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''}'.trim()
          : null,
      passengerAvatarUrl: userData?['avatar_url'] as String?,
      seatsRequested: json['seats_requested'] as int? ?? 1,
      message: json['message'] as String?,
      status: json['status'] as String? ?? 'pending',
      respondedAt: json['responded_at'] != null
          ? DateTime.parse(json['responded_at'] as String)
          : null,
      responseMessage: json['response_message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'offer_id': offerId,
      'passenger_id': passengerId,
      'seats_requested': seatsRequested,
      'message': message,
      'status': status,
    };
  }

  CarpoolRequestEntity toEntity() {
    return CarpoolRequestEntity(
      id: id,
      offerId: offerId,
      passengerId: passengerId,
      passengerName: passengerName,
      passengerAvatarUrl: passengerAvatarUrl,
      seatsRequested: seatsRequested,
      message: message,
      status: CarpoolRequestStatus.fromString(status),
      respondedAt: respondedAt,
      responseMessage: responseMessage,
      createdAt: createdAt,
    );
  }
}

/// Carpool Waypoint Model
class CarpoolWaypointModel {
  final String id;
  final String offerId;
  final String? pickupLocationId;
  final String? pickupLocationName;
  final String? customLocationName;
  final double? lat;
  final double? lng;
  final int sortOrder;
  final DateTime? estimatedArrivalTime;

  const CarpoolWaypointModel({
    required this.id,
    required this.offerId,
    this.pickupLocationId,
    this.pickupLocationName,
    this.customLocationName,
    this.lat,
    this.lng,
    required this.sortOrder,
    this.estimatedArrivalTime,
  });

  factory CarpoolWaypointModel.fromJson(Map<String, dynamic> json) {
    final locationData = json['pickup_locations'] as Map<String, dynamic>?;

    return CarpoolWaypointModel(
      id: json['id'] as String,
      offerId: json['offer_id'] as String,
      pickupLocationId: json['pickup_location_id'] as String?,
      pickupLocationName: locationData?['name'] as String?,
      customLocationName: json['custom_location_name'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      sortOrder: json['sort_order'] as int,
      estimatedArrivalTime: json['estimated_arrival_time'] != null
          ? DateTime.parse(json['estimated_arrival_time'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'offer_id': offerId,
      'pickup_location_id': pickupLocationId,
      'custom_location_name': customLocationName,
      'lat': lat,
      'lng': lng,
      'sort_order': sortOrder,
      'estimated_arrival_time': estimatedArrivalTime?.toIso8601String(),
    };
  }

  CarpoolWaypointEntity toEntity() {
    return CarpoolWaypointEntity(
      id: id,
      offerId: offerId,
      pickupLocationId: pickupLocationId,
      pickupLocationName: pickupLocationName,
      customLocationName: customLocationName,
      lat: lat,
      lng: lng,
      sortOrder: sortOrder,
      estimatedArrivalTime: estimatedArrivalTime,
    );
  }
}
