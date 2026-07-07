import '../../members_groups/data/models/group_model.dart';
import '../../members_groups/domain/entities/group_entity.dart';
import '../../integrations/shared/weekly_program_device_sync.dart';
import '../../workout/data/models/workout_model.dart';

WorkoutDefinitionModel? _parseWorkoutDefinition(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map<String, dynamic>) {
    return WorkoutDefinitionModel.fromJson(raw);
  }
  if (raw is Map) {
    return WorkoutDefinitionModel.fromJson(Map<String, dynamic>.from(raw));
  }
  if (raw is List) {
    return WorkoutDefinitionModel.fromJsonList(raw);
  }
  return null;
}

EventGroupProgramModel monthlyRowToEventGroupProgram(
  Map<String, dynamic> row, {
  required String eventId,
}) {
  final groupData = row['training_groups'] as Map<String, dynamic>?;
  final trainingTypeData = row['training_types'] as Map<String, dynamic>?;

  return EventGroupProgramModel(
    id: row['id'] as String,
    eventId: eventId,
    trainingGroupId: row['training_group_id'] as String,
    groupName: groupData?['name'] as String?,
    groupColor: groupData?['color'] as String?,
    programContent: (row['program_content'] as String?) ?? '',
    coachNotes: row['coach_notes'] as String?,
    workoutDefinition: _parseWorkoutDefinition(row['workout_definition']),
    routeId: null,
    routeName: null,
    trainingTypeId: row['training_type_id'] as String?,
    trainingTypeName: trainingTypeData?['display_name'] as String?,
    trainingTypeDescription: trainingTypeData?['description'] as String?,
    trainingTypeColor: trainingTypeData?['color'] as String?,
    thresholdOffsetMinSeconds:
        trainingTypeData?['threshold_offset_min_seconds'] as int?,
    thresholdOffsetMaxSeconds:
        trainingTypeData?['threshold_offset_max_seconds'] as int?,
    orderIndex: row['sort_order'] as int? ?? 0,
    createdAt: DateTime.now(),
  );
}

EventMemberProgramModel monthlyRowToEventMemberProgram(
  Map<String, dynamic> row, {
  required String eventId,
}) {
  final userData = row['users'] as Map<String, dynamic>?;
  final groupData = row['training_groups'] as Map<String, dynamic>?;
  final trainingTypeData = row['training_types'] as Map<String, dynamic>?;
  final userName = userData != null
      ? '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''}'.trim()
      : null;

  return EventMemberProgramModel(
    id: row['id'] as String,
    eventId: eventId,
    userId: row['user_id'] as String,
    userName: (userName != null && userName.isNotEmpty) ? userName : null,
    userAvatarUrl: userData?['avatar_url'] as String?,
    trainingGroupId: row['training_group_id'] as String,
    groupName: groupData?['name'] as String?,
    groupColor: groupData?['color'] as String?,
    programContent: (row['program_content'] as String?) ?? '',
    coachNotes: row['coach_notes'] as String?,
    workoutDefinition: _parseWorkoutDefinition(row['workout_definition']),
    routeId: null,
    routeName: null,
    trainingTypeId: row['training_type_id'] as String?,
    trainingTypeName: trainingTypeData?['display_name'] as String?,
    trainingTypeDescription: trainingTypeData?['description'] as String?,
    trainingTypeColor: trainingTypeData?['color'] as String?,
    thresholdOffsetMinSeconds:
        trainingTypeData?['threshold_offset_min_seconds'] as int?,
    thresholdOffsetMaxSeconds:
        trainingTypeData?['threshold_offset_max_seconds'] as int?,
    orderIndex: row['sort_order'] as int? ?? 0,
    createdAt: DateTime.now(),
  );
}

bool monthlyRowHasProgramContent(Map<String, dynamic> row) {
  final content = ((row['program_content'] as String?) ?? '').trim();
  final wd = row['workout_definition'];
  final hasWorkout = wd != null &&
      ((wd is Map && wd.isNotEmpty) || (wd is List && wd.isNotEmpty));
  return content.isNotEmpty || hasWorkout;
}

Map<String, dynamic> _trainingTypeMap({
  String? name,
  String? description,
  String? color,
  int? offsetMin,
  int? offsetMax,
}) {
  final map = <String, dynamic>{};
  if (name != null) map['display_name'] = name;
  if (description != null) map['description'] = description;
  if (color != null) map['color'] = color;
  if (offsetMin != null) map['threshold_offset_min_seconds'] = offsetMin;
  if (offsetMax != null) map['threshold_offset_max_seconds'] = offsetMax;
  return map;
}

Map<String, dynamic> eventGroupProgramToMonthlyRow(
  EventGroupProgramEntity program, {
  int? trackLane,
}) {
  final row = <String, dynamic>{
    'id': program.id,
    'program_content': program.programContent,
    'coach_notes': program.coachNotes,
    'training_groups': <String, dynamic>{
      if (program.groupName != null) 'name': program.groupName,
      if (program.groupColor != null) 'color': program.groupColor,
    },
    'training_types': _trainingTypeMap(
      name: program.trainingTypeName,
      description: program.trainingTypeDescription,
      color: program.trainingTypeColor,
      offsetMin: program.thresholdOffsetMinSeconds,
      offsetMax: program.thresholdOffsetMaxSeconds,
    ),
  };
  final workoutJson = workoutDefinitionJson(program.workoutDefinition);
  if (workoutJson != null) {
    row['workout_definition'] = workoutJson;
  }
  if (trackLane != null) {
    row['track_lane'] = trackLane;
  }
  return row;
}

Map<String, dynamic> eventMemberProgramToMonthlyRow(
  EventMemberProgramEntity program, {
  String? displayGroupName,
  int? trackLane,
}) {
  final row = <String, dynamic>{
    'id': program.id,
    'program_content': program.programContent,
    'coach_notes': program.coachNotes,
    'training_groups': <String, dynamic>{
      'name': displayGroupName ?? program.groupName,
      if (program.groupColor != null) 'color': program.groupColor,
    },
    'training_types': _trainingTypeMap(
      name: program.trainingTypeName,
      description: program.trainingTypeDescription,
      color: program.trainingTypeColor,
      offsetMin: program.thresholdOffsetMinSeconds,
      offsetMax: program.thresholdOffsetMaxSeconds,
    ),
  };
  final workoutJson = workoutDefinitionJson(program.workoutDefinition);
  if (workoutJson != null) {
    row['workout_definition'] = workoutJson;
  }
  if (trackLane != null) {
    row['track_lane'] = trackLane;
  }
  return row;
}
