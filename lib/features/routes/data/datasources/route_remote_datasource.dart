import 'dart:typed_data';
import 'dart:math' as math;

import 'package:gpx/gpx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/route_entity.dart';
import '../models/route_model.dart';

/// Route Remote Data Source
class RouteRemoteDataSource {
  final SupabaseClient _supabase;

  RouteRemoteDataSource(this._supabase);

  /// Tüm rotaları getir
  Future<List<RouteModel>> getRoutes() async {
    try {
      final response = await _supabase
          .from('routes')
          .select()
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => RouteModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Rotalar alınamadı: $e');
    }
  }

  /// Tek bir rota getir
  Future<RouteModel> getRouteById(String id) async {
    try {
      final response = await _supabase
          .from('routes')
          .select()
          .eq('id', id)
          .single();

      return RouteModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Rota alınamadı: $e');
    }
  }

  /// GPX dosyasından veya GPX olmadan rota oluştur (GPX opsiyonel)
  Future<RouteModel> createRouteFromGpx({
    required String name,
    String? gpxContent,
    required double locationLat,
    required double locationLng,
    String? locationName,
    String? description,
    String? terrainType,
    int difficultyLevel = 1,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw const ServerException(message: 'Kullanıcı giriş yapmamış');

      final _ParsedGpxData parsedData;
      if (gpxContent != null && gpxContent.trim().isNotEmpty) {
        final gpx = GpxReader().fromString(gpxContent);
        parsedData = _parseGpxData(gpx);
      } else {
        parsedData = _ParsedGpxData(
          coordinates: [],
          totalDistance: 0,
          elevationGain: 0,
          elevationLoss: 0,
          maxElevation: 0,
          minElevation: 0,
          elevationProfile: [],
          startLocation: null,
          endLocation: null,
        );
      }

      // Rotayı veritabanına kaydet (konum haritadan seçilir, lat/lng kaydedilir)
      final routeData = <String, dynamic>{
        'name': name,
        'description': description,
        'location_lat': locationLat,
        'location_lng': locationLng,
        'location_name': locationName,
        'total_distance': parsedData.totalDistance,
        'elevation_gain': parsedData.elevationGain,
        'elevation_loss': parsedData.elevationLoss,
        'max_elevation': parsedData.maxElevation,
        'min_elevation': parsedData.minElevation,
        'elevation_profile': parsedData.elevationProfile.map((e) => e.toJson()).toList(),
        'start_location': parsedData.startLocation?.toJson(),
        'end_location': parsedData.endLocation?.toJson(),
        'terrain_type': terrainType ?? 'asphalt',
        'difficulty_level': difficultyLevel,
        'created_by': userId,
      };
      if (gpxContent != null && gpxContent.trim().isNotEmpty) {
        routeData['gpx_data'] = gpxContent;
      }

      final response = await _supabase
          .from('routes')
          .insert(routeData)
          .select()
          .single();

      return RouteModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Rota oluşturulamadı: $e');
    }
  }

  /// GPX dosyasını storage'a yükle ve rota oluştur
  /// [gpxContent]: GPX dosyasının string içeriği
  /// [gpxBytes]: GPX dosyasının binary içeriği (storage upload için)
  Future<RouteModel> uploadGpxFileAndCreateRoute({
    required String gpxContent,
    required Uint8List gpxBytes,
    required String name,
    required double locationLat,
    required double locationLng,
    String? locationName,
    String? description,
    String? terrainType,
    int difficultyLevel = 1,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw const ServerException(message: 'Kullanıcı giriş yapmamış');

      // Storage'a yükle (bytes ile hem web hem mobil uyumlu)
      final fileName = 'route_${DateTime.now().millisecondsSinceEpoch}.gpx';
      await _supabase.storage.from('routes').uploadBinary(
        fileName,
        gpxBytes,
        fileOptions: const FileOptions(contentType: 'application/gpx+xml'),
      );
      final gpxFileUrl = _supabase.storage.from('routes').getPublicUrl(fileName);

      // GPX'i parse et
      final gpx = GpxReader().fromString(gpxContent);
      final parsedData = _parseGpxData(gpx);

      // Rotayı veritabanına kaydet
      final routeData = {
        'name': name,
        'description': description,
        'gpx_data': gpxContent,
        'gpx_file_url': gpxFileUrl,
        'location_lat': locationLat,
        'location_lng': locationLng,
        'location_name': locationName,
        'total_distance': parsedData.totalDistance,
        'elevation_gain': parsedData.elevationGain,
        'elevation_loss': parsedData.elevationLoss,
        'max_elevation': parsedData.maxElevation,
        'min_elevation': parsedData.minElevation,
        'elevation_profile': parsedData.elevationProfile.map((e) => e.toJson()).toList(),
        'start_location': parsedData.startLocation?.toJson(),
        'end_location': parsedData.endLocation?.toJson(),
        'terrain_type': terrainType ?? 'asphalt',
        'difficulty_level': difficultyLevel,
        'created_by': userId,
      };

      final response = await _supabase
          .from('routes')
          .insert(routeData)
          .select()
          .single();

      return RouteModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Rota yüklenemedi: $e');
    }
  }

