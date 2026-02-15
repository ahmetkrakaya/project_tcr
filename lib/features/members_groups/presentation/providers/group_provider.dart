import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/domain/entities/user_entity.dart';
import '../../data/datasources/group_remote_datasource.dart';
import '../../data/models/group_model.dart';
import '../../domain/entities/group_entity.dart';

/// Supabase client provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Group datasource provider
final groupDataSourceProvider = Provider<GroupRemoteDataSource>((ref) {
  final supabase = ref.watch(_supabaseProvider);
  return GroupRemoteDataSource(supabase);
});

/// Tüm gruplar provider (cache ile optimize edilmiş)
final allGroupsProvider = FutureProvider<List<TrainingGroupEntity>>((ref) async {
  final dataSource = ref.watch(groupDataSourceProvider);
  final models = await dataSource.getGroups();
  return models.map((m) => m.toEntity()).toList();
});

/// Kullanıcının grupları (computed)
final userGroupsComputedProvider = Provider<List<TrainingGroupEntity>>((ref) {
  final groupsAsync = ref.watch(allGroupsProvider);
  return groupsAsync.maybeWhen(
    data: (groups) => groups.where((g) => g.isUserMember).toList(),
    orElse: () => [],
  );
});

/// Diğer gruplar (computed)
final otherGroupsComputedProvider = Provider<List<TrainingGroupEntity>>((ref) {
  final groupsAsync = ref.watch(allGroupsProvider);
  return groupsAsync.maybeWhen(
    data: (groups) => groups.where((g) => !g.isUserMember).toList(),
    orElse: () => [],
  );
});

/// Tek grup provider
final groupByIdProvider =
    FutureProvider.family<TrainingGroupEntity, String>((ref, id) async {
  final dataSource = ref.watch(groupDataSourceProvider);
  final model = await dataSource.getGroupById(id);
  return model.toEntity();
});

/// Kullanıcının grupları provider
final userGroupsProvider = FutureProvider<List<TrainingGroupEntity>>((ref) async {
  final dataSource = ref.watch(groupDataSourceProvider);
  final userId = Supabase.instance.client.auth.currentUser?.id;
  
  if (userId == null) {
    return [];
  }
  
  final models = await dataSource.getUserGroups(userId);
  return models.map((m) => m.toEntity()).toList();
});

/// Grup üyeleri provider
final groupMembersProvider =
    FutureProvider.family<List<GroupMemberEntity>, String>((ref, groupId) async {
  final dataSource = ref.watch(groupDataSourceProvider);
  final models = await dataSource.getGroupMembers(groupId);
  return models.map((m) => m.toEntity()).toList();
});

/// Gruba katılma/ayrılma state
class GroupMembershipNotifier extends StateNotifier<AsyncValue<void>> {
  final GroupRemoteDataSource _dataSource;
  final Ref _ref;

  GroupMembershipNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<void> joinGroup(String groupId) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.joinGroup(groupId);
      state = const AsyncValue.data(null);
      
      // Refresh providers
      _ref.invalidate(allGroupsProvider);
      _ref.invalidate(userGroupsProvider);
      _ref.invalidate(groupByIdProvider(groupId));
      _ref.invalidate(groupMembersProvider(groupId));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> leaveGroup(String groupId) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.leaveGroup(groupId);
      state = const AsyncValue.data(null);
      
      // Refresh providers
      _ref.invalidate(allGroupsProvider);
      _ref.invalidate(userGroupsProvider);
      _ref.invalidate(groupByIdProvider(groupId));
      _ref.invalidate(groupMembersProvider(groupId));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Gruba katılma/ayrılma provider
final groupMembershipProvider =
    StateNotifierProvider<GroupMembershipNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(groupDataSourceProvider);
  return GroupMembershipNotifier(dataSource, ref);
});

/// Grup oluşturma state
class GroupCreationState {
  final bool isLoading;
  final String? error;
  final TrainingGroupEntity? createdGroup;

