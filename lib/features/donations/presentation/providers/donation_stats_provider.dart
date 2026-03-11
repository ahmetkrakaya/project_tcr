import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/donation_entity.dart';
import 'donation_provider.dart';

/// Kişi bazlı sıralama modeli
class DonationUserRanking {
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final double totalAmount;
  final int raceCount;

  const DonationUserRanking({
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.totalAmount,
    required this.raceCount,
  });
}

/// Yarış bazlı sıralama modeli (dropdown için)
class DonationRaceRanking {
  final String raceKey;
  final String raceName;
  final double totalAmount;
  final int donorCount;

  const DonationRaceRanking({
    required this.raceKey,
    required this.raceName,
    required this.totalAmount,
    required this.donorCount,
  });
}

/// Vakıf bazlı sıralama modeli
class DonationFoundationRanking {
  final String foundationName;
  final double totalAmount;
  final int donorCount;

  const DonationFoundationRanking({
    required this.foundationName,
    required this.totalAmount,
    required this.donorCount,
  });
}

/// TCR genel istatistik modeli
class DonationTcrStats {
  final double grandTotal;
  final List<DonationRaceRanking> raceBreakdowns;
  final List<DonationFoundationRanking> foundationBreakdowns;

  const DonationTcrStats({
    required this.grandTotal,
    required this.raceBreakdowns,
    required this.foundationBreakdowns,
  });
}

/// Yarış için benzersiz anahtar (event veya manuel)
String _raceKey(DonationEntity d) {
  if (d.eventId != null) return d.eventId!;
  return '${d.raceName ?? ''}_${d.raceDate?.toIso8601String() ?? ''}';
}

/// Kişi bazlı sıralama
final donationUserRankingsProvider =
    Provider<AsyncValue<List<DonationUserRanking>>>((ref) {
  return ref.watch(allDonationsProvider).whenData((donations) {
    final byUser = <String, _UserAgg>{};
    for (final d in donations) {
      final agg = byUser.putIfAbsent(
        d.userId,
        () => _UserAgg(
          userName: d.userName,
          userAvatarUrl: d.userAvatarUrl,
          races: {},
        ),
      );
      agg.total += d.amount;
      agg.races.add(_raceKey(d));
    }
    return byUser.entries
        .map((e) => DonationUserRanking(
              userId: e.key,
              userName: e.value.userName,
              userAvatarUrl: e.value.userAvatarUrl,
              totalAmount: e.value.total,
              raceCount: e.value.races.length,
            ))
        .toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
  });
});

/// Yarış bazlı sıralama
final donationRaceRankingsProvider =
    Provider<AsyncValue<List<DonationRaceRanking>>>((ref) {
  return ref.watch(allDonationsProvider).whenData((donations) {
    final byRace = <String, _RaceAgg>{};
    for (final d in donations) {
      final key = _raceKey(d);
      final name = d.displayRaceName.isNotEmpty ? d.displayRaceName : 'Bilinmeyen';
      final agg = byRace.putIfAbsent(
        key,
        () => _RaceAgg(raceName: name, donors: {}),
      );
      agg.total += d.amount;
      agg.donors.add(d.userId);
    }
    return byRace.entries
        .map((e) => DonationRaceRanking(
              raceKey: e.key,
              raceName: e.value.raceName,
              totalAmount: e.value.total,
              donorCount: e.value.donors.length,
            ))
        .toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
  });
});

/// Seçilen yarışa göre kişi sıralaması (en çok toplayandan en aza)
final donationUserRankingsByRaceProvider = Provider.family<
    AsyncValue<List<DonationUserRanking>>, String>((ref, raceKey) {
  return ref.watch(allDonationsProvider).whenData((donations) {
    final byUser = <String, _UserAgg>{};
    for (final d in donations) {
      if (_raceKey(d) != raceKey) continue;
      final agg = byUser.putIfAbsent(
        d.userId,
        () => _UserAgg(
          userName: d.userName,
          userAvatarUrl: d.userAvatarUrl,
          races: {},
        ),
      );
      agg.total += d.amount;
      agg.races.add(_raceKey(d));
    }
    return byUser.entries
        .map((e) => DonationUserRanking(
              userId: e.key,
              userName: e.value.userName,
              userAvatarUrl: e.value.userAvatarUrl,
              totalAmount: e.value.total,
              raceCount: 1,
            ))
        .toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
  });
});

