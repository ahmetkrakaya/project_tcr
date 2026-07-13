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

    test('user warmup interval cooldown multiline', () {
      const s = '''15dk ısınma
4x8dk vdot R 1dk
10dk soğuma''';
      final r = parseCoachText(s);
      expect(r.ok, isTrue, reason: r.error);
      final steps = r.workoutDefinition!['steps'] as List;
      expect(steps.length, 3);
      final warmup = (steps[0] as Map)['segment'] as Map;
      expect(warmup['segment_type'], 'warmup');
      expect(warmup['duration_seconds'], 900);
      final cooldown = (steps[2] as Map)['segment'] as Map;
      expect(cooldown['segment_type'], 'cooldown');
    });

    test('warmup with pace keyword', () {
      final r = parseCoachText('15dk 7:00 pace ısınma');
      expect(r.ok, isTrue, reason: r.error);
      final seg = ((r.workoutDefinition!['steps'] as List).first as Map)['segment'] as Map;
      expect(seg['segment_type'], 'warmup');
      expect(seg['pace_seconds_per_km_min'], 420);
    });

    test('warmup with pace range keyword', () {
      final r = parseCoachText('15dk 9:00-10:00 pace ısınma');
      expect(r.ok, isTrue, reason: r.error);
      final seg = ((r.workoutDefinition!['steps'] as List).first as Map)['segment'] as Map;
      expect(seg['pace_seconds_per_km_min'], 540);
      expect(seg['pace_seconds_per_km_max'], 600);
    });

    test('distance warmup', () {
      final r = parseCoachText('500m ısınma');
      expect(r.ok, isTrue, reason: r.error);
      final seg = ((r.workoutDefinition!['steps'] as List).first as Map)['segment'] as Map;
      expect(seg['segment_type'], 'warmup');
      expect(seg['distance_meters'], 500);
    });

    test('bare vdot distance rep with dk recovery', () {
      final r = parseCoachText('400m vdot R 1dk');
      expect(r.ok, isTrue, reason: r.error);
      final repeat = (r.workoutDefinition!['steps'] as List).first as Map;
      final inner = repeat['steps'] as List;
      final main = (inner[0] as Map)['segment'] as Map;
      expect(main['use_vdot_for_pace'], isTrue);
      final recovery = (inner[1] as Map)['segment'] as Map;
      expect(recovery['duration_seconds'], 60);
    });

    test('long distance rep with recovery', () {
      final r = parseCoachText('10km vdot R 1dk');
      expect(r.ok, isTrue, reason: r.error);
      final main = _firstMainSegment(r.workoutDefinition!);
      expect(main['distance_meters'], 10000);
      expect(main['use_vdot_for_pace'], isTrue);
    });

    test('5pace shorthand target', () {
      final r = parseCoachText('400m 5pace R 1dk');
      expect(r.ok, isTrue, reason: r.error);
      final main = _firstMainSegment(r.workoutDefinition!);
      expect(main['pace_seconds_per_km_min'], 300);
    });

    test('recovery with pace shorthand', () {
      final r = parseCoachText('400m vdot R 200 3pace');
      expect(r.ok, isTrue, reason: r.error);
      final repeat = (r.workoutDefinition!['steps'] as List).first as Map;
      final inner = repeat['steps'] as List;
      final recovery = (inner[1] as Map)['segment'] as Map;
      expect(recovery['distance_meters'], 200);
      expect(recovery['pace_seconds_per_km_min'], 180);
    });

    test('15min warmup alias', () {
      final r = parseCoachText('15min ısınma');
      expect(r.ok, isTrue, reason: r.error);
      final seg = ((r.workoutDefinition!['steps'] as List).first as Map)['segment'] as Map;
      expect(seg['duration_seconds'], 900);
    });

    test('glued pace without space on main interval', () {
      final r = parseCoachText('6x5dk 3:00pace R 1dk 3:00 pace');
      expect(r.ok, isTrue, reason: r.error);
      final repeat = (r.workoutDefinition!['steps'] as List).first as Map;
      final main = ((repeat['steps'] as List)[0] as Map)['segment'] as Map;
      expect(main['duration_seconds'], 300);
      expect(main['pace_seconds_per_km_min'], 180);
      final recovery = ((repeat['steps'] as List)[1] as Map)['segment'] as Map;
      expect(recovery['duration_seconds'], 60);
      expect(recovery['pace_seconds_per_km_min'], 180);
    });

    test('recovery duration plus pace', () {
      final r = parseCoachText('4x8dk vdot R 1dk 3:00 pace');
      expect(r.ok, isTrue, reason: r.error);
      final recovery = (((r.workoutDefinition!['steps'] as List).first as Map)['steps'] as List)[1] as Map;
      final seg = recovery['segment'] as Map;
      expect(seg['duration_seconds'], 60);
      expect(seg['pace_seconds_per_km_min'], 180);
    });

    test('spaced and glued unit variants parse the same', () {
      const pairs = [
        ('15 dk ısınma', '15dk ısınma'),
        ('15dakika ısınma', '15dk ısınma'),
        ('15 dakika ısınma', '15dk ısınma'),
        ('500 m ısınma', '500m ısınma'),
        ('500metre ısınma', '500m ısınma'),
        ('500 metre ısınma', '500m ısınma'),
        ('6 x 5 dk 3:00 pace R 1 dk 3:00 pace', '6x5dk 3:00pace R1dk 3:00pace'),
        ('6 x 5 dakika 3:00 p R 1 dakika 3:00 p', '6x5dk 3:00 R 1dk 3:00'),
        ('4 x 400 m vdot R 200 m 3 pace', '4x400m vdot R200m 3pace'),
        ('4 x 400 m vdot R 200 m 3p', '4x400m vdot R200m 3p'),
        ('45 min ısınma', '45min ısınma'),
        ('1 saat ısınma', '1saat ısınma'),
        ('2 kilometre soğuma', '2km soğuma'),
      ];
      for (final (spaced, glued) in pairs) {
        final a = parseCoachText(spaced);
        final b = parseCoachText(glued);
        expect(a.ok, isTrue, reason: '$spaced: ${a.error}');
        expect(b.ok, isTrue, reason: '$glued: ${b.error}');
        expect(a.workoutDefinition, b.workoutDefinition, reason: '$spaced vs $glued');
      }
    });

    test('6x5 dakika with p pace suffix parses interval', () {
      final r = parseCoachText('6x5 dakika 3:00p R 1 dakika 3:00 p');
      expect(r.ok, isTrue, reason: r.error);
      final repeat = (r.workoutDefinition!['steps'] as List).first as Map;
      final main = ((repeat['steps'] as List)[0] as Map)['segment'] as Map;
      expect(main['duration_seconds'], 300);
      expect(main['pace_seconds_per_km_min'], 180);
    });

    test('standalone recovery line without repeat prefix', () {
      const s = '''15dk 5:30 pace
R 400m 7 pace
15dk 5:20 pace
R 400m 7 pace
15dk 5:10 pace
R 400m 7 pace''';
      final r = parseCoachText(s);
      expect(r.ok, isTrue, reason: r.error);
      final steps = r.workoutDefinition!['steps'] as List;
      expect(steps.length, 6);
      final recovery = (steps[1] as Map)['segment'] as Map;
      expect(recovery['segment_type'], 'recovery');
      expect(recovery['distance_meters'], 400);
      expect(recovery['pace_seconds_per_km_min'], 420);
    });

    test('toparlanma label as standalone recovery', () {
      final r = parseCoachText('toparlanma 400m 7 pace');
      expect(r.ok, isTrue, reason: r.error);
      final seg = ((r.workoutDefinition!['steps'] as List).first as Map)['segment'] as Map;
      expect(seg['segment_type'], 'recovery');
      expect(seg['distance_meters'], 400);
    });

    test('duration with inline recovery without repeat', () {
      final r = parseCoachText('15dk 5:30 pace R 400m 7 pace');
      expect(r.ok, isTrue, reason: r.error);
      final repeat = (r.workoutDefinition!['steps'] as List).first as Map;
      expect(repeat['repeat_count'], 1);
      final inner = repeat['steps'] as List;
      expect(inner.length, 2);
      final main = (inner[0] as Map)['segment'] as Map;
      expect(main['duration_seconds'], 900);
      expect(main['pace_seconds_per_km_min'], 330);
      final recovery = (inner[1] as Map)['segment'] as Map;
      expect(recovery['segment_type'], 'recovery');
      expect(recovery['distance_meters'], 400);
    });

    test('recovery spaced duration is not parsed as meters', () {
      final r = parseCoachText(
        '2x4k(5:40 pace/5:30pace) R 2 dk 7:30pace/7:00pace',
      );
      expect(r.ok, isTrue, reason: r.error);
      final recovery = (((r.workoutDefinition!['steps'] as List).first as Map)['steps'] as List)[1] as Map;
      final seg = recovery['segment'] as Map;
      expect(seg['duration_seconds'], 120);
      expect(seg['distance_meters'], isNull);
      expect(seg['pace_seconds_per_km_min'], isNotNull);
    });

    test('user interval workout with inline warmup cooldown and pace suffixes', () {
      const input =
          '3k ısınma 6:30/6:00p + 6x1k (5:00p) R200 + R400 3:30-3:00dk + 800m 4:40p R1:30 +600m 4:35p R1:00 +400m 4:30p R0:30 +1k soğuma 6:00/6:30p';
      final r = parseCoachText(input);
      expect(r.ok, isTrue, reason: r.error);

      final steps = r.workoutDefinition!['steps'] as List;
      expect(steps.length, 7);

      final warmup = (steps[0] as Map)['segment'] as Map;
      expect(warmup['segment_type'], 'warmup');
      expect(warmup['distance_meters'], 3000);
      expect(warmup['pace_seconds_per_km_min'], 360);
      expect(warmup['pace_seconds_per_km_max'], 390);

      final mainRepeat = steps[1] as Map;
      expect(mainRepeat['repeat_count'], 6);
      final mainInner = mainRepeat['steps'] as List;
      final main = (mainInner[0] as Map)['segment'] as Map;
      expect(main['distance_meters'], 1000);
      expect(main['pace_seconds_per_km_min'], 300);
      final mainRec = (mainInner[1] as Map)['segment'] as Map;
      expect(mainRec['distance_meters'], 200);

      final floatRec = (steps[2] as Map)['segment'] as Map;
      expect(floatRec['segment_type'], 'recovery');
      expect(floatRec['distance_meters'], 400);
      expect(floatRec['duration_seconds_min'], 180);
      expect(floatRec['duration_seconds_max'], 210);

      final eightHundred = steps[3] as Map;
      final eightMain = ((eightHundred['steps'] as List)[0] as Map)['segment'] as Map;
      expect(eightMain['distance_meters'], 800);
      expect(eightMain['pace_seconds_per_km_min'], 280);
      final eightRec = ((eightHundred['steps'] as List)[1] as Map)['segment'] as Map;
      expect(eightRec['duration_seconds'], 90);

      final sixHundred = steps[4] as Map;
      final sixMain = ((sixHundred['steps'] as List)[0] as Map)['segment'] as Map;
      expect(sixMain['distance_meters'], 600);
      expect(sixMain['pace_seconds_per_km_min'], 275);
      final sixRec = ((sixHundred['steps'] as List)[1] as Map)['segment'] as Map;
      expect(sixRec['duration_seconds'], 60);

      final fourHundred = steps[5] as Map;
      final fourMain = ((fourHundred['steps'] as List)[0] as Map)['segment'] as Map;
      expect(fourMain['distance_meters'], 400);
      expect(fourMain['pace_seconds_per_km_min'], 270);
      final fourRec = ((fourHundred['steps'] as List)[1] as Map)['segment'] as Map;
      expect(fourRec['duration_seconds'], 30);

      final cooldown = (steps[6] as Map)['segment'] as Map;
      expect(cooldown['segment_type'], 'cooldown');
      expect(cooldown['distance_meters'], 1000);
      expect(cooldown['pace_seconds_per_km_min'], 360);
      expect(cooldown['pace_seconds_per_km_max'], 390);
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
