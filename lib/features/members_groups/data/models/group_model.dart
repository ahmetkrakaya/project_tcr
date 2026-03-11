import '../../domain/entities/group_entity.dart';
import '../../../workout/data/models/workout_model.dart';

/// Training Group Model - Supabase JSON mapping
class TrainingGroupModel {
  final String id;
  final String name;
  final String? description;
  final String? targetDistance;
  final int difficultyLevel;
  final String color;
  final String icon;
  final bool isActive;
  final String groupType;
  final int memberCount;
  final bool isUserMember;
  final String? createdBy;
  final DateTime createdAt;

  const TrainingGroupModel({
    required this.id,
    required this.name,
    this.description,
    this.targetDistance,
    this.difficultyLevel = 1,
    this.color = '#3B82F6',
    this.icon = 'directions_run',
    this.isActive = true,
    this.groupType = 'normal',
    this.memberCount = 0,
    this.isUserMember = false,
    this.createdBy,
    required this.createdAt,
  });

  factory TrainingGroupModel.fromJson(
    Map<String, dynamic> json, {
    int? memberCount,
    bool? isUserMember,
  }) {
    return TrainingGroupModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      targetDistance: json['target_distance'] as String?,
      difficultyLevel: json['difficulty_level'] as int? ?? 1,
      color: json['color'] as String? ?? '#3B82F6',
      icon: json['icon'] as String? ?? 'directions_run',
      isActive: json['is_active'] as bool? ?? true,
      groupType: json['group_type'] as String? ?? 'normal',
      memberCount: memberCount ?? 0,
      isUserMember: isUserMember ?? false,
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'target_distance': targetDistance,
      'difficulty_level': difficultyLevel,
      'color': color,
      'icon': icon,
      'is_active': isActive,
      'group_type': groupType,
      'created_by': createdBy,
    };
  }

  TrainingGroupEntity toEntity() {
    return TrainingGroupEntity(
      id: id,
      name: name,
      description: description,
      targetDistance: targetDistance,
      difficultyLevel: difficultyLevel,
      color: color,
      icon: icon,
      isActive: isActive,
      groupType: groupType,
      memberCount: memberCount,
      isUserMember: isUserMember,
      createdBy: createdBy,
      createdAt: createdAt,
    );
  }
}

/// Group Member Model - Supabase JSON mapping
class GroupMemberModel {
  final String id;
  final String groupId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final DateTime joinedAt;

  const GroupMemberModel({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.joinedAt,
  });

  factory GroupMemberModel.fromJson(Map<String, dynamic> json) {
    final userData = json['users'] as Map<String, dynamic>?;
    final userName = userData != null
        ? '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''}'.trim()
        : 'Anonim';

    return GroupMemberModel(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      userName: userName.isEmpty ? 'Anonim' : userName,
      userAvatarUrl: userData?['avatar_url'] as String?,
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }

  GroupMemberEntity toEntity() {
    return GroupMemberEntity(
      id: id,
      groupId: groupId,
      userId: userId,
      userName: userName,
      userAvatarUrl: userAvatarUrl,
      joinedAt: joinedAt,
    );
  }
}

/// Event Group Program Model - Supabase JSON mapping
class EventGroupProgramModel {
  final String id;
  final String eventId;
  final String trainingGroupId;
  final String? groupName;
  final String? groupColor;
  final String programContent;
  final WorkoutDefinitionModel? workoutDefinition;
  final String? routeId;
  final String? routeName;
  final String? trainingTypeId;
  final String? trainingTypeName;
  final String? trainingTypeDescription;
  final String? trainingTypeColor;
  final int? thresholdOffsetMinSeconds;
  final int? thresholdOffsetMaxSeconds;
  final int orderIndex;
  final DateTime createdAt;

  const EventGroupProgramModel({
    required this.id,
    required this.eventId,
    required this.trainingGroupId,
    this.groupName,
    this.groupColor,
    required this.programContent,
    this.workoutDefinition,
    this.routeId,
    this.routeName,
    this.trainingTypeId,
    this.trainingTypeName,
    this.trainingTypeDescription,
    this.trainingTypeColor,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
    this.orderIndex = 0,
    required this.createdAt,
  });

