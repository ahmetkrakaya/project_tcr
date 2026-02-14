/// Carpool Offer Entity
class CarpoolOfferEntity {
  final String id;
  final String eventId;
  final String driverId;
  final String driverName;
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
  final CarpoolOfferStatus status;
  final DateTime createdAt;
  final List<CarpoolRequestEntity> requests;
  final List<CarpoolWaypointEntity> waypoints;

  const CarpoolOfferEntity({
    required this.id,
    required this.eventId,
    required this.driverId,
    this.driverName = '',
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

  String get pickupLocationDisplay {
    if (waypoints.isNotEmpty) {
      // Güzergah varsa tüm noktaları göster
      return waypoints
          .map((w) => w.locationName)
          .where((name) => name.isNotEmpty)
          .join(' → ');
    }
    // Eski yapı (geriye dönük uyumluluk)
    return pickupLocationName ?? customPickupLocation ?? 'Konum belirtilmemiş';
  }

  String get carInfo {
    if (carModel != null && carColor != null) {
      return '$carModel - $carColor';
    } else if (carModel != null) {
      return carModel!;
    }
    return 'Araç bilgisi yok';
  }

  bool get isFull => availableSeats <= 0;
  bool get isActive => status == CarpoolOfferStatus.active;
}

/// Carpool Request Entity
class CarpoolRequestEntity {
  final String id;
  final String offerId;
  final String passengerId;
  final String? passengerName;
  final String? passengerAvatarUrl;
  final int seatsRequested;
  final String? message;
  final CarpoolRequestStatus status;
  final DateTime? respondedAt;
  final String? responseMessage;
  final DateTime createdAt;

  const CarpoolRequestEntity({
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

  bool get isPending => status == CarpoolRequestStatus.pending;
  bool get isAccepted => status == CarpoolRequestStatus.accepted;
  bool get isRejected => status == CarpoolRequestStatus.rejected;
}

/// Carpool Offer Status
enum CarpoolOfferStatus {
  active,
  full,
  cancelled,
  completed;

  static CarpoolOfferStatus fromString(String value) {
    return CarpoolOfferStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CarpoolOfferStatus.active,
    );
  }

  String toDbString() => name;
}

/// Carpool Request Status
enum CarpoolRequestStatus {
  pending,
  accepted,
  rejected,
  cancelled;

  static CarpoolRequestStatus fromString(String value) {
    return CarpoolRequestStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CarpoolRequestStatus.pending,
    );
  }

  String toDbString() => name;
}

/// Carpool Waypoint Entity - Güzergah noktası
class CarpoolWaypointEntity {
  final String id;
  final String offerId;
  final String? pickupLocationId;
  final String? pickupLocationName;
  final String? customLocationName;
  final double? lat;
  final double? lng;
  final int sortOrder;
  final DateTime? estimatedArrivalTime;

  const CarpoolWaypointEntity({
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

  String get locationName {
    return pickupLocationName ?? customLocationName ?? 'Konum belirtilmemiş';
  }
}
