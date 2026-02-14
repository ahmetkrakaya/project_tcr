import '../../../../core/errors/failures.dart';
import '../entities/integration_entity.dart';

/// Strava Repository Interface
abstract class StravaRepository {
  /// Strava OAuth URL'i oluştur
  String getAuthorizationUrl();

  /// Authorization code ile token al
  Future<({IntegrationEntity? integration, Failure? failure})> exchangeCodeForToken(
    String code,
  );

  /// Access token'ı yenile
  Future<({String? accessToken, Failure? failure})> refreshAccessToken(
    String refreshToken,
  );

  /// Kullanıcının Strava entegrasyonunu getir
  Future<({IntegrationEntity? integration, Failure? failure})> getIntegration();

  /// Strava bağlantısını kaldır
  Future<Failure?> disconnectStrava();

  /// Strava'dan aktiviteleri çek
  Future<({List<StravaActivityEntity>? activities, Failure? failure})> fetchActivities({
    DateTime? after,
    DateTime? before,
    int page = 1,
    int perPage = 30,
  });

  /// Aktiviteleri veritabanına senkronize et
  Future<({int syncedCount, Failure? failure})> syncActivities({
    DateTime? since,
    bool fetchAllPages = false,
  });

  /// Son senkronizasyon zamanını güncelle
  Future<Failure?> updateLastSyncTime();

  /// Senkronizasyonu etkinleştir/devre dışı bırak
  Future<Failure?> toggleSync(bool enabled);

  /// Strava'dan detaylı aktivite bilgisi çek (splits, best efforts vb.)
  Future<({StravaActivityDetailEntity? detail, Failure? failure})> fetchActivityDetail({
    required int activityId,
  });

  /// Strava'dan aktivite heart rate zones çek
  Future<({List<StravaHeartZoneEntity>? zones, Failure? failure})> fetchActivityZones({
    required int activityId,
  });

  /// Tek bir aktiviteyi import et
  Future<({bool success, Failure? failure})> importSingleActivity({
    required StravaActivityEntity activity,
  });

  /// Aktivitelerin import durumunu kontrol et (hangi aktiviteler import edilmiş)
  Future<({Set<String>? importedActivityIds, Failure? failure})> checkImportedActivities({
    required List<StravaActivityEntity> activities,
  });
}
