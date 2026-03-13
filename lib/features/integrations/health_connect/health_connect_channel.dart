import 'package:flutter/services.dart';

import '../../../core/utils/vdot_calculator.dart';
import '../../workout/domain/entities/workout_entity.dart'
    show WorkoutDefinitionEntity, WorkoutSegmentEntity, WorkoutStepEntity;

/// Android Health Connect MethodChannel köprüsü.
class HealthConnectChannel {
  HealthConnectChannel._();

  static const _channel = MethodChannel('tcr/health_connect_workout');

  static Future<bool> isSupported() async {
    try {
      final v = await _channel.invokeMethod<bool>('isSupported');
      return v ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<String> requestAuthorization() async {
    final v = await _channel.invokeMethod<String>('requestAuthorization');
    return v ?? 'unknown';
  }

  static Future<String> getAuthorizationStatus() async {
    final v = await _channel.invokeMethod<String>('getAuthorizationStatus');
    return v ?? 'unknown';
  }

  /// Planlı antrenmanları Health Connect'e yazar.
  static Future<void> syncScheduledWorkouts({
    required List<HealthConnectWorkoutPayload> payloads,
  }) async {
    await _channel.invokeMethod<void>(
      'syncScheduledWorkouts',
      {
        'payloads': payloads.map((e) => e.toJson()).toList(),
      },
    );
  }
}

/// Android'e gönderilecek payload (Apple Watch formatıyla uyumlu).
class HealthConnectWorkoutPayload {
  final String id;
  final String title;
  final DateTime scheduledAt;
  final WorkoutDefinitionEntity definition;
  final String? trainingTypeName;
  final double? userVdot;
  final int? thresholdOffsetMinSeconds;
  final int? thresholdOffsetMaxSeconds;

  const HealthConnectWorkoutPayload({
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.definition,
    this.trainingTypeName,
    this.userVdot,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'scheduledAt': scheduledAt.toIso8601String(),
      'trainingTypeName': trainingTypeName,
      'definition': _definitionToJson(definition),
    };
  }

  Map<String, dynamic> _definitionToJson(WorkoutDefinitionEntity d) {
    return {
      'steps': d.steps.map((s) => _stepToJson(s)).toList(),
    };
  }

  Map<String, dynamic> _stepToJson(WorkoutStepEntity s) {
    return {
      'type': s.type,
      'repeatCount': s.repeatCount,
      'segment': s.segment != null ? _segmentToJson(s.segment!) : null,
      'steps': s.steps?.map((e) => _stepToJson(e)).toList(),
    };
  }

  Map<String, dynamic> _segmentToJson(WorkoutSegmentEntity s) {
    int? resolvedPaceMin;
    int? resolvedPaceMax;

    if (s.useVdotForPace == true && userVdot != null && userVdot! > 0) {
      final paceRange = VdotCalculator.getPaceRangeForSegmentType(
        userVdot!,
        s.segmentType.name,
        thresholdOffsetMinSeconds,
        thresholdOffsetMaxSeconds,
      );
      if (paceRange != null) {
        resolvedPaceMin = paceRange.$1;
        resolvedPaceMax = paceRange.$2;
      }
    }

    final fallbackMin =
        s.paceSecondsPerKmMin ?? s.customPaceSecondsPerKm ?? s.paceSecondsPerKm;
    final fallbackMax = s.paceSecondsPerKmMax ?? fallbackMin;
    final paceMinToSend = resolvedPaceMin ?? fallbackMin;
    final paceMaxToSend = resolvedPaceMax ?? fallbackMax;

    return {
      'segmentType': s.segmentType.name,
      'targetType': s.targetType.name,
      'target': s.target.name,
      'durationSeconds': s.durationSeconds,
      'distanceMeters': s.distanceMeters,
      'useVdotForPace': s.useVdotForPace,
      'customPaceSecondsPerKm': s.customPaceSecondsPerKm,
      'paceSecondsPerKm': paceMinToSend,
      'paceSecondsPerKmMin': paceMinToSend,
      'paceSecondsPerKmMax': paceMaxToSend,
      'heartRateBpmMin': s.heartRateBpmMin,
      'heartRateBpmMax': s.heartRateBpmMax,
      'cadenceMin': s.cadenceMin,
      'cadenceMax': s.cadenceMax,
      'powerWattsMin': s.powerWattsMin,
      'powerWattsMax': s.powerWattsMax,
    };
  }
}
