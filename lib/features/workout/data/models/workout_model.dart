import '../../domain/entities/workout_entity.dart';

/// JSONB ve export için WorkoutSegment modeli
class WorkoutSegmentModel {
  final String segmentType;
  final String targetType;
  final String target;
  final int? durationSeconds;
  final double? distanceMeters;
  final int? paceSecondsPerKm;
  final int? paceSecondsPerKmMin;
  final int? paceSecondsPerKmMax;
  final int? customPaceSecondsPerKm;
  final bool? useVdotForPace;
  final int? heartRateBpmMin;
  final int? heartRateBpmMax;
  final int? cadenceMin;
  final int? cadenceMax;
  final int? powerWattsMin;
  final int? powerWattsMax;

  const WorkoutSegmentModel({
    required this.segmentType,
    required this.targetType,
    required this.target,
    this.durationSeconds,
    this.distanceMeters,
    this.paceSecondsPerKm,
    this.paceSecondsPerKmMin,
    this.paceSecondsPerKmMax,
    this.customPaceSecondsPerKm,
    this.useVdotForPace,
    this.heartRateBpmMin,
    this.heartRateBpmMax,
    this.cadenceMin,
    this.cadenceMax,
    this.powerWattsMin,
    this.powerWattsMax,
  });

  factory WorkoutSegmentModel.fromJson(Map<String, dynamic> json) {
    return WorkoutSegmentModel(
      segmentType: json['segment_type'] as String? ?? json['segmentType'] as String? ?? 'warmup',
      targetType: json['target_type'] as String? ?? json['targetType'] as String? ?? 'duration',
      target: json['target'] as String? ?? 'none',
      durationSeconds: json['duration_seconds'] as int? ?? json['durationSeconds'] as int?,
      distanceMeters: (json['distance_meters'] as num?)?.toDouble() ?? (json['distanceMeters'] as num?)?.toDouble(),
      paceSecondsPerKm: json['pace_seconds_per_km'] as int? ?? json['paceSecondsPerKm'] as int?,
      paceSecondsPerKmMin: json['pace_seconds_per_km_min'] as int? ?? json['paceSecondsPerKmMin'] as int?,
      paceSecondsPerKmMax: json['pace_seconds_per_km_max'] as int? ?? json['paceSecondsPerKmMax'] as int?,
      customPaceSecondsPerKm: json['custom_pace_seconds_per_km'] as int? ?? json['customPaceSecondsPerKm'] as int?,
      useVdotForPace: json['use_vdot_for_pace'] as bool? ?? json['useVdotForPace'] as bool?,
      heartRateBpmMin: json['heart_rate_bpm_min'] as int? ?? json['heartRateBpmMin'] as int?,
      heartRateBpmMax: json['heart_rate_bpm_max'] as int? ?? json['heartRateBpmMax'] as int?,
      cadenceMin: json['cadence_min'] as int? ?? json['cadenceMin'] as int?,
      cadenceMax: json['cadence_max'] as int? ?? json['cadenceMax'] as int?,
      powerWattsMin: json['power_watts_min'] as int? ?? json['powerWattsMin'] as int?,
      powerWattsMax: json['power_watts_max'] as int? ?? json['powerWattsMax'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'segment_type': segmentType,
      'target_type': targetType,
      'target': target,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (distanceMeters != null) 'distance_meters': distanceMeters,
      if (paceSecondsPerKm != null) 'pace_seconds_per_km': paceSecondsPerKm,
      if (paceSecondsPerKmMin != null) 'pace_seconds_per_km_min': paceSecondsPerKmMin,
      if (paceSecondsPerKmMax != null) 'pace_seconds_per_km_max': paceSecondsPerKmMax,
      if (customPaceSecondsPerKm != null) 'custom_pace_seconds_per_km': customPaceSecondsPerKm,
      if (useVdotForPace != null) 'use_vdot_for_pace': useVdotForPace,
      if (heartRateBpmMin != null) 'heart_rate_bpm_min': heartRateBpmMin,
      if (heartRateBpmMax != null) 'heart_rate_bpm_max': heartRateBpmMax,
      if (cadenceMin != null) 'cadence_min': cadenceMin,
      if (cadenceMax != null) 'cadence_max': cadenceMax,
      if (powerWattsMin != null) 'power_watts_min': powerWattsMin,
      if (powerWattsMax != null) 'power_watts_max': powerWattsMax,
    };
  }

  WorkoutSegmentEntity toEntity() {
    return WorkoutSegmentEntity(
      segmentType: _parseSegmentType(segmentType),
      targetType: _parseTargetType(targetType),
      target: _parseTarget(target),
      durationSeconds: durationSeconds,
      distanceMeters: distanceMeters,
      paceSecondsPerKm: paceSecondsPerKm,
      paceSecondsPerKmMin: paceSecondsPerKmMin,
      paceSecondsPerKmMax: paceSecondsPerKmMax,
      customPaceSecondsPerKm: customPaceSecondsPerKm,
      useVdotForPace: useVdotForPace,
      heartRateBpmMin: heartRateBpmMin,
      heartRateBpmMax: heartRateBpmMax,
      cadenceMin: cadenceMin,
      cadenceMax: cadenceMax,
      powerWattsMin: powerWattsMin,
      powerWattsMax: powerWattsMax,
    );
  }

  static WorkoutSegmentType _parseSegmentType(String v) {
    return WorkoutSegmentType.values.firstWhere(
      (e) => e.name == v,
      orElse: () => WorkoutSegmentType.warmup,
    );
  }

  static WorkoutTargetType _parseTargetType(String v) {
    return WorkoutTargetType.values.firstWhere(
      (e) => e.name == v,
      orElse: () => WorkoutTargetType.duration,
    );
  }

  static WorkoutTarget _parseTarget(String v) {
    if (v == 'heart_rate') return WorkoutTarget.heartRate;
    if (v == 'power') return WorkoutTarget.power;
    return WorkoutTarget.values.firstWhere(
      (e) => e.name == v,
      orElse: () => WorkoutTarget.none,
    );
  }

  static WorkoutSegmentModel fromEntity(WorkoutSegmentEntity e) {
    return WorkoutSegmentModel(
      segmentType: e.segmentType.name,
      targetType: e.targetType.name,
      target: e.target == WorkoutTarget.heartRate ? 'heart_rate' : (e.target == WorkoutTarget.power ? 'power' : e.target.name),
      durationSeconds: e.durationSeconds,
      distanceMeters: e.distanceMeters,
      paceSecondsPerKm: e.paceSecondsPerKm,
      paceSecondsPerKmMin: e.paceSecondsPerKmMin,
      paceSecondsPerKmMax: e.paceSecondsPerKmMax,
      customPaceSecondsPerKm: e.customPaceSecondsPerKm,
      useVdotForPace: e.useVdotForPace,
      heartRateBpmMin: e.heartRateBpmMin,
      heartRateBpmMax: e.heartRateBpmMax,
      cadenceMin: e.cadenceMin,
      cadenceMax: e.cadenceMax,
      powerWattsMin: e.powerWattsMin,
      powerWattsMax: e.powerWattsMax,
    );
  }
}

/// Adım: segment veya repeat
class WorkoutStepModel {
  final String type;
  final WorkoutSegmentModel? segment;
  final int? repeatCount;
  final List<WorkoutStepModel>? steps;

