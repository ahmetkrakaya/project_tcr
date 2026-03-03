import 'package:flutter_test/flutter_test.dart';

import 'package:project_tcr/features/integrations/apple_watch/apple_watch_workoutkit_channel.dart';
import 'package:project_tcr/features/workout/domain/entities/workout_entity.dart';

void main() {
  test('AppleWatchScheduledWorkoutPayload encodes scheduledAt and repeat block', () {
    final warmupSeg = WorkoutSegmentEntity(
      segmentType: WorkoutSegmentType.warmup,
      targetType: WorkoutTargetType.duration,
      target: WorkoutTarget.none,
      durationSeconds: 5 * 60,
    );

    final mainSeg = WorkoutSegmentEntity(
      segmentType: WorkoutSegmentType.main,
      targetType: WorkoutTargetType.duration,
      target: WorkoutTarget.none,
      durationSeconds: 3 * 60,
    );

    final recoverySeg = WorkoutSegmentEntity(
      segmentType: WorkoutSegmentType.recovery,
      targetType: WorkoutTargetType.duration,
      target: WorkoutTarget.none,
      durationSeconds: 90,
    );

    final cooldownSeg = WorkoutSegmentEntity(
      segmentType: WorkoutSegmentType.cooldown,
      targetType: WorkoutTargetType.open,
      target: WorkoutTarget.none,
    );

    final definition = WorkoutDefinitionEntity(
      steps: [
        WorkoutStepEntity(type: 'segment', segment: warmupSeg),
        WorkoutStepEntity(
          type: 'repeat',
          repeatCount: 2,
          steps: [
            WorkoutStepEntity(type: 'segment', segment: mainSeg),
            WorkoutStepEntity(type: 'segment', segment: recoverySeg),
          ],
        ),
        WorkoutStepEntity(type: 'segment', segment: cooldownSeg),
      ],
    );

    final scheduledAt = DateTime.utc(2025, 1, 1, 10, 0);

    final payload = AppleWatchScheduledWorkoutPayload(
      id: 'test-apple-repeat',
      title: 'Test Repeat Workout',
      scheduledAt: scheduledAt,
      definition: definition,
    );

    final json = payload.toJson();

    expect(json['id'], 'test-apple-repeat');
    expect(json['title'], 'Test Repeat Workout');
    expect(json['scheduledAt'], isA<String>());
    expect(json['scheduledAtMs'], scheduledAt.millisecondsSinceEpoch);

    final defJson = json['definition'] as Map<String, dynamic>;
    final stepsJson = defJson['steps'] as List<dynamic>;

    expect(stepsJson.length, 3);

    final repeatStep = stepsJson[1] as Map<String, dynamic>;
    expect(repeatStep['type'], 'repeat');
    expect(repeatStep['repeatCount'], 2);

    final innerSteps = repeatStep['steps'] as List<dynamic>;
    expect(innerSteps.length, 2);

    final firstInner = innerSteps.first as Map<String, dynamic>;
    final lastInner = innerSteps.last as Map<String, dynamic>;

    expect(firstInner['type'], 'segment');
    expect(lastInner['type'], 'segment');
  });
}

