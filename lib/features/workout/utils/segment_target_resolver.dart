import '../../../../core/utils/vdot_calculator.dart';
import '../domain/entities/workout_entity.dart';

/// Performans hedefi türü (tempo, süre veya ikisi).
enum SegmentPerformanceTarget { none, pace, time, both }

/// Mesafe segmentlerinde süre hedefi (split) alanları.
bool hasTimeTarget(WorkoutSegmentEntity s) {
  if (s.targetType == WorkoutTargetType.duration) {
    return s.durationSeconds != null ||
        s.durationSecondsMin != null ||
        s.durationSecondsMax != null;
  }
  if (s.targetType == WorkoutTargetType.distance) {
    return s.durationSeconds != null ||
        s.durationSecondsMin != null ||
        s.durationSecondsMax != null;
  }
  return false;
}

bool hasPaceTarget(WorkoutSegmentEntity s) {
  if (s.useVdotForPace == true) return true;
  if (s.paceSecondsPerKmMin != null || s.paceSecondsPerKmMax != null) return true;
  if (s.customPaceSecondsPerKm != null || s.paceSecondsPerKm != null) return true;
  if (s.target == WorkoutTarget.pace) return true;
  return false;
}

/// Eski kayıtlar ve parser çıktısı için otomatik hedef çıkarımı.
SegmentPerformanceTarget inferPerformanceTarget(WorkoutSegmentEntity s) {
  final pace = hasPaceTarget(s);
  final time = hasSplitTarget(s);
  if (pace && time) return SegmentPerformanceTarget.both;
  if (pace) return SegmentPerformanceTarget.pace;
  if (time) return SegmentPerformanceTarget.time;
  if (s.target == WorkoutTarget.time) return SegmentPerformanceTarget.time;
  if (s.target == WorkoutTarget.pace) return SegmentPerformanceTarget.pace;
  return SegmentPerformanceTarget.none;
}

/// Mesafe adımında split/süre performans hedefi var mı?
bool hasSplitTarget(WorkoutSegmentEntity s) {
  if (s.targetType != WorkoutTargetType.distance) return false;
  return s.durationSeconds != null ||
      s.durationSecondsMin != null ||
      s.durationSecondsMax != null;
}

int? _paceFromSplit(int splitSec, double? distanceMeters) {
  if (distanceMeters == null || distanceMeters <= 0) return null;
  return (splitSec / (distanceMeters / 1000)).round();
}

/// Export ve cihaz aktarımı için etkili tempo aralığı (saniye/km).
(int, int)? effectivePaceRange(
  WorkoutSegmentEntity s, {
  double? userVdot,
  int? offsetMin,
  int? offsetMax,
}) {
  if (s.target == WorkoutTarget.pace || s.useVdotForPace == true) {
  } else if (s.target != WorkoutTarget.time &&
      inferPerformanceTarget(s) == SegmentPerformanceTarget.time) {
    // sadece süre — aşağıda türet
  } else if (!hasPaceTarget(s) && !hasSplitTarget(s)) {
    // HR/kadans/güç veya hedef yok
    if (s.target != WorkoutTarget.pace && s.useVdotForPace != true) {
      if (s.target == WorkoutTarget.heartRate ||
          s.target == WorkoutTarget.cadence ||
          s.target == WorkoutTarget.power) {
        return null;
      }
    }
  }

  if (s.useVdotForPace == true &&
      userVdot != null &&
      userVdot > 0) {
    final paceRange = VdotCalculator.getPaceRangeForSegmentType(
      userVdot,
      s.segmentType.name,
      offsetMin,
      offsetMax,
    );
    if (paceRange != null) return (paceRange.$1, paceRange.$2);
  }

  final paceMin = s.paceSecondsPerKmMin ?? s.customPaceSecondsPerKm ?? s.paceSecondsPerKm;
  final paceMax = s.paceSecondsPerKmMax ?? paceMin;
  if (paceMin != null && paceMin > 0) {
    return (paceMin, paceMax ?? paceMin);
  }

  if (hasSplitTarget(s) && s.targetType == WorkoutTargetType.distance) {
    if (s.durationSecondsMin != null && s.durationSecondsMax != null) {
      final minPace = _paceFromSplit(s.durationSecondsMax!, s.distanceMeters);
      final maxPace = _paceFromSplit(s.durationSecondsMin!, s.distanceMeters);
      if (minPace != null && maxPace != null) {
        return (minPace < maxPace ? minPace : maxPace, minPace > maxPace ? minPace : maxPace);
      }
    }
    if (s.durationSeconds != null) {
      final derived = _paceFromSplit(s.durationSeconds!, s.distanceMeters);
      if (derived != null) return (derived, derived);
    }
  }

  if (userVdot != null &&
      userVdot > 0 &&
      (offsetMin != null || offsetMax != null)) {
    final paceRange = VdotCalculator.getPaceRangeForSegmentType(
      userVdot,
      s.segmentType.name,
      offsetMin,
      offsetMax,
    );
    if (paceRange != null) return (paceRange.$1, paceRange.$2);
  }

  return null;
}

String _formatDurationSec(int sec) {
  final m = sec ~/ 60;
  final s = sec % 60;
  if (m <= 0) return '${s}s';
  if (s == 0) return '$m dk';
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// UI için süre/split metni (mesafe adımlarında).
String? effectiveSplitDisplay(WorkoutSegmentEntity s) {
  if (s.targetType == WorkoutTargetType.duration && s.durationSeconds != null) {
    return _formatDurationSec(s.durationSeconds!);
  }
  if (!hasSplitTarget(s)) return null;
  final min = s.durationSecondsMin;
  final max = s.durationSecondsMax;
  if (min != null && max != null) {
    return '${_formatDurationSec(min)} – ${_formatDurationSec(max)}';
  }
  if (s.durationSeconds != null) {
    return _formatDurationSec(s.durationSeconds!);
  }
  return null;
}

/// UI için tempo metni.
String? effectivePaceDisplay(
  WorkoutSegmentEntity s, {
  double? userVdot,
  int? offsetMin,
  int? offsetMax,
  bool isAdminView = false,
}) {
  if (s.useVdotForPace == true) {
    if (isAdminView) return 'VDOT Pace';
    if (userVdot != null && userVdot > 0) {
      final paceStr = VdotCalculator.getPaceForSegmentType(
        userVdot,
        s.segmentType.name,
        offsetMin,
        offsetMax,
      );
      if (paceStr != null) return paceStr;
    }
    return 'VDOT Pace';
  }

  final range = effectivePaceRange(s, userVdot: userVdot, offsetMin: offsetMin, offsetMax: offsetMax);
  if (range != null) {
    final (min, max) = range;
    if (min != max) {
      return '${VdotCalculator.formatPace(min)} – ${VdotCalculator.formatPace(max)}';
    }
    return VdotCalculator.formatPace(min);
  }

  return null;
}

String performanceTargetToJson(WorkoutSegmentEntity s) {
  switch (inferPerformanceTarget(s)) {
    case SegmentPerformanceTarget.pace:
      return 'pace';
    case SegmentPerformanceTarget.time:
      return 'time';
    case SegmentPerformanceTarget.both:
      return 'pace';
    case SegmentPerformanceTarget.none:
      if (s.target == WorkoutTarget.heartRate) return 'heart_rate';
      if (s.target == WorkoutTarget.power) return 'power';
      if (s.target == WorkoutTarget.cadence) return 'cadence';
      return 'none';
  }
}
