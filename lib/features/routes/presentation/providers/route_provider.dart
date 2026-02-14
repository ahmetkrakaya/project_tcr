import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/route_remote_datasource.dart';
import '../../domain/entities/route_entity.dart';

/// Supabase client provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Route datasource provider
final routeDataSourceProvider = Provider<RouteRemoteDataSource>((ref) {
  final supabase = ref.watch(_supabaseProvider);
  return RouteRemoteDataSource(supabase);
});

/// Tüm rotalar provider
final allRoutesProvider = FutureProvider<List<RouteEntity>>((ref) async {
  final dataSource = ref.watch(routeDataSourceProvider);
  final models = await dataSource.getRoutes();
  return models.map((m) => m.toEntity()).toList();
});

/// Tek rota provider
final routeByIdProvider = FutureProvider.family<RouteEntity, String>((ref, id) async {
  final dataSource = ref.watch(routeDataSourceProvider);
  final model = await dataSource.getRouteById(id);
  return model.toEntity();
});

/// Rota koordinatları provider
final routeCoordinatesProvider = FutureProvider.family<List<RouteCoordinate>, String>((ref, routeId) async {
  final dataSource = ref.watch(routeDataSourceProvider);
  final route = await dataSource.getRouteById(routeId);
  
  if (route.gpxData == null || route.gpxData!.isEmpty) {
    return [];
  }
  
  return dataSource.parseGpxCoordinates(route.gpxData!);
});

/// Rota oluşturma state
class RouteCreationState {
  final bool isLoading;
  final String? error;
  final RouteEntity? createdRoute;

  const RouteCreationState({
    this.isLoading = false,
    this.error,
    this.createdRoute,
  });

  RouteCreationState copyWith({
    bool? isLoading,
    String? error,
    RouteEntity? createdRoute,
  }) {
    return RouteCreationState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      createdRoute: createdRoute ?? this.createdRoute,
    );
  }
}

/// Rota oluşturma notifier
class RouteCreationNotifier extends StateNotifier<RouteCreationState> {
  final RouteRemoteDataSource _dataSource;
  final Ref _ref;

  RouteCreationNotifier(this._dataSource, this._ref)
      : super(const RouteCreationState());

  /// GPX içeriğinden veya GPX olmadan rota oluştur (GPX opsiyonel)
  Future<void> createFromGpxContent({
    required String name,
    String? gpxContent,
    required double locationLat,
    required double locationLng,
    String? locationName,
    String? description,
    String? terrainType,
    int difficultyLevel = 1,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final model = await _dataSource.createRouteFromGpx(
        name: name,
        gpxContent: gpxContent,
        locationLat: locationLat,
        locationLng: locationLng,
        locationName: locationName,
        description: description,
        terrainType: terrainType,
        difficultyLevel: difficultyLevel,
      );

      state = state.copyWith(
        isLoading: false,
        createdRoute: model.toEntity(),
      );

      // Routes listesini yenile
      _ref.invalidate(allRoutesProvider);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// GPX dosyasından rota oluştur
  Future<void> createFromGpxFile({
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
    state = state.copyWith(isLoading: true, error: null);

    try {
      final model = await _dataSource.uploadGpxFileAndCreateRoute(
        gpxContent: gpxContent,
        gpxBytes: gpxBytes,
        name: name,
        locationLat: locationLat,
        locationLng: locationLng,
        locationName: locationName,
        description: description,
        terrainType: terrainType,
        difficultyLevel: difficultyLevel,
      );

      state = state.copyWith(
        isLoading: false,
        createdRoute: model.toEntity(),
      );

      // Routes listesini yenile
      _ref.invalidate(allRoutesProvider);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Rotayı güncelle (düzenleme modu)
  Future<void> updateRoute({
    required String routeId,
    required String name,
    required double locationLat,
    required double locationLng,
    String? locationName,
    String? description,
    String? terrainType,
    int difficultyLevel = 1,
    String? gpxContent,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final model = await _dataSource.updateRouteWithData(
        id: routeId,
        name: name,
        locationLat: locationLat,
        locationLng: locationLng,
        locationName: locationName,
        description: description,
        terrainType: terrainType,
        difficultyLevel: difficultyLevel,
        gpxContent: gpxContent,
      );

      state = state.copyWith(
        isLoading: false,
        createdRoute: model.toEntity(),
      );

      _ref.invalidate(allRoutesProvider);
      _ref.invalidate(routeByIdProvider(routeId));
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void reset() {
    state = const RouteCreationState();
  }
}

/// Rota oluşturma provider
final routeCreationProvider =
    StateNotifierProvider<RouteCreationNotifier, RouteCreationState>((ref) {
  final dataSource = ref.watch(routeDataSourceProvider);
  return RouteCreationNotifier(dataSource, ref);
});

/// Rota silme notifier
class RouteDeleteNotifier extends StateNotifier<AsyncValue<void>> {
  final RouteRemoteDataSource _dataSource;
  final Ref _ref;

  RouteDeleteNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<void> deleteRoute(String routeId) async {
    state = const AsyncValue.loading();

    try {
      await _dataSource.deleteRoute(routeId);
      state = const AsyncValue.data(null);
      
      // Routes listesini yenile
      _ref.invalidate(allRoutesProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Rota silme provider
final routeDeleteProvider =
    StateNotifierProvider<RouteDeleteNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(routeDataSourceProvider);
  return RouteDeleteNotifier(dataSource, ref);
});
