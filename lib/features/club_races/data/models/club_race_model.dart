import '../../domain/entities/club_race_entity.dart';

/// Club Race Model - Supabase JSON mapping
class ClubRaceModel {
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

  const ClubRaceModel({
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

  factory ClubRaceModel.fromJson(Map<String, dynamic> json) {
    return ClubRaceModel(
      id: json['id'] as String,
      name: json['name'] as String,
      date: DateTime.parse(json['date'] as String),
      location: json['location'] as String,
      locationLat: (json['location_lat'] as num?)?.toDouble(),
      locationLng: (json['location_lng'] as num?)?.toDouble(),
      distance: json['distance'] as String?,
      description: json['description'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'location': location,
      'location_lat': locationLat,
      'location_lng': locationLng,
      'distance': distance,
      'description': description,
      'created_by': createdBy,
    };
  }

  ClubRaceEntity toEntity() {
    return ClubRaceEntity(
      id: id,
      name: name,
      date: date,
      location: location,
      locationLat: locationLat,
      locationLng: locationLng,
      distance: distance,
      description: description,
      createdBy: createdBy,
      createdAt: createdAt,
    );
  }
}
