import 'package:flutter/material.dart';

import '../../domain/entities/event_entity.dart';
import '../../domain/entities/event_template_entity.dart';
import '../../../workout/data/models/workout_model.dart';

/// Event Template Model - Supabase JSON mapping
class EventTemplateModel {
  final String id;
  final String name;
  final String? description;
  final String eventType;
  final String? locationName;
  final String? locationAddress;
  final double? locationLat;
  final double? locationLng;
  final String? routeId;
  final String? routeName;
  final String? trainingTypeId;
  final String? trainingTypeName;
  final String? trainingTypeColor;
  final String? defaultStartTime;
  final int? durationMinutes;
  final bool isActive;
  final String createdBy;
  final DateTime createdAt;
  final List<EventTemplateGroupProgramModel> groupPrograms;
  final String participationType;
  final LaneConfigEntity? laneConfig;

  const EventTemplateModel({
    required this.id,
    required this.name,
    this.description,
    required this.eventType,
    this.locationName,
    this.locationAddress,
    this.locationLat,
    this.locationLng,
    this.routeId,
    this.routeName,
    this.trainingTypeId,
    this.trainingTypeName,
    this.trainingTypeColor,
    this.defaultStartTime,
    this.durationMinutes,
    this.isActive = true,
    required this.createdBy,
    required this.createdAt,
    this.groupPrograms = const [],
    this.participationType = 'team',
    this.laneConfig,
  });

