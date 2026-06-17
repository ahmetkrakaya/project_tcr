import '../../features/workout/domain/entities/workout_entity.dart';
import '../../features/workout/utils/segment_target_resolver.dart';

/// IAAF standart pist: kulvar 1 = 400 m, kulvar genişliği 1,22 m.
class TrackLaneCalculator {
  TrackLaneCalculator._();

  static const double laneWidthM = 1.22;
  static const double defaultLane1Km = 0.4;
  static const int minLane = 1;
  static const int maxLane = 8;

  static double lapLengthKm(int lane, {double lane1Km = defaultLane1Km}) {
    if (lane <= 1) return lane1Km;
    const extraMetersPerLane = 2 * 3.14159265359 * laneWidthM;
    return lane1Km + (lane - 1) * (extraMetersPerLane / 1000);
  }

  static double laneRatio(
    int referenceLane,
    int viewLane, {
    double lane1Km = defaultLane1Km,
  }) {
    final ref = lapLengthKm(referenceLane, lane1Km: lane1Km);
    final view = lapLengthKm(viewLane, lane1Km: lane1Km);
    if (ref <= 0) return 1;
    return view / ref;
  }

  /// Pist görünümü: kulvar dönüşümü + pace'ten türetilmiş süreler.
  static WorkoutDefinitionEntity prepareForTrackView(
    WorkoutDefinitionEntity definition, {
    required int referenceLane,
    required int viewLane,
    double lane1Km = defaultLane1Km,
  }) {
    return WorkoutDefinitionEntity(
      steps: definition.steps
          .map(
            (step) => _prepareStep(
              step,
              referenceLane,
              viewLane,
              lane1Km,
            ),
          )
          .toList(),
    );
  }

  static WorkoutStepEntity _prepareStep(
    WorkoutStepEntity step,
    int referenceLane,
    int viewLane,
    double lane1Km,
  ) {
    if (step.isSegment && step.segment != null) {
      return WorkoutStepEntity(
        type: step.type,
        segment: prepareSegmentForTrackView(
          step.segment!,
          referenceLane: referenceLane,
          viewLane: viewLane,
          lane1Km: lane1Km,
        ),
      );
    }
    if (step.isRepeat && step.steps != null) {
      return WorkoutStepEntity(
        type: step.type,
        repeatCount: step.repeatCount,
        steps: step.steps!
            .map((s) => _prepareStep(s, referenceLane, viewLane, lane1Km))
            .toList(),
      );
    }
    return step;
  }

  static WorkoutSegmentEntity prepareSegmentForTrackView(
    WorkoutSegmentEntity segment, {
    required int referenceLane,
    required int viewLane,
    double lane1Km = defaultLane1Km,
  }) {
    if (!_shouldAdjustSegment(segment)) return segment;

    var prepared = segment;
    if (referenceLane != viewLane) {
      prepared = adjustSegmentForLane(
        prepared,
        referenceLane: referenceLane,
        viewLane: viewLane,
        lane1Km: lane1Km,
      );
    }
    return _enrichDurationFromPace(
      prepared,
      referenceLane: referenceLane,
      viewLane: viewLane,
      lane1Km: lane1Km,
    );
  }

  /// Pace verilmiş ama süre yoksa, seçili kulvara göre süreyi hesaplar.
  static WorkoutSegmentEntity _enrichDurationFromPace(
    WorkoutSegmentEntity segment, {
    required int referenceLane,
    required int viewLane,
    double lane1Km = defaultLane1Km,
  }) {
    final distanceM = segment.distanceMeters;
    if (distanceM == null || distanceM <= 0) return segment;
    if (!hasPaceTarget(segment)) return segment;
    if (_hasStoredDuration(segment)) return segment;

    final paceMin = segment.paceSecondsPerKmMin ??
        segment.customPaceSecondsPerKm ??
        segment.paceSecondsPerKm;
    final paceMax = segment.paceSecondsPerKmMax ?? paceMin;
    if (paceMin == null || paceMin <= 0) return segment;

    final viewKm = _effectiveDistanceKm(
      distanceM,
      referenceLane: referenceLane,
      viewLane: viewLane,
      lane1Km: lane1Km,
    );

    int? durationSecondsMin;
    int? durationSecondsMax;
    if (paceMax != null && paceMax != paceMin) {
      final fast = paceMin < paceMax ? paceMin : paceMax;
      final slow = paceMin > paceMax ? paceMin : paceMax;
      durationSecondsMin = (fast * viewKm).round();
      durationSecondsMax = (slow * viewKm).round();
    }

    final durationSeconds = durationSecondsMin ?? (paceMin * viewKm).round();

    return WorkoutSegmentEntity(
      segmentType: segment.segmentType,
      targetType: segment.targetType,
      target: segment.target,
      durationSeconds: durationSeconds,
      durationSecondsMin: durationSecondsMin,
      durationSecondsMax: durationSecondsMax,
      distanceMeters: segment.distanceMeters,
      paceSecondsPerKm: segment.paceSecondsPerKm,
      paceSecondsPerKmMin: segment.paceSecondsPerKmMin,
      paceSecondsPerKmMax: segment.paceSecondsPerKmMax,
      customPaceSecondsPerKm: segment.customPaceSecondsPerKm,
      useVdotForPace: segment.useVdotForPace,
      heartRateBpmMin: segment.heartRateBpmMin,
      heartRateBpmMax: segment.heartRateBpmMax,
      cadenceMin: segment.cadenceMin,
      cadenceMax: segment.cadenceMax,
      powerWattsMin: segment.powerWattsMin,
      powerWattsMax: segment.powerWattsMax,
    );
  }

