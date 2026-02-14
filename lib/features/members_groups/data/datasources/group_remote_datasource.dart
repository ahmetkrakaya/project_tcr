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
        .select('id, name, description, target_distance, difficulty_level, color, icon, is_active, created_by, created_at')
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
        .select('id, name, description, target_distance, difficulty_level, color, icon, is_active, created_by, created_at')
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
        .select('group_id, training_groups(id, name, description, target_distance, difficulty_level, color, icon, is_active, created_by, created_at)')
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

  /// Gruba katıl. Kullanıcı zaten başka bir gruba üyeyse UserAlreadyInGroupException fırlatır.
  Future<void> joinGroup(String groupId) async {
    if (_currentUserId == null) {
      throw Exception('Kullanıcı giriş yapmamış');
    }

    final currentGroupId = await getCurrentUserGroupId();
    if (currentGroupId != null && currentGroupId != groupId) {
      final groupRow = await _supabase
          .from('training_groups')
          .select('name')
          .eq('id', currentGroupId)
          .maybeSingle();
      final groupName = groupRow?['name'] as String? ?? 'mevcut grup';
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

    // Kullanıcının grup ID'lerini al
    final userGroups = await _supabase
        .from('group_members')
        .select('group_id')
        .eq('user_id', _currentUserId!);

    final groupIds =
        (userGroups as List).map((g) => g['group_id'] as String).toList();

    if (groupIds.isEmpty) {
      return [];
    }

    // Bu gruplara ait programları getir
    final response = await _supabase
        .from('event_group_programs')
        .select('*, training_groups(name, color), routes(name), training_types(display_name, description, color, threshold_offset_min_seconds, threshold_offset_max_seconds)')
        .eq('event_id', eventId)
        .inFilter('training_group_id', groupIds)
        .order('order_index', ascending: true);

    return (response as List)
        .map((json) =>
            EventGroupProgramModel.fromJson(json as Map<String, dynamic>))
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
