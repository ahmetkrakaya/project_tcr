import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/donation_model.dart';

class DonationRemoteDataSource {
  final SupabaseClient _supabase;

  DonationRemoteDataSource(this._supabase);

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  /// Tüm bağışları amount DESC sıralı getir (user + event + foundation join)
  Future<List<DonationModel>> getDonations() async {
    final response = await _supabase
        .from('user_donations')
        .select('''
          *,
          users!inner(first_name, last_name, avatar_url),
          events(title, start_time),
          foundations(name)
        ''')
        .order('amount', ascending: false);

    return (response as List)
        .map((json) => DonationModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Kullanıcının katıldığı race tipindeki etkinlikleri getir
  Future<List<Map<String, dynamic>>> getUserParticipatedRaceEvents() async {
    final userId = _currentUserId;
    if (userId == null) return [];

    final participantResponse = await _supabase
        .from('event_participants')
        .select('event_id')
        .eq('user_id', userId)
        .eq('status', 'going');

    final eventIds = (participantResponse as List<dynamic>)
        .map((e) => e['event_id'] as String)
        .toList();

    if (eventIds.isEmpty) return [];

    final eventsResponse = await _supabase
        .from('events')
        .select('id, title, start_time, event_type')
        .inFilter('id', eventIds)
        .eq('event_type', 'race')
        .eq('status', 'published')
        .order('start_time', ascending: false);

    return (eventsResponse as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  /// Yeni bağış ekle
  Future<void> createDonation({
    String? eventId,
    String? raceName,
    DateTime? raceDate,
    required String foundationId,
    required double amount,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('Kullanıcı giriş yapmamış');

    final data = <String, dynamic>{
      'user_id': userId,
      'foundation_id': foundationId,
      'amount': amount,
    };

    if (eventId != null) {
      data['event_id'] = eventId;
    } else {
      data['race_name'] = raceName;
      data['race_date'] =
          '${raceDate!.year}-${raceDate.month.toString().padLeft(2, '0')}-${raceDate.day.toString().padLeft(2, '0')}';
    }

    await _supabase.from('user_donations').insert(data);
  }

  /// Bağış tutarını güncelle
  Future<void> updateDonationAmount(String donationId, double amount) async {
    await _supabase
        .from('user_donations')
        .update({'amount': amount})
        .eq('id', donationId);
  }

  /// Bağış sil
  Future<void> deleteDonation(String donationId) async {
    await _supabase.from('user_donations').delete().eq('id', donationId);
  }
}
