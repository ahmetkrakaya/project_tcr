import 'package:flutter_test/flutter_test.dart';
import 'package:project_tcr/features/workout/data/models/workout_model.dart';
import 'package:project_tcr/features/workout/utils/segment_target_resolver.dart';

void main() {
  test('WorkoutSegmentModel accepts numeric pace fields from jsonb', () {
    final model = WorkoutSegmentModel.fromJson({
      'segment_type': 'main',
      'target_type': 'duration',
      'target': 'pace',
      'duration_seconds': 3600,
      'pace_seconds_per_km_min': 360.0,
      'pace_seconds_per_km_max': 390.0,
    });
    final seg = model.toEntity();
    expect(seg.paceSecondsPerKmMin, 360);
    expect(seg.paceSecondsPerKmMax, 390);
    expect(effectivePaceDisplay(seg, isAdminView: true), isNotNull);
  });
}
