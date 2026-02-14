import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/event_model.dart';
import '../models/event_info_block_model.dart';
import '../models/event_template_model.dart';
import '../models/event_activity_stat_model.dart';
import '../models/user_activity_report_model.dart';

/// Event Remote Data Source
abstract class EventRemoteDataSource {
  /// Yaklaşan etkinlikleri getir
  Future<List<EventModel>> getUpcomingEvents({int limit = 20, int offset = 0});

  /// Bu haftanın etkinliklerini getir
  Future<List<EventModel>> getThisWeekEvents();

  /// Tüm etkinlikleri getir
  Future<List<EventModel>> getAllEvents({int limit = 50, int offset = 0});

  /// Tek bir etkinlik getir
  Future<EventModel> getEventById(String id);

  /// Etkinlik oluştur
  Future<EventModel> createEvent(EventModel event);

  /// Etkinlik güncelle
  Future<EventModel> updateEvent(EventModel event);

  /// Tekrarlayan seride bu etkinlik ve sonrakileri güncelle (RPC)
  Future<void> updateRecurringSeriesFromEvent(String eventId, Map<String, dynamic> updates);

  /// Etkinlik sil
  Future<void> deleteEvent(String id);

  /// Etkinliğe katıl (RSVP)
  Future<void> rsvpToEvent(String eventId, String status, {String? note});

  /// RSVP iptal et
  Future<void> cancelRsvp(String eventId);

  /// Etkinlik katılımcılarını getir
  Future<List<EventParticipantModel>> getEventParticipants(String eventId);

  /// Kullanıcının katıldığı etkinlikleri getir
  Future<List<EventModel>> getUserEvents(String userId);

  /// Antrenman gruplarını getir
  Future<List<TrainingGroupModel>> getTrainingGroups();

  /// Antrenman türlerini getir
  Future<List<TrainingTypeModel>> getTrainingTypes();

  // ========== Event Info Blocks ==========

  /// Etkinlik bilgi bloklarını getir
  Future<List<EventInfoBlockModel>> getEventInfoBlocks(String eventId);

  /// Bilgi bloğu oluştur
  Future<EventInfoBlockModel> createInfoBlock(EventInfoBlockModel block);

  /// Bilgi bloğu güncelle
  Future<EventInfoBlockModel> updateInfoBlock(EventInfoBlockModel block);

  /// Bilgi bloğu sil
  Future<void> deleteInfoBlock(String blockId);

  /// Tüm blokları toplu güncelle (sıralama için)
  Future<void> reorderInfoBlocks(String eventId, List<EventInfoBlockModel> blocks);

  /// Tüm blokları sil
  Future<void> deleteAllInfoBlocks(String eventId);

  // ========== Event Templates ==========

  /// Tüm etkinlik şablonlarını getir
  Future<List<EventTemplateModel>> getEventTemplates();

  /// Tek bir şablon getir
  Future<EventTemplateModel> getEventTemplateById(String id);

  /// Şablon oluştur
  Future<EventTemplateModel> createEventTemplate(EventTemplateModel template);

  /// Mevcut etkinlikten şablon oluştur
  Future<EventTemplateModel> createTemplateFromEvent(String eventId, String templateName);

  /// Şablon güncelle
  Future<EventTemplateModel> updateEventTemplate(EventTemplateModel template);

  /// Şablon sil
  Future<void> deleteEventTemplate(String id);

  /// Etkinlik pinle / pin kaldır (sadece admin)
  Future<void> setEventPinned(String eventId, bool pinned);

  /// Etkinlik raporu getir (tarih aralığına göre)
  Future<Map<String, dynamic>> getEventReport({
    required DateTime startDate,
    required DateTime endDate,
    String? eventType,
    String? groupId,
  });

  /// Belirli bir etkinliğe ait aktivitelerden kullanıcı bazında
  /// mesafe / süre / pace istatistikleri getir
  Future<List<EventActivityStatModel>> getEventActivityStats(String eventId);

  /// Grup raporu: Belirli bir grup ve tarih aralığı için
  /// grup üyelerinin aktivite istatistiklerini getir
  Future<Map<String, dynamic>> getGroupReport({
    required String groupId,
    required DateTime startDate,
    required DateTime endDate,
  });

  /// Kullanıcı aktivite raporu: Belirli bir kullanıcı ve tarih aralığı için
  /// yaptığı tüm aktiviteleri (etkinlik eşleşmesi olsa da olmasa da) getir
  Future<List<UserActivityReportModel>> getUserActivityReport({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  });
}

/// Event Remote Data Source Implementation
class EventRemoteDataSourceImpl implements EventRemoteDataSource {
  final SupabaseClient _supabase;

