import 'package:dio/dio.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/integration_model.dart';
import '../models/strava_models.dart';

/// Strava Remote Data Source Interface
abstract class StravaRemoteDataSource {
  /// Strava OAuth başlat ve authorization code al
  Future<String> authenticate();

  /// Authorization code ile token al
  Future<StravaTokenResponse> exchangeCodeForToken(String code);

  /// Access token'ı yenile
  Future<StravaRefreshTokenResponse> refreshAccessToken(String refreshToken);

  /// Strava'dan aktiviteleri çek
  Future<List<StravaActivityModel>> getActivities({
    required String accessToken,
    DateTime? after,
    DateTime? before,
    int page = 1,
    int perPage = 30,
  });

  /// Strava'dan detaylı aktivite bilgisi çek (splits, best efforts vb.)
  Future<StravaActivityDetailModel> getActivityDetail({
    required String accessToken,
    required int activityId,
  });

  /// Strava'dan aktivite heart rate zones çek
  Future<List<StravaHeartZoneModel>> getActivityZones({
    required String accessToken,
    required int activityId,
  });

  /// Kullanıcının entegrasyonunu veritabanına kaydet
  Future<IntegrationModel> saveIntegration({
    required String userId,
    required StravaTokenResponse tokenResponse,
  });

  /// Kullanıcının Strava entegrasyonunu getir
  Future<IntegrationModel?> getIntegration(String userId);

  /// Entegrasyonu güncelle
  Future<IntegrationModel> updateIntegration({
    required String integrationId,
    String? accessToken,
    String? refreshToken,
    DateTime? tokenExpiresAt,
    DateTime? lastSyncAt,
    bool? syncEnabled,
  });

  /// Entegrasyonu sil
  Future<void> deleteIntegration(String integrationId);
}

/// Strava Remote Data Source Implementation
class StravaRemoteDataSourceImpl implements StravaRemoteDataSource {
  final SupabaseClient _supabaseClient;
  final Dio _dio;

  StravaRemoteDataSourceImpl({
    required SupabaseClient supabaseClient,
    Dio? dio,
  })  : _supabaseClient = supabaseClient,
        _dio = dio ?? Dio();

