import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/integration_entity.dart';
import '../../domain/repositories/strava_repository.dart';
import '../datasources/strava_remote_datasource.dart';

/// Strava Repository Implementation
class StravaRepositoryImpl implements StravaRepository {
  final StravaRemoteDataSource _remoteDataSource;
  final SupabaseClient _supabaseClient;

  StravaRepositoryImpl({
    required StravaRemoteDataSource remoteDataSource,
    required SupabaseClient supabaseClient,
  })  : _remoteDataSource = remoteDataSource,
        _supabaseClient = supabaseClient;

  String? get _currentUserId => _supabaseClient.auth.currentUser?.id;

  @override
  String getAuthorizationUrl() {
    final authUrl = Uri.https('www.strava.com', '/oauth/authorize', {
      'client_id': AppConstants.stravaClientId,
      'redirect_uri': AppConstants.stravaRedirectUri,
      'response_type': 'code',
      'scope': AppConstants.stravaScopes,
      'approval_prompt': 'auto',
    });
    return authUrl.toString();
  }

  @override
  Future<({IntegrationEntity? integration, Failure? failure})>
      exchangeCodeForToken(String code) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return (
          integration: null,
          failure: const AuthFailure(message: 'Kullanıcı oturumu bulunamadı'),
        );
      }

      // Token al
      final tokenResponse = await _remoteDataSource.exchangeCodeForToken(code);

      // Veritabanına kaydet
      final integration = await _remoteDataSource.saveIntegration(
        userId: userId,
        tokenResponse: tokenResponse,
      );

      return (integration: integration.toEntity(), failure: null);
    } on ServerException catch (e) {
      return (integration: null, failure: ServerFailure(message: e.message));
    } catch (e) {
      return (integration: null, failure: ServerFailure(message: 'Beklenmeyen hata: $e'));
    }
  }

  @override
  Future<({String? accessToken, Failure? failure})> refreshAccessToken(
    String refreshToken,
  ) async {
    try {
      final tokenResponse =
          await _remoteDataSource.refreshAccessToken(refreshToken);

      // Entegrasyonu güncelle
      final userId = _currentUserId;
      if (userId != null) {
        final integration = await _remoteDataSource.getIntegration(userId);
        if (integration != null) {
          await _remoteDataSource.updateIntegration(
            integrationId: integration.id,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenExpiresAt: tokenResponse.expiresAtDateTime,
          );
        }
      }

      return (accessToken: tokenResponse.accessToken, failure: null);
    } on ServerException catch (e) {
      return (accessToken: null, failure: ServerFailure(message: e.message));
    } catch (e) {
      return (accessToken: null, failure: ServerFailure(message: 'Token yenilenemedi: $e'));
    }
  }

  @override
  Future<({IntegrationEntity? integration, Failure? failure})>
      getIntegration() async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return (
          integration: null,
          failure: const AuthFailure(message: 'Kullanıcı oturumu bulunamadı'),
        );
      }

      final integration = await _remoteDataSource.getIntegration(userId);
      if (integration == null) {
        return (integration: null, failure: null);
      }

      return (integration: integration.toEntity(), failure: null);
    } on ServerException catch (e) {
      return (integration: null, failure: ServerFailure(message: e.message));
    } catch (e) {
      return (integration: null, failure: ServerFailure(message: 'Entegrasyon alınamadı: $e'));
    }
  }

  @override
  Future<Failure?> disconnectStrava() async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return const AuthFailure(message: 'Kullanıcı oturumu bulunamadı');
      }

      final integration = await _remoteDataSource.getIntegration(userId);
      if (integration == null) {
        return const ServerFailure(message: 'Strava bağlantısı bulunamadı');
      }

      await _remoteDataSource.deleteIntegration(integration.id);
      return null;
    } on ServerException catch (e) {
      return ServerFailure(message: e.message);
    } catch (e) {
      return ServerFailure(message: 'Bağlantı kaldırılamadı: $e');
    }
  }

  @override
  Future<({List<StravaActivityEntity>? activities, Failure? failure})>
      fetchActivities({
    DateTime? after,
    DateTime? before,
    int page = 1,
    int perPage = 30,
  }) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return (
          activities: null,
          failure: const AuthFailure(message: 'Kullanıcı oturumu bulunamadı'),
        );
      }

      // Entegrasyonu al
      final integration = await _remoteDataSource.getIntegration(userId);
      if (integration == null) {
        return (
          activities: null,
          failure: const ServerFailure(message: 'Strava bağlantısı bulunamadı'),
        );
      }

      // Token süresi dolmuşsa yenile
      String accessToken = integration.accessToken;
      if (integration.tokenExpiresAt != null &&
          integration.tokenExpiresAt!.isBefore(DateTime.now())) {
        if (integration.refreshToken != null) {
          final refreshResult =
              await refreshAccessToken(integration.refreshToken!);
          if (refreshResult.failure != null) {
            return (activities: null, failure: refreshResult.failure);
          }
          accessToken = refreshResult.accessToken!;
        } else {
          return (
            activities: null,
            failure: const ServerFailure(
              message: 'Strava oturumu sona erdi. Lütfen tekrar bağlanın.',
            ),
          );
        }
      }

      // Aktiviteleri çek
      final activities = await _remoteDataSource.getActivities(
        accessToken: accessToken,
        after: after,
        before: before,
        page: page,
        perPage: perPage,
      );

      final entities = activities.map((a) => a.toEntity()).toList();
      
      return (
        activities: entities,
        failure: null,
      );
    } on ServerException catch (e) {
      return (activities: null, failure: ServerFailure(message: e.message));
    } catch (e) {
      return (activities: null, failure: ServerFailure(message: 'Aktiviteler alınamadı: $e'));
    }
  }

  @override
  Future<({int syncedCount, Failure? failure})> syncActivities({
    DateTime? since,
    bool fetchAllPages = false,
  }) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return (
          syncedCount: 0,
          failure: const AuthFailure(message: 'Kullanıcı oturumu bulunamadı'),
        );
      }

      // Entegrasyonu al
      final integration = await _remoteDataSource.getIntegration(userId);
      if (integration == null) {
        return (
          syncedCount: 0,
          failure: const ServerFailure(message: 'Strava bağlantısı bulunamadı'),
        );
      }

      // Tüm geçmiş verileri çekmek için after parametresini null yap
      DateTime? after;
      if (fetchAllPages) {
        // Tüm geçmiş verileri çek - after parametresi null
        after = null;
      } else if (since != null) {
        after = since;
      } else if (integration.lastSyncAt != null) {
        // Son senkronizasyon zamanından sonraki aktiviteleri çek
        after = integration.lastSyncAt!;
      } else {
        // İlk senkronizasyon: son 30 gün
        after = DateTime.now().subtract(const Duration(days: 30));
      }

      // Tüm sayfaları çek
      int syncedCount = 0;
      int page = 1;
      const perPage = 200; // Strava API maksimum sayfa başına 200 aktivite döndürebilir
      bool hasMorePages = true;

      while (hasMorePages) {
        final fetchResult = await fetchActivities(
          after: after,
          page: page,
          perPage: perPage,
        );

        if (fetchResult.failure != null) {
          // İlk sayfada hata varsa durdur, sonraki sayfalarda hata varsa devam et
          if (page == 1) {
            return (syncedCount: 0, failure: fetchResult.failure);
          } else {
            // Sonraki sayfalarda hata varsa durdur (rate limit vb.)
            break;
          }
        }

        final activities = fetchResult.activities ?? [];

        // Eğer aktivite yoksa, daha fazla sayfa yok demektir
        if (activities.isEmpty) {
          hasMorePages = false;
          break;
        }

        // Her aktiviteyi veritabanına kaydet
        for (var i = 0; i < activities.length; i++) {
          final activity = activities[i];
          try {
            await _saveActivityToDatabase(userId, activity);
            syncedCount++;
          } catch (e) {
            // Duplikat veya hata varsa devam et
            continue;
          }
        }

        // Eğer bu sayfada perPage'den az aktivite varsa, son sayfa demektir
        if (activities.length < perPage) {
          hasMorePages = false;
        } else {
          // Bir sonraki sayfaya geç
          page++;
          // Rate limiting için kısa bir bekleme (opsiyonel)
          await Future.delayed(const Duration(milliseconds: 100));
        }

        // fetchAllPages false ise sadece ilk sayfayı çek
        if (!fetchAllPages) {
          hasMorePages = false;
        }
      }

      // Eğer hiç aktivite yoksa, sadece lastSyncAt'i güncelle
      if (syncedCount == 0) {
        try {
          await _remoteDataSource.updateIntegration(
            integrationId: integration.id,
            lastSyncAt: DateTime.now(),
          );
        } catch (e) {
          throw ServerException(message: 'lastSyncAt güncellenemedi: $e');
        }
        return (syncedCount: 0, failure: null);
      }

      // Son senkronizasyon zamanını güncelle
      try {
        await _remoteDataSource.updateIntegration(
          integrationId: integration.id,
          lastSyncAt: DateTime.now(),
        );
      } catch (e) {
        throw ServerException(message: 'lastSyncAt güncellenemedi: $e');
      }

      return (syncedCount: syncedCount, failure: null);
    } on ServerException catch (e) {
      return (syncedCount: 0, failure: ServerFailure(message: e.message));
    } catch (e) {
      return (syncedCount: 0, failure: ServerFailure(message: 'Senkronizasyon başarısız: $e'));
    }
  }

  Future<String?> _saveActivityToDatabase(
    String userId,
    StravaActivityEntity activity,
  ) async {
    // Strava aktivite tipini uygulama tipine dönüştür
    String activityType;
    switch (activity.type.toLowerCase()) {
      case 'run':
      case 'virtualrun':
      case 'trailrun':
        activityType = 'running';
        break;
      case 'walk':
      case 'hike':
        activityType = 'walking';
        break;
      case 'ride':
      case 'virtualride':
      case 'ebikeride':
      case 'mountainbikeride':
      case 'gravelride':
        activityType = 'cycling';
        break;
      case 'swim':
        activityType = 'swimming';
        break;
      case 'weighttraining':
      case 'crossfit':
        activityType = 'strength';
        break;
      case 'yoga':
        activityType = 'yoga';
        break;
      default:
        activityType = 'other';
    }

    // maxSpeed'den best_pace_seconds hesapla (m/s -> saniye/km)
    int? bestPaceSeconds;
    if (activity.maxSpeed != null && activity.maxSpeed! > 0 && activityType == 'running') {
      final kmPerSecond = activity.maxSpeed! / 1000; // m/s -> km/s
      if (kmPerSecond > 0) {
        bestPaceSeconds = (1 / kmPerSecond).round(); // saniye/km
      }
    }

    // end_time hesapla (start_time + elapsed_time)
    final endTime = activity.startDate.add(Duration(seconds: activity.elapsedTime));

    // Ekstra metadata (start/end koordinatları, sosyal metrikler vb.)
    final metadata = <String, dynamic>{};
    if (activity.startLatlng != null) {
      metadata['start_latlng'] = activity.startLatlng;
    }
    if (activity.endLatlng != null) {
      metadata['end_latlng'] = activity.endLatlng;
    }
    // Sosyal metrikler (Strava'dan gelen) - şimdilik kullanılmıyor
    // Not: Strava model'inde bu alanlar var ama entity'ye aktarılmıyor
    // İleride entity'ye eklenebilir

    final data = {
      'user_id': userId,
      'activity_type': activityType,
      'source': 'strava',
      'external_id': activity.id.toString(),
      'title': activity.name,
      'start_time': activity.startDate.toIso8601String(),
      'end_time': endTime.toIso8601String(), // Bitiş zamanı eklendi
      'duration_seconds': activity.movingTime, // Moving time (aktif süre)
      'distance_meters': activity.distance,
      'elevation_gain': activity.totalElevationGain,
      'average_pace_seconds': activity.averagePaceSeconds,
      'best_pace_seconds': bestPaceSeconds, // Max speed'den hesaplanan en iyi pace
      'average_heart_rate': activity.averageHeartrate?.round(),
      'max_heart_rate': activity.maxHeartrate?.round(),
      'average_cadence': activity.averageCadence?.round(),
      'route_polyline': activity.mapPolyline,
      'calories_burned': activity.calories?.round(),
      'is_public': true,
      // Ekstra metadata'yı weather_conditions alanına ekliyoruz (geçici çözüm)
      // İleride ayrı bir metadata JSONB alanı eklenebilir
      'weather_conditions': metadata.isNotEmpty ? metadata : null,
    };

    // Önce mevcut aktiviteyi kontrol et
    final existing = await _supabaseClient
        .from('activities')
        .select('id')
        .eq('user_id', userId)
        .eq('source', 'strava')
        .eq('external_id', activity.id.toString())
        .maybeSingle();

    if (existing != null) {
      // Mevcut aktiviteyi güncelle
      await _supabaseClient
          .from('activities')
          .update(data)
          .eq('id', existing['id'] as String);
      return existing['id'] as String;
    } else {
      // Yeni aktivite ekle
      final response = await _supabaseClient
          .from('activities')
          .insert(data)
          .select('id')
          .single();
      return response['id'] as String;
    }
  }

  /// Splits'leri veritabanına kaydet
  Future<void> _saveSplitsToDatabase(
    String activityId,
    List<StravaSplitEntity> splits,
  ) async {
    if (splits.isEmpty) return;

    
    // Önce mevcut splits'leri sil
    await _supabaseClient
        .from('activity_splits')
        .delete()
        .eq('activity_id', activityId);

    // Yeni splits'leri ekle
    final splitsData = splits.map((split) {
      return {
        'activity_id': activityId,
        'split_number': split.split,
        'distance_meters': split.distance,
        'duration_seconds': split.movingTime,
        'pace_seconds': split.paceSeconds,
        'elevation_change': split.elevationDifference,
        'average_heart_rate': split.averageHeartrate?.round(),
      };
    }).toList();

    if (splitsData.isNotEmpty) {
      await _supabaseClient.from('activity_splits').insert(splitsData);
    }
  }

  @override
  Future<Failure?> updateLastSyncTime() async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return const AuthFailure(message: 'Kullanıcı oturumu bulunamadı');
      }

      final integration = await _remoteDataSource.getIntegration(userId);
      if (integration == null) {
        return const ServerFailure(message: 'Strava bağlantısı bulunamadı');
      }

      await _remoteDataSource.updateIntegration(
        integrationId: integration.id,
        lastSyncAt: DateTime.now(),
      );

      return null;
    } on ServerException catch (e) {
      return ServerFailure(message: e.message);
    } catch (e) {
      return ServerFailure(message: 'Güncelleme başarısız: $e');
    }
  }

  @override
  Future<Failure?> toggleSync(bool enabled) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return const AuthFailure(message: 'Kullanıcı oturumu bulunamadı');
      }

      final integration = await _remoteDataSource.getIntegration(userId);
      if (integration == null) {
        return const ServerFailure(message: 'Strava bağlantısı bulunamadı');
      }

      await _remoteDataSource.updateIntegration(
        integrationId: integration.id,
        syncEnabled: enabled,
      );

      return null;
    } on ServerException catch (e) {
      return ServerFailure(message: e.message);
    } catch (e) {
      return ServerFailure(message: 'Güncelleme başarısız: $e');
    }
  }

  @override
  Future<({StravaActivityDetailEntity? detail, Failure? failure})> fetchActivityDetail({
    required int activityId,
  }) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return (
          detail: null,
          failure: const AuthFailure(message: 'Kullanıcı oturumu bulunamadı'),
        );
      }

      // Entegrasyonu al
      final integration = await _remoteDataSource.getIntegration(userId);
      if (integration == null) {
        return (
          detail: null,
          failure: const ServerFailure(message: 'Strava bağlantısı bulunamadı'),
        );
      }

      // Token süresi dolmuşsa yenile
      String accessToken = integration.accessToken;
      if (integration.tokenExpiresAt != null &&
          integration.tokenExpiresAt!.isBefore(DateTime.now())) {
        if (integration.refreshToken != null) {
          final refreshResult = await refreshAccessToken(integration.refreshToken!);
          if (refreshResult.failure != null) {
            return (detail: null, failure: refreshResult.failure);
          }
          accessToken = refreshResult.accessToken!;
        } else {
          return (
            detail: null,
            failure: const ServerFailure(
              message: 'Strava oturumu sona erdi. Lütfen tekrar bağlanın.',
            ),
          );
        }
      }

      // Detaylı aktivite bilgisini çek
      try {
        final detailModel = await _remoteDataSource.getActivityDetail(
          accessToken: accessToken,
          activityId: activityId,
        );

        // Splits'leri veritabanına kaydet
        if (detailModel.splits.isNotEmpty) {
          // Önce aktivite ID'sini bul (external_id ile)
          final activityRecord = await _supabaseClient
              .from('activities')
              .select('id')
              .eq('external_id', activityId.toString())
              .eq('source', 'strava')
              .maybeSingle();
          
          if (activityRecord != null) {
            final activityDbId = activityRecord['id'] as String;
            await _saveSplitsToDatabase(activityDbId, detailModel.splits.map((s) => s.toEntity()).toList());
          } else {
          }
        }

        final detailEntity = detailModel.toEntity();
        return (detail: detailEntity, failure: null);
      } on ServerException catch (e) {
        // 404 (NOT_FOUND) - Aktivite detayı yoksa, bu normal bir durum
        if (e.message == 'NOT_FOUND') {
          return (detail: null, failure: null); // Hata değil, sadece veri yok
        }
        // Diğer hatalar için yukarı fırlat
        rethrow;
      } catch (e) {
        return (detail: null, failure: ServerFailure(message: 'Aktivite detayı alınamadı: $e'));
      }
    } on ServerException catch (e) {
      return (detail: null, failure: ServerFailure(message: e.message));
    } catch (e) {
      return (detail: null, failure: ServerFailure(message: 'Aktivite detayı alınamadı: $e'));
    }
  }

  @override
  Future<({List<StravaHeartZoneEntity>? zones, Failure? failure})> fetchActivityZones({
    required int activityId,
  }) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return (
          zones: null,
          failure: const AuthFailure(message: 'Kullanıcı oturumu bulunamadı'),
        );
      }

      // Entegrasyonu al
      final integration = await _remoteDataSource.getIntegration(userId);
      if (integration == null) {
        return (
          zones: null,
          failure: const ServerFailure(message: 'Strava bağlantısı bulunamadı'),
        );
      }

      // Token süresi dolmuşsa yenile
      String accessToken = integration.accessToken;
      if (integration.tokenExpiresAt != null &&
          integration.tokenExpiresAt!.isBefore(DateTime.now())) {
        if (integration.refreshToken != null) {
          final refreshResult = await refreshAccessToken(integration.refreshToken!);
          if (refreshResult.failure != null) {
            return (zones: null, failure: refreshResult.failure);
          }
          accessToken = refreshResult.accessToken!;
        } else {
          return (
            zones: null,
            failure: const ServerFailure(
              message: 'Strava oturumu sona erdi. Lütfen tekrar bağlanın.',
            ),
          );
        }
      }

      // Heart zones çek
      try {
        final zonesModels = await _remoteDataSource.getActivityZones(
          accessToken: accessToken,
          activityId: activityId,
        );

        final zonesEntities = zonesModels.map((z) => z.toEntity()).toList();
        return (zones: zonesEntities, failure: null);
      } on ServerException catch (e) {
        // 404 (Record Not Found) - Heart zones yoksa, bu normal bir durum, boş liste döndür
        if (e.message.contains('NOT_FOUND') || e.message.contains('Record Not Found')) {
          return (zones: <StravaHeartZoneEntity>[], failure: null); // Hata değil, sadece veri yok
        }
        return (zones: null, failure: ServerFailure(message: e.message));
      }
    } on ServerException catch (e) {
      // 404 durumunda boş liste döndür
      if (e.message.contains('NOT_FOUND') || e.message.contains('Record Not Found')) {
        return (zones: <StravaHeartZoneEntity>[], failure: null);
      }
      return (zones: null, failure: ServerFailure(message: e.message));
    } catch (e) {
      return (zones: null, failure: ServerFailure(message: 'Heart zones alınamadı: $e'));
    }
  }

  @override
  Future<({bool success, Failure? failure})> importSingleActivity({
    required StravaActivityEntity activity,
  }) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return (
          success: false,
          failure: const AuthFailure(message: 'Kullanıcı oturumu bulunamadı'),
        );
      }

      await _saveActivityToDatabase(userId, activity);
      return (success: true, failure: null);
    } catch (e) {
      return (
        success: false,
        failure: ServerFailure(message: 'Aktivite import edilemedi: $e'),
      );
    }
  }

  @override
  Future<({Set<String>? importedActivityIds, Failure? failure})> checkImportedActivities({
    required List<StravaActivityEntity> activities,
  }) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return (
          importedActivityIds: null,
          failure: const AuthFailure(message: 'Kullanıcı oturumu bulunamadı'),
        );
      }

      if (activities.isEmpty) {
        return (importedActivityIds: <String>{}, failure: null);
      }

      // Tüm external_id'leri topla
      final externalIds = activities.map((a) => a.id.toString()).toList();

      // Veritabanında hangileri var kontrol et
      final response = await _supabaseClient
          .from('activities')
          .select('external_id')
          .eq('user_id', userId)
          .eq('source', 'strava')
          .inFilter('external_id', externalIds);

      final importedIds = (response as List)
          .map((item) => item['external_id'] as String)
          .toSet();

      return (importedActivityIds: importedIds, failure: null);
    } catch (e) {
      return (
        importedActivityIds: null,
        failure: ServerFailure(message: 'Import durumu kontrol edilemedi: $e'),
      );
    }
  }
}
