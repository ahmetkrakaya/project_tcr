import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/foundation_model.dart';

class FoundationRemoteDataSource {
  final SupabaseClient _supabase;

  FoundationRemoteDataSource(this._supabase);

  /// Tüm vakıfları listele (dropdown için)
  Future<List<FoundationModel>> getFoundations() async {
    final response = await _supabase
        .from('foundations')
        .select('id, name')
        .order('name');

    return (response as List)
        .map((json) => FoundationModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Yeni vakıf ekle
  Future<FoundationModel> createFoundation(String name) async {
    final response = await _supabase
        .from('foundations')
        .insert({'name': name.trim()})
        .select('id, name')
        .single();

    return FoundationModel.fromJson(response as Map<String, dynamic>);
  }

  /// Vakıf adını güncelle
  Future<void> updateFoundation(String id, String name) async {
    await _supabase
        .from('foundations')
        .update({'name': name.trim()})
        .eq('id', id);
  }

  /// Vakıf sil
  /// Bağış kaydı kullanan vakıflar RESTRICT ile silinemez
  Future<void> deleteFoundation(String id) async {
    await _supabase.from('foundations').delete().eq('id', id);
  }
}