  factory EventGroupProgramModel.fromJson(Map<String, dynamic> json) {
    final groupData = json['training_groups'] as Map<String, dynamic>?;
    final routeData = json['routes'] as Map<String, dynamic>?;
    final trainingTypeData = json['training_types'] as Map<String, dynamic>?;
    WorkoutDefinitionModel? workoutDefinition;
    final wd = json['workout_definition'];
    if (wd != null) {
      if (wd is Map<String, dynamic>) {
        workoutDefinition = WorkoutDefinitionModel.fromJson(wd);
      } else if (wd is List) {
        workoutDefinition = WorkoutDefinitionModel.fromJsonList(wd);
      }
    }

    return EventGroupProgramModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      trainingGroupId: json['training_group_id'] as String,
      groupName: groupData?['name'] as String?,
      groupColor: groupData?['color'] as String?,
      programContent: json['program_content'] as String? ?? '',
      workoutDefinition: workoutDefinition,
      routeId: json['route_id'] as String?,
      routeName: routeData?['name'] as String?,
      trainingTypeId: json['training_type_id'] as String?,
      trainingTypeName: trainingTypeData?['display_name'] as String?,
      trainingTypeDescription: trainingTypeData?['description'] as String?,
      trainingTypeColor: trainingTypeData?['color'] as String?,
      thresholdOffsetMinSeconds: trainingTypeData?['threshold_offset_min_seconds'] as int?,
      thresholdOffsetMaxSeconds: trainingTypeData?['threshold_offset_max_seconds'] as int?,
      orderIndex: json['order_index'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'training_group_id': trainingGroupId,
      'program_content': programContent,
      if (workoutDefinition != null) 'workout_definition': workoutDefinition!.toJson(),
      'route_id': routeId,
      'training_type_id': trainingTypeId,
      'order_index': orderIndex,
    };
  }

  EventGroupProgramEntity toEntity() {
    return EventGroupProgramEntity(
      id: id,
      eventId: eventId,
      trainingGroupId: trainingGroupId,
      groupName: groupName,
      groupColor: groupColor,
      programContent: programContent,
      workoutDefinition: workoutDefinition?.toEntity(),
      routeId: routeId,
      routeName: routeName,
      trainingTypeId: trainingTypeId,
      trainingTypeName: trainingTypeName,
      trainingTypeDescription: trainingTypeDescription,
      trainingTypeColor: trainingTypeColor,
      thresholdOffsetMinSeconds: thresholdOffsetMinSeconds,
      thresholdOffsetMaxSeconds: thresholdOffsetMaxSeconds,
      orderIndex: orderIndex,
      createdAt: createdAt,
    );
  }
}

/// Group Join Request Model - Supabase JSON mapping
class GroupJoinRequestModel {
  final String id;
  final String groupId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String status;
  final DateTime requestedAt;
  final DateTime? respondedAt;
  final String? respondedBy;

  const GroupJoinRequestModel({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.status,
    required this.requestedAt,
    this.respondedAt,
    this.respondedBy,
  });

  factory GroupJoinRequestModel.fromJson(Map<String, dynamic> json) {
    final userData = json['users'] as Map<String, dynamic>?;
    final userName = userData != null
        ? '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''}'.trim()
        : 'Anonim';

    return GroupJoinRequestModel(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      userName: userName.isEmpty ? 'Anonim' : userName,
      userAvatarUrl: userData?['avatar_url'] as String?,
      status: json['status'] as String,
      requestedAt: DateTime.parse(json['requested_at'] as String),
      respondedAt: json['responded_at'] != null
          ? DateTime.parse(json['responded_at'] as String)
          : null,
      respondedBy: json['responded_by'] as String?,
    );
  }