  @override
  Future<String> authenticate() async {
    try {
      final authUrl = Uri.https('www.strava.com', '/oauth/authorize', {
        'client_id': AppConstants.stravaClientId,
        'redirect_uri': AppConstants.stravaRedirectUri,
        'response_type': 'code',
        'scope': AppConstants.stravaScopes,
        'approval_prompt': 'auto',
      });

      final result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: 'tcr',
      );

      final uri = Uri.parse(result);
      final code = uri.queryParameters['code'];
      final error = uri.queryParameters['error'];

      if (error != null) {
        throw ServerException(message: 'Strava yetkilendirme hatası: $error');
      }

      if (code == null || code.isEmpty) {
        throw const ServerException(message: 'Yetkilendirme kodu alınamadı');
      }

      return code;
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException(message: 'Strava yetkilendirme başarısız: $e');
    }
  }

  @override
  Future<StravaTokenResponse> exchangeCodeForToken(String code) async {
    try {
      final response = await _dio.post(
        AppConstants.stravaTokenUrl,
        data: {
          'client_id': AppConstants.stravaClientId,
          'client_secret': AppConstants.stravaClientSecret,
          'code': code,
          'grant_type': 'authorization_code',
        },
      );

      if (response.statusCode == 200) {
        return StravaTokenResponse.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw ServerException(
          message: 'Token alınamadı: ${response.statusMessage}',
        );
      }
    } on DioException catch (e) {
      throw ServerException(
        message: 'Token exchange hatası: ${e.response?.data?['message'] ?? e.message}',
      );
    }
  }

  @override
  Future<StravaRefreshTokenResponse> refreshAccessToken(String refreshToken) async {
    try {
      final response = await _dio.post(
        AppConstants.stravaTokenUrl,
        data: {
          'client_id': AppConstants.stravaClientId,
          'client_secret': AppConstants.stravaClientSecret,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      );

      if (response.statusCode == 200) {
        return StravaRefreshTokenResponse.fromJson(
          response.data as Map<String, dynamic>,
        );
      } else {
        throw ServerException(
          message: 'Token yenilenemedi: ${response.statusMessage}',
        );
      }
    } on DioException catch (e) {
      throw ServerException(
        message: 'Token refresh hatası: ${e.response?.data?['message'] ?? e.message}',
      );
    }
  }

  @override
  Future<List<StravaActivityModel>> getActivities({
    required String accessToken,
    DateTime? after,
    DateTime? before,
    int page = 1,
    int perPage = 30,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };

      if (after != null) {
        queryParams['after'] = after.millisecondsSinceEpoch ~/ 1000;
      }
      if (before != null) {
        queryParams['before'] = before.millisecondsSinceEpoch ~/ 1000;
      }

      final response = await _dio.get(
        '${AppConstants.stravaApiUrl}/athlete/activities',
        queryParameters: queryParams,
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        if (response.data == null) {
          return [];
        }
        
        if (response.data is! List) {
          throw ServerException(
            message: 'Aktiviteler alınamadı: Beklenmeyen response formatı',
          );
        }
        
        final dataList = response.data as List;
        
        final activities = dataList
            .map((json) {
              try {
                return StravaActivityModel.fromJson(json as Map<String, dynamic>);
              } catch (e) {
                rethrow;
              }
            })
            .toList();
        return activities;
      } else {
        throw ServerException(
          message: 'Aktiviteler alınamadı: ${response.statusMessage}',
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const ServerException(message: 'Strava oturumu sona erdi. Lütfen tekrar bağlanın.');
      }
      throw ServerException(
        message: 'Aktivite çekme hatası: ${e.response?.data?['message'] ?? e.message}',
      );
    }
  }

  @override
  Future<IntegrationModel> saveIntegration({
    required String userId,
    required StravaTokenResponse tokenResponse,
  }) async {
    try {
      final now = DateTime.now();
      final data = {
        'user_id': userId,
        'provider': 'strava',
        'provider_user_id': tokenResponse.athlete.id.toString(),
        'access_token': tokenResponse.accessToken,
        'refresh_token': tokenResponse.refreshToken,
        'token_expires_at': tokenResponse.expiresAtDateTime.toIso8601String(),
        'scopes': AppConstants.stravaScopes.split(','),
        'athlete_data': tokenResponse.athlete.toJson(),
        'connected_at': now.toIso8601String(),
        'sync_enabled': true,
      };

      final response = await _supabaseClient
          .from('user_integrations')
          .upsert(data, onConflict: 'user_id,provider')
          .select()
          .single();

      return IntegrationModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: 'Entegrasyon kaydedilemedi: ${e.message}');
    }
  }

  @override
  Future<IntegrationModel?> getIntegration(String userId) async {
    try {
      final response = await _supabaseClient
          .from('user_integrations')
          .select()
          .eq('user_id', userId)
          .eq('provider', 'strava')
          .maybeSingle();

      if (response == null) return null;
      return IntegrationModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: 'Entegrasyon alınamadı: ${e.message}');
    }
  }

  @override
  Future<IntegrationModel> updateIntegration({
    required String integrationId,
    String? accessToken,
    String? refreshToken,
    DateTime? tokenExpiresAt,
    DateTime? lastSyncAt,
    bool? syncEnabled,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (accessToken != null) data['access_token'] = accessToken;
      if (refreshToken != null) data['refresh_token'] = refreshToken;
      if (tokenExpiresAt != null) {
        data['token_expires_at'] = tokenExpiresAt.toIso8601String();
      }
      if (lastSyncAt != null) {
        data['last_sync_at'] = lastSyncAt.toIso8601String();
      }
      if (syncEnabled != null) data['sync_enabled'] = syncEnabled;

      final response = await _supabaseClient
          .from('user_integrations')
          .update(data)
          .eq('id', integrationId)
          .select()
          .maybeSingle();

      
      if (response == null) {
        throw ServerException(message: 'Entegrasyon güncellenemedi: Kayıt bulunamadı');
      }

      return IntegrationModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: 'Entegrasyon güncellenemedi: ${e.message}');
    }
  }

  @override
  Future<void> deleteIntegration(String integrationId) async {
    try {
      await _supabaseClient
          .from('user_integrations')
          .delete()
          .eq('id', integrationId);
    } on PostgrestException catch (e) {
      throw ServerException(message: 'Entegrasyon silinemedi: ${e.message}');
    }
  }

  @override
  Future<StravaActivityDetailModel> getActivityDetail({
    required String accessToken,
    required int activityId,
  }) async {
    try {
      final response = await _dio.get(
        '${AppConstants.stravaApiUrl}/activities/$activityId',
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        return StravaActivityDetailModel.fromJson(
          response.data as Map<String, dynamic>,
        );
      } else {
        throw ServerException(
          message: 'Aktivite detayı alınamadı: ${response.statusMessage}',
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const ServerException(message: 'Strava oturumu sona erdi. Lütfen tekrar bağlanın.');
      }
      // 404 (Record Not Found) - Aktivite detayı yoksa, bu normal bir durum
      if (e.response?.statusCode == 404) {
        throw const ServerException(message: 'NOT_FOUND'); // Özel mesaj ile işaretle
      }
      throw ServerException(
        message: 'Aktivite detayı çekme hatası: ${e.response?.data?['message'] ?? e.message}',
      );
    }
  }

  @override
  Future<List<StravaHeartZoneModel>> getActivityZones({
    required String accessToken,
    required int activityId,
  }) async {
    try {
      final response = await _dio.get(
        '${AppConstants.stravaApiUrl}/activities/$activityId/zones',
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        // Strava zones endpoint'i farklı formatlar döndürebilir
        // distribution_buckets veya doğrudan zone listesi
        if (response.data is Map) {
          final dataMap = response.data as Map<String, dynamic>;
          // distribution_buckets formatı
          if (dataMap.containsKey('distribution_buckets')) {
            final buckets = dataMap['distribution_buckets'] as List<dynamic>?;
            if (buckets != null) {
              return buckets
                  .map((json) => StravaHeartZoneModel.fromJson(json as Map<String, dynamic>))
                  .toList();
            }
          }
          // Heart rate zones formatı
          if (dataMap.containsKey('heart_rate')) {
            final heartRate = dataMap['heart_rate'] as Map<String, dynamic>?;
            if (heartRate != null && heartRate.containsKey('zones')) {
              final zones = heartRate['zones'] as List<dynamic>?;
              if (zones != null) {
                return zones
                    .map((json) => StravaHeartZoneModel.fromJson(json as Map<String, dynamic>))
                    .toList();
              }
            }
          }
        } else if (response.data is List) {
          // Liste formatı - her eleman bir zone tipi (heartrate, pace, power)
          // Heart rate zones için type: "heartrate" olanı bul
          final data = response.data as List<dynamic>;
          for (var zoneType in data) {
            if (zoneType is Map<String, dynamic>) {
              final type = zoneType['type'] as String?;
              if (type == 'heartrate' && zoneType.containsKey('distribution_buckets')) {
                final buckets = zoneType['distribution_buckets'] as List<dynamic>?;
                if (buckets != null && buckets.isNotEmpty) {
                  return buckets
                      .map((json) => StravaHeartZoneModel.fromJson(json as Map<String, dynamic>))
                      .toList();
                }
              }
            }
          }
          // Eğer heartrate zones bulunamadıysa, boş liste döndür
          return [];
        }
        
        return [];
      } else {
        throw ServerException(
          message: 'Heart zones alınamadı: ${response.statusMessage}',
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const ServerException(message: 'Strava oturumu sona erdi. Lütfen tekrar bağlanın.');
      }
      // 404 (Record Not Found) - Heart zones yoksa, bu normal bir durum, boş liste döndür
      if (e.response?.statusCode == 404) {
        return [];
      }
      throw ServerException(
        message: 'Heart zones çekme hatası: ${e.response?.data?['message'] ?? e.message}',
      );
    } catch (e) {
      // Parse hatası olsa bile boş liste döndür (kritik değil)
      return [];
    }
  }
}