  /// Rotayı güncelle (sadece gönderilen alanlar)
  Future<RouteModel> updateRoute(String id, Map<String, dynamic> data) async {
    try {
      final response = await _supabase
          .from('routes')
          .update(data)
          .eq('id', id)
          .select()
          .single();

      return RouteModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Rota güncellenemedi: $e');
    }
  }

  /// Rotayı GPX dahil güncelle (yeni GPX seçildiyse parse edilir)
  Future<RouteModel> updateRouteWithData({
    required String id,
    required String name,
    required double locationLat,
    required double locationLng,
    String? locationName,
    String? description,
    String? terrainType,
    int difficultyLevel = 1,
    String? gpxContent,
  }) async {
    try {
      final Map<String, dynamic> data = {
        'name': name,
        'location_lat': locationLat,
        'location_lng': locationLng,
        'location_name': locationName,
        'description': description,
        'terrain_type': terrainType ?? 'asphalt',
        'difficulty_level': difficultyLevel,
      };

      if (gpxContent != null && gpxContent.isNotEmpty) {
        final gpx = GpxReader().fromString(gpxContent);
        final parsedData = _parseGpxData(gpx);
        data['gpx_data'] = gpxContent;
        data['total_distance'] = parsedData.totalDistance;
        data['elevation_gain'] = parsedData.elevationGain;
        data['elevation_loss'] = parsedData.elevationLoss;
        data['max_elevation'] = parsedData.maxElevation;
        data['min_elevation'] = parsedData.minElevation;
        data['elevation_profile'] = parsedData.elevationProfile.map((e) => e.toJson()).toList();
        data['start_location'] = parsedData.startLocation?.toJson();
        data['end_location'] = parsedData.endLocation?.toJson();
      }

      return updateRoute(id, data);
    } catch (e) {
      throw ServerException(message: 'Rota güncellenemedi: $e');
    }
  }

  /// Rotayı sil
  Future<void> deleteRoute(String id) async {
    try {
      await _supabase.from('routes').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Rota silinemedi: $e');
    }
  }

  /// GPX verisinden koordinatları parse et
  List<RouteCoordinate> parseGpxCoordinates(String gpxData) {
    try {
      final gpx = GpxReader().fromString(gpxData);
      final coordinates = <RouteCoordinate>[];

      // Tracks
      for (final track in gpx.trks) {
        for (final segment in track.trksegs) {
          for (final point in segment.trkpts) {
            if (point.lat != null && point.lon != null) {
              coordinates.add(RouteCoordinate(
                lat: point.lat!,
                lng: point.lon!,
                elevation: point.ele,
              ));
            }
          }
        }
      }

      // Routes (eğer track yoksa)
      if (coordinates.isEmpty) {
        for (final route in gpx.rtes) {
          for (final point in route.rtepts) {
            if (point.lat != null && point.lon != null) {
              coordinates.add(RouteCoordinate(
                lat: point.lat!,
                lng: point.lon!,
                elevation: point.ele,
              ));
            }
          }
        }
      }

      // Waypoints (en son çare)
      if (coordinates.isEmpty) {
        for (final point in gpx.wpts) {
          if (point.lat != null && point.lon != null) {
            coordinates.add(RouteCoordinate(
              lat: point.lat!,
              lng: point.lon!,
              elevation: point.ele,
            ));
          }
        }
      }

      return coordinates;
    } catch (e) {
      throw ServerException(message: 'GPX parse edilemedi: $e');
    }
  }

