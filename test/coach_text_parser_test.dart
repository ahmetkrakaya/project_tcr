import 'package:flutter_test/flutter_test.dart';
import 'package:project_tcr/features/events/utils/coach_text_parser.dart';

void main() {
  group('parseCoachText', () {
    test('empty and REST', () {
      final empty = parseCoachText('');
      expect(empty.ok, isTrue);
      expect(empty.isRest, isTrue);

      final rest = parseCoachText('REST');
      expect(rest.ok, isTrue);
      expect(rest.isRest, isTrue);
    });

    test('duration with pace range', () {
      final r = parseCoachText('60dk 6:00/5:50');
      expect(r.ok, isTrue);
      expect(r.isRest, isFalse);
      final steps = r.workoutDefinition!['steps'] as List;
      expect(steps.length, 1);
      final seg = (steps.first as Map)['segment'] as Map;
      expect(seg['duration_seconds'], 3600);
      expect(seg['pace_seconds_per_km_min'], 350);
      expect(seg['pace_seconds_per_km_max'], 360);
    });

    test('vdot duration', () {
      final r = parseCoachText('60dk vdot');
      expect(r.ok, isTrue);
      final seg = ((r.workoutDefinition!['steps'] as List).first as Map)['segment'] as Map;
      expect(seg['use_vdot_for_pace'], isTrue);
    });

    test('interval with recovery', () {
      final r = parseCoachText('5x1200(5:10/5:00) R400m 2:20');
      expect(r.ok, isTrue);
      expect(r.trainingTypeHint, CoachTrainingTypeHint.interval);
      final repeat = (r.workoutDefinition!['steps'] as List).first as Map;
      expect(repeat['repeat_count'], 5);
      final inner = repeat['steps'] as List;
      expect(inner.length, 2);
    });

    test('interval without recovery fails', () {
      final r = parseCoachText('5x1200(5:10/5:00)');
      expect(r.ok, isFalse);
      expect(r.error, contains('toparlanma'));
    });

    test('chained workout', () {
      final r = parseCoachText('3k 6:10/6:00 +5x1200(5:10/5:00) R400m +1k 6:00/6:10');
      expect(r.ok, isTrue);
      final steps = r.workoutDefinition!['steps'] as List;
      expect(steps.length, greaterThanOrEqualTo(3));
    });

    test('long run segments', () {
      final r = parseCoachText('18k: 3k 5:40 / 12k 5:30 / 3k 5:20');
      expect(r.ok, isTrue);
      expect(r.trainingTypeHint, CoachTrainingTypeHint.longRun);
      final steps = r.workoutDefinition!['steps'] as List;
      expect(steps.length, 3);
    });

    test('duration progression', () {
      final r = parseCoachText('15dk 6:00 +30dk 5:20/5:25 +15dk 5:14');
      expect(r.ok, isTrue);
      final steps = r.workoutDefinition!['steps'] as List;
      expect(steps.length, 3);
    });

    test('split target interval', () {
      final r = parseCoachText('5x400 (1:51) R200m');
      expect(r.ok, isTrue);
      expect(r.trainingTypeHint, CoachTrainingTypeHint.repetition);
      final seg = (((r.workoutDefinition!['steps'] as List).first as Map)['steps'] as List)
          .first as Map;
      final main = seg['segment'] as Map;
      expect(main['duration_seconds'], 111);
      expect(main['target'], 'time');
      expect(main['pace_seconds_per_km_min'], 278);
    });

    test('split plus pace in parens', () {
      final r = parseCoachText('5x400 (1:51-4:38p) R200m');
      expect(r.ok, isTrue, reason: r.error);
      final seg = (((r.workoutDefinition!['steps'] as List).first as Map)['steps'] as List)
          .first as Map;
      final main = seg['segment'] as Map;
      expect(main['duration_seconds'], 111);
      expect(main['target'], 'pace');
      expect(main['pace_seconds_per_km_min'], 278);
      expect(main['pace_seconds_per_km_max'], 278);
    });

    test('pace range in parens', () {
      final r = parseCoachText('5x400 (4:30-4:38p) R200m');
      expect(r.ok, isTrue);
      final main = ((((r.workoutDefinition!['steps'] as List).first as Map)['steps'] as List)
          .first as Map)['segment'] as Map;
      expect(main['target'], 'pace');
      expect(main['pace_seconds_per_km_min'], 270);
      expect(main['pace_seconds_per_km_max'], 278);
      expect(main['duration_seconds'], isNull);
    });

    test('split time range in parens', () {
      final r = parseCoachText('5x400 (1:50-1:55dk) R200m');
      expect(r.ok, isTrue);
      final main = ((((r.workoutDefinition!['steps'] as List).first as Map)['steps'] as List)
          .first as Map)['segment'] as Map;
      expect(main['target'], 'time');
      expect(main['duration_seconds_min'], 110);
      expect(main['duration_seconds_max'], 115);
    });

    test('pace with dash separator', () {
      final spec = parsePaceSpec('6:00-6:10');
      expect(spec, isA<CoachPaceRange>());
      final range = spec as CoachPaceRange;
      expect(range.minSec, 360);
      expect(range.maxSec, 370);
    });

    test('multiline coach sheet workout', () {
      const s = '''2km 6:00/5:50
5x400 (1:51-4:38p) R200m
1200 (2:08-5:20p) R400
800 (1:56-4:51p) R400
6x500(1:51-4:38) R200
1k 5:50/6:00''';
      final r = parseCoachText(s);
      expect(r.ok, isTrue, reason: r.error);
      final steps = r.workoutDefinition!['steps'] as List;
      expect(steps.length, greaterThanOrEqualTo(6));
    });

    test('standalone rep without repeat prefix', () {
      expect(parseCoachText('1200 (2:08-5:20p) R400').ok, isTrue);
      expect(parseCoachText('800(1:56-4:51p) R400').ok, isTrue);
    });

    test('distance with stray slash after unit', () {
      final r = parseCoachText('1k/ 5:50/6:00');
      expect(r.ok, isTrue, reason: r.error);
      expect(parseCoachText('1k 5:50/6:00').ok, isTrue);
    });

    test('chain without explicit warmup/cooldown labels uses main', () {
      const s = '''2km 6:00/5:50
5x400 (1:51-4:38p) R200m
1k 5:50/6:00''';
      final r = parseCoachText(s);
      expect(r.ok, isTrue, reason: r.error);
      final first = ((r.workoutDefinition!['steps'] as List).first as Map)['segment'] as Map;
      final last = ((r.workoutDefinition!['steps'] as List).last as Map)['segment'] as Map;
      expect(first['segment_type'], 'main');
      expect(last['segment_type'], 'main');
    });

    test('explicit warmup and cooldown labels', () {
      const s = '''ısınma 2km 6:00/5:50
5x400 (1:51-4:38p) R200m
soğuma 1k 5:50/6:00''';
      final r = parseCoachText(s);
      expect(r.ok, isTrue, reason: r.error);
      final first = ((r.workoutDefinition!['steps'] as List).first as Map)['segment'] as Map;
      final last = ((r.workoutDefinition!['steps'] as List).last as Map)['segment'] as Map;
      expect(first['segment_type'], 'warmup');
      expect(last['segment_type'], 'cooldown');
    });

    test('suffix warmup and cooldown labels', () {
      final warmup = parseCoachText('2k 5:40 ısınma');
      expect(warmup.ok, isTrue, reason: warmup.error);
      final warmupSeg =
          ((warmup.workoutDefinition!['steps'] as List).first as Map)['segment'] as Map;
      expect(warmupSeg['segment_type'], 'warmup');
      expect(warmupSeg['distance_meters'], 2000);

      final cooldown = parseCoachText('1k 5:50/6:00 soğuma');
      expect(cooldown.ok, isTrue, reason: cooldown.error);
      final cooldownSeg =
          ((cooldown.workoutDefinition!['steps'] as List).first as Map)['segment'] as Map;
      expect(cooldownSeg['segment_type'], 'cooldown');
    });

    test('duration interval repeats with dk unit', () {
      final r = parseCoachText('30dk 6:30/7:00 + 5x4dk (5:20p) R200');
      expect(r.ok, isTrue, reason: r.error);
      final steps = r.workoutDefinition!['steps'] as List;
      expect(steps.length, 2);

      final warmup = (steps[0] as Map)['segment'] as Map;
      expect(warmup['duration_seconds'], 1800);
      expect(warmup['pace_seconds_per_km_min'], 390);
      expect(warmup['pace_seconds_per_km_max'], 420);

      final repeat = steps[1] as Map;
      expect(repeat['repeat_count'], 5);
      final inner = repeat['steps'] as List;
      expect(inner.length, 2);
      final main = (inner[0] as Map)['segment'] as Map;
      expect(main['target_type'], 'duration');
      expect(main['duration_seconds'], 240);
      expect(main['pace_seconds_per_km_min'], 320);
      expect(main['pace_seconds_per_km_max'], 320);
      final recovery = (inner[1] as Map)['segment'] as Map;
      expect(recovery['distance_meters'], 200);
    });

    test('pace notation variants parse consistently', () {
      const paceInputs = [
        '4x500 (4:30p) R200',
        '4x500 4:30 R200',
        '4x500 (4:30) R200',
        '15dk 4:30',
        '15dk 4:30p',
        '15dk (4:30p)',
        '500m 4:30',
        '500m 4:30p',
        '500m (4:30p)',
      ];
      for (final input in paceInputs) {
        final r = parseCoachText(input);
        expect(r.ok, isTrue, reason: '${input}: ${r.error}');
        final seg = _firstMainSegment(r.workoutDefinition!);
        expect(seg['pace_seconds_per_km_min'], 270, reason: input);
        expect(seg['pace_seconds_per_km_max'], 270, reason: input);
      }
    });
  });
}

Map _firstMainSegment(Map<String, dynamic> workoutDefinition) {
  final steps = workoutDefinition['steps'] as List;
  final first = steps.first as Map;
  if (first['type'] == 'repeat') {
    final inner = (first['steps'] as List).first as Map;
    return inner['segment'] as Map;
  }
  return first['segment'] as Map;
}