  const GroupCreationState({
    this.isLoading = false,
    this.error,
    this.createdGroup,
  });

  GroupCreationState copyWith({
    bool? isLoading,
    String? error,
    TrainingGroupEntity? createdGroup,
  }) {
    return GroupCreationState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      createdGroup: createdGroup ?? this.createdGroup,
    );
  }
}

/// Grup oluşturma notifier
class GroupCreationNotifier extends StateNotifier<GroupCreationState> {
  final GroupRemoteDataSource _dataSource;
  final Ref _ref;

  GroupCreationNotifier(this._dataSource, this._ref)
      : super(const GroupCreationState());

  Future<void> createGroup({
    required String name,
    String? description,
    String? targetDistance,
    int difficultyLevel = 1,
    String color = '#3B82F6',
    String icon = 'directions_run',
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final model = TrainingGroupModel(
        id: '',
        name: name,
        description: description,
        targetDistance: targetDistance,
        difficultyLevel: difficultyLevel,
        color: color,
        icon: icon,
        isActive: true,
        createdAt: DateTime.now(),
      );

      final created = await _dataSource.createGroup(model);

      state = state.copyWith(
        isLoading: false,
        createdGroup: created.toEntity(),
      );

      // Refresh groups
      _ref.invalidate(allGroupsProvider);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> updateGroup({
    required String groupId,
    required String name,
    String? description,
    String? targetDistance,
    int difficultyLevel = 1,
    String color = '#3B82F6',
    String icon = 'directions_run',
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final model = TrainingGroupModel(
        id: groupId,
        name: name,
        description: description,
        targetDistance: targetDistance,
        difficultyLevel: difficultyLevel,
        color: color,
        icon: icon,
        isActive: true,
        createdAt: DateTime.now(),
      );

      final updated = await _dataSource.updateGroup(model);

      state = state.copyWith(
        isLoading: false,
        createdGroup: updated.toEntity(),
      );

      // Refresh groups
      _ref.invalidate(allGroupsProvider);
      _ref.invalidate(groupByIdProvider(groupId));
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void reset() {
    state = const GroupCreationState();
  }
}

/// Grup oluşturma provider
final groupCreationProvider =
    StateNotifierProvider<GroupCreationNotifier, GroupCreationState>((ref) {
  final dataSource = ref.watch(groupDataSourceProvider);
  return GroupCreationNotifier(dataSource, ref);
});

/// Grup silme provider
final groupDeleteProvider =
    StateNotifierProvider<GroupDeleteNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(groupDataSourceProvider);
  return GroupDeleteNotifier(dataSource, ref);
});

class GroupDeleteNotifier extends StateNotifier<AsyncValue<void>> {
  final GroupRemoteDataSource _dataSource;
  final Ref _ref;

  GroupDeleteNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<void> deleteGroup(String groupId) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.deleteGroup(groupId);
      state = const AsyncValue.data(null);
      _ref.invalidate(allGroupsProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

// ==================== Event Group Programs ====================

/// Etkinliğin grup programları provider
final eventGroupProgramsProvider =
    FutureProvider.family<List<EventGroupProgramEntity>, String>((ref, eventId) async {
  final dataSource = ref.watch(groupDataSourceProvider);
  final models = await dataSource.getEventGroupPrograms(eventId);
  return models.map((m) => m.toEntity()).toList();
});

/// Kullanıcının gruplarına göre etkinlik programları provider
final userEventGroupProgramsProvider =
    FutureProvider.family<List<EventGroupProgramEntity>, String>((ref, eventId) async {
  final dataSource = ref.watch(groupDataSourceProvider);
  final models = await dataSource.getUserEventGroupPrograms(eventId);
  return models.map((m) => m.toEntity()).toList();
});

/// Etkinlik grup programı kaydetme state
class EventGroupProgramsState {
  final bool isLoading;
  final String? error;
  final List<EventGroupProgramEntity> programs;

  const EventGroupProgramsState({
    this.isLoading = false,
    this.error,
    this.programs = const [],
  });

  EventGroupProgramsState copyWith({
    bool? isLoading,
    String? error,
    List<EventGroupProgramEntity>? programs,
  }) {
    return EventGroupProgramsState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      programs: programs ?? this.programs,
    );
  }
}

/// Etkinlik grup programlarını kaydetme notifier
class EventGroupProgramsNotifier
    extends StateNotifier<EventGroupProgramsState> {
  final GroupRemoteDataSource _dataSource;
  final Ref _ref;

  EventGroupProgramsNotifier(this._dataSource, this._ref)
      : super(const EventGroupProgramsState());

  Future<void> savePrograms(
    String eventId,
    List<EventGroupProgramModel> programs,
  ) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final saved = await _dataSource.saveEventGroupPrograms(eventId, programs);

      state = state.copyWith(
        isLoading: false,
        programs: saved.map((m) => m.toEntity()).toList(),
      );

      // Refresh providers
      _ref.invalidate(eventGroupProgramsProvider(eventId));
      _ref.invalidate(userEventGroupProgramsProvider(eventId));
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void reset() {
    state = const EventGroupProgramsState();
  }
}

/// Etkinlik grup programlarını kaydetme provider
final eventGroupProgramsSaveProvider =
    StateNotifierProvider<EventGroupProgramsNotifier, EventGroupProgramsState>(
        (ref) {
  final dataSource = ref.watch(groupDataSourceProvider);
  return EventGroupProgramsNotifier(dataSource, ref);
});

// ==================== User Management ====================

/// Aktif kullanıcılar provider
final activeUsersProvider = FutureProvider<List<UserEntity>>((ref) async {
  final dataSource = ref.watch(groupDataSourceProvider);
  final supabase = ref.watch(_supabaseProvider);
  final models = await dataSource.getActiveUsers();
  
  if (models.isEmpty) {
    return [];
  }
  
  // Tüm kullanıcı ID'lerini al
  final userIds = models.map((m) => m.id).toList();
  
  // Tek sorgu ile tüm rolleri al (performans optimizasyonu)
  final rolesResponse = await supabase
      .from('user_roles')
      .select('user_id, role')
      .inFilter('user_id', userIds);
  
  // Rolleri user_id'ye göre grupla
  final rolesMap = <String, List<String>>{};
  for (final roleData in rolesResponse as List) {
    final userId = roleData['user_id'] as String;
    final role = roleData['role'] as String;
    rolesMap.putIfAbsent(userId, () => []).add(role);
  }
  
  // Kullanıcıları oluştur ve rolleri eşleştir
  final users = <UserEntity>[];
  for (final model in models) {
    final roleList = rolesMap[model.id] ?? ['member'];
    users.add(model.toEntity(roles: roleList));
  }
  
  // Rol bazında sıralama: super_admin > coach > member
  users.sort((a, b) {
    // Rol öncelikleri
    int getRolePriority(UserEntity user) {
      if (user.isAdmin) return 0; // En yüksek öncelik
      if (user.isCoach) return 1;
      return 2; // member
    }
    
    final priorityA = getRolePriority(a);
    final priorityB = getRolePriority(b);
    
    // Önce rol önceliğine göre sırala
    if (priorityA != priorityB) {
      return priorityA.compareTo(priorityB);
    }
    
    // Aynı rol ise isme göre alfabetik sırala
    return a.fullName.compareTo(b.fullName);
  });
  
  return users;
});

/// Onay bekleyen kullanıcılar provider (sadece admin için)
final pendingUsersProvider = FutureProvider<List<UserEntity>>((ref) async {
  final dataSource = ref.watch(groupDataSourceProvider);
  final supabase = ref.watch(_supabaseProvider);
  final models = await dataSource.getPendingUsers();
  
  if (models.isEmpty) {
    return [];
  }
  
  // Tüm kullanıcı ID'lerini al
  final userIds = models.map((m) => m.id).toList();
  
  // Tek sorgu ile tüm rolleri al (performans optimizasyonu)
  final rolesResponse = await supabase
      .from('user_roles')
      .select('user_id, role')
      .inFilter('user_id', userIds);
  
  // Rolleri user_id'ye göre grupla
  final rolesMap = <String, List<String>>{};
  for (final roleData in rolesResponse as List) {
    final userId = roleData['user_id'] as String;
    final role = roleData['role'] as String;
    rolesMap.putIfAbsent(userId, () => []).add(role);
  }
  
  // Kullanıcıları oluştur ve rolleri eşleştir
  final users = <UserEntity>[];
  for (final model in models) {
    final roleList = rolesMap[model.id] ?? ['member'];
    users.add(model.toEntity(roles: roleList));
  }
  
  // Rol bazında sıralama: super_admin > coach > member
  users.sort((a, b) {
    // Rol öncelikleri
    int getRolePriority(UserEntity user) {
      if (user.isAdmin) return 0; // En yüksek öncelik
      if (user.isCoach) return 1;
      return 2; // member
    }
    
    final priorityA = getRolePriority(a);
    final priorityB = getRolePriority(b);
    
    // Önce rol önceliğine göre sırala
    if (priorityA != priorityB) {
      return priorityA.compareTo(priorityB);
    }
    
    // Aynı rol ise isme göre alfabetik sırala
    return a.fullName.compareTo(b.fullName);
  });
  
  return users;
});

// ==================== Upcoming Birthdays ====================

/// Yaklaşan doğum günleri provider
/// Doğum günü 2 gün içinde olan veya dün olan kullanıcıları listeler
final upcomingBirthdaysProvider = Provider<AsyncValue<List<UserEntity>>>((ref) {
  final usersAsync = ref.watch(activeUsersProvider);
  return usersAsync.whenData((users) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final result = <MapEntry<UserEntity, int>>[];

    for (final user in users) {
      if (user.birthDate == null) continue;

      final bMonth = user.birthDate!.month;
      final bDay = user.birthDate!.day;

      // Bu yılki doğum günü (29 Şubat özel durumu)
      DateTime birthdayThisYear;
      try {
        birthdayThisYear = DateTime(now.year, bMonth, bDay);
      } catch (_) {
        // 29 Şubat artık yıl değilse 28 Şubat'a düş
        birthdayThisYear = DateTime(now.year, 2, 28);
      }

      // Gelecek yılki doğum günü (yıl geçişi durumu)
      DateTime birthdayNextYear;
      try {
        birthdayNextYear = DateTime(now.year + 1, bMonth, bDay);
      } catch (_) {
        birthdayNextYear = DateTime(now.year + 1, 2, 28);
      }

      // Geçen yılki doğum günü (yıl geçişi durumu)
      DateTime birthdayLastYear;
      try {
        birthdayLastYear = DateTime(now.year - 1, bMonth, bDay);
      } catch (_) {
        birthdayLastYear = DateTime(now.year - 1, 2, 28);
      }

      // En yakın doğum gününü bul
      int diff = birthdayThisYear.difference(today).inDays;

      // Yıl geçişi: Eğer bu yılki çok uzaksa, gelecek veya geçen yılı dene
      final diffNext = birthdayNextYear.difference(today).inDays;
      final diffLast = birthdayLastYear.difference(today).inDays;

      if (diffNext.abs() < diff.abs()) diff = diffNext;
      if (diffLast.abs() < diff.abs()) diff = diffLast;

      // -1 (dün) ile +2 (2 gün sonra) arasında olanlar
      if (diff >= -1 && diff <= 2) {
        result.add(MapEntry(user, diff));
      }
    }

    // Doğum gününe yakınlığa göre sırala (bugün > yarın > ...)
    result.sort((a, b) => a.value.compareTo(b.value));

    return result.map((e) => e.key).toList();
  });
});

/// Kullanıcının doğum gününe kaç gün kaldığını hesapla
int birthdayDaysRemaining(UserEntity user) {
  if (user.birthDate == null) return 999;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final bMonth = user.birthDate!.month;
  final bDay = user.birthDate!.day;

  DateTime birthdayThisYear;
  try {
    birthdayThisYear = DateTime(now.year, bMonth, bDay);
  } catch (_) {
    birthdayThisYear = DateTime(now.year, 2, 28);
  }

  DateTime birthdayNextYear;
  try {
    birthdayNextYear = DateTime(now.year + 1, bMonth, bDay);
  } catch (_) {
    birthdayNextYear = DateTime(now.year + 1, 2, 28);
  }

  DateTime birthdayLastYear;
  try {
    birthdayLastYear = DateTime(now.year - 1, bMonth, bDay);
  } catch (_) {
    birthdayLastYear = DateTime(now.year - 1, 2, 28);
  }

  int diff = birthdayThisYear.difference(today).inDays;
  final diffNext = birthdayNextYear.difference(today).inDays;
  final diffLast = birthdayLastYear.difference(today).inDays;

  if (diffNext.abs() < diff.abs()) diff = diffNext;
  if (diffLast.abs() < diff.abs()) diff = diffLast;

  return diff;
}

/// Kullanıcının kaç yaşına gireceğini/girdiğini hesapla
int birthdayAge(UserEntity user) {
  if (user.birthDate == null) return 0;
  final now = DateTime.now();
  int age = now.year - user.birthDate!.year;

  // Bu yılki doğum günü henüz gelmediyse yaşı bir azalt
  final birthdayThisYear = DateTime(now.year, user.birthDate!.month, user.birthDate!.day);
  if (birthdayThisYear.isAfter(DateTime(now.year, now.month, now.day))) {
    // Doğum günü henüz gelmedi - gireceği yaş
    return age;
  }
  return age;
}

// ==================== User Approval ====================

/// Kullanıcı onaylama notifier
class UserApprovalNotifier extends StateNotifier<AsyncValue<void>> {
  final GroupRemoteDataSource _dataSource;
  final Ref _ref;

  UserApprovalNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<void> approveUser(String userId) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.approveUser(userId);
      state = const AsyncValue.data(null);
      
      // Refresh providers
      _ref.invalidate(activeUsersProvider);
      _ref.invalidate(pendingUsersProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deactivateUser(String userId) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.deactivateUser(userId);
      state = const AsyncValue.data(null);
      
      // Refresh providers
      _ref.invalidate(activeUsersProvider);
      _ref.invalidate(pendingUsersProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Kullanıcı onaylama provider
final userApprovalProvider =
    StateNotifierProvider<UserApprovalNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(groupDataSourceProvider);
  return UserApprovalNotifier(dataSource, ref);
});

/// Kullanıcı rol güncelleme notifier
class UserRoleUpdateNotifier extends StateNotifier<AsyncValue<void>> {
  final GroupRemoteDataSource _dataSource;
  final Ref _ref;

  UserRoleUpdateNotifier(this._dataSource, this._ref)
      : super(const AsyncValue.data(null));

  Future<void> updateUserRole(String userId, List<String> roles) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.updateUserRole(userId, roles);
      state = const AsyncValue.data(null);
      
      // Refresh providers
      _ref.invalidate(activeUsersProvider);
      _ref.invalidate(pendingUsersProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

/// Kullanıcı rol güncelleme provider
final userRoleUpdateProvider =
    StateNotifierProvider<UserRoleUpdateNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(groupDataSourceProvider);
  return UserRoleUpdateNotifier(dataSource, ref);
});