  EventRemoteDataSourceImpl(this._supabase);

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  @override
  Future<List<EventModel>> getUpcomingEvents({int limit = 20, int offset = 0}) async {
    try {
      final now = DateTime.now().toIso8601String();
      
      final response = await _supabase
          .from('events')
          .select('*, training_types(display_name, description, color, threshold_offset_min_seconds, threshold_offset_max_seconds)')
          .eq('status', 'published')
          .gte('start_time', now)
          .order('is_pinned', ascending: false)
          .order('pinned_at', ascending: false)
          .order('start_time', ascending: true)
          .range(offset, offset + limit - 1);

      final List<dynamic> data = response as List<dynamic>;
      
      // Grup bazlı filtreleme uygula (antrenman türündeki etkinlikler için)
      // Önce kullanıcının gruplarını ve tüm event'lerin grup programlarını toplu al
      final eventIds = data.map((e) => e['id'] as String).toList();
      final userGroupIds = await _getUserGroupIds();
      final eventGroupsMap = await _getAllEventGroupIds(eventIds);
      
      // Memory'de filtreleme yap
      final filteredEventsData = <dynamic>[];
      for (final json in data) {
        final canSee = _canUserSeeEvent(
          json as Map<String, dynamic>,
          userGroupIds,
          eventGroupsMap,
        );
        if (canSee) {
          filteredEventsData.add(json);
        }
      }
      
      // Filtrelenmiş event ID'lerini topla
      final filteredEventIds = filteredEventsData.map((e) => e['id'] as String).toList();
      
      // Toplu sorgular: participant count ve kullanıcı katılım durumları
      final participantCounts = await _getAllParticipantCounts(filteredEventIds);
      final userParticipatingStatuses = await _getAllUserParticipatingStatuses(filteredEventIds);
      
      // Event modellerini oluştur
      return filteredEventsData.map((json) {
        final eventId = json['id'] as String;
        final participantCount = participantCounts[eventId] ?? 0;
        final isParticipating = userParticipatingStatuses[eventId] ?? false;
        
        return EventModel.fromJson(
          {...json as Map<String, dynamic>, 'participant_count': participantCount},
          isParticipating: isParticipating,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Etkinlikler alınamadı: $e');
    }
  }

  @override
  Future<List<EventModel>> getThisWeekEvents() async {
    try {
      final now = DateTime.now();
      final weekStart = DateTime(now.year, now.month, now.day);
      final weekEnd = weekStart.add(const Duration(days: 7));

      // İki sorguyu paralel yap (performans için)
      final results = await Future.wait([
        // Pinlenen etkinlikleri al (bu hafta içinde olmasa bile)
        _supabase
            .from('events')
            .select('*, training_types(display_name, description, color, threshold_offset_min_seconds, threshold_offset_max_seconds)')
            .eq('status', 'published')
            .eq('is_pinned', true)
            .order('pinned_at', ascending: false)
            .then((response) => response as List<dynamic>),
        
        // Bu haftanın etkinliklerini al
        _supabase
            .from('events')
            .select('*, training_types(display_name, description, color, threshold_offset_min_seconds, threshold_offset_max_seconds)')
            .eq('status', 'published')
            .gte('start_time', weekStart.toIso8601String())
            .lt('start_time', weekEnd.toIso8601String())
            .eq('is_pinned', false) // Pinlenmemiş olanlar
            .order('start_time', ascending: true)
            .then((response) => response as List<dynamic>),
      ]);
      
      final pinnedData = results[0];
      final thisWeekData = results[1];

      // Pinlenen etkinliklerin ID'lerini topla (duplicate kontrolü için)
      final pinnedIds = <String>{};
      for (final json in pinnedData) {
        pinnedIds.add(json['id'] as String);
      }
      
      // Pinlenen etkinlikleri ve bu haftanın etkinliklerini birleştir
      final allEventsData = <dynamic>[...pinnedData];
      for (final json in thisWeekData) {
        if (!pinnedIds.contains(json['id'] as String)) {
          allEventsData.add(json);
        }
      }
      
      // Grup bazlı filtreleme uygula (antrenman türündeki etkinlikler için)
      // Önce kullanıcının gruplarını ve tüm event'lerin grup programlarını toplu al
      final eventIds = allEventsData.map((e) => e['id'] as String).toList();
      final userGroupIds = await _getUserGroupIds();
      final eventGroupsMap = await _getAllEventGroupIds(eventIds);
      
      // Memory'de filtreleme yap
      final filteredEventsData = <dynamic>[];
      for (final json in allEventsData) {
        final canSee = _canUserSeeEvent(
          json as Map<String, dynamic>,
          userGroupIds,
          eventGroupsMap,
        );
        if (canSee) {
          filteredEventsData.add(json);
        }
      }
      
      // Filtrelenmiş event ID'lerini topla
      final filteredEventIds = filteredEventsData.map((e) => e['id'] as String).toList();
      
      // Toplu sorgular: participant count ve kullanıcı katılım durumları
      final participantCounts = await _getAllParticipantCounts(filteredEventIds);
      final userParticipatingStatuses = await _getAllUserParticipatingStatuses(filteredEventIds);
      
      // Event modellerini oluştur ve sırala (pinlenenler önce, sonra start_time'a göre)
      final eventModels = filteredEventsData.map((json) {
        final eventId = json['id'] as String;
        final participantCount = participantCounts[eventId] ?? 0;
        final isParticipating = userParticipatingStatuses[eventId] ?? false;
        
        return EventModel.fromJson(
          {...json as Map<String, dynamic>, 'participant_count': participantCount},
          isParticipating: isParticipating,
        );
      }).toList();
      
      // Sıralama: Pinlenenler önce (pinned_at'e göre), sonra start_time'a göre
      eventModels.sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        if (a.isPinned && b.isPinned) {
          if (a.pinnedAt != null && b.pinnedAt != null) {
            return b.pinnedAt!.compareTo(a.pinnedAt!);
          }
          if (a.pinnedAt != null) return -1;
          if (b.pinnedAt != null) return 1;
        }
        return a.startTime.compareTo(b.startTime);
      });
      
      return eventModels;
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Bu haftanın etkinlikleri alınamadı: $e');
    }
  }

  @override
  Future<List<EventModel>> getAllEvents({int limit = 50, int offset = 0}) async {
    try {
      final response = await _supabase
          .from('events')
          .select('*, training_types(display_name, description, color, threshold_offset_min_seconds, threshold_offset_max_seconds)')
          .eq('status', 'published')
          .order('is_pinned', ascending: false)
          .order('pinned_at', ascending: false)
          .order('start_time', ascending: false)
          .range(offset, offset + limit - 1);

      final List<dynamic> data = response as List<dynamic>;
      
      // Grup bazlı filtreleme uygula (antrenman türündeki etkinlikler için)
      // Önce kullanıcının gruplarını ve tüm event'lerin grup programlarını toplu al
      final eventIds = data.map((e) => e['id'] as String).toList();
      final userGroupIds = await _getUserGroupIds();
      final eventGroupsMap = await _getAllEventGroupIds(eventIds);
      
      // Memory'de filtreleme yap
      final filteredEventsData = <dynamic>[];
      for (final json in data) {
        final canSee = _canUserSeeEvent(
          json as Map<String, dynamic>,
          userGroupIds,
          eventGroupsMap,
        );
        if (canSee) {
          filteredEventsData.add(json);
        }
      }
      
      // Filtrelenmiş event ID'lerini topla
      final filteredEventIds = filteredEventsData.map((e) => e['id'] as String).toList();
      
      // Toplu sorgular: participant count ve kullanıcı katılım durumları
      final participantCounts = await _getAllParticipantCounts(filteredEventIds);
      final userParticipatingStatuses = await _getAllUserParticipatingStatuses(filteredEventIds);
      
      // Event modellerini oluştur
      return filteredEventsData.map((json) {
        final eventId = json['id'] as String;
        final participantCount = participantCounts[eventId] ?? 0;
        final isParticipating = userParticipatingStatuses[eventId] ?? false;
        
        return EventModel.fromJson(
          {...json as Map<String, dynamic>, 'participant_count': participantCount},
          isParticipating: isParticipating,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Etkinlikler alınamadı: $e');
    }
  }

  @override
  Future<EventModel> getEventById(String id) async {
    try {
      final response = await _supabase
          .from('events')
          .select('*, training_types(display_name, description, color, threshold_offset_min_seconds, threshold_offset_max_seconds)')
          .eq('id', id)
          .single();

      final participantCount = await _getParticipantCount(id);
      final isParticipating = await _isUserParticipating(id);

      return EventModel.fromJson(
        {...response, 'participant_count': participantCount},
        isParticipating: isParticipating,
      );
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Etkinlik bulunamadı: $e');
    }
  }

  @override
  Future<EventModel> createEvent(EventModel event) async {
    try {
      final response = await _supabase
          .from('events')
          .insert(event.toJson())
          .select()
          .single();

      return EventModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Etkinlik oluşturulamadı: $e');
    }
  }

  @override
  Future<EventModel> updateEvent(EventModel event) async {
    try {
      // Mevcut etkinliği yükle ve korunması gereken değerleri al
      final existingEvent = await getEventById(event.id);
      
      final json = event.toJson();
      
      // bannerImageUrl için null değerleri mevcut değerle değiştir (kapak görseli korunmalı)
      if (json['banner_image_url'] == null && existingEvent.bannerImageUrl != null) {
        json['banner_image_url'] = existingEvent.bannerImageUrl;
      }
      
      // isPinned ve pinnedAt için mevcut değerleri koru (pin durumu korunmalı)
      json['is_pinned'] = existingEvent.isPinned;
      if (existingEvent.pinnedAt != null) {
        json['pinned_at'] = existingEvent.pinnedAt?.toIso8601String();
      } else {
        json['pinned_at'] = null;
      }
      // is_recurrence_exception "sadece bu etkinliği düzenle" ile gönderilir; koruma yok
      
      final response = await _supabase
          .from('events')
          .update(json)
          .eq('id', event.id)
          .select()
          .single();

      return EventModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Etkinlik güncellenemedi: $e');
    }
  }

  @override
  Future<void> updateRecurringSeriesFromEvent(String eventId, Map<String, dynamic> updates) async {
    try {
      await _supabase.rpc(
        'update_recurring_series_from_event',
        params: {'p_event_id': eventId, 'p_updates': updates},
      );
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Seri güncellenemedi: $e');
    }
  }

  @override
  Future<void> deleteEvent(String id) async {
    try {
      await _supabase.from('events').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Etkinlik silinemedi: $e');
    }
  }

  @override
  Future<void> rsvpToEvent(String eventId, String status, {String? note}) async {
    try {
      final userId = _currentUserId;
      if (userId == null) throw ServerException(message: 'Kullanıcı giriş yapmamış');

      await _supabase.from('event_participants').upsert(
        {
          'event_id': eventId,
          'user_id': userId,
          'status': status,
          'note': note,
          'responded_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'event_id,user_id',
      );
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Katılım kaydedilemedi: $e');
    }
  }

  @override
  Future<void> cancelRsvp(String eventId) async {
    try {
      final userId = _currentUserId;
      if (userId == null) throw ServerException(message: 'Kullanıcı giriş yapmamış');

      await _supabase
          .from('event_participants')
          .delete()
          .eq('event_id', eventId)
          .eq('user_id', userId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Katılım iptal edilemedi: $e');
    }
  }

  @override
  Future<List<EventParticipantModel>> getEventParticipants(String eventId) async {
    try {
      final response = await _supabase
          .from('event_participants')
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .eq('event_id', eventId)
          .eq('status', 'going')
          .order('responded_at', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => EventParticipantModel.fromJson(json as Map<String, dynamic>)).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Katılımcılar alınamadı: $e');
    }
  }

  @override
  Future<List<EventModel>> getUserEvents(String userId) async {
    try {
      // Kullanıcının katıldığı etkinliklerin ID'lerini al
      final participantResponse = await _supabase
          .from('event_participants')
          .select('event_id')
          .eq('user_id', userId)
          .eq('status', 'going');

      final eventIds = (participantResponse as List<dynamic>)
          .map((e) => e['event_id'] as String)
          .toList();

      if (eventIds.isEmpty) return [];

      final response = await _supabase
          .from('events')
          .select('*, training_types(display_name, description, color, threshold_offset_min_seconds, threshold_offset_max_seconds)')
          .inFilter('id', eventIds)
          .order('start_time', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => EventModel.fromJson(
        json as Map<String, dynamic>,
        isParticipating: true,
      )).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Kullanıcı etkinlikleri alınamadı: $e');
    }
  }

  @override
  Future<List<TrainingGroupModel>> getTrainingGroups() async {
    try {
      final response = await _supabase
          .from('training_groups')
          .select()
          .eq('is_active', true)
          .order('name', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => TrainingGroupModel.fromJson(json as Map<String, dynamic>)).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Antrenman grupları alınamadı: $e');
    }
  }

  @override
  Future<List<TrainingTypeModel>> getTrainingTypes() async {
    try {
      final response = await _supabase
          .from('training_types')
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => TrainingTypeModel.fromJson(json as Map<String, dynamic>)).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Antrenman türleri alınamadı: $e');
    }
  }

  // Helper methods
  Future<int> _getParticipantCount(String eventId) async {
    try {
      final response = await _supabase
          .from('event_participants')
          .select()
          .eq('event_id', eventId)
          .eq('status', 'going');
      
      return (response as List<dynamic>).length;
    } catch (e) {
      return 0;
    }
  }

  Future<bool> _isUserParticipating(String eventId) async {
    final userId = _currentUserId;
    if (userId == null) return false;

    try {
      final response = await _supabase
          .from('event_participants')
          .select()
          .eq('event_id', eventId)
          .eq('user_id', userId)
          .eq('status', 'going')
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      return false;
    }
  }

  /// Tüm event'ler için participant count'ları toplu olarak getir
  Future<Map<String, int>> _getAllParticipantCounts(List<String> eventIds) async {
    if (eventIds.isEmpty) return {};

    try {
      final response = await _supabase
          .from('event_participants')
          .select('event_id')
          .inFilter('event_id', eventIds)
          .eq('status', 'going');
      
      final Map<String, int> counts = {};
      for (final item in response as List<dynamic>) {
        final eventId = item['event_id'] as String;
        counts[eventId] = (counts[eventId] ?? 0) + 1;
      }
      
      // Event'ler için 0 count ekle (hiç participant yoksa)
      for (final eventId in eventIds) {
        counts.putIfAbsent(eventId, () => 0);
      }
      
      return counts;
    } catch (e) {
      // Hata durumunda tüm event'ler için 0 döndür
      return {for (final eventId in eventIds) eventId: 0};
    }
  }

  /// Tüm event'ler için kullanıcının katılım durumlarını toplu olarak getir
  Future<Map<String, bool>> _getAllUserParticipatingStatuses(List<String> eventIds) async {
    final userId = _currentUserId;
    if (userId == null || eventIds.isEmpty) {
      return {for (final eventId in eventIds) eventId: false};
    }

    try {
      final response = await _supabase
          .from('event_participants')
          .select('event_id')
          .inFilter('event_id', eventIds)
          .eq('user_id', userId)
          .eq('status', 'going');
      
      final Set<String> participatingEventIds = {};
      for (final item in response as List<dynamic>) {
        participatingEventIds.add(item['event_id'] as String);
      }
      
      // Tüm event'ler için durum map'i oluştur
      return {
        for (final eventId in eventIds)
          eventId: participatingEventIds.contains(eventId)
      };
    } catch (e) {
      // Hata durumunda tüm event'ler için false döndür
      return {for (final eventId in eventIds) eventId: false};
    }
  }

  /// Kullanıcının gruplarını getir (cache'lenmiş)
  List<String>? _cachedUserGroupIds;
  String? _cachedUserId;
  
  Future<List<String>> _getUserGroupIds() async {
    final userId = _currentUserId;
    
    // Kullanıcı değiştiyse cache'i temizle
    if (userId != _cachedUserId) {
      _cachedUserGroupIds = null;
      _cachedUserId = userId;
    }
    
    if (_cachedUserGroupIds != null) {
      return _cachedUserGroupIds!;
    }

    if (userId == null) {
      _cachedUserGroupIds = [];
      return [];
    }

    try {
      final response = await _supabase
          .from('group_members')
          .select('group_id')
          .eq('user_id', userId);
      
      _cachedUserGroupIds = (response as List<dynamic>)
          .map((e) => e['group_id'] as String)
          .toList();
      return _cachedUserGroupIds!;
    } catch (e) {
      _cachedUserGroupIds = [];
      return [];
    }
  }

  /// Tüm event'lerin grup programlarını toplu olarak getir
  Future<Map<String, List<String>>> _getAllEventGroupIds(List<String> eventIds) async {
    if (eventIds.isEmpty) return {};

    try {
      final response = await _supabase
          .from('event_group_programs')
          .select('event_id, training_group_id')
          .inFilter('event_id', eventIds);
      
      final Map<String, List<String>> eventGroupsMap = {};
      for (final item in response as List<dynamic>) {
        final eventId = item['event_id'] as String;
        final groupId = item['training_group_id'] as String;
        eventGroupsMap.putIfAbsent(eventId, () => []).add(groupId);
      }
      
      return eventGroupsMap;
    } catch (e) {
      return {};
    }
  }

  /// Antrenman türündeki bir event'i kullanıcı görebilir mi? (Memory'de filtreleme)
  bool _canUserSeeEvent(
    Map<String, dynamic> eventJson,
    List<String> userGroupIds,
    Map<String, List<String>> eventGroupsMap,
  ) {
    final eventType = eventJson['event_type'] as String?;
    
    // Antrenman türü değilse herkes görebilir
    if (eventType != 'training') {
      return true;
    }

    // Antrenman türü ise grup kontrolü yap
    final eventId = eventJson['id'] as String;
    final eventGroupIds = eventGroupsMap[eventId] ?? [];
    
    // Event'in grup programı yoksa herkes görebilir
    if (eventGroupIds.isEmpty) {
      return true;
    }

    // Event'in grup programı varsa, kullanıcının gruplarını kontrol et
    // Kullanıcının gruplarından biri event'in gruplarında mı?
    return userGroupIds.any((groupId) => eventGroupIds.contains(groupId));
  }

  // ========== Event Info Blocks Implementation ==========

  @override
  Future<List<EventInfoBlockModel>> getEventInfoBlocks(String eventId) async {
    try {
      final response = await _supabase
          .from('event_info_blocks')
          .select()
          .eq('event_id', eventId)
          .order('order_index', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => EventInfoBlockModel.fromJson(json as Map<String, dynamic>)).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Bilgi blokları alınamadı: $e');
    }
  }

  @override
  Future<EventInfoBlockModel> createInfoBlock(EventInfoBlockModel block) async {
    try {
      final response = await _supabase
          .from('event_info_blocks')
          .insert(block.toJson())
          .select()
          .single();

      return EventInfoBlockModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Bilgi bloğu oluşturulamadı: $e');
    }
  }

  @override
  Future<EventInfoBlockModel> updateInfoBlock(EventInfoBlockModel block) async {
    try {
      final response = await _supabase
          .from('event_info_blocks')
          .update(block.toJson())
          .eq('id', block.id)
          .select()
          .single();

      return EventInfoBlockModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Bilgi bloğu güncellenemedi: $e');
    }
  }

  @override
  Future<void> deleteInfoBlock(String blockId) async {
    try {
      await _supabase
          .from('event_info_blocks')
          .delete()
          .eq('id', blockId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Bilgi bloğu silinemedi: $e');
    }
  }

  @override
  Future<void> reorderInfoBlocks(String eventId, List<EventInfoBlockModel> blocks) async {
    try {
      // Her bloğu yeni sırasıyla güncelle
      for (int i = 0; i < blocks.length; i++) {
        await _supabase
            .from('event_info_blocks')
            .update({'order_index': i})
            .eq('id', blocks[i].id);
      }
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Blok sıralaması güncellenemedi: $e');
    }
  }

  @override
  Future<void> deleteAllInfoBlocks(String eventId) async {
    try {
      await _supabase
          .from('event_info_blocks')
          .delete()
          .eq('event_id', eventId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Bilgi blokları silinemedi: $e');
    }
  }

  // ========== Event Templates Implementation ==========

  @override
  Future<List<EventTemplateModel>> getEventTemplates() async {
    try {
      final response = await _supabase
          .from('event_templates')
          .select('''
            *,
            training_types(display_name, color, threshold_offset_min_seconds, threshold_offset_max_seconds),
            routes(name),
            event_template_group_programs(
              *,
              training_groups(name, color),
              routes(name),
              training_types(display_name, color, threshold_offset_min_seconds, threshold_offset_max_seconds)
            )
          ''')
          .eq('is_active', true)
          .order('name', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      return data
          .map((json) =>
              EventTemplateModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Şablonlar alınamadı: $e');
    }
  }

  @override
  Future<EventTemplateModel> getEventTemplateById(String id) async {
    try {
      final response = await _supabase
          .from('event_templates')
          .select('''
            *,
            training_types(display_name, color, threshold_offset_min_seconds, threshold_offset_max_seconds),
            routes(name),
            event_template_group_programs(
              *,
              training_groups(name, color),
              routes(name),
              training_types(display_name, color, threshold_offset_min_seconds, threshold_offset_max_seconds)
            )
          ''')
          .eq('id', id)
          .single();

      return EventTemplateModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Şablon bulunamadı: $e');
    }
  }

  @override
  Future<EventTemplateModel> createEventTemplate(
      EventTemplateModel template) async {
    try {
      // Önce şablonu oluştur
      final response = await _supabase
          .from('event_templates')
          .insert(template.toJson())
          .select()
          .single();

      final templateId = response['id'] as String;

      // Grup programlarını ekle
      if (template.groupPrograms.isNotEmpty) {
        final programsToInsert = template.groupPrograms.map((p) {
          final map = <String, dynamic>{
            'template_id': templateId,
            'training_group_id': p.trainingGroupId,
            'program_content': p.programContent,
            'route_id': p.routeId,
            'training_type_id': p.trainingTypeId,
            'sort_order': p.sortOrder,
          };
          if (p.workoutDefinition != null) {
            map['workout_definition'] = p.workoutDefinition!.toJson();
          }
          return map;
        }).toList();

        await _supabase
            .from('event_template_group_programs')
            .insert(programsToInsert);
      }

      // Tam şablonu geri getir
      return getEventTemplateById(templateId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Şablon oluşturulamadı: $e');
    }
  }

  @override
  Future<EventTemplateModel> createTemplateFromEvent(
      String eventId, String templateName) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış');
      }

      // Etkinlik bilgilerini al
      final event = await getEventById(eventId);

      // Etkinlik grup programlarını al
      final groupProgramsResponse = await _supabase
          .from('event_group_programs')
          .select('''
            *,
            training_groups(name, color),
            routes(name),
            training_types(display_name, color, threshold_offset_min_seconds, threshold_offset_max_seconds)
          ''')
          .eq('event_id', eventId);

      final groupProgramsData = groupProgramsResponse as List<dynamic>;

      // Şablon oluştur (bireysel/ekip dahil tüm yeni alanlar kopyalanır)
      final templateResponse = await _supabase
          .from('event_templates')
          .insert({
            'name': templateName,
            'description': event.description,
            'event_type': event.eventType,
            'location_name': event.locationName,
            'location_address': event.locationAddress,
            'location_lat': event.locationLat,
            'location_lng': event.locationLng,
            'route_id': event.routeId,
            'training_type_id': event.trainingTypeId,
            'default_start_time':
                '${event.startTime.hour.toString().padLeft(2, '0')}:${event.startTime.minute.toString().padLeft(2, '0')}:00',
            'duration_minutes':
                event.endTime?.difference(event.startTime).inMinutes,
            'created_by': userId,
            'participation_type': event.participationType,
            'lane_config': (event.laneConfig != null && !event.laneConfig!.isEmpty)
                ? event.laneConfig!.toJson()
                : null,
          })
          .select()
          .single();

      final templateId = templateResponse['id'] as String;

      // Grup programlarını şablona ekle
      if (groupProgramsData.isNotEmpty) {
        final programsToInsert = groupProgramsData.map((p) {
          final map = <String, dynamic>{
            'template_id': templateId,
            'training_group_id': p['training_group_id'],
            'program_content': p['program_content'] ?? '',
            'route_id': p['route_id'],
            'training_type_id': p['training_type_id'],
            'sort_order': p['sort_order'] ?? 0,
          };
          if (p['workout_definition'] != null) {
            map['workout_definition'] = p['workout_definition'];
          }
          return map;
        }).toList();

        await _supabase
            .from('event_template_group_programs')
            .insert(programsToInsert);
      }

      // Tam şablonu geri getir
      return getEventTemplateById(templateId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Şablon oluşturulamadı: $e');
    }
  }

  @override
  Future<EventTemplateModel> updateEventTemplate(
      EventTemplateModel template) async {
    try {
      await _supabase
          .from('event_templates')
          .update(template.toJson())
          .eq('id', template.id);

      // Mevcut grup programlarını sil ve yeniden ekle
      await _supabase
          .from('event_template_group_programs')
          .delete()
          .eq('template_id', template.id);

      if (template.groupPrograms.isNotEmpty) {
        final programsToInsert = template.groupPrograms.map((p) {
          final map = <String, dynamic>{
            'template_id': template.id,
            'training_group_id': p.trainingGroupId,
            'program_content': p.programContent,
            'route_id': p.routeId,
            'training_type_id': p.trainingTypeId,
            'sort_order': p.sortOrder,
          };
          if (p.workoutDefinition != null) {
            map['workout_definition'] = p.workoutDefinition!.toJson();
          }
          return map;
        }).toList();

        await _supabase
            .from('event_template_group_programs')
            .insert(programsToInsert);
      }

      return getEventTemplateById(template.id);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Şablon güncellenemedi: $e');
    }
  }

  @override
  Future<void> deleteEventTemplate(String id) async {
    try {
      await _supabase.from('event_templates').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Şablon silinemedi: $e');
    }
  }

  @override
  Future<void> setEventPinned(String eventId, bool pinned) async {
    try {
      await _supabase.from('events').update({
        'is_pinned': pinned,
        'pinned_at': pinned ? DateTime.now().toUtc().toIso8601String() : null,
      }).eq('id', eventId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Etkinlik pinlenemedi: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> getEventReport({
    required DateTime startDate,
    required DateTime endDate,
    String? eventType,
    String? groupId,
  }) async {
    try {
      // Tarih aralığına göre etkinlikleri çek
      var query = _supabase
          .from('events')
          .select('id, title, start_time, event_type, participation_type')
          .eq('status', 'published')
          .gte('start_time', startDate.toIso8601String())
          .lte('start_time', endDate.toIso8601String());

      // Etkinlik türü filtresi varsa ekle
      if (eventType != null && eventType.isNotEmpty) {
        query = query.eq('event_type', eventType);
      }

      final eventsResponse = await query.order('start_time', ascending: true);

      var events = eventsResponse as List<dynamic>;
      
      // Grup filtresi varsa, o gruba atanmış etkinlikleri filtrele
      if (groupId != null && groupId.isNotEmpty) {
        final eventIds = events.map((e) => e['id'] as String).toList();
        if (eventIds.isEmpty) {
          return {
            'total_events': 0,
            'total_participants': 0,
            'average_participants': 0.0,
            'events': <Map<String, dynamic>>[],
          };
        }

        // Bu gruba atanmış etkinlik ID'lerini al
        final groupProgramsResponse = await _supabase
            .from('event_group_programs')
            .select('event_id')
            .eq('training_group_id', groupId)
            .inFilter('event_id', eventIds);

        final groupEventIds = (groupProgramsResponse as List<dynamic>)
            .map((e) => e['event_id'] as String)
            .toSet();

        // Sadece bu gruba atanmış etkinlikleri filtrele
        events = events.where((e) => groupEventIds.contains(e['id'] as String)).toList();
      }

      if (events.isEmpty) {
        return {
          'total_events': 0,
          'total_participants': 0,
          'average_participants': 0.0,
          'events': <Map<String, dynamic>>[],
        };
      }

      // Etkinlik ID'lerini ve tarihlerini topla
      final eventIds = events.map((e) => e['id'] as String).toList();
      final eventDates = <String, DateTime>{};
      for (final event in events) {
        eventDates[event['id'] as String] = DateTime.parse(event['start_time'] as String);
      }

      // Grup filtresi varsa, sadece o gruptaki kişilerin katılımlarını hesapla
      Set<String>? groupUserIds;
      if (groupId != null && groupId.isNotEmpty) {
        final groupMembersResponse = await _supabase
            .from('group_members')
            .select('user_id')
            .eq('group_id', groupId);

        groupUserIds = (groupMembersResponse as List<dynamic>)
            .map((e) => e['user_id'] as String)
            .toSet();
      }

      // Tüm RSVP'leri tek sorguda çek
      var rsvpsQuery = _supabase
          .from('event_participants')
          .select('event_id, user_id')
          .inFilter('event_id', eventIds)
          .eq('status', 'going');

      // Grup filtresi varsa, sadece o gruptaki kişilerin RSVP'lerini al
      if (groupUserIds != null && groupUserIds.isNotEmpty) {
        rsvpsQuery = rsvpsQuery.inFilter('user_id', groupUserIds.toList());
      }

      final allRsvpsResponse = await rsvpsQuery;

      // Event ID'ye göre RSVP'leri grupla
      final rsvpsByEvent = <String, Set<String>>{};
      for (final rsvp in allRsvpsResponse as List<dynamic>) {
        final eventId = rsvp['event_id'] as String;
        final userId = rsvp['user_id'] as String;
        rsvpsByEvent.putIfAbsent(eventId, () => <String>{}).add(userId);
      }

      // Tüm Strava aktivitelerini tek sorguda çek (tarih aralığına göre)
      // Tüm etkinlik tarihlerini kapsayan aralık
      final minDate = eventDates.values.reduce((a, b) => a.isBefore(b) ? a : b);
      final maxDate = eventDates.values.reduce((a, b) => a.isAfter(b) ? a : b);
      final activitiesStart = DateTime(minDate.year, minDate.month, minDate.day);
      final activitiesEnd = DateTime(maxDate.year, maxDate.month, maxDate.day).add(const Duration(days: 1));

      // Tüm Strava koşu aktivitelerini tek sorguda çek
      var activitiesQuery = _supabase
          .from('activities')
          .select('user_id, start_time')
          .gte('start_time', activitiesStart.toIso8601String())
          .lt('start_time', activitiesEnd.toIso8601String())
          .eq('source', 'strava')
          .eq('activity_type', 'running');

      // Grup filtresi varsa, sadece o gruptaki kişilerin aktivitelerini al
      if (groupUserIds != null && groupUserIds.isNotEmpty) {
        activitiesQuery = activitiesQuery.inFilter('user_id', groupUserIds.toList());
      }

      final allActivitiesResponse = await activitiesQuery;

      // Her etkinlik için katılımcıları hesapla
      final eventReports = <Map<String, dynamic>>[];
      int totalParticipants = 0;

      for (final event in events) {
        final eventId = event['id'] as String;
        final eventDate = eventDates[eventId]!;
        
        // RSVP ile katılanlar
        final rsvpUserIds = rsvpsByEvent[eventId] ?? <String>{};

        // Etkinlik tarihinde Strava aktivitesi yapmış kullanıcıları bul
        final eventDayStart = DateTime(eventDate.year, eventDate.month, eventDate.day);
        final eventDayEnd = eventDayStart.add(const Duration(days: 1));

        final activityUserIds = <String>{};
        for (final activity in allActivitiesResponse as List<dynamic>) {
          final activityStartTime = DateTime.parse(activity['start_time'] as String);
          if (activityStartTime.isAfter(eventDayStart) && activityStartTime.isBefore(eventDayEnd)) {
            activityUserIds.add(activity['user_id'] as String);
          }
        }

        // İki kümenin birleşimi (tekrar edenler tek sayılacak)
        final allParticipantIds = rsvpUserIds.union(activityUserIds);
        final participantCount = allParticipantIds.length;
        totalParticipants += participantCount;

        eventReports.add({
          'event_id': eventId,
          'event_title': event['title'] as String,
          'event_date': event['start_time'] as String,
          'participant_count': participantCount,
          'event_type': event['event_type'] as String,
          'participation_type': event['participation_type'] as String?,
        });
      }

      final totalEvents = events.length;
      final averageParticipants = totalEvents > 0 
          ? totalParticipants / totalEvents 
          : 0.0;

      return {
        'total_events': totalEvents,
        'total_participants': totalParticipants,
        'average_participants': averageParticipants,
        'events': eventReports,
      };
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Rapor alınamadı: $e');
    }
  }

  @override
  Future<List<EventActivityStatModel>> getEventActivityStats(String eventId) async {
    try {
      // Önce etkinliğin tarihini al
      final eventResponse = await _supabase
          .from('events')
          .select('start_time')
          .eq('id', eventId)
          .single();

      final eventStartTime = DateTime.parse(eventResponse['start_time'] as String);
      
      // Etkinlik tarihinin başlangıcı ve bitişi (aynı gün içinde)
      final eventDayStart = DateTime(eventStartTime.year, eventStartTime.month, eventStartTime.day);
      final eventDayEnd = eventDayStart.add(const Duration(days: 1));

      // Etkinlik tarihinde yapılan Strava koşu aktivitelerini al
      final response = await _supabase
          .from('activities')
          .select('''
            user_id,
            distance_meters,
            duration_seconds,
            average_pace_seconds,
            start_time,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .gte('start_time', eventDayStart.toIso8601String())
          .lt('start_time', eventDayEnd.toIso8601String())
          .eq('source', 'strava')
          .eq('activity_type', 'running');

      final data = response as List<dynamic>;

      // Kullanıcı bazında grupla
      final Map<String, _UserActivityAccumulator> acc = {};

      for (final raw in data) {
        final map = raw as Map<String, dynamic>;
        final userId = map['user_id'] as String;
        final distance = (map['distance_meters'] as num?)?.toDouble() ?? 0.0;
        final duration = map['duration_seconds'] as int? ?? 0;

        final userData = map['users'] as Map<String, dynamic>?;
        final firstName = (userData?['first_name'] as String?) ?? '';
        final lastName = (userData?['last_name'] as String?) ?? '';
        final avatarUrl = userData?['avatar_url'] as String?;
        final fullName = '$firstName $lastName'.trim();
        final name = fullName.isEmpty ? 'Anonim' : fullName;

        final entry = acc.putIfAbsent(
          userId,
          () => _UserActivityAccumulator(
            userId: userId,
            userName: name,
            avatarUrl: avatarUrl,
          ),
        );
        entry.totalDistanceMeters += distance;
        entry.totalDurationSeconds += duration;
      }

      // Accumulator'dan model listesine dönüştür
      return acc.values.map((e) {
        double? pace;
        if (e.totalDistanceMeters > 0 && e.totalDurationSeconds > 0) {
          final km = e.totalDistanceMeters / 1000.0;
          pace = e.totalDurationSeconds / km;
        }

        return EventActivityStatModel(
          userId: e.userId,
          userName: e.userName,
          avatarUrl: e.avatarUrl,
          totalDistanceMeters: e.totalDistanceMeters,
          totalDurationSeconds: e.totalDurationSeconds,
          averagePaceSecondsPerKm: pace,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Etkinlik aktivite istatistikleri alınamadı: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> getGroupReport({
    required String groupId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      // Grup üyelerini al
      final groupMembersResponse = await _supabase
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId);

      final groupMembers = groupMembersResponse as List<dynamic>;
      if (groupMembers.isEmpty) {
        return {
          'total_distance_meters': 0.0,
          'total_duration_seconds': 0,
          'average_pace_seconds_per_km': null,
          'user_stats': <Map<String, dynamic>>[],
        };
      }

      final groupUserIds = groupMembers.map((m) => m['user_id'] as String).toList();

      // Tarih aralığındaki aktiviteleri al
      final activitiesStart = DateTime(startDate.year, startDate.month, startDate.day);
      final activitiesEnd = DateTime(endDate.year, endDate.month, endDate.day).add(const Duration(days: 1));

      final activitiesResponse = await _supabase
          .from('activities')
          .select('''
            user_id,
            distance_meters,
            duration_seconds,
            average_pace_seconds,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .inFilter('user_id', groupUserIds)
          .gte('start_time', activitiesStart.toIso8601String())
          .lt('start_time', activitiesEnd.toIso8601String())
          .eq('source', 'strava')
          .eq('activity_type', 'running');

      final activities = activitiesResponse as List<dynamic>;

      // Kullanıcı bazında grupla
      final Map<String, _UserActivityAccumulator> acc = {};

      for (final raw in activities) {
        final map = raw as Map<String, dynamic>;
        final userId = map['user_id'] as String;
        final distance = (map['distance_meters'] as num?)?.toDouble() ?? 0.0;
        final duration = map['duration_seconds'] as int? ?? 0;

        final userData = map['users'] as Map<String, dynamic>?;
        final firstName = (userData?['first_name'] as String?) ?? '';
        final lastName = (userData?['last_name'] as String?) ?? '';
        final avatarUrl = userData?['avatar_url'] as String?;
        final fullName = '$firstName $lastName'.trim();
        final name = fullName.isEmpty ? 'Anonim' : fullName;

        final entry = acc.putIfAbsent(
          userId,
          () => _UserActivityAccumulator(
            userId: userId,
            userName: name,
            avatarUrl: avatarUrl,
          ),
        );
        entry.totalDistanceMeters += distance;
        entry.totalDurationSeconds += duration;
      }

      // Toplam istatistikleri hesapla
      double totalDistanceMeters = 0;
      int totalDurationSeconds = 0;
      for (final entry in acc.values) {
        totalDistanceMeters += entry.totalDistanceMeters;
        totalDurationSeconds += entry.totalDurationSeconds;
      }

      // Ortalama pace hesapla
      double? averagePaceSecondsPerKm;
      if (totalDistanceMeters > 0 && totalDurationSeconds > 0) {
        final km = totalDistanceMeters / 1000.0;
        averagePaceSecondsPerKm = totalDurationSeconds / km;
      }

      // Kullanıcı bazında istatistikleri hazırla
      final userStats = acc.values.map((e) {
        double? pace;
        if (e.totalDistanceMeters > 0 && e.totalDurationSeconds > 0) {
          final km = e.totalDistanceMeters / 1000.0;
          pace = e.totalDurationSeconds / km;
        }

        return {
          'user_id': e.userId,
          'user_name': e.userName,
          'avatar_url': e.avatarUrl,
          'total_distance_meters': e.totalDistanceMeters,
          'total_duration_seconds': e.totalDurationSeconds,
          'average_pace_seconds_per_km': pace,
        };
      }).toList();

      return {
        'total_distance_meters': totalDistanceMeters,
        'total_duration_seconds': totalDurationSeconds,
        'average_pace_seconds_per_km': averagePaceSecondsPerKm,
        'user_stats': userStats,
      };
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Grup raporu alınamadı: $e');
    }
  }

  @override
  Future<List<UserActivityReportModel>> getUserActivityReport({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final activitiesStart =
          DateTime(startDate.year, startDate.month, startDate.day);
      final activitiesEnd = DateTime(endDate.year, endDate.month, endDate.day)
          .add(const Duration(days: 1));

      // İlgili tarih aralığındaki tüm etkinlikleri al
      final eventsResponse = await _supabase
          .from('events')
          .select('id, title, start_time')
          .eq('status', 'published')
          .gte('start_time', activitiesStart.toIso8601String())
          .lt('start_time', activitiesEnd.toIso8601String());

      final eventsData = eventsResponse as List<dynamic>;

      // Etkinlikleri gün bazında grupla (sadece tarih kısmı önemli)
      final Map<DateTime, List<Map<String, dynamic>>> eventsByDay = {};
      for (final raw in eventsData) {
        final e = raw as Map<String, dynamic>;
        final start = DateTime.parse(e['start_time'] as String);
        final day = DateTime(start.year, start.month, start.day);
        eventsByDay.putIfAbsent(day, () => []).add(e);
      }

      final response = await _supabase
          .from('activities')
          .select('''
            id,
            event_id,
            start_time,
            distance_meters,
            duration_seconds,
            average_pace_seconds,
            events!left(id, title, start_time)
          ''')
          .eq('user_id', userId)
          .gte('start_time', activitiesStart.toIso8601String())
          .lt('start_time', activitiesEnd.toIso8601String())
          .eq('source', 'strava')
          .eq('activity_type', 'running')
          .order('start_time', ascending: false);

      final data = response as List<dynamic>;

      return data.map((raw) {
        final map = raw as Map<String, dynamic>;

        // Önce doğrudan ilişkili etkinlik (event_id) var mı bak
        Map<String, dynamic>? eventData =
            map['events'] as Map<String, dynamic>?;

        // Eğer doğrudan ilişki yoksa, aynı gün içinde yayınlanmış
        // bir etkinlik var mı ona bak (Strava koşusu ama etkinliğe katılmamış senaryosu)
        String? effectiveEventId = map['event_id'] as String?;
        String? effectiveEventTitle =
            eventData != null ? eventData['title'] as String? : null;

        if (effectiveEventId == null) {
          final activityStart =
              DateTime.parse(map['start_time'] as String);
          final activityDay = DateTime(
              activityStart.year, activityStart.month, activityStart.day);

          final candidates = eventsByDay[activityDay];
          if (candidates != null && candidates.isNotEmpty) {
            final first = candidates.first;
            effectiveEventId = first['id'] as String?;
            effectiveEventTitle = first['title'] as String?;
          }
        }

        return UserActivityReportModel.fromJson({
          'activity_id': map['id'] as String,
          'event_id': effectiveEventId,
          'event_title': effectiveEventTitle,
          'start_time': map['start_time'] as String,
          'distance_meters':
              (map['distance_meters'] as num?)?.toDouble() ?? 0.0,
          'duration_seconds': map['duration_seconds'] as int? ?? 0,
          'average_pace_seconds_per_km':
              (map['average_pace_seconds'] as num?)?.toDouble(),
        });
      }).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Kullanıcı aktivite raporu alınamadı: $e');
    }
  }
}

class _UserActivityAccumulator {
  final String userId;
  final String userName;
  final String? avatarUrl;
  double totalDistanceMeters;
  int totalDurationSeconds;

  _UserActivityAccumulator({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
  })  : totalDistanceMeters = 0,
        totalDurationSeconds = 0;
}