  const WorkoutStepModel({
    required this.type,
    this.segment,
    this.repeatCount,
    this.steps,
  });

  factory WorkoutStepModel.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'segment';
    final segmentJson = json['segment'] as Map<String, dynamic>?;
    final stepsList = json['steps'] as List<dynamic>?;
    return WorkoutStepModel(
      type: type,
      segment: segmentJson != null ? WorkoutSegmentModel.fromJson(segmentJson) : null,
      repeatCount: json['repeat_count'] as int? ?? json['repeatCount'] as int?,
      steps: stepsList
          ?.map((e) => WorkoutStepModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (segment != null) 'segment': segment!.toJson(),
      if (repeatCount != null) 'repeat_count': repeatCount,
      if (steps != null) 'steps': steps!.map((e) => e.toJson()).toList(),
    };
  }

  WorkoutStepEntity toEntity() {
    return WorkoutStepEntity(
      type: type,
      segment: segment?.toEntity(),
      repeatCount: repeatCount,
      steps: steps?.map((e) => e.toEntity()).toList(),
    );
  }

  static WorkoutStepModel fromEntity(WorkoutStepEntity e) {
    return WorkoutStepModel(
      type: e.type,
      segment: e.segment != null ? WorkoutSegmentModel.fromEntity(e.segment!) : null,
      repeatCount: e.repeatCount,
      steps: e.steps?.map((e) => WorkoutStepModel.fromEntity(e)).toList(),
    );
  }
}

/// WorkoutDefinition model (JSONB)
class WorkoutDefinitionModel {
  final List<WorkoutStepModel> steps;

  const WorkoutDefinitionModel({required this.steps});

  factory WorkoutDefinitionModel.fromJson(Map<String, dynamic> json) {
    final stepsList = json['steps'] as List<dynamic>? ?? [];
    return WorkoutDefinitionModel(
      steps: stepsList.map((e) => WorkoutStepModel.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  factory WorkoutDefinitionModel.fromJsonList(List<dynamic>? list) {
    if (list == null || list.isEmpty) return WorkoutDefinitionModel(steps: []);
    return WorkoutDefinitionModel(
      steps: list.map((e) => WorkoutStepModel.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'steps': steps.map((e) => e.toJson()).toList()};
  }

  WorkoutDefinitionEntity toEntity() {
    return WorkoutDefinitionEntity(
      steps: steps.map((e) => e.toEntity()).toList(),
    );
  }

  static WorkoutDefinitionModel fromEntity(WorkoutDefinitionEntity e) {
    return WorkoutDefinitionModel(
      steps: e.steps.map((e) => WorkoutStepModel.fromEntity(e)).toList(),
    );
  }
}