  GroupJoinRequestEntity toEntity() {
    return GroupJoinRequestEntity(
      id: id,
      groupId: groupId,
      userId: userId,
      userName: userName,
      userAvatarUrl: userAvatarUrl,
      status: status,
      requestedAt: requestedAt,
      respondedAt: respondedAt,
      respondedBy: respondedBy,
    );
  }
}

/// Event Member Program Model - Performans Grubu Kişisel Program
class EventMemberProgramModel {
  final String id;
  final String eventId;
  final String userId;
  final String? userName;
  final String? userAvatarUrl;
  final String trainingGroupId;
  final String? groupName;
  final String? groupColor;
  final String programContent;
  final WorkoutDefinitionModel? workoutDefinition;
  final String? routeId;
  final String? routeName;
  final String? trainingTypeId;
  final String? trainingTypeName;
  final String? trainingTypeDescription;
  final String? trainingTypeColor;
  final int? thresholdOffsetMinSeconds;
  final int? thresholdOffsetMaxSeconds;
  final int orderIndex;
  final DateTime createdAt;

  const EventMemberProgramModel({
    required this.id,
    required this.eventId,
    required this.userId,
    this.userName,
    this.userAvatarUrl,
    required this.trainingGroupId,
    this.groupName,
    this.groupColor,
    required this.programContent,
    this.workoutDefinition,
    this.routeId,
    this.routeName,
    this.trainingTypeId,
    this.trainingTypeName,
    this.trainingTypeDescription,
    this.trainingTypeColor,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
    this.orderIndex = 0,
    required this.createdAt,
  });

  factory EventMemberProgramModel.fromJson(Map<String, dynamic> json) {
    final userData = json['users'] as Map<String, dynamic>?;
    final groupData = json['training_groups'] as Map<String, dynamic>?;
    final routeData = json['routes'] as Map<String, dynamic>?;
    final trainingTypeData = json['training_types'] as Map<String, dynamic>?;

    WorkoutDefinitionModel? workoutDefinition;
    final wd = json['workout_definition'];
    if (wd != null) {
      if (wd is Map<String, dynamic>) {
        workoutDefinition = WorkoutDefinitionModel.fromJson(wd);
      } else if (wd is List) {
        workoutDefinition = WorkoutDefinitionModel.fromJsonList(wd);
      }
    }

    final userName = userData != null
        ? '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''}'.trim()
        : null;

    return EventMemberProgramModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      userId: json['user_id'] as String,
      userName: (userName != null && userName.isNotEmpty) ? userName : null,
      userAvatarUrl: userData?['avatar_url'] as String?,
      trainingGroupId: json['training_group_id'] as String,
      groupName: groupData?['name'] as String?,
      groupColor: groupData?['color'] as String?,
      programContent: json['program_content'] as String? ?? '',
      workoutDefinition: workoutDefinition,
      routeId: json['route_id'] as String?,
      routeName: routeData?['name'] as String?,
      trainingTypeId: json['training_type_id'] as String?,
      trainingTypeName: trainingTypeData?['display_name'] as String?,
      trainingTypeDescription: trainingTypeData?['description'] as String?,
      trainingTypeColor: trainingTypeData?['color'] as String?,
      thresholdOffsetMinSeconds: trainingTypeData?['threshold_offset_min_seconds'] as int?,
      thresholdOffsetMaxSeconds: trainingTypeData?['threshold_offset_max_seconds'] as int?,
      orderIndex: json['order_index'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'user_id': userId,
      'training_group_id': trainingGroupId,
      'program_content': programContent,
      if (workoutDefinition != null) 'workout_definition': workoutDefinition!.toJson(),
      'route_id': routeId,
      'training_type_id': trainingTypeId,
      'order_index': orderIndex,
    };
  }

  EventMemberProgramEntity toEntity() {
    return EventMemberProgramEntity(
      id: id,
      eventId: eventId,
      userId: userId,
      userName: userName,
      userAvatarUrl: userAvatarUrl,
      trainingGroupId: trainingGroupId,
      groupName: groupName,
      groupColor: groupColor,
      programContent: programContent,
      workoutDefinition: workoutDefinition?.toEntity(),
      routeId: routeId,
      routeName: routeName,
      trainingTypeId: trainingTypeId,
      trainingTypeName: trainingTypeName,
      trainingTypeDescription: trainingTypeDescription,
      trainingTypeColor: trainingTypeColor,
      thresholdOffsetMinSeconds: thresholdOffsetMinSeconds,
      thresholdOffsetMaxSeconds: thresholdOffsetMaxSeconds,
      orderIndex: orderIndex,
      createdAt: createdAt,
    );
  }
}
