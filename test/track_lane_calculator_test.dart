import 'package:flutter_test/flutter_test.dart';
import 'package:project_tcr/core/utils/track_lane_calculator.dart';
import 'package:project_tcr/features/workout/domain/entities/workout_entity.dart';

void main() {
  group('TrackLaneCalculator', () {
    test('lapLengthKm increases per lane', () {
      expect(TrackLaneCalculator.lapLengthKm(1), closeTo(0.4, 0.001));
      expect(
        TrackLaneCalculator.lapLengthKm(3),
        closeTo(0.41533, 0.001),
      );
    });

    test('scales split time for distance rep when lane changes', () {
      const segment = WorkoutSegmentEntity(
        segmentType: WorkoutSegmentType.main,
        targetType: WorkoutTargetType.distance,
        target: WorkoutTarget.time,
        distanceMeters: 500,
        durationSeconds: 111,
      );

      final adjusted = TrackLaneCalculator.adjustSegmentForLane(
        segment,
        referenceLane: 1,
        viewLane: 3,
      );

      final ratio = TrackLaneCalculator.laneRatio(1, 3);
      expect(adjusted.durationSeconds, (111 * ratio).round());
    });

    test('derives split from pace when only pace is set', () {
      const segment = WorkoutSegmentEntity(
        segmentType: WorkoutSegmentType.main,
        targetType: WorkoutTargetType.distance,
        target: WorkoutTarget.pace,
        distanceMeters: 500,
        paceSecondsPerKmMin: 222,
        paceSecondsPerKmMax: 222,
      );

      final adjusted = TrackLaneCalculator.adjustSegmentForLane(
        segment,
        referenceLane: 1,
        viewLane: 3,
      );

      expect(adjusted.durationSeconds, isNotNull);
      expect(adjusted.durationSeconds!, greaterThan(111));
    });

    test('does not scale long duration-only segments', () {
      const segment = WorkoutSegmentEntity(
        segmentType: WorkoutSegmentType.main,
        targetType: WorkoutTargetType.duration,
        target: WorkoutTarget.none,
        durationSeconds: 2700,
      );

      final adjusted = TrackLaneCalculator.adjustSegmentForLane(
        segment,
        referenceLane: 1,
        viewLane: 5,
      );

      expect(adjusted.durationSeconds, 2700);
    });
  });
}
