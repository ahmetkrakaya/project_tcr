import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../data/datasources/strava_remote_datasource.dart';
import '../../data/repositories/strava_repository_impl.dart';
import '../../domain/entities/integration_entity.dart';
import '../../domain/repositories/strava_repository.dart';

/// Strava Remote Data Source Provider
final stravaRemoteDataSourceProvider = Provider<StravaRemoteDataSource>((ref) {
  final supabaseClient = ref.watch(supabaseClientProvider);
  return StravaRemoteDataSourceImpl(supabaseClient: supabaseClient);
});

/// Strava Repository Provider
final stravaRepositoryProvider = Provider<StravaRepository>((ref) {
  final remoteDataSource = ref.watch(stravaRemoteDataSourceProvider);
  final supabaseClient = ref.watch(supabaseClientProvider);
  return StravaRepositoryImpl(
    remoteDataSource: remoteDataSource,
    supabaseClient: supabaseClient,
  );
});

/// Strava Integration State
class StravaState {
  final IntegrationEntity? integration;
  final bool isLoading;
  final bool isSyncing;
  final String? error;
  final int? lastSyncCount;

  const StravaState({
    this.integration,
    this.isLoading = false,
    this.isSyncing = false,
    this.error,
    this.lastSyncCount,
  });

  bool get isConnected => integration != null;

  StravaState copyWith({
    IntegrationEntity? integration,
    bool? isLoading,
    bool? isSyncing,
    String? error,
    int? lastSyncCount,
    bool clearError = false,
    bool clearIntegration = false,
  }) {
    return StravaState(
      integration: clearIntegration ? null : (integration ?? this.integration),
      isLoading: isLoading ?? this.isLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      error: clearError ? null : (error ?? this.error),
      lastSyncCount: lastSyncCount ?? this.lastSyncCount,
    );
  }
}

/// Strava Notifier
class StravaNotifier extends StateNotifier<StravaState> {
  final StravaRepository _repository;

  StravaNotifier(this._repository) : super(const StravaState()) {
    // İlk yüklemede entegrasyonu kontrol et
    loadIntegration();
  }

  /// Mevcut entegrasyonu yükle
  Future<void> loadIntegration() async {
    state = state.copyWith(isLoading: true, clearError: true);

    final result = await _repository.getIntegration();

    if (result.failure != null) {
      state = state.copyWith(
        isLoading: false,
        error: result.failure!.message,
      );
      return;
    }

    state = state.copyWith(
      isLoading: false,
      integration: result.integration,
      clearIntegration: result.integration == null,
    );
  }

