import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/club_race_remote_datasource.dart';
import '../../domain/entities/club_race_entity.dart';

/// Supabase client provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Club race datasource provider
final clubRaceDataSourceProvider = Provider<ClubRaceRemoteDataSource>((ref) {
  final supabase = ref.watch(_supabaseProvider);
  return ClubRaceRemoteDataSource(supabase);
});

/// Tüm yarışlar provider (tarih sıralamalı - en yakın önce)
final allClubRacesProvider = FutureProvider<List<ClubRaceEntity>>((ref) async {
  final dataSource = ref.watch(clubRaceDataSourceProvider);
  final models = await dataSource.getRaces();
  return models.map((m) => m.toEntity()).toList();
});

/// Yarış oluşturma state
class ClubRaceCreationNotifier extends StateNotifier<AsyncValue<void>> {
  final ClubRaceRemoteDataSource _dataSource;
  final Ref _ref;

  ClubRaceCreationNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<bool> createRace({
    required String name,
    required DateTime date,
    required String location,
    double? locationLat,
    double? locationLng,
    String? distance,
    String? description,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.createRace(
        name: name,
        date: date,
        location: location,
        locationLat: locationLat,
        locationLng: locationLng,
        distance: distance,
        description: description,
      );
      _ref.invalidate(allClubRacesProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final clubRaceCreationProvider =
    StateNotifierProvider<ClubRaceCreationNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(clubRaceDataSourceProvider);
  return ClubRaceCreationNotifier(dataSource, ref);
});

/// Yarış güncelleme state
class ClubRaceUpdateNotifier extends StateNotifier<AsyncValue<void>> {
  final ClubRaceRemoteDataSource _dataSource;
  final Ref _ref;

  ClubRaceUpdateNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<bool> updateRace({
    required String raceId,
    required String name,
    required DateTime date,
    required String location,
    double? locationLat,
    double? locationLng,
    String? distance,
    String? description,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.updateRace(
        raceId: raceId,
        name: name,
        date: date,
        location: location,
        locationLat: locationLat,
        locationLng: locationLng,
        distance: distance,
        description: description,
      );
      _ref.invalidate(allClubRacesProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final clubRaceUpdateProvider =
    StateNotifierProvider<ClubRaceUpdateNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(clubRaceDataSourceProvider);
  return ClubRaceUpdateNotifier(dataSource, ref);
});

/// Yarış silme state
class ClubRaceDeleteNotifier extends StateNotifier<AsyncValue<void>> {
  final ClubRaceRemoteDataSource _dataSource;
  final Ref _ref;

  ClubRaceDeleteNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<bool> deleteRace(String raceId) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.deleteRace(raceId);
      _ref.invalidate(allClubRacesProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final clubRaceDeleteProvider =
    StateNotifierProvider<ClubRaceDeleteNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(clubRaceDataSourceProvider);
  return ClubRaceDeleteNotifier(dataSource, ref);
});
