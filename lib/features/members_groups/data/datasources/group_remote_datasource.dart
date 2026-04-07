import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../auth/data/models/user_model.dart';
import '../models/group_model.dart';

/// Group Remote DataSource
class GroupRemoteDataSource {
  final SupabaseClient _supabase;

  GroupRemoteDataSource(this._supabase);

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  /// Tüm aktif grupları getir
  Future<List<TrainingGroupModel>> getGroups() async {
    // Tüm grupları tek sorguda al
    final groupsResponse = await _supabase
        .from('training_groups')
        .select('id, name, description, target_distance, difficulty_level, color, icon, is_active, group_type, created_by, created_at')
        .eq('is_active', true)
        .order('difficulty_level', ascending: true);

    if ((groupsResponse as List).isEmpty) {
      return [];
    }

    // Tüm grup ID'lerini al
    final groupIds = (groupsResponse as List)
        .map((g) => g['id'] as String)
        .toList();

    // Kullanıcının üye olduğu grupları tek sorguda al
    final userMemberGroups = <String>{};
    if (_currentUserId != null) {
      final userMembershipsResponse = await _supabase
          .from('group_members')
          .select('group_id')
          .eq('user_id', _currentUserId!)
          .inFilter('group_id', groupIds);

      for (final membership in userMembershipsResponse as List) {
        userMemberGroups.add(membership['group_id'] as String);
      }
    }

    // Grupları oluştur (üye sayısı 0 olarak ayarlanır, detay sayfasında gösterilir)
    final groups = <TrainingGroupModel>[];
    for (final json in groupsResponse as List) {
      final groupId = json['id'] as String;
      final isUserMember = userMemberGroups.contains(groupId);

      groups.add(TrainingGroupModel.fromJson(
        json as Map<String, dynamic>,
        memberCount: 0, // Liste sayfasında gösterilmediği için 0
        isUserMember: isUserMember,
      ));
    }

    return groups;
  }

  /// Grup detayını getir
  Future<TrainingGroupModel> getGroupById(String groupId) async {
    final response = await _supabase
        .from('training_groups')
        .select('id, name, description, target_distance, difficulty_level, color, icon, is_active, group_type, created_by, created_at')
        .eq('id', groupId)
        .single();

    // Üye sayısını al
    final memberCountResponse = await _supabase
        .from('group_members')
        .select()
        .eq('group_id', groupId);
    final memberCount = (memberCountResponse as List).length;

    // Kullanıcı üye mi kontrol et
    bool isUserMember = false;
    if (_currentUserId != null) {
      final membershipResponse = await _supabase
          .from('group_members')
          .select()
          .eq('group_id', groupId)
          .eq('user_id', _currentUserId!)
          .maybeSingle();
      isUserMember = membershipResponse != null;
    }

    return TrainingGroupModel.fromJson(
      response,
      memberCount: memberCount,
      isUserMember: isUserMember,
    );
  }

  /// Kullanıcının üye olduğu grupları getir
  Future<List<TrainingGroupModel>> getUserGroups(String userId) async {
    final response = await _supabase
        .from('group_members')
        .select('group_id, training_groups(id, name, description, target_distance, difficulty_level, color, icon, is_active, group_type, created_by, created_at)')
        .eq('user_id', userId);

    final groups = <TrainingGroupModel>[];
    for (final json in response as List) {
      final groupData = json['training_groups'] as Map<String, dynamic>?;
      if (groupData != null) {
        groups.add(TrainingGroupModel.fromJson(
          groupData,
          isUserMember: true,
        ));
      }
    }

    return groups;
  }

