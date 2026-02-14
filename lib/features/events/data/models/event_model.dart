import '../../domain/entities/event_entity.dart';

/// Event Model - Supabase JSON mapping
class EventModel {
  final String id;
  final String title;
  final String? description;
  final String eventType;
  final String status;
  final DateTime startTime;
  final DateTime? endTime;
  final String? locationName;
  final String? locationAddress;
  final double? locationLat;
  final double? locationLng;
  final String? routeId;
  final String? trainingGroupId;
  final String? trainingTypeId;
  final String? trainingTypeName;
  final String? trainingTypeDescription;
  final String? trainingTypeColor;
  final int? thresholdOffsetMinSeconds;
  final int? thresholdOffsetMaxSeconds;
  final String? weatherNote;
  final String? coachNotes;
  final String? bannerImageUrl;
  final String createdBy;
  final DateTime createdAt;
  final int participantCount;
  final bool isUserParticipating;
  final String participationType;
  final LaneConfigEntity? laneConfig;
  final bool isPinned;
  final DateTime? pinnedAt;
  final bool isRecurring;
  final String? recurrenceRule;
  final String? parentEventId;
  final DateTime? recurrenceEndDate;
  final bool isRecurrenceException;

  const EventModel({
    required this.id,
    required this.title,
    this.description,
    required this.eventType,
    required this.status,
    required this.startTime,
    this.endTime,
    this.locationName,
    this.locationAddress,
    this.locationLat,
    this.locationLng,
    this.routeId,
    this.trainingGroupId,
    this.trainingTypeId,
    this.trainingTypeName,
    this.trainingTypeDescription,
    this.trainingTypeColor,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
    this.weatherNote,
    this.coachNotes,
    this.bannerImageUrl,
    required this.createdBy,
    required this.createdAt,
    this.participantCount = 0,
    this.isUserParticipating = false,
    this.participationType = 'team',
    this.laneConfig,
    this.isPinned = false,
    this.pinnedAt,
    this.isRecurring = false,
    this.recurrenceRule,
    this.parentEventId,
    this.recurrenceEndDate,
    this.isRecurrenceException = false,
  });

  factory EventModel.fromJson(Map<String, dynamic> json, {bool? isParticipating}) {
    // Training type bilgilerini nested object'ten al
    final trainingTypeData = json['training_types'] as Map<String, dynamic>?;
    
    return EventModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      eventType: json['event_type'] as String? ?? 'training',
      status: json['status'] as String? ?? 'draft',
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time'] as String) : null,
      locationName: json['location_name'] as String?,
      locationAddress: json['location_address'] as String?,
      locationLat: (json['location_lat'] as num?)?.toDouble(),
      locationLng: (json['location_lng'] as num?)?.toDouble(),
      routeId: json['route_id'] as String?,
      trainingGroupId: json['training_group_id'] as String?,
      trainingTypeId: json['training_type_id'] as String?,
      trainingTypeName: trainingTypeData?['display_name'] as String?,
      trainingTypeDescription: trainingTypeData?['description'] as String?,
      trainingTypeColor: trainingTypeData?['color'] as String?,
      thresholdOffsetMinSeconds: trainingTypeData?['threshold_offset_min_seconds'] as int?,
      thresholdOffsetMaxSeconds: trainingTypeData?['threshold_offset_max_seconds'] as int?,
      weatherNote: json['weather_note'] as String?,
      coachNotes: json['coach_notes'] as String?,
      bannerImageUrl: json['banner_image_url'] as String?,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      participantCount: json['participant_count'] as int? ?? 0,
      isUserParticipating: isParticipating ?? false,
      participationType: json['participation_type'] as String? ?? 'team',
      laneConfig: LaneConfigEntity.fromJson(
        json['lane_config'] as Map<String, dynamic>?,
      ),
      isPinned: json['is_pinned'] as bool? ?? false,
      pinnedAt: json['pinned_at'] != null
          ? DateTime.parse(json['pinned_at'] as String)
          : null,
      isRecurring: json['is_recurring'] as bool? ?? false,
      recurrenceRule: json['recurrence_rule'] as String?,
      parentEventId: json['parent_event_id'] as String?,
      recurrenceEndDate: json['recurrence_end_date'] != null
          ? DateTime.parse(json['recurrence_end_date'] as String)
          : null,
      isRecurrenceException: json['is_recurrence_exception'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'event_type': eventType,
      'status': status,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'location_name': locationName,
      'location_address': locationAddress,
      'location_lat': locationLat,
      'location_lng': locationLng,
      'route_id': routeId,
      'training_group_id': trainingGroupId,
      'training_type_id': trainingTypeId,
      'weather_note': weatherNote,
      'coach_notes': coachNotes,
      'banner_image_url': bannerImageUrl,
      'created_by': createdBy,
      'participation_type': participationType,
      'lane_config': (laneConfig != null && !laneConfig!.isEmpty) ? laneConfig!.toJson() : null,
      'is_pinned': isPinned,
      'pinned_at': pinnedAt?.toIso8601String(),
      'is_recurring': isRecurring,
      'recurrence_rule': recurrenceRule,
      'parent_event_id': parentEventId,
      'recurrence_end_date':
          recurrenceEndDate?.toIso8601String().split('T').first,
      'is_recurrence_exception': isRecurrenceException,
    };
  }