  /// Strava'ya bağlan
  Future<bool> connectStrava() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // OAuth akışını başlat
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
        state = state.copyWith(
          isLoading: false,
          error: 'Strava yetkilendirme hatası: $error',
        );
        return false;
      }

      if (code == null || code.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'Yetkilendirme kodu alınamadı',
        );
        return false;
      }

      // Token exchange
      final exchangeResult = await _repository.exchangeCodeForToken(code);

      if (exchangeResult.failure != null) {
        state = state.copyWith(
          isLoading: false,
          error: exchangeResult.failure!.message,
        );
        return false;
      }

      state = state.copyWith(
        isLoading: false,
        integration: exchangeResult.integration,
      );

      // İlk senkronizasyonu başlat
      await syncActivities();

      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Bağlantı hatası: $e',
      );
      return false;
    }
  }

  /// Yetkilendirme kodu ile bağlan (Android WebView akışından gelen code için).
  Future<bool> connectStravaWithCode(String code) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final exchangeResult = await _repository.exchangeCodeForToken(code);

      if (exchangeResult.failure != null) {
        state = state.copyWith(
          isLoading: false,
          error: exchangeResult.failure!.message,
        );
        return false;
      }

      state = state.copyWith(
        isLoading: false,
        integration: exchangeResult.integration,
      );

      await syncActivities();
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Bağlantı hatası: $e',
      );
      return false;
    }
  }

  /// Strava bağlantısını kaldır
  Future<bool> disconnectStrava() async {
    state = state.copyWith(isLoading: true, clearError: true);

    final failure = await _repository.disconnectStrava();

    if (failure != null) {
      state = state.copyWith(
        isLoading: false,
        error: failure.message,
      );
      return false;
    }

    state = state.copyWith(
      isLoading: false,
      clearIntegration: true,
    );
    return true;
  }

  /// Strava'dan aktiviteleri çek (liste görünümü için)
  Future<({List<StravaActivityEntity>? activities, Failure? failure})> fetchActivities({
    DateTime? after,
    DateTime? before,
    int page = 1,
    int perPage = 30,
  }) async {
    if (state.integration == null) {
      return (
        activities: null,
        failure: const ServerFailure(message: 'Strava bağlantısı bulunamadı'),
      );
    }

    final result = await _repository.fetchActivities(
      after: after,
      before: before,
      page: page,
      perPage: perPage,
    );

    return result;
  }

  /// Aktiviteleri senkronize et
  Future<bool> syncActivities({bool forceFullSync = false}) async {
    if (state.integration == null) {
      return false;
    }

    state = state.copyWith(isSyncing: true, clearError: true);

    final result = await _repository.syncActivities(
      since: forceFullSync ? null : null, // forceFullSync true ise tüm geçmiş verileri çek (since: null)
      fetchAllPages: forceFullSync, // Tüm sayfaları çek
    );

    if (result.failure != null) {
      state = state.copyWith(
        isSyncing: false,
        error: result.failure!.message,
      );
      return false;
    }

    // Entegrasyonu yeniden yükle (lastSyncAt güncellendi)
    await loadIntegration();

    state = state.copyWith(
      isSyncing: false,
      lastSyncCount: result.syncedCount,
    );

    return true;
  }

  /// Senkronizasyonu etkinleştir/devre dışı bırak
  Future<bool> toggleSync(bool enabled) async {
    final failure = await _repository.toggleSync(enabled);

    if (failure != null) {
      state = state.copyWith(error: failure.message);
      return false;
    }

    // Entegrasyonu yeniden yükle
    await loadIntegration();
    return true;
  }

  /// Hatayı temizle
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// OAuth akışından dönen hata mesajını set eder (örn. Android WebView iptal/hata).
  void setAuthError(String message) {
    state = state.copyWith(isLoading: false, error: message);
  }

  /// Detaylı aktivite bilgisi çek (splits, best efforts vb.)
  Future<StravaActivityDetailEntity?> fetchActivityDetail(int activityId) async {
    final result = await _repository.fetchActivityDetail(activityId: activityId);
    
    if (result.failure != null) {
      return null;
    }
    
    return result.detail;
  }

  /// Heart rate zones çek
  Future<List<StravaHeartZoneEntity>> fetchActivityZones(int activityId) async {
    final result = await _repository.fetchActivityZones(activityId: activityId);
    
    if (result.failure != null) {
      return [];
    }
    
    return result.zones ?? [];
  }

  /// Tek bir aktiviteyi import et
  Future<bool> importSingleActivity(StravaActivityEntity activity) async {
    final result = await _repository.importSingleActivity(activity: activity);
    if (result.failure != null) {
      state = state.copyWith(error: result.failure!.message);
      return false;
    }
    return result.success;
  }

  /// Aktivitelerin import durumunu kontrol et
  Future<Set<String>?> checkImportedActivities(List<StravaActivityEntity> activities) async {
    final result = await _repository.checkImportedActivities(activities: activities);
    if (result.failure != null) {
      state = state.copyWith(error: result.failure!.message);
      return null;
    }
    return result.importedActivityIds;
  }
}

/// Strava Notifier Provider (cached)
final stravaNotifierProvider =
    StateNotifierProvider<StravaNotifier, StravaState>((ref) {
  ref.keepAlive(); // Bellekte tut - sayfa geçişlerinde yeniden yükleme yapma
  final repository = ref.watch(stravaRepositoryProvider);
  return StravaNotifier(repository);
});

/// Strava bağlantı durumu
final isStravaConnectedProvider = Provider<bool>((ref) {
  final state = ref.watch(stravaNotifierProvider);
  return state.isConnected;
});

/// Strava entegrasyonu
final stravaIntegrationProvider = Provider<IntegrationEntity?>((ref) {
  final state = ref.watch(stravaNotifierProvider);
  return state.integration;
});

/// Strava Aktivite Listesi State
class StravaActivityListState {
  final List<StravaActivityEntity> activities;
  final Set<String> importedIds;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final int page;
  final bool hasMore;

  const StravaActivityListState({
    this.activities = const [],
    this.importedIds = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.page = 1,
    this.hasMore = true,
  });

