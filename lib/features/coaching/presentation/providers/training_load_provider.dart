import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/training_load_remote_datasource.dart';
import '../../data/models/training_load_models.dart';

final _trainingLoadDataSourceProvider =
    Provider<TrainingLoadRemoteDataSource>((ref) {
  return TrainingLoadRemoteDataSource(Supabase.instance.client);
});

/// Koc paneli sporcu ozet listesi. groupId null -> tum aktif sporcular.
final coachTrainingLoadOverviewProvider = FutureProvider.family<
    List<AthleteLoadOverviewModel>, String?>((ref, groupId) async {
  final ds = ref.watch(_trainingLoadDataSourceProvider);
  return ds.getCoachOverview(groupId: groupId);
});

/// Bir etkinligin katilimcilarinin guncel form/yuk durumu.
final eventTrainingLoadProvider = FutureProvider.family<
    List<AthleteLoadOverviewModel>, String>((ref, eventId) async {
  final ds = ref.watch(_trainingLoadDataSourceProvider);
  return ds.getEventLoad(eventId: eventId);
});

/// Tek sporcu icin PMC zaman serisi parametreleri.
class AthleteLoadParams {
  const AthleteLoadParams({required this.userId, required this.days});

  final String userId;
  final int days;

  @override
  bool operator ==(Object other) =>
      other is AthleteLoadParams &&
      other.userId == userId &&
      other.days == days;

  @override
  int get hashCode => Object.hash(userId, days);
}

final athleteTrainingLoadProvider = FutureProvider.family<
    List<TrainingLoadPointModel>, AthleteLoadParams>((ref, params) async {
  final ds = ref.watch(_trainingLoadDataSourceProvider);
  return ds.getAthleteLoad(userId: params.userId, days: params.days);
});
