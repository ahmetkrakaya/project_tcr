import '../../domain/entities/workout_entity.dart';

/// JSONB ve export için WorkoutSegment modeli
class WorkoutSegmentModel {
  final String segmentType;
  final String targetType;
  final String target;
  final int? durationSeconds;
  final int? durationSecondsMin;
  final int? durationSecondsMax;
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
    this.durationSecondsMin,
    this.durationSecondsMax,
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

  static int? _jsonInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  factory WorkoutSegmentModel.fromJson(Map<String, dynamic> json) {
    return WorkoutSegmentModel(
      segmentType: json['segment_type'] as String? ?? json['segmentType'] as String? ?? 'warmup',
      targetType: json['target_type'] as String? ?? json['targetType'] as String? ?? 'duration',
      target: json['target'] as String? ?? 'none',
      durationSeconds: _jsonInt(json['duration_seconds'] ?? json['durationSeconds']),
      durationSecondsMin: _jsonInt(json['duration_seconds_min'] ?? json['durationSecondsMin']),
      durationSecondsMax: _jsonInt(json['duration_seconds_max'] ?? json['durationSecondsMax']),
      distanceMeters: (json['distance_meters'] as num?)?.toDouble() ?? (json['distanceMeters'] as num?)?.toDouble(),
      paceSecondsPerKm: _jsonInt(json['pace_seconds_per_km'] ?? json['paceSecondsPerKm']),
      paceSecondsPerKmMin: _jsonInt(json['pace_seconds_per_km_min'] ?? json['paceSecondsPerKmMin']),
      paceSecondsPerKmMax: _jsonInt(json['pace_seconds_per_km_max'] ?? json['paceSecondsPerKmMax']),
      customPaceSecondsPerKm: _jsonInt(json['custom_pace_seconds_per_km'] ?? json['customPaceSecondsPerKm']),
      useVdotForPace: json['use_vdot_for_pace'] as bool? ?? json['useVdotForPace'] as bool?,
      heartRateBpmMin: _jsonInt(json['heart_rate_bpm_min'] ?? json['heartRateBpmMin']),
      heartRateBpmMax: _jsonInt(json['heart_rate_bpm_max'] ?? json['heartRateBpmMax']),
      cadenceMin: _jsonInt(json['cadence_min'] ?? json['cadenceMin']),
      cadenceMax: _jsonInt(json['cadence_max'] ?? json['cadenceMax']),
      powerWattsMin: _jsonInt(json['power_watts_min'] ?? json['powerWattsMin']),
      powerWattsMax: _jsonInt(json['power_watts_max'] ?? json['powerWattsMax']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'segment_type': segmentType,
      'target_type': targetType,
      'target': target,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (durationSecondsMin != null) 'duration_seconds_min': durationSecondsMin,
      if (durationSecondsMax != null) 'duration_seconds_max': durationSecondsMax,
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
      durationSecondsMin: durationSecondsMin,
      durationSecondsMax: durationSecondsMax,
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
      durationSecondsMin: e.durationSecondsMin,
      durationSecondsMax: e.durationSecondsMax,
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
      repeatCount: WorkoutSegmentModel._jsonInt(json['repeat_count'] ?? json['repeatCount']),
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
