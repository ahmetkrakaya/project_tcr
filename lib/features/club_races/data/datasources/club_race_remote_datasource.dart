import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/club_race_model.dart';

/// Club Race Remote DataSource
class ClubRaceRemoteDataSource {
  final SupabaseClient _supabase;

  ClubRaceRemoteDataSource(this._supabase);

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  /// Tüm yarışları tarih sırasına göre getir (en yakın önce)
  Future<List<ClubRaceModel>> getRaces() async {
    final response = await _supabase
        .from('club_races')
        .select()
        .order('date', ascending: true);

    return (response as List)
        .map((json) => ClubRaceModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Yeni yarış oluştur
  Future<ClubRaceModel> createRace({
    required String name,
    required DateTime date,
    required String location,
    double? locationLat,
    double? locationLng,
    String? distance,
    String? description,
  }) async {
    final data = {
      'name': name,
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'location': location,
      'location_lat': locationLat,
      'location_lng': locationLng,
      'distance': distance,
      'description': description,
      'created_by': _currentUserId,
    };

    final response = await _supabase
        .from('club_races')
        .insert(data)
        .select()
        .single();

    return ClubRaceModel.fromJson(response);
  }

  /// Yarış güncelle
  Future<ClubRaceModel> updateRace({
    required String raceId,
    required String name,
    required DateTime date,
    required String location,
    double? locationLat,
    double? locationLng,
    String? distance,
    String? description,
  }) async {
    final data = {
      'name': name,
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'location': location,
      'location_lat': locationLat,
      'location_lng': locationLng,
      'distance': distance,
      'description': description,
    };

    final response = await _supabase
        .from('club_races')
        .update(data)
        .eq('id', raceId)
        .select()
        .single();

    return ClubRaceModel.fromJson(response);
  }

  /// Yarış sil
  Future<void> deleteRace(String raceId) async {
    await _supabase.from('club_races').delete().eq('id', raceId);
  }
}
