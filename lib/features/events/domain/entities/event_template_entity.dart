import 'package:flutter/material.dart';

import 'event_entity.dart';
import '../../../workout/domain/entities/workout_entity.dart' show WorkoutDefinitionEntity;

/// Event Template Entity - Etkinlik Şablonu
class EventTemplateEntity {
  final String id;
  final String name;
  final String? description;
  final EventType eventType;
  final String? locationName;
  final String? locationAddress;
  final double? locationLat;
  final double? locationLng;
  final String? routeId;
  final String? routeName;
  final String? trainingTypeId;
  final String? trainingTypeName;
  final String? trainingTypeColor;
  final TimeOfDay? defaultStartTime;
  final int? durationMinutes;
  final bool isActive;
  final String createdBy;
  final DateTime createdAt;
  final List<EventTemplateGroupProgramEntity> groupPrograms;
  final String participationType;
  final LaneConfigEntity? laneConfig;

  const EventTemplateEntity({
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

  /// Kısa açıklama (liste için)
  String get shortDescription {
    final parts = <String>[];
    if (locationName != null && locationName!.isNotEmpty) {
      parts.add(locationName!);
    }
    if (trainingTypeName != null && trainingTypeName!.isNotEmpty) {
      parts.add(trainingTypeName!);
    }
    if (defaultStartTime != null) {
      final hour = defaultStartTime!.hour.toString().padLeft(2, '0');
      final minute = defaultStartTime!.minute.toString().padLeft(2, '0');
      parts.add('$hour:$minute');
    }
    return parts.isEmpty ? eventType.displayName : parts.join(' • ');
  }
}

/// Event Template Group Program Entity - Şablon Grup Programı
class EventTemplateGroupProgramEntity {
  final String id;
  final String templateId;
  final String trainingGroupId;
  final String? trainingGroupName;
  final String? trainingGroupColor;
  final String programContent;
  final WorkoutDefinitionEntity? workoutDefinition;
  final String? routeId;
  final String? routeName;
  final String? trainingTypeId;
  final String? trainingTypeName;
  final String? trainingTypeColor;
  final int? thresholdOffsetMinSeconds;
  final int? thresholdOffsetMaxSeconds;
  final int sortOrder;

  const EventTemplateGroupProgramEntity({
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
}
