import 'dart:async';

import 'package:flutter/services.dart';

import '../../../core/utils/vdot_calculator.dart';
import '../../workout/domain/entities/workout_entity.dart'
    show WorkoutDefinitionEntity, WorkoutSegmentEntity, WorkoutStepEntity;

/// iOS WorkoutKit köprüsü için platform kanalı.
class AppleWatchWorkoutKitChannel {
  AppleWatchWorkoutKitChannel._();

  static const _channel = MethodChannel('tcr/apple_watch_workoutkit');

  static Future<bool> isSupported() async {
    final v = await _channel.invokeMethod<bool>('isSupported');
    return v ?? false;
  }

  /// iOS tarafında WorkoutScheduler authorization ister.
  ///
  /// Dönen değerler:
  /// - `authorized`
  /// - `denied`
  /// - `notDetermined`
  /// - `restricted`
  /// - `notSupported`
  static Future<String> requestAuthorization() async {
    final v = await _channel.invokeMethod<String>('requestAuthorization');
    return v ?? 'unknown';
  }

  static Future<String> getAuthorizationStatus() async {
    final v = await _channel.invokeMethod<String>('getAuthorizationStatus');
    return v ?? 'unknown';
  }

  /// Planlı antrenmanları Apple Watch Workout uygulamasına schedule eder.
  ///
  /// `payloads` iOS tarafında `WorkoutPlan(.custom(...))` olarak oluşturulup schedule edilir.
  static Future<void> syncScheduledWorkouts({
    required List<AppleWatchScheduledWorkoutPayload> payloads,
  }) async {
    await _channel.invokeMethod<void>(
      'syncScheduledWorkouts',
      {
        'payloads': payloads.map((e) => e.toJson()).toList(),
      },
    );
  }
}

/// iOS tarafına gidecek minimum payload.
class AppleWatchScheduledWorkoutPayload {
  final String id;
  final String title;
  final DateTime scheduledAt;
  final WorkoutDefinitionEntity definition;
  final String? trainingTypeName;
  /// VDOT segmentlerinde pace çözümlemek için (ısınma/ana/soğuma tempo saate gitsin).
  final double? userVdot;
  /// Eşik temposuna göre minimum sapma (saniye).
  final int? thresholdOffsetMinSeconds;
  /// Eşik temposuna göre maksimum sapma (saniye).
  final int? thresholdOffsetMaxSeconds;

  const AppleWatchScheduledWorkoutPayload({
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
      'scheduledAtMs': scheduledAt.millisecondsSinceEpoch,
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
    // Isınma/Ana/Soğuma için pace: önce mevcut değer, yoksa VDOT+offset ile çözümle
    int? resolvedPaceMin;
    int? resolvedPaceMax;

    if (s.effectivePaceSecondsPerKm != null) {
      resolvedPaceMin = s.effectivePaceSecondsPerKm;
      resolvedPaceMax = s.effectivePaceSecondsPerKm;
    } else if (s.useVdotForPace == true && userVdot != null && userVdot! > 0) {
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

    final fallbackPace = s.customPaceSecondsPerKm ?? s.paceSecondsPerKm ?? s.paceSecondsPerKmMin;
    final paceMinToSend = resolvedPaceMin ?? fallbackPace;
    final paceMaxToSend = resolvedPaceMax ?? fallbackPace;

    return {
      'segmentType': s.segmentType.name,
      'targetType': s.targetType.name,
      'target': s.target.name,
      'durationSeconds': s.durationSeconds,
      'distanceMeters': s.distanceMeters,
      'useVdotForPace': s.useVdotForPace,
      'customPaceSecondsPerKm': s.customPaceSecondsPerKm,
      'paceSecondsPerKm': paceMinToSend, // Hızlı pace (geriye uyumluluk)
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
