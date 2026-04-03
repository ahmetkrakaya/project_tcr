/// Route Entity - GPX Rota
class RouteEntity {
  final String id;
  final String name;
  final String? description;
  /// Yarış rotası mı (örn. Runtalya) yoksa normal parkur mu?
  final bool isRace;
  final String? gpxData; // Raw GPX XML
  final String? gpxFileUrl; // Supabase Storage URL
  final double? totalDistance; // Kilometre
  final double? elevationGain; // Metre
  final double? elevationLoss;
  final double? maxElevation;
  final double? minElevation;
  final List<ElevationPoint>? elevationProfile;
  final RouteLocation? startLocation;
  final RouteLocation? endLocation;
  /// Opsiyonel çoklu GPX varyantları (örn. 21K/10K)
  ///
  /// Geriye dönük uyumluluk için:
  /// - `gpx_variants` yoksa model tarafında tek bir "default" varyant üretilecektir.
  final List<RouteGpxVariantEntity> gpxVariants;
  /// Haritadan seçilen rota konumu (lat/lng)
  final double? locationLat;
  final double? locationLng;
  final String? locationName;
  final TerrainType terrainType;
  final int difficultyLevel; // 1-5
  final String? thumbnailUrl;
  final String createdBy;
  final DateTime createdAt;

  const RouteEntity({
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
    this.terrainType = TerrainType.asphalt,
    this.difficultyLevel = 1,
    this.thumbnailUrl,
    required this.createdBy,
    required this.createdAt,
  });

  /// Formatlanmış mesafe (örn: "10.5 km")
  String get formattedDistance {
    if (totalDistance == null) return '-';
    return '${totalDistance!.toStringAsFixed(1)} km';
  }

  /// Formatlanmış yükseliş (örn: "250 m")
  String get formattedElevationGain {
    if (elevationGain == null) return '-';
    return '${elevationGain!.toInt()} m';
  }

  /// Zorluk seviyesi metni
  String get difficultyText {
    switch (difficultyLevel) {
      case 1:
        return 'Çok Kolay';
      case 2:
        return 'Kolay';
      case 3:
        return 'Orta';
      case 4:
        return 'Zor';
      case 5:
        return 'Çok Zor';
      default:
        return 'Bilinmiyor';
    }
  }

  /// Rota koordinatları (GPX'ten parse edilmiş)
  List<RouteCoordinate> get coordinates {
    // Bu method GPX data'dan parse edilecek
    // Şimdilik boş döndürüyor, actual implementation datasource'da
    return [];
  }
}

/// Elevation profili noktası
class ElevationPoint {
  final double distance; // Km cinsinden
  final double elevation; // Metre cinsinden

  const ElevationPoint({
    required this.distance,
    required this.elevation,
  });

  factory ElevationPoint.fromJson(Map<String, dynamic> json) {
    return ElevationPoint(
      distance: (json['distance'] as num).toDouble(),
      elevation: (json['elevation'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'distance': distance,
      'elevation': elevation,
    };
  }
}

/// Rota koordinatı
class RouteCoordinate {
  final double lat;
  final double lng;
  final double? elevation;

  const RouteCoordinate({
    required this.lat,
    required this.lng,
    this.elevation,
  });
}

/// Rota lokasyonu (başlangıç/bitiş)
class RouteLocation {
  final double lat;
  final double lng;
  final String? name;

  const RouteLocation({
    required this.lat,
    required this.lng,
    this.name,
  });

  factory RouteLocation.fromJson(Map<String, dynamic> json) {
    return RouteLocation(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lng': lng,
      'name': name,
    };
  }
}

/// GPX varyantı (tek bir rota içinde birden fazla mesafe/variant)
class RouteGpxVariantEntity {
  final String label; // Örn: "21K", "10K"
  final String? gpxData;
  final String? gpxFileUrl;

  final double? totalDistance; // Kilometre
  final double? elevationGain;
  final double? elevationLoss;
  final double? maxElevation;
  final double? minElevation;
  final List<ElevationPoint>? elevationProfile;
  final RouteLocation? startLocation;
  final RouteLocation? endLocation;

  const RouteGpxVariantEntity({
    required this.label,
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
  });

  String get formattedDistance {
    if (totalDistance == null) return '-';
    return '${totalDistance!.toStringAsFixed(1)} km';
  }

  String get formattedElevationGain {
    if (elevationGain == null) return '-';
    return '${elevationGain!.toInt()} m';
  }
}

/// Zemin tipi: Asfalt, Trail, Pist
enum TerrainType {
  asphalt,
  trail,
  track;

  static TerrainType fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'asphalt':
        return TerrainType.asphalt;
      case 'trail':
        return TerrainType.trail;
      case 'track':
      case 'pist':
        return TerrainType.track;
      default:
        return TerrainType.asphalt;
    }
  }

  String get displayName {
    switch (this) {
      case TerrainType.asphalt:
        return 'Asfalt';
      case TerrainType.trail:
        return 'Trail';
      case TerrainType.track:
        return 'Pist';
    }
  }

  String get icon {
    switch (this) {
      case TerrainType.asphalt:
        return '🛣️';
      case TerrainType.trail:
        return '🏔️';
      case TerrainType.track:
        return '🏃';
    }
  }
}