  /// Grup üyelerini getir
  Future<List<GroupMemberModel>> getGroupMembers(String groupId) async {
    final response = await _supabase
        .from('group_members')
        .select('*, users(first_name, last_name, avatar_url)')
        .eq('group_id', groupId)
        .order('joined_at', ascending: true);

    return (response as List)
        .map((json) => GroupMemberModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Kullanıcının şu an üye olduğu grubun ID'si (yoksa null).
  Future<String?> getCurrentUserGroupId() async {
    if (_currentUserId == null) return null;
    final response = await _supabase
        .from('group_members')
        .select('group_id')
        .eq('user_id', _currentUserId!)
        .maybeSingle();
    return response?['group_id'] as String?;
  }

  /// Gruba katıl. Performans grubuysa talep oluşturur, normal gruba direkt katılır.
  /// Kullanıcı zaten başka bir gruba üyeyse UserAlreadyInGroupException fırlatır.
  Future<void> joinGroup(String groupId) async {
    if (_currentUserId == null) {
      throw Exception('Kullanıcı giriş yapmamış');
    }

    // Grup tipini kontrol et
    final groupRow = await _supabase
        .from('training_groups')
        .select('group_type, name')
        .eq('id', groupId)
        .single();

    final groupType = groupRow['group_type'] as String? ?? 'normal';

    if (groupType == 'performance') {
      // Performans grubu - talep oluştur
      await requestJoinGroup(groupId);
      return;
    }

    // Normal grup - direkt katıl
    final currentGroupId = await getCurrentUserGroupId();
    if (currentGroupId != null && currentGroupId != groupId) {
      final currentGroupRow = await _supabase
          .from('training_groups')
          .select('name')
          .eq('id', currentGroupId)
          .maybeSingle();
      final groupName = currentGroupRow?['name'] as String? ?? 'mevcut grup';
      throw UserAlreadyInGroupException(
        message:
            'Zaten bir gruba üyesiniz. Başka gruba geçmek için önce mevcut gruptan ayrılmalısınız.',
        currentGroupId: currentGroupId,
        currentGroupName: groupName,
      );
    }

    await _supabase.from('group_members').insert({
      'group_id': groupId,
      'user_id': _currentUserId,
    });
  }

  /// Gruptan ayrıl
  Future<void> leaveGroup(String groupId) async {
    if (_currentUserId == null) {
      throw Exception('Kullanıcı giriş yapmamış');
    }

    await _supabase
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', _currentUserId!);

    // Performans grubundan ayrılınca tekrar katılım için yeniden onay gereksin:
    // (group_id,user_id) unique olduğu için eski approved kaydı kalırsa yeni talep açılamaz.
    final groupRow = await _supabase
        .from('training_groups')
        .select('group_type')
        .eq('id', groupId)
        .maybeSingle();
    final groupType = groupRow?['group_type'] as String? ?? 'normal';
    if (groupType == 'performance') {
      await _supabase
          .from('group_join_requests')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', _currentUserId!);
    }
  }

  /// Belirli bir kullanıcının üye olduğu grubun ID'si (yoksa null).
  Future<String?> getUserGroupId(String userId) async {
    final response = await _supabase
        .from('group_members')
        .select('group_id')
        .eq('user_id', userId)
        .maybeSingle();
    return response?['group_id'] as String?;
  }

  // ==================== Join Requests (Performans Grupları) ====================

  /// Performans grubuna katılım talebi oluştur
  Future<void> requestJoinGroup(String groupId) async {
    if (_currentUserId == null) {
      throw Exception('Kullanıcı giriş yapmamış');
    }

    // Aynı kullanıcı+grup için daha önce talep var mı?
    final existing = await _supabase
        .from('group_join_requests')
        .select('id, status')
        .eq('group_id', groupId)
        .eq('user_id', _currentUserId!)
        .maybeSingle();

    if (existing != null) {
      final status = (existing['status'] as String?) ?? 'pending';
      if (status == 'pending') {
        // İstek zaten gönderilmiş: idempotent davran, hata verme.
        return;
      }
      if (status == 'approved') {
        // Talep daha önce onaylanmış olabilir ama kullanıcı gruptan çıkmışsa
        // yeniden katılım için tekrar onay gereksin: pending'e çek.
        await _supabase
            .from('group_join_requests')
            .update({'status': 'pending', 'requested_at': DateTime.now().toIso8601String()})
            .eq('id', existing['id'] as String);
        return;
      }
      // rejected/diğer: aşağıda yeniden pending'e çekilecek
    }

    // Unique constraint (group_id,user_id) olduğu için insert yerine upsert kullan.
    // Böylece mevcut kayıt rejected ise yeniden pending olur; varsa duplicate key hatası düşmez.
    try {
      await _supabase.from('group_join_requests').upsert(
        {
          'group_id': groupId,
          'user_id': _currentUserId,
          'status': 'pending',
        },
        onConflict: 'group_id,user_id',
      );
    } on PostgrestException catch (e) {
      // 23505: duplicate key -> zaten talep vardır; idempotent davran.
      if (e.code == '23505') return;
      rethrow;
    }
  }

  /// Grubun katılım taleplerini getir (admin)
  Future<List<GroupJoinRequestModel>> getGroupJoinRequests(String groupId) async {
    final response = await _supabase
        .from('group_join_requests')
        .select('*, users!group_join_requests_user_id_fkey(first_name, last_name, avatar_url)')
        .eq('group_id', groupId)
        .eq('status', 'pending')
        .order('requested_at', ascending: true);

    return (response as List)
        .map((json) => GroupJoinRequestModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Tüm grupların bekleyen katılım taleplerini getir (admin)
  Future<List<GroupJoinRequestModel>> getAllPendingJoinRequests() async {
    final response = await _supabase
        .from('group_join_requests')
        .select('*, users!group_join_requests_user_id_fkey(first_name, last_name, avatar_url), training_groups(name)')
        .eq('status', 'pending')
        .order('requested_at', ascending: true);

    return (response as List)
        .map((json) => GroupJoinRequestModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Kullanıcının bekleyen taleplerini getir
  Future<List<GroupJoinRequestModel>> getUserPendingJoinRequests() async {
    if (_currentUserId == null) return [];

    final response = await _supabase
        .from('group_join_requests')
        .select('*, users!group_join_requests_user_id_fkey(first_name, last_name, avatar_url)')
        .eq('user_id', _currentUserId!)
        .eq('status', 'pending')
        .order('requested_at', ascending: true);

    return (response as List)
        .map((json) => GroupJoinRequestModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Katılım talebini onayla (admin) - RPC kullanır
  Future<void> approveJoinRequest(String requestId) async {
    if (_currentUserId == null) {
      throw Exception('Kullanıcı giriş yapmamış');
    }

    await _supabase.rpc('approve_group_join_request', params: {
      'request_id': requestId,
      'admin_user_id': _currentUserId,
    });
  }

  /// Katılım talebini reddet (admin)
  Future<void> rejectJoinRequest(String requestId) async {
    if (_currentUserId == null) {
      throw Exception('Kullanıcı giriş yapmamış');
    }

    await _supabase
        .from('group_join_requests')
        .update({
          'status': 'rejected',
          'responded_at': DateTime.now().toIso8601String(),
          'responded_by': _currentUserId,
        })
        .eq('id', requestId);
  }

  /// Kullanıcının bekleyen talebini iptal et
  Future<void> cancelJoinRequest(String groupId) async {
    if (_currentUserId == null) {
      throw Exception('Kullanıcı giriş yapmamış');
    }

    await _supabase
        .from('group_join_requests')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', _currentUserId!)
        .eq('status', 'pending');
  }

  /// Kullanıcıyı başka bir gruba taşı (admin).
  /// Kullanıcı zaten bir gruptaysa önce mevcut gruptan çıkarılır, sonra yeni gruba eklenir.
  Future<void> transferMemberToGroup(String userId, String targetGroupId) async {
    // 1. Mevcut gruptan çıkar (varsa)
    final currentGroupId = await getUserGroupId(userId);
    if (currentGroupId != null) {
      await _supabase
          .from('group_members')
          .delete()
          .eq('user_id', userId)
          .eq('group_id', currentGroupId);
    }

    // 2. Yeni gruba ekle
    await _supabase.from('group_members').insert({
      'group_id': targetGroupId,
      'user_id': userId,
    });
  }

  /// Grubun tipini getir
  Future<String> getGroupType(String groupId) async {
    final response = await _supabase
        .from('training_groups')
        .select('group_type')
        .eq('id', groupId)
        .single();
    return response['group_type'] as String? ?? 'normal';
  }

  /// Kullanıcının belirli bir gruba bekleyen talebi var mı?
  Future<bool> hasUserPendingRequest(String groupId) async {
    if (_currentUserId == null) return false;

    final response = await _supabase
        .from('group_join_requests')
        .select('id')
        .eq('group_id', groupId)
        .eq('user_id', _currentUserId!)
        .eq('status', 'pending')
        .maybeSingle();

    return response != null;
  }

  /// Gruba üye ekle (Admin). Kullanıcı zaten başka bir gruba üyeyse UserAlreadyInGroupException fırlatır.
  Future<void> addMemberToGroup(String groupId, String userId) async {
    final currentGroupId = await getUserGroupId(userId);
    if (currentGroupId != null && currentGroupId != groupId) {
      final groupRow = await _supabase
          .from('training_groups')
          .select('name')
          .eq('id', currentGroupId)
          .maybeSingle();
      final groupName = groupRow?['name'] as String? ?? 'mevcut grup';
      throw UserAlreadyInGroupException(
        message:
            'Bu kullanıcı zaten bir gruba üye. Başka gruba eklemek için önce mevcut gruptan çıkarılmalı.',
        currentGroupId: currentGroupId,
        currentGroupName: groupName,
      );
    }
    await _supabase.from('group_members').insert({
      'group_id': groupId,
      'user_id': userId,
    });
  }

  /// Gruptan üye çıkar (Admin)
  Future<void> removeMemberFromGroup(String groupId, String userId) async {
    await _supabase
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId);
  }

  /// Yeni grup oluştur (Admin)
  Future<TrainingGroupModel> createGroup(TrainingGroupModel group) async {
    final data = group.toJson();
    data['created_by'] = _currentUserId;

    final response = await _supabase
        .from('training_groups')
        .insert(data)
        .select()
        .single();

    return TrainingGroupModel.fromJson(response);
  }

  /// Grup güncelle (Admin)
  Future<TrainingGroupModel> updateGroup(TrainingGroupModel group) async {
    final response = await _supabase
        .from('training_groups')
        .update(group.toJson())
        .eq('id', group.id)
        .select()
        .single();

    return TrainingGroupModel.fromJson(response);
  }

  /// Grup sil (Admin)
  Future<void> deleteGroup(String groupId) async {
    await _supabase.from('training_groups').delete().eq('id', groupId);
  }

  // ==================== Event Group Programs ====================

  /// Etkinliğin grup programlarını getir
  Future<List<EventGroupProgramModel>> getEventGroupPrograms(
    String eventId,
  ) async {
    final response = await _supabase
        .from('event_group_programs')
        .select('*, training_groups(name, color), routes(name), training_types(display_name, description, color, threshold_offset_min_seconds, threshold_offset_max_seconds)')
        .eq('event_id', eventId)
        .order('order_index', ascending: true);

    return (response as List)
        .map((json) =>
            EventGroupProgramModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Kullanıcının gruplarına göre etkinlik programlarını getir
  Future<List<EventGroupProgramModel>> getUserEventGroupPrograms(
    String eventId,
  ) async {
    if (_currentUserId == null) {
      return [];
    }

    // 037 migration sonrası kullanıcı tek grupta olmalı (UNIQUE(user_id)).
    // Önce tek kaydı okumayı dene (daha deterministik, daha az edge-case).
    final singleMembership = await _supabase
        .from('group_members')
        .select('group_id')
        .eq('user_id', _currentUserId!)
        .maybeSingle();

    List<String> groupIds;
    if (singleMembership != null && singleMembership['group_id'] != null) {
      groupIds = [(singleMembership['group_id'] as String)];
    } else {
      // Fallback: birden fazla üyelik veya eski veriler için liste çek.
      final userGroups = await _supabase
          .from('group_members')
          .select('group_id')
          .eq('user_id', _currentUserId!);
      groupIds =
          (userGroups as List).map((g) => g['group_id'] as String).toList();
    }

    if (groupIds.isEmpty) return [];

    // Bu gruplara ait programları getir
    final response = await _supabase
        .from('event_group_programs')
        .select(
          '*, training_groups(name, color), routes(name), training_types(display_name, description, color, threshold_offset_min_seconds, threshold_offset_max_seconds)',
        )
        .eq('event_id', eventId)
        .inFilter('training_group_id', groupIds)
        .order('order_index', ascending: true);

    return (response as List)
        .map(
            (json) => EventGroupProgramModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Etkinliğe grup programı ekle
  Future<EventGroupProgramModel> addEventGroupProgram(
    EventGroupProgramModel program,
  ) async {
    final response = await _supabase
        .from('event_group_programs')
        .insert(program.toJson())
        .select('*, training_groups(name, color), routes(name)')
        .single();

    return EventGroupProgramModel.fromJson(response);
  }

  /// Etkinlik grup programını güncelle
  Future<EventGroupProgramModel> updateEventGroupProgram(
    EventGroupProgramModel program,
  ) async {
    final response = await _supabase
        .from('event_group_programs')
        .update(program.toJson())
        .eq('id', program.id)
        .select('*, training_groups(name, color), routes(name)')
        .single();

    return EventGroupProgramModel.fromJson(response);
  }

  /// Etkinlik grup programını sil
  Future<void> deleteEventGroupProgram(String programId) async {
    await _supabase.from('event_group_programs').delete().eq('id', programId);
  }

  /// Etkinliğin tüm grup programlarını sil ve yenilerini ekle
  Future<List<EventGroupProgramModel>> saveEventGroupPrograms(
    String eventId,
    List<EventGroupProgramModel> programs,
  ) async {
    // Önce mevcut programları sil
    await _supabase
        .from('event_group_programs')
        .delete()
        .eq('event_id', eventId);

    if (programs.isEmpty) {
      return [];
    }

    // Yeni programları ekle
    final dataList = programs.asMap().entries.map((entry) {
      final program = entry.value;
      final data = program.toJson();
      data['event_id'] = eventId;
      data['order_index'] = entry.key;
      return data;
    }).toList();

    final response = await _supabase
        .from('event_group_programs')
        .insert(dataList)
        .select('*, training_groups(name, color), routes(name)');

    return (response as List)
        .map((json) =>
            EventGroupProgramModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // ==================== Event Member Programs (Performans Grupları) ====================

  /// Performans grubunun etkinlik için üye bazlı programlarını getir
  Future<List<EventMemberProgramModel>> getEventMemberPrograms(
    String eventId,
    String groupId,
  ) async {
    final response = await _supabase
        .from('event_member_programs')
        .select('*, users(first_name, last_name, avatar_url), training_groups(name, color), routes(name), training_types(display_name, description, color, threshold_offset_min_seconds, threshold_offset_max_seconds)')
        .eq('event_id', eventId)
        .eq('training_group_id', groupId)
        .order('order_index', ascending: true);

    return (response as List)
        .map((json) => EventMemberProgramModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Kullanıcının performans grubu kişisel programını getir
  Future<List<EventMemberProgramModel>> getUserEventMemberPrograms(
    String eventId,
  ) async {
    if (_currentUserId == null) return [];

    final response = await _supabase
        .from('event_member_programs')
        .select('*, users(first_name, last_name, avatar_url), training_groups(name, color), routes(name), training_types(display_name, description, color, threshold_offset_min_seconds, threshold_offset_max_seconds)')
        .eq('event_id', eventId)
        .eq('user_id', _currentUserId!)
        .order('order_index', ascending: true);

    return (response as List)
        .map((json) => EventMemberProgramModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Performans grubu için etkinlik üye programlarını kaydet (sil ve yeniden ekle)
  Future<List<EventMemberProgramModel>> saveEventMemberPrograms(
    String eventId,
    String groupId,
    List<EventMemberProgramModel> programs,
  ) async {
    const placeholderProgramContent = 'Kişiye özel program';

    // Önce bu grubun mevcut programlarını sil
    await _supabase
        .from('event_member_programs')
        .delete()
        .eq('event_id', eventId)
        .eq('training_group_id', groupId);

    if (programs.isEmpty) {
      // Performans grubu bu etkinlikten kaldırıldıysa, placeholder group-program kaydını da temizle
      final existing = await _supabase
          .from('event_group_programs')
          .select('id, program_content')
          .eq('event_id', eventId)
          .eq('training_group_id', groupId)
          .maybeSingle();

      if (existing != null &&
          (existing['program_content'] as String?) == placeholderProgramContent) {
        await _supabase
            .from('event_group_programs')
            .delete()
            .eq('id', existing['id'] as String);
      }

      return [];
    }

    final dataList = programs.asMap().entries.map((entry) {
      final program = entry.value;
      final data = program.toJson();
      data['event_id'] = eventId;
      data['training_group_id'] = groupId;
      data['order_index'] = entry.key;
      return data;
    }).toList();

    final response = await _supabase
        .from('event_member_programs')
        .insert(dataList)
        .select('*, users(first_name, last_name, avatar_url), training_groups(name, color), routes(name)');

    // Bu performans grubunun etkinliğe "dahil" olduğunu göstermek için event_group_programs'a placeholder kayıt ekle.
    // Not: Mevcut (admin tarafından) gerçek bir grup programı varsa üzerine yazmamak için önce var mı kontrol ederiz.
    final existingGroupProgram = await _supabase
        .from('event_group_programs')
        .select('id')
        .eq('event_id', eventId)
        .eq('training_group_id', groupId)
        .maybeSingle();

    if (existingGroupProgram == null) {
      await _supabase.from('event_group_programs').insert({
        'event_id': eventId,
        'training_group_id': groupId,
        'program_content': placeholderProgramContent,
        'order_index': 0,
      });
    }

    return (response as List)
        .map((json) => EventMemberProgramModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // ==================== User Management ====================

  /// Tüm aktif kullanıcıları getir
  Future<List<UserModel>> getActiveUsers() async {
    final response = await _supabase
        .from('users')
        .select('*')
        .eq('is_active', true)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => UserModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Onay bekleyen kullanıcıları getir (sadece admin için)
  Future<List<UserModel>> getPendingUsers() async {
    final response = await _supabase
        .from('users')
        .select('*')
        .eq('is_active', false)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => UserModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Herhangi bir gruba üye olmayan (aktif) kullanıcıları getir
  Future<List<UserModel>> getUsersWithoutGroup() async {
    // Supabase left-join + null filtresi bazen ilişki/alias tarafında
    // beklenildiği gibi davranmayabiliyor. Bu yüzden iki adımda ilerliyoruz:
    // 1) Aktif tüm kullanıcıları çek
    // 2) group_members içindeki tüm user_id'leri alıp filtrele
    final activeUsersResponse = await _supabase
        .from('users')
        .select('*')
        .eq('is_active', true)
        .order('created_at', ascending: false);

    final activeUsers = (activeUsersResponse as List)
        .map((json) => UserModel.fromJson(json as Map<String, dynamic>))
        .toList();

    if (activeUsers.isEmpty) return [];

    // Sadece aktif gruplar üzerinden üyelik kontrolü yap
    final activeGroupIdsResponse = await _supabase
        .from('training_groups')
        .select('id')
        .eq('is_active', true);

    final activeGroupIds = (activeGroupIdsResponse as List)
        .map((row) => row['id'] as String)
        .toList();

    // Aktif grup yoksa herkes "gruba dahil olmayan" kabul edilir.
    if (activeGroupIds.isEmpty) return activeUsers;

    final memberIdsResponse = await _supabase
        .from('group_members')
        .select('user_id')
        .inFilter('group_id', activeGroupIds);
    final memberIds = (memberIdsResponse as List)
        .map((row) => row['user_id'] as String)
        .toSet();

    return activeUsers
        .where((u) => !memberIds.contains(u.id))
        .toList();
  }

  /// Kullanıcıyı onayla (admin için)
  Future<void> approveUser(String userId) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      throw Exception('Kullanıcı giriş yapmamış');
    }

    // Supabase RPC fonksiyonunu çağır
    await _supabase.rpc('approve_user', params: {
      'user_id_to_approve': userId,
      'approved_by': currentUserId,
    });
  }

  /// Kullanıcıyı pasifleştir (admin için)
  Future<void> deactivateUser(String userId) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      throw Exception('Kullanıcı giriş yapmamış');
    }

    // Supabase RPC fonksiyonunu çağır
    await _supabase.rpc('deactivate_user', params: {
      'user_id_to_deactivate': userId,
      'deactivated_by': currentUserId,
    });
  }

  /// Kullanıcının rolünü güncelle (admin için)
  /// roles: Güncellenecek rol listesi (ör: ['member', 'coach'] veya ['super_admin'])
  Future<void> updateUserRole(String userId, List<String> roles) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      throw Exception('Kullanıcı giriş yapmamış');
    }

    // Admin kullanıcıların rolü değiştirilemez
    final existingRoles = await _supabase
        .from('user_roles')
        .select('role')
        .eq('user_id', userId);

    final hasSuperAdminRole = (existingRoles as List)
        .any((row) => row['role'] == 'super_admin');

    if (hasSuperAdminRole) {
      throw Exception('Admin rolüne sahip kullanıcıların rolü değiştirilemez.');
    }

    // Önce mevcut rolleri sil
    await _supabase
        .from('user_roles')
        .delete()
        .eq('user_id', userId);

    // Yeni rolleri ekle
    if (roles.isNotEmpty) {
      final roleData = roles.map((role) => {
        'user_id': userId,
        'role': role,
        'assigned_by': currentUserId,
      }).toList();

      await _supabase.from('user_roles').insert(roleData);
    } else {
      // Eğer rol yoksa, varsayılan olarak member rolü ekle
      await _supabase.from('user_roles').insert({
        'user_id': userId,
        'role': 'member',
        'assigned_by': currentUserId,
      });
    }
  }
}