  /// GPX verisini parse et ve istatistikleri hesapla
  _ParsedGpxData _parseGpxData(Gpx gpx) {
    final coordinates = <RouteCoordinate>[];
    final elevationProfile = <ElevationPoint>[];

    // Tracks'tan koordinatları al
    for (final track in gpx.trks) {
      for (final segment in track.trksegs) {
        for (final point in segment.trkpts) {
          if (point.lat != null && point.lon != null) {
            coordinates.add(RouteCoordinate(
              lat: point.lat!,
              lng: point.lon!,
              elevation: point.ele,
            ));
          }
        }
      }
    }

    // Routes'tan koordinatları al (eğer track yoksa)
    if (coordinates.isEmpty) {
      for (final route in gpx.rtes) {
        for (final point in route.rtepts) {
          if (point.lat != null && point.lon != null) {
            coordinates.add(RouteCoordinate(
              lat: point.lat!,
              lng: point.lon!,
              elevation: point.ele,
            ));
          }
        }
      }
    }

    if (coordinates.isEmpty) {
      return _ParsedGpxData(
        coordinates: [],
        totalDistance: 0,
        elevationGain: 0,
        elevationLoss: 0,
        maxElevation: 0,
        minElevation: 0,
        elevationProfile: [],
        startLocation: null,
        endLocation: null,
      );
    }

    // Mesafe ve elevation hesapla
    double totalDistance = 0;
    double elevationGain = 0;
    double elevationLoss = 0;
    double? maxElevation;
    double? minElevation;

    for (int i = 0; i < coordinates.length; i++) {
      final point = coordinates[i];

      // Elevation min/max
      if (point.elevation != null) {
        maxElevation = maxElevation == null
            ? point.elevation!
            : (point.elevation! > maxElevation ? point.elevation! : maxElevation);
        minElevation = minElevation == null
            ? point.elevation!
            : (point.elevation! < minElevation ? point.elevation! : minElevation);
      }

      if (i > 0) {
        final prevPoint = coordinates[i - 1];

        // Mesafe hesapla (Haversine)
        final distance = _calculateDistance(
          prevPoint.lat,
          prevPoint.lng,
          point.lat,
          point.lng,
        );
        totalDistance += distance;

        // Elevation gain/loss
        if (point.elevation != null && prevPoint.elevation != null) {
          final elevDiff = point.elevation! - prevPoint.elevation!;
          if (elevDiff > 0) {
            elevationGain += elevDiff;
          } else {
            elevationLoss += elevDiff.abs();
          }
        }
      }

      // Elevation profile (her 100m'de bir nokta)
      if (point.elevation != null) {
        // Her 50 noktada bir veya son nokta
        if (i % 50 == 0 || i == coordinates.length - 1) {
          elevationProfile.add(ElevationPoint(
            distance: totalDistance,
            elevation: point.elevation!,
          ));
        }
      }
    }

    return _ParsedGpxData(
      coordinates: coordinates,
      totalDistance: totalDistance,
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      maxElevation: maxElevation ?? 0,
      minElevation: minElevation ?? 0,
      elevationProfile: elevationProfile,
      startLocation: coordinates.isNotEmpty
          ? RouteLocation(lat: coordinates.first.lat, lng: coordinates.first.lng)
          : null,
      endLocation: coordinates.isNotEmpty
          ? RouteLocation(lat: coordinates.last.lat, lng: coordinates.last.lng)
          : null,
    );
  }

  /// Haversine formülü ile mesafe hesapla (km)
  /// Daha hassas hesaplama için dart:math kullanılıyor
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371.0; // Dünya yarıçapı kilometre cinsinden

    // Derece -> Radyan dönüşümü
    final lat1Rad = lat1 * math.pi / 180.0;
    final lat2Rad = lat2 * math.pi / 180.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;

    // Haversine formülü
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) * 
        math.sin(dLon / 2) * math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }
}

/// Parsed GPX data
class _ParsedGpxData {
  final List<RouteCoordinate> coordinates;
  final double totalDistance;
  final double elevationGain;
  final double elevationLoss;
  final double maxElevation;
  final double minElevation;
  final List<ElevationPoint> elevationProfile;
  final RouteLocation? startLocation;
  final RouteLocation? endLocation;

  _ParsedGpxData({
    required this.coordinates,
    required this.totalDistance,
    required this.elevationGain,
    required this.elevationLoss,
    required this.maxElevation,
    required this.minElevation,
    required this.elevationProfile,
    required this.startLocation,
    required this.endLocation,
  });
}
