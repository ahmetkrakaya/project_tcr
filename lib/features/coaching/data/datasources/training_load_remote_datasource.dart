import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/training_load_models.dart';

/// Antrenman yuku (CTL/ATL/TSB) verilerini Supabase RPC'lerinden ceken katman.
class TrainingLoadRemoteDataSource {
  TrainingLoadRemoteDataSource(this._client);

  final SupabaseClient _client;

  /// Koc paneli icin tum (veya gruba ait) sporcularin guncel yuk ozeti.
  Future<List<AthleteLoadOverviewModel>> getCoachOverview({
    String? groupId,
  }) async {
    try {
      final response = await _client.rpc(
        'get_coach_training_load_overview',
        params: {'p_group_id': groupId},
      );
      final list = (response as List<dynamic>? ?? []);
      return list
          .map((item) => AthleteLoadOverviewModel.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Antrenman yükü özeti alınamadı: $e');
    }
  }

  /// Bir etkinlige "going" diyen katilimcilarin guncel form/yuk durumu.
  Future<List<AthleteLoadOverviewModel>> getEventLoad({
    required String eventId,
  }) async {
    try {
      final response = await _client.rpc(
        'get_event_training_load',
        params: {'p_event_id': eventId},
      );
      final list = (response as List<dynamic>? ?? []);
      return list
          .map((item) => AthleteLoadOverviewModel.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Etkinlik form raporu alınamadı: $e');
    }
  }

  /// Tek bir sporcunun gunluk TSS + CTL/ATL/TSB zaman serisi (PMC).
  Future<List<TrainingLoadPointModel>> getAthleteLoad({
    required String userId,
    int days = 90,
  }) async {
    try {
      final response = await _client.rpc(
        'get_athlete_training_load',
        params: {'p_user_id': userId, 'p_days': days},
      );
      final list = (response as List<dynamic>? ?? []);
      return list
          .map((item) => TrainingLoadPointModel.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Sporcu antrenman yükü alınamadı: $e');
    }
  }
}
