import '../../domain/entities/route_entity.dart';

/// Route Model - Supabase JSON mapping
class RouteModel {
  final String id;
  final String name;
  final String? description;
  final bool isRace;
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
  final List<RouteGpxVariantEntity> gpxVariants;
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
    this.isRace = false,
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
    this.gpxVariants = const [],
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

    // GPX variants parsing
    final gpxVariantsJson = json['gpx_variants'] as List<dynamic>?;
    final variants = <RouteGpxVariantEntity>[];
    if (gpxVariantsJson != null && gpxVariantsJson.isNotEmpty) {
      double? numToDouble(dynamic v) {
        if (v == null) return null;
        if (v is num) return v.toDouble();
        if (v is String) {
          final normalized = v.trim().replaceAll(',', '.');
          return double.tryParse(normalized);
        }
        return null;
      }

      RouteLocation? parseLocation(dynamic v) {
        if (v is! Map) return null;
        final lat = numToDouble(v['lat']);
        final lng = numToDouble(v['lng']);
        final name = v['name']?.toString();
        if (lat == null || lng == null) return null;
        return RouteLocation(lat: lat, lng: lng, name: name);
      }

      List<ElevationPoint>? parseElevationProfile(dynamic v) {
        if (v is! List) return null;
        final points = <ElevationPoint>[];
        for (final e in v) {
          if (e is! Map) continue;
          final distance = numToDouble(e['distance']);
          final elevation = numToDouble(e['elevation']);
          if (distance == null || elevation == null) continue;
          points.add(ElevationPoint(distance: distance, elevation: elevation));
        }
        return points.isEmpty ? null : points;
      }

      for (final variantRaw in gpxVariantsJson) {
        if (variantRaw is! Map) continue;

        final labelRaw = variantRaw['label'];
        final label = labelRaw?.toString().trim().isNotEmpty == true
            ? labelRaw.toString().trim()
            : 'Default';

        variants.add(RouteGpxVariantEntity(
          label: label,
          gpxData: variantRaw['gpx_data']?.toString(),
          gpxFileUrl: variantRaw['gpx_file_url']?.toString(),
          totalDistance: numToDouble(variantRaw['total_distance']),
          elevationGain: numToDouble(variantRaw['elevation_gain']),
          elevationLoss: numToDouble(variantRaw['elevation_loss']),
          maxElevation: numToDouble(variantRaw['max_elevation']),
          minElevation: numToDouble(variantRaw['min_elevation']),
          elevationProfile: parseElevationProfile(variantRaw['elevation_profile']),
          startLocation: parseLocation(variantRaw['start_location']),
          endLocation: parseLocation(variantRaw['end_location']),
        ));
      }
    }

    // Geriye dönük uyumluluk: `gpx_variants` yoksa top-level GPX'ten tek default varyant üret.
    if (variants.isEmpty) {
      final topLevelGpxData = json['gpx_data'] as String?;
      if (topLevelGpxData != null && topLevelGpxData.trim().isNotEmpty) {
        variants.add(RouteGpxVariantEntity(
          label: 'Default',
          gpxData: topLevelGpxData,
          gpxFileUrl: json['gpx_file_url'] as String?,
          totalDistance: (json['total_distance'] as num?)?.toDouble(),
          elevationGain: (json['elevation_gain'] as num?)?.toDouble(),
          elevationLoss: (json['elevation_loss'] as num?)?.toDouble(),
          maxElevation: (json['max_elevation'] as num?)?.toDouble(),
          minElevation: (json['min_elevation'] as num?)?.toDouble(),
          elevationProfile: elevationProfile,
          startLocation: startLocation,
          endLocation: endLocation,
        ));
      }
    }

    return RouteModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isRace: (json['is_race'] as bool?) ?? false,
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
      gpxVariants: variants,
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
      'is_race': isRace,
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
      'gpx_variants': gpxVariants.isNotEmpty
          ? gpxVariants
              .map((e) => {
                    'label': e.label,
                    'gpx_data': e.gpxData,
                    'gpx_file_url': e.gpxFileUrl,
                    'total_distance': e.totalDistance,
                    'elevation_gain': e.elevationGain,
                    'elevation_loss': e.elevationLoss,
                    'max_elevation': e.maxElevation,
                    'min_elevation': e.minElevation,
                    'elevation_profile': e.elevationProfile
                        ?.map((p) => p.toJson())
                        .toList(),
                    'start_location': e.startLocation?.toJson(),
                    'end_location': e.endLocation?.toJson(),
                  })
              .toList()
          : null,
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
      isRace: isRace,
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
      gpxVariants: gpxVariants,
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