  static bool _hasStoredDuration(WorkoutSegmentEntity segment) {
    if (segment.targetType == WorkoutTargetType.duration &&
        segment.durationSeconds != null) {
      return true;
    }
    return hasSplitTarget(segment);
  }

  static double _effectiveDistanceKm(
    double distanceMeters, {
    required int referenceLane,
    required int viewLane,
    double lane1Km = defaultLane1Km,
  }) {
    final refKm = lapLengthKm(referenceLane, lane1Km: lane1Km);
    final lapCount = distanceMeters / (refKm * 1000);
    return lapCount * lapLengthKm(viewLane, lane1Km: lane1Km);
  }

  /// Tek tur süresi (sn); pace aralığı varsa (hızlı, yavaş) döner.
  static (int minSec, int maxSec)? lapTimeRangeForSegment(
    WorkoutSegmentEntity segment,
    int viewLane, {
    double lane1Km = defaultLane1Km,
  }) {
    final range = effectivePaceRange(segment);
    if (range == null) return null;
    final lapKm = lapLengthKm(viewLane, lane1Km: lane1Km);
    final fastPace = range.$1 < range.$2 ? range.$1 : range.$2;
    final slowPace = range.$1 > range.$2 ? range.$1 : range.$2;
    return (
      (fastPace * lapKm).round(),
      (slowPace * lapKm).round(),
    );
  }

  /// Pistte koçun referans kulvarından sporcu kulvarına süre dönüşümü (pace sabit).
  static WorkoutSegmentEntity adjustSegmentForLane(
    WorkoutSegmentEntity segment, {
    required int referenceLane,
    required int viewLane,
    double lane1Km = defaultLane1Km,
  }) {
    if (referenceLane == viewLane) return segment;
    if (!_shouldAdjustSegment(segment)) return segment;

    final ratio = laneRatio(referenceLane, viewLane, lane1Km: lane1Km);
    if ((ratio - 1).abs() < 0.0001) return segment;

    int? scaleSec(int? sec) =>
        sec != null && sec > 0 ? (sec * ratio).round().clamp(1, 86400) : null;

    var durationSeconds = scaleSec(segment.durationSeconds);
    var durationSecondsMin = scaleSec(segment.durationSecondsMin);
    var durationSecondsMax = scaleSec(segment.durationSecondsMax);

    final distanceM = segment.distanceMeters;
    final hasPace = hasPaceTarget(segment);
    final hasTime = _hasStoredDuration(segment);

    if (distanceM != null &&
        distanceM > 0 &&
        hasPace &&
        !hasTime &&
        segment.paceSecondsPerKmMin != null) {
      final viewKm = _effectiveDistanceKm(
        distanceM,
        referenceLane: referenceLane,
        viewLane: viewLane,
        lane1Km: lane1Km,
      );
      final pace = segment.paceSecondsPerKmMin!;
      durationSeconds = (pace * viewKm).round();
      if (segment.paceSecondsPerKmMax != null &&
          segment.paceSecondsPerKmMax != segment.paceSecondsPerKmMin) {
        final paceMax = segment.paceSecondsPerKmMax!;
        final fast = pace < paceMax ? pace : paceMax;
        final slow = pace > paceMax ? pace : paceMax;
        durationSecondsMin = (fast * viewKm).round();
        durationSecondsMax = (slow * viewKm).round();
      }
    }

    return WorkoutSegmentEntity(
      segmentType: segment.segmentType,
      targetType: segment.targetType,
      target: segment.target,
      durationSeconds: durationSeconds,
      durationSecondsMin: durationSecondsMin,
      durationSecondsMax: durationSecondsMax,
      distanceMeters: segment.distanceMeters,
      paceSecondsPerKm: segment.paceSecondsPerKm,
      paceSecondsPerKmMin: segment.paceSecondsPerKmMin,
      paceSecondsPerKmMax: segment.paceSecondsPerKmMax,
      customPaceSecondsPerKm: segment.customPaceSecondsPerKm,
      useVdotForPace: segment.useVdotForPace,
      heartRateBpmMin: segment.heartRateBpmMin,
      heartRateBpmMax: segment.heartRateBpmMax,
      cadenceMin: segment.cadenceMin,
      cadenceMax: segment.cadenceMax,
      powerWattsMin: segment.powerWattsMin,
      powerWattsMax: segment.powerWattsMax,
    );
  }

  static bool _shouldAdjustSegment(WorkoutSegmentEntity segment) {
    if (segment.distanceMeters != null && segment.distanceMeters! > 0) {
      return true;
    }
    if (segment.targetType == WorkoutTargetType.duration &&
        segment.durationSeconds != null) {
      return segment.durationSeconds! < 1200;
    }
    return hasSplitTarget(segment);
  }

  @Deprecated('Use prepareForTrackView instead')
  static WorkoutDefinitionEntity adjustDefinitionForLane(
    WorkoutDefinitionEntity definition, {
    required int referenceLane,
    required int viewLane,
    double lane1Km = defaultLane1Km,
  }) {
    return prepareForTrackView(
      definition,
      referenceLane: referenceLane,
      viewLane: viewLane,
      lane1Km: lane1Km,
    );
  }
}
