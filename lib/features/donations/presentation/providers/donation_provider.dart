import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/donation_remote_datasource.dart';
import '../../domain/entities/donation_entity.dart';

final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final donationDataSourceProvider = Provider<DonationRemoteDataSource>((ref) {
  final supabase = ref.watch(_supabaseProvider);
  return DonationRemoteDataSource(supabase);
});

/// Tüm bağışlar (amount DESC)
final allDonationsProvider = FutureProvider<List<DonationEntity>>((ref) async {
  final dataSource = ref.watch(donationDataSourceProvider);
  final models = await dataSource.getDonations();
  return models.map((m) => m.toEntity()).toList();
});

/// Kullanıcının katıldığı race etkinlikleri
final userParticipatedRaceEventsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dataSource = ref.watch(donationDataSourceProvider);
  return dataSource.getUserParticipatedRaceEvents();
});

/// Bağış oluşturma
class DonationCreationNotifier extends StateNotifier<AsyncValue<void>> {
  final DonationRemoteDataSource _dataSource;
  final Ref _ref;

  DonationCreationNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<bool> createDonation({
    String? eventId,
    String? raceName,
    DateTime? raceDate,
    required String foundationId,
    required double amount,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.createDonation(
        eventId: eventId,
        raceName: raceName,
        raceDate: raceDate,
        foundationId: foundationId,
        amount: amount,
      );
      _ref.invalidate(allDonationsProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final donationCreationProvider =
    StateNotifierProvider<DonationCreationNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(donationDataSourceProvider);
  return DonationCreationNotifier(dataSource, ref);
});

/// Bağış güncelleme
class DonationUpdateNotifier extends StateNotifier<AsyncValue<void>> {
  final DonationRemoteDataSource _dataSource;
  final Ref _ref;

  DonationUpdateNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<bool> updateAmount(String donationId, double amount) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.updateDonationAmount(donationId, amount);
      _ref.invalidate(allDonationsProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final donationUpdateProvider =
    StateNotifierProvider<DonationUpdateNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(donationDataSourceProvider);
  return DonationUpdateNotifier(dataSource, ref);
});

/// Bağış silme
class DonationDeleteNotifier extends StateNotifier<AsyncValue<void>> {
  final DonationRemoteDataSource _dataSource;
  final Ref _ref;

  DonationDeleteNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<bool> deleteDonation(String donationId) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.deleteDonation(donationId);
      _ref.invalidate(allDonationsProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final donationDeleteProvider =
    StateNotifierProvider<DonationDeleteNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(donationDataSourceProvider);
  return DonationDeleteNotifier(dataSource, ref);
});
