import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/admin_reports_models.dart';

/// Admin rapor RPC'leri (etkinlik turu trendi, grup durumu, kisi 360).
class AdminReportsRemoteDataSource {
  AdminReportsRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<List<EventTypeTrendItem>> getEventTypeTrend({
    DateTime? start,
    DateTime? end,
  }) async {
    try {
      final response = await _client.rpc('get_event_type_trend', params: {
        if (start != null) 'p_start': start.toIso8601String().split('T').first,
        if (end != null) 'p_end': end.toIso8601String().split('T').first,
      });
      final list = (response as List<dynamic>? ?? []);
      return list
          .map((e) =>
              EventTypeTrendItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Etkinlik türü trendi alınamadı: $e');
    }
  }

  Future<List<GroupStatusItem>> getGroupStatusOverview() async {
    try {
      final response = await _client.rpc('get_group_status_overview');
      final list = (response as List<dynamic>? ?? []);
      return list
          .map((e) =>
              GroupStatusItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Grup durum raporu alınamadı: $e');
    }
  }

  Future<Person360> getPerson360(String userId) async {
    try {
      final response = await _client
          .rpc('get_person_360', params: {'p_user_id': userId});
      return Person360.fromJson(Map<String, dynamic>.from(response as Map));
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Kişi 360 raporu alınamadı: $e');
    }
  }
}