  StravaActivityListState copyWith({
    List<StravaActivityEntity>? activities,
    Set<String>? importedIds,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    int? page,
    bool? hasMore,
    bool clearError = false,
    bool clearActivities = false,
  }) {
    return StravaActivityListState(
      activities: clearActivities ? const [] : (activities ?? this.activities),
      importedIds: importedIds ?? this.importedIds,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

/// Strava Aktivite Listesi Notifier (cached)
class StravaActivityListNotifier extends StateNotifier<StravaActivityListState> {
  final StravaNotifier _stravaNotifier;

  StravaActivityListNotifier(this._stravaNotifier) : super(const StravaActivityListState());

  /// Aktiviteleri yükle (ilk yükleme veya refresh)
  Future<void> loadActivities({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;

    state = state.copyWith(
      isLoading: true,
      error: null,
      page: refresh ? 1 : state.page,
      clearActivities: refresh,
    );

    try {
      final result = await _stravaNotifier.fetchActivities(
        page: refresh ? 1 : state.page,
        perPage: 30,
      );

      if (result.failure != null) {
        state = state.copyWith(
          isLoading: false,
          error: result.failure!.message,
        );
        return;
      }

      final all = result.activities ?? [];
      final activities = all.where((a) => _isStravaRunningType(a.type)).toList();

      state = state.copyWith(
        activities: refresh ? activities : [...state.activities, ...activities],
        isLoading: false,
        hasMore: all.length >= 30,
        page: all.isNotEmpty ? (refresh ? 2 : state.page + 1) : state.page,
      );

      // Import durumunu arka planda kontrol et
      if (activities.isNotEmpty) {
        _checkImportedStatusInBackground(activities);
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Aktiviteler yüklenemedi: $e',
      );
    }
  }

  /// Daha fazla aktivite yükle (pagination)
  Future<void> loadMoreActivities() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final result = await _stravaNotifier.fetchActivities(
        page: state.page,
        perPage: 30,
      );

      if (result.failure != null) {
        state = state.copyWith(
          isLoadingMore: false,
          error: result.failure!.message,
        );
        return;
      }

      final all = result.activities ?? [];
      final activities = all.where((a) => _isStravaRunningType(a.type)).toList();

      state = state.copyWith(
        activities: [...state.activities, ...activities],
        isLoadingMore: false,
        hasMore: all.length >= 30,
        page: all.isNotEmpty ? state.page + 1 : state.page,
      );

      // Import durumunu arka planda kontrol et
      if (activities.isNotEmpty) {
        _checkImportedStatusInBackground(activities);
      }
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: 'Aktiviteler yüklenemedi: $e',
      );
    }
  }

  /// Import durumunu arka planda kontrol et
  Future<void> _checkImportedStatusInBackground(List<StravaActivityEntity> activities) async {
    try {
      final importedResult = await _stravaNotifier.checkImportedActivities(activities);
      if (importedResult != null) {
        state = state.copyWith(
          importedIds: {...state.importedIds, ...importedResult},
        );
      }
    } catch (e) {
      // Sessizce hata yok say
    }
  }

  /// Tek bir aktiviteyi import et
  Future<bool> importActivity(StravaActivityEntity activity) async {
    final success = await _stravaNotifier.importSingleActivity(activity);
    if (success) {
      state = state.copyWith(
        importedIds: {...state.importedIds, activity.id.toString()},
      );
    }
    return success;
  }

  /// Refresh (yeniden yükle)
  Future<void> refresh() async {
    await loadActivities(refresh: true);
  }
}

/// Strava'da koşu sayılan aktivite tipleri (sadece bunlar uygulamada listelenir)
bool _isStravaRunningType(String type) {
  final t = type.toLowerCase().replaceAll(' ', '');
  return t == 'run' || t == 'virtualrun' || t == 'trailrun';
}

/// Strava Aktivite Listesi Provider (cached)
final stravaActivityListProvider =
    StateNotifierProvider<StravaActivityListNotifier, StravaActivityListState>((ref) {
  ref.keepAlive(); // Bellekte tut - sayfa geçişlerinde cache'lenmiş verileri kullan
  final stravaNotifier = ref.watch(stravaNotifierProvider.notifier);
  return StravaActivityListNotifier(stravaNotifier);
});
