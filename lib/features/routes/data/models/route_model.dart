import '../../domain/entities/route_entity.dart';

/// Route Model - Supabase JSON mapping
class RouteModel {
  final String id;
  final String name;
  final String? description;
  final String? gpxData;
  final String? gpxFileUrl;
  final double? totalDistance;
  final double? elevationGain;
  final double? elevationLoss;
  final double? maxElevation;
  final double? minElevation;
  final List<ElevationPoint>? elevationProfile;
  final RouteLocation? startLocation;
  final RouteLocation? endLocation;
  final double? locationLat;
  final double? locationLng;
  final String? locationName;
  final String? terrainType;
  final int difficultyLevel;
  final String? thumbnailUrl;
  final String createdBy;
  final DateTime createdAt;

  const RouteModel({
    required this.id,
    required this.name,
    this.description,
    this.gpxData,
    this.gpxFileUrl,
    this.totalDistance,
    this.elevationGain,
    this.elevationLoss,
    this.maxElevation,
    this.minElevation,
    this.elevationProfile,
    this.startLocation,
    this.endLocation,
    this.locationLat,
    this.locationLng,
    this.locationName,
    this.terrainType,
    this.difficultyLevel = 1,
    this.thumbnailUrl,
    required this.createdBy,
    required this.createdAt,
  });

  factory RouteModel.fromJson(Map<String, dynamic> json) {
    // Elevation profile parsing
    List<ElevationPoint>? elevationProfile;
    if (json['elevation_profile'] != null) {
      final profileList = json['elevation_profile'] as List;
      elevationProfile = profileList
          .map((e) => ElevationPoint.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    // Start location parsing
    RouteLocation? startLocation;
    if (json['start_location'] != null) {
      startLocation = RouteLocation.fromJson(
        json['start_location'] as Map<String, dynamic>,
      );
    }

    // End location parsing
    RouteLocation? endLocation;
    if (json['end_location'] != null) {
      endLocation = RouteLocation.fromJson(
        json['end_location'] as Map<String, dynamic>,
      );
    }

    return RouteModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      gpxData: json['gpx_data'] as String?,
      gpxFileUrl: json['gpx_file_url'] as String?,
      totalDistance: (json['total_distance'] as num?)?.toDouble(),
      elevationGain: (json['elevation_gain'] as num?)?.toDouble(),
      elevationLoss: (json['elevation_loss'] as num?)?.toDouble(),
      maxElevation: (json['max_elevation'] as num?)?.toDouble(),
      minElevation: (json['min_elevation'] as num?)?.toDouble(),
      elevationProfile: elevationProfile,
      startLocation: startLocation,
      endLocation: endLocation,
      locationLat: (json['location_lat'] as num?)?.toDouble(),
      locationLng: (json['location_lng'] as num?)?.toDouble(),
      locationName: json['location_name'] as String?,
      terrainType: json['terrain_type'] as String?,
      difficultyLevel: json['difficulty_level'] as int? ?? 1,
      thumbnailUrl: json['thumbnail_url'] as String?,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'gpx_data': gpxData,
      'gpx_file_url': gpxFileUrl,
      'total_distance': totalDistance,
      'elevation_gain': elevationGain,
      'elevation_loss': elevationLoss,
      'max_elevation': maxElevation,
      'min_elevation': minElevation,
      'elevation_profile': elevationProfile?.map((e) => e.toJson()).toList(),
      'start_location': startLocation?.toJson(),
      'end_location': endLocation?.toJson(),
      'location_lat': locationLat,
      'location_lng': locationLng,
      'location_name': locationName,
      'terrain_type': terrainType,
      'difficulty_level': difficultyLevel,
      'thumbnail_url': thumbnailUrl,
      'created_by': createdBy,
    };
  }

  RouteEntity toEntity() {
    return RouteEntity(
      id: id,
      name: name,
      description: description,
      gpxData: gpxData,
      gpxFileUrl: gpxFileUrl,
      totalDistance: totalDistance,
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      maxElevation: maxElevation,
      minElevation: minElevation,
      elevationProfile: elevationProfile,
      startLocation: startLocation,
      endLocation: endLocation,
      locationLat: locationLat,
      locationLng: locationLng,
      locationName: locationName,
      terrainType: TerrainType.fromString(terrainType),
      difficultyLevel: difficultyLevel,
      thumbnailUrl: thumbnailUrl,
      createdBy: createdBy,
      createdAt: createdAt,
    );
  }
}