  factory EventTemplateModel.fromJson(Map<String, dynamic> json) {
    // Training type bilgilerini nested object'ten al
    final trainingTypeData = json['training_types'] as Map<String, dynamic>?;
    // Route bilgilerini nested object'ten al
    final routeData = json['routes'] as Map<String, dynamic>?;
    // Grup programlarını al
    final programsData = json['event_template_group_programs'] as List<dynamic>?;

    return EventTemplateModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      eventType: json['event_type'] as String? ?? 'training',
      locationName: json['location_name'] as String?,
      locationAddress: json['location_address'] as String?,
      locationLat: (json['location_lat'] as num?)?.toDouble(),
      locationLng: (json['location_lng'] as num?)?.toDouble(),
      routeId: json['route_id'] as String?,
      routeName: routeData?['name'] as String?,
      trainingTypeId: json['training_type_id'] as String?,
      trainingTypeName: trainingTypeData?['display_name'] as String?,
      trainingTypeColor: trainingTypeData?['color'] as String?,
      defaultStartTime: json['default_start_time'] as String?,
      durationMinutes: json['duration_minutes'] as int?,
      isActive: json['is_active'] as bool? ?? true,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      participationType: json['participation_type'] as String? ?? 'team',
      laneConfig: LaneConfigEntity.fromJson(
        json['lane_config'] as Map<String, dynamic>?,
      ),
      groupPrograms: programsData
              ?.map((p) => EventTemplateGroupProgramModel.fromJson(
                  p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'event_type': eventType,
      'location_name': locationName,
      'location_address': locationAddress,
      'location_lat': locationLat,
      'location_lng': locationLng,
      'route_id': routeId,
      'training_type_id': trainingTypeId,
      'default_start_time': defaultStartTime,
      'duration_minutes': durationMinutes,
      'is_active': isActive,
      'created_by': createdBy,
      'participation_type': participationType,
      'lane_config': (laneConfig != null && !laneConfig!.isEmpty) ? laneConfig!.toJson() : null,
    };
  }

  EventTemplateEntity toEntity() {
    TimeOfDay? startTime;
    if (defaultStartTime != null && defaultStartTime!.isNotEmpty) {
      final parts = defaultStartTime!.split(':');
      if (parts.length >= 2) {
        startTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 8,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }

    return EventTemplateEntity(
      id: id,
      name: name,
      description: description,
      eventType: EventType.fromString(eventType),
      locationName: locationName,
      locationAddress: locationAddress,
      locationLat: locationLat,
      locationLng: locationLng,
      routeId: routeId,
      routeName: routeName,
      trainingTypeId: trainingTypeId,
      trainingTypeName: trainingTypeName,
      trainingTypeColor: trainingTypeColor,
      defaultStartTime: startTime,
      durationMinutes: durationMinutes,
      isActive: isActive,
      createdBy: createdBy,
      createdAt: createdAt,
      groupPrograms: groupPrograms.map((p) => p.toEntity()).toList(),
      participationType: participationType,
      laneConfig: laneConfig,
    );
  }
}

/// Event Template Group Program Model
class EventTemplateGroupProgramModel {
  final String id;
  final String templateId;
  final String trainingGroupId;
  final String? trainingGroupName;
  final String? trainingGroupColor;
  final String programContent;
  final WorkoutDefinitionModel? workoutDefinition;
  final String? routeId;
  final String? routeName;
  final String? trainingTypeId;
  final String? trainingTypeName;
  final String? trainingTypeColor;
  final int? thresholdOffsetMinSeconds;
  final int? thresholdOffsetMaxSeconds;
  final int sortOrder;

  const EventTemplateGroupProgramModel({
    required this.id,
    required this.templateId,
    required this.trainingGroupId,
    this.trainingGroupName,
    this.trainingGroupColor,
    required this.programContent,
    this.workoutDefinition,
    this.routeId,
    this.routeName,
    this.trainingTypeId,
    this.trainingTypeName,
    this.trainingTypeColor,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
    this.sortOrder = 0,
  });

  factory EventTemplateGroupProgramModel.fromJson(Map<String, dynamic> json) {
    final groupData = json['training_groups'] as Map<String, dynamic>?;
    final routeData = json['routes'] as Map<String, dynamic>?;
    final typeData = json['training_types'] as Map<String, dynamic>?;
    WorkoutDefinitionModel? workoutDefinition;
    final wd = json['workout_definition'];
    if (wd != null) {
      if (wd is Map<String, dynamic>) {
        workoutDefinition = WorkoutDefinitionModel.fromJson(wd);
      } else if (wd is List) {
        workoutDefinition = WorkoutDefinitionModel.fromJsonList(wd);
      }
    }

    return EventTemplateGroupProgramModel(
      id: json['id'] as String,
      templateId: json['template_id'] as String,
      trainingGroupId: json['training_group_id'] as String,
      trainingGroupName: groupData?['name'] as String?,
      trainingGroupColor: groupData?['color'] as String?,
      programContent: json['program_content'] as String? ?? '',
      workoutDefinition: workoutDefinition,
      routeId: json['route_id'] as String?,
      routeName: routeData?['name'] as String?,
      trainingTypeId: json['training_type_id'] as String?,
      trainingTypeName: typeData?['display_name'] as String?,
      trainingTypeColor: typeData?['color'] as String?,
      thresholdOffsetMinSeconds: typeData?['threshold_offset_min_seconds'] as int?,
      thresholdOffsetMaxSeconds: typeData?['threshold_offset_max_seconds'] as int?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'template_id': templateId,
      'training_group_id': trainingGroupId,
      'program_content': programContent,
      if (workoutDefinition != null) 'workout_definition': workoutDefinition!.toJson(),
      'route_id': routeId,
      'training_type_id': trainingTypeId,
      'sort_order': sortOrder,
    };
  }

  EventTemplateGroupProgramEntity toEntity() {
    return EventTemplateGroupProgramEntity(
      id: id,
      templateId: templateId,
      trainingGroupId: trainingGroupId,
      trainingGroupName: trainingGroupName,
      trainingGroupColor: trainingGroupColor,
      programContent: programContent,
      workoutDefinition: workoutDefinition?.toEntity(),
      routeId: routeId,
      routeName: routeName,
      trainingTypeId: trainingTypeId,
      trainingTypeName: trainingTypeName,
      trainingTypeColor: trainingTypeColor,
      thresholdOffsetMinSeconds: thresholdOffsetMinSeconds,
      thresholdOffsetMaxSeconds: thresholdOffsetMaxSeconds,
      sortOrder: sortOrder,
    );
  }
}