  EventEntity toEntity() {
    return EventEntity(
      id: id,
      title: title,
      description: description,
      eventType: EventType.fromString(eventType),
      status: EventStatus.fromString(status),
      startTime: startTime,
      endTime: endTime,
      locationName: locationName,
      locationAddress: locationAddress,
      locationLat: locationLat,
      locationLng: locationLng,
      routeId: routeId,
      trainingGroupId: trainingGroupId,
      trainingTypeId: trainingTypeId,
      trainingTypeName: trainingTypeName,
      trainingTypeDescription: trainingTypeDescription,
      trainingTypeColor: trainingTypeColor,
      thresholdOffsetMinSeconds: thresholdOffsetMinSeconds,
      thresholdOffsetMaxSeconds: thresholdOffsetMaxSeconds,
      weatherNote: weatherNote,
      coachNotes: coachNotes,
      bannerImageUrl: bannerImageUrl,
      createdBy: createdBy,
      createdAt: createdAt,
      participantCount: participantCount,
      isUserParticipating: isUserParticipating,
      participationType: participationType,
      laneConfig: laneConfig,
      isPinned: isPinned,
      pinnedAt: pinnedAt,
      isRecurring: isRecurring,
      recurrenceRule: recurrenceRule,
      parentEventId: parentEventId,
      recurrenceEndDate: recurrenceEndDate,
      isRecurrenceException: isRecurrenceException,
    );
  }
}

/// Event Participant Model
class EventParticipantModel {
  final String id;
  final String eventId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String status;
  final String? note;
  final DateTime respondedAt;
  final bool checkedIn;
  final DateTime? checkedInAt;

  const EventParticipantModel({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.status,
    this.note,
    required this.respondedAt,
    this.checkedIn = false,
    this.checkedInAt,
  });

  factory EventParticipantModel.fromJson(Map<String, dynamic> json) {
    final userData = json['users'] as Map<String, dynamic>?;
    final userName = userData != null
        ? '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''}'.trim()
        : 'Anonim';

    return EventParticipantModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      userId: json['user_id'] as String,
      userName: userName.isEmpty ? 'Anonim' : userName,
      userAvatarUrl: userData?['avatar_url'] as String?,
      status: json['status'] as String? ?? 'going',
      note: json['note'] as String?,
      respondedAt: DateTime.parse(json['responded_at'] as String),
      checkedIn: json['checked_in'] as bool? ?? false,
      checkedInAt: json['checked_in_at'] != null 
          ? DateTime.parse(json['checked_in_at'] as String) 
          : null,
    );
  }

  EventParticipantEntity toEntity() {
    return EventParticipantEntity(
      id: id,
      eventId: eventId,
      userId: userId,
      userName: userName,
      userAvatarUrl: userAvatarUrl,
      status: RsvpStatus.fromString(status),
      note: note,
      respondedAt: respondedAt,
      checkedIn: checkedIn,
      checkedInAt: checkedInAt,
    );
  }
}

/// Training Group Model
class TrainingGroupModel {
  final String id;
  final String name;
  final String? description;
  final String? targetDistance;
  final int difficultyLevel;
  final String color;
  final String icon;
  final bool isActive;

  const TrainingGroupModel({
    required this.id,
    required this.name,
    this.description,
    this.targetDistance,
    this.difficultyLevel = 1,
    this.color = '#3B82F6',
    this.icon = 'running',
    this.isActive = true,
  });

  factory TrainingGroupModel.fromJson(Map<String, dynamic> json) {
    return TrainingGroupModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      targetDistance: json['target_distance'] as String?,
      difficultyLevel: json['difficulty_level'] as int? ?? 1,
      color: json['color'] as String? ?? '#3B82F6',
      icon: json['icon'] as String? ?? 'running',
      isActive: json['is_active'] as bool? ?? true,
    );
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
    );
  }
}

/// Training Type Model - Antrenman Türü
class TrainingTypeModel {
  final String id;
  final String name;
  final String displayName;
  final String description;
  final String icon;
  final String color;
  final int sortOrder;
  final bool isActive;
  final int? thresholdOffsetMinSeconds;
  final int? thresholdOffsetMaxSeconds;

  const TrainingTypeModel({
    required this.id,
    required this.name,
    required this.displayName,
    required this.description,
    this.icon = 'directions_run',
    this.color = '#3B82F6',
    this.sortOrder = 0,
    this.isActive = true,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
  });

  factory TrainingTypeModel.fromJson(Map<String, dynamic> json) {
    return TrainingTypeModel(
      id: json['id'] as String,
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      description: json['description'] as String,
      icon: json['icon'] as String? ?? 'directions_run',
      color: json['color'] as String? ?? '#3B82F6',
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      thresholdOffsetMinSeconds: json['threshold_offset_min_seconds'] as int?,
      thresholdOffsetMaxSeconds: json['threshold_offset_max_seconds'] as int?,
    );
  }

  TrainingTypeEntity toEntity() {
    return TrainingTypeEntity(
      id: id,
      name: name,
      displayName: displayName,
      description: description,
      icon: icon,
      color: color,
      sortOrder: sortOrder,
      isActive: isActive,
      thresholdOffsetMinSeconds: thresholdOffsetMinSeconds,
      thresholdOffsetMaxSeconds: thresholdOffsetMaxSeconds,
    );
  }
}
