import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/foundation_remote_datasource.dart';
import '../../domain/entities/foundation_entity.dart';

final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final foundationDataSourceProvider = Provider<FoundationRemoteDataSource>((ref) {
  final supabase = ref.watch(_supabaseProvider);
  return FoundationRemoteDataSource(supabase);
});

/// Tüm vakıflar (dropdown için)
final foundationsProvider = FutureProvider<List<FoundationEntity>>((ref) async {
  final dataSource = ref.watch(foundationDataSourceProvider);
  final models = await dataSource.getFoundations();
  return models.map((m) => m.toEntity()).toList();
});

/// Vakıf oluşturma
class FoundationCreationNotifier extends StateNotifier<AsyncValue<void>> {
  final FoundationRemoteDataSource _dataSource;
  final Ref _ref;

  FoundationCreationNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<bool> createFoundation(String name) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.createFoundation(name);
      _ref.invalidate(foundationsProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final foundationCreationProvider =
    StateNotifierProvider<FoundationCreationNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(foundationDataSourceProvider);
  return FoundationCreationNotifier(dataSource, ref);
});

/// Vakıf güncelleme
class FoundationUpdateNotifier extends StateNotifier<AsyncValue<void>> {
  final FoundationRemoteDataSource _dataSource;
  final Ref _ref;

  FoundationUpdateNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<bool> updateFoundation(String id, String name) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.updateFoundation(id, name);
      _ref.invalidate(foundationsProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final foundationUpdateProvider =
    StateNotifierProvider<FoundationUpdateNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(foundationDataSourceProvider);
  return FoundationUpdateNotifier(dataSource, ref);
});

/// Vakıf silme
class FoundationDeleteNotifier extends StateNotifier<AsyncValue<void>> {
  final FoundationRemoteDataSource _dataSource;
  final Ref _ref;

  FoundationDeleteNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<bool> deleteFoundation(String id) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.deleteFoundation(id);
      _ref.invalidate(foundationsProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final foundationDeleteProvider =
    StateNotifierProvider<FoundationDeleteNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(foundationDataSourceProvider);
  return FoundationDeleteNotifier(dataSource, ref);
});
