/// Club Race Entity - TCR Kulübü Yarışı
class ClubRaceEntity {
  final String id;
  final String name;
  final DateTime date;
  final String location;
  final double? locationLat;
  final double? locationLng;
  final String? distance;
  final String? description;
  final String? createdBy;
  final DateTime createdAt;

  const ClubRaceEntity({
    required this.id,
    required this.name,
    required this.date,
    required this.location,
    this.locationLat,
    this.locationLng,
    this.distance,
    this.description,
    this.createdBy,
    required this.createdAt,
  });

  bool get isPast => date.isBefore(DateTime.now());

  bool get hasCoordinates => locationLat != null && locationLng != null;
}
