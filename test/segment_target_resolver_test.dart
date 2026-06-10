import 'package:flutter_test/flutter_test.dart';
import 'package:project_tcr/features/workout/domain/entities/workout_entity.dart';
import 'package:project_tcr/features/workout/utils/segment_target_resolver.dart';

WorkoutSegmentEntity _distanceSeg({
  int? durationSeconds,
  int? durationSecondsMin,
  int? durationSecondsMax,
  int? paceMin,
  int? paceMax,
  WorkoutTarget target = WorkoutTarget.pace,
}) {
  return WorkoutSegmentEntity(
    segmentType: WorkoutSegmentType.main,
    targetType: WorkoutTargetType.distance,
    target: target,
    distanceMeters: 400,
    durationSeconds: durationSeconds,
    durationSecondsMin: durationSecondsMin,
    durationSecondsMax: durationSecondsMax,
    paceSecondsPerKmMin: paceMin,
    paceSecondsPerKmMax: paceMax,
  );
}

void main() {
  group('inferPerformanceTarget', () {
    test('pace only', () {
      final s = _distanceSeg(paceMin: 270, paceMax: 278);
      expect(inferPerformanceTarget(s), SegmentPerformanceTarget.pace);
    });

    test('time only from split', () {
      final s = _distanceSeg(durationSeconds: 111, target: WorkoutTarget.time);
      expect(inferPerformanceTarget(s), SegmentPerformanceTarget.time);
    });

    test('both pace and split', () {
      final s = _distanceSeg(durationSeconds: 111, paceMin: 278, paceMax: 278);
      expect(inferPerformanceTarget(s), SegmentPerformanceTarget.both);
    });
  });

  group('effectivePaceRange', () {
    test('derives pace from split-only segment', () {
      final s = _distanceSeg(durationSeconds: 111, target: WorkoutTarget.time);
      final range = effectivePaceRange(s);
      expect(range, isNotNull);
      expect(range!.$1, 278);
      expect(range.$2, 278);
    });

    test('derives pace range from split min/max', () {
      final s = _distanceSeg(
        durationSecondsMin: 110,
        durationSecondsMax: 115,
        target: WorkoutTarget.time,
      );
      final range = effectivePaceRange(s);
      expect(range, isNotNull);
      expect(range!.$1, lessThan(range.$2));
    });

    test('both keeps explicit pace for export', () {
      final s = _distanceSeg(durationSeconds: 111, paceMin: 278, paceMax: 278);
      final range = effectivePaceRange(s);
      expect(range, (278, 278));
    });
  });

  group('effectiveSplitDisplay', () {
    test('single split', () {
      final s = _distanceSeg(durationSeconds: 111);
      expect(effectiveSplitDisplay(s), '1:51');
    });

    test('split range', () {
      final s = _distanceSeg(durationSecondsMin: 110, durationSecondsMax: 115);
      expect(effectiveSplitDisplay(s), contains('–'));
    });
  });

  group('performanceTargetToJson', () {
    test('time target serializes as time', () {
      final s = _distanceSeg(durationSeconds: 111, target: WorkoutTarget.time);
      expect(performanceTargetToJson(s), 'time');
    });

    test('both serializes as pace for device export', () {
      final s = _distanceSeg(durationSeconds: 111, paceMin: 278, paceMax: 278);
      expect(performanceTargetToJson(s), 'pace');
    });
  });
}
