import 'dart:async';
import 'package:dio/dio.dart';

class NominatimPlace {
  final double lat;
  final double lng;
  final String displayName;
  final String? type;

  const NominatimPlace({
    required this.lat,
    required this.lng,
    required this.displayName,
    this.type,
  });

  factory NominatimPlace.fromJson(Map<String, dynamic> json) {
    return NominatimPlace(
      lat: double.parse(json['lat'] as String),
      lng: double.parse(json['lon'] as String),
      displayName: json['display_name'] as String,
      type: json['type'] as String?,
    );
  }

  /// Kısa bir etiket döner (ilk 2-3 parça: mekan adı, mahalle, ilçe)
  String get shortName {
    final parts = displayName.split(', ');
    if (parts.length <= 3) return displayName;
    return parts.take(3).join(', ');
  }
}

class NominatimService {
  static final NominatimService _instance = NominatimService._();
  factory NominatimService() => _instance;
  NominatimService._();

  final _dio = Dio(BaseOptions(
    baseUrl: 'https://nominatim.openstreetmap.org',
    headers: {
      'User-Agent': 'project_tcr/1.0 (Flutter; kosu-kulubu-app)',
      'Accept-Language': 'tr,en',
    },
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  DateTime? _lastRequestTime;

  /// Nominatim saniyede 1 istek sınırına uyum
  Future<void> _respectRateLimit() async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed < const Duration(milliseconds: 1100)) {
        await Future.delayed(const Duration(milliseconds: 1100) - elapsed);
      }
    }
    _lastRequestTime = DateTime.now();
  }

  /// Mekan adı, mahalle, sokak vb. ile arama yapar
  Future<List<NominatimPlace>> search(String query, {int limit = 5}) async {
    if (query.trim().length < 2) return [];

    await _respectRateLimit();

    try {
      final response = await _dio.get('/search', queryParameters: {
        'q': query.trim(),
        'format': 'json',
        'addressdetails': '1',
        'limit': limit.toString(),
      });

      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((e) => NominatimPlace.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Koordinattan adres çözümler (reverse geocoding)
  Future<String?> reverseGeocode(double lat, double lng) async {
    await _respectRateLimit();

    try {
      final response = await _dio.get('/reverse', queryParameters: {
        'lat': lat.toString(),
        'lon': lng.toString(),
        'format': 'json',
        'addressdetails': '1',
      });

      if (response.statusCode == 200 && response.data is Map) {
        return response.data['display_name'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