/// Seçilen vakfa göre kişi sıralaması (en çok toplayandan en aza)
final donationUserRankingsByFoundationProvider = Provider.family<
    AsyncValue<List<DonationUserRanking>>, String>((ref, foundationName) {
  return ref.watch(allDonationsProvider).whenData((donations) {
    final byUser = <String, _UserAgg>{};
    for (final d in donations) {
      if (d.foundationName != foundationName) continue;
      final agg = byUser.putIfAbsent(
        d.userId,
        () => _UserAgg(
          userName: d.userName,
          userAvatarUrl: d.userAvatarUrl,
          races: {},
        ),
      );
      agg.total += d.amount;
      agg.races.add(_raceKey(d));
    }
    return byUser.entries
        .map((e) => DonationUserRanking(
              userId: e.key,
              userName: e.value.userName,
              userAvatarUrl: e.value.userAvatarUrl,
              totalAmount: e.value.total,
              raceCount: e.value.races.length,
            ))
        .toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
  });
});

/// Vakıf bazlı sıralama
final donationFoundationRankingsProvider =
    Provider<AsyncValue<List<DonationFoundationRanking>>>((ref) {
  return ref.watch(allDonationsProvider).whenData((donations) {
    final byFoundation = <String, _FoundationAgg>{};
    for (final d in donations) {
      final agg = byFoundation.putIfAbsent(
        d.foundationName,
        () => _FoundationAgg(donors: {}),
      );
      agg.total += d.amount;
      agg.donors.add(d.userId);
    }
    return byFoundation.entries
        .map((e) => DonationFoundationRanking(
              foundationName: e.key,
              totalAmount: e.value.total,
              donorCount: e.value.donors.length,
            ))
        .toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
  });
});

/// TCR genel istatistikler
final donationTcrStatsProvider = Provider<AsyncValue<DonationTcrStats>>((ref) {
  return ref.watch(allDonationsProvider).whenData((donations) {
    double grandTotal = 0;
    final byRace = <String, _RaceAgg>{};
    final byFoundation = <String, _FoundationAgg>{};

    for (final d in donations) {
      grandTotal += d.amount;

      final raceKey = _raceKey(d);
      final raceName = d.displayRaceName.isNotEmpty ? d.displayRaceName : 'Bilinmeyen';
      final raceAgg = byRace.putIfAbsent(
        raceKey,
        () => _RaceAgg(raceName: raceName, donors: {}),
      );
      raceAgg.total += d.amount;
      raceAgg.donors.add(d.userId);

      final fAgg = byFoundation.putIfAbsent(
        d.foundationName,
        () => _FoundationAgg(donors: {}),
      );
      fAgg.total += d.amount;
      fAgg.donors.add(d.userId);
    }

    final raceBreakdowns = byRace.entries
        .map((e) => DonationRaceRanking(
              raceKey: e.key,
              raceName: e.value.raceName,
              totalAmount: e.value.total,
              donorCount: e.value.donors.length,
            ))
        .toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    final foundationBreakdowns = byFoundation.entries
        .map((e) => DonationFoundationRanking(
              foundationName: e.key,
              totalAmount: e.value.total,
              donorCount: e.value.donors.length,
            ))
        .toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    return DonationTcrStats(
      grandTotal: grandTotal,
      raceBreakdowns: raceBreakdowns,
      foundationBreakdowns: foundationBreakdowns,
    );
  });
});

class _UserAgg {
  String userName;
  String? userAvatarUrl;
  double total = 0;
  Set<String> races;

  _UserAgg({
    required this.userName,
    this.userAvatarUrl,
    required this.races,
  });
}

class _RaceAgg {
  String raceName;
  double total = 0;
  Set<String> donors;

  _RaceAgg({required this.raceName, required this.donors});
}

class _FoundationAgg {
  double total = 0;
  Set<String> donors;

  _FoundationAgg({required this.donors});
}
