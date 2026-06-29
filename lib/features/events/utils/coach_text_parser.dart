// Koç kısa notasyonu → workout_definition JSON (önizleme için).
// Sunucu tarafı: supabase/functions/weekly-program-upsert/coach_text_parser.ts

import 'coach_text_normalizer.dart';

enum CoachSegmentKind { warmup, main, recovery, cooldown }

enum CoachTrainingTypeHint {
  easyRun,
  longRun,
  interval,
  repetition,
  threshold,
}

sealed class CoachPaceSpec {
  const CoachPaceSpec();
}

class CoachPaceVdot extends CoachPaceSpec {
  const CoachPaceVdot();
}

class CoachPaceRange extends CoachPaceSpec {
  final int minSec;
  final int maxSec;
  const CoachPaceRange(this.minSec, this.maxSec);
}

class CoachPaceSingle extends CoachPaceSpec {
  final int secPerKm;
  const CoachPaceSingle(this.secPerKm);
}

class CoachRepTarget {
  final int? splitSec;
  final int? splitSecMin;
  final int? splitSecMax;
  final CoachPaceSpec? pace;

  const CoachRepTarget({
    this.splitSec,
    this.splitSecMin,
    this.splitSecMax,
    this.pace,
  });
}

class _RecoverySpec {
  final int? distanceM;
  final int? durationSec;
  final CoachPaceSpec? pace;

  const _RecoverySpec({this.distanceM, this.durationSec, this.pace});
}

typedef CoachParseResult = ({
  bool ok,
  bool isRest,
  Map<String, dynamic>? workoutDefinition,
  CoachTrainingTypeHint? trainingTypeHint,
  String? error,
  String programContent,
});

int? parsePaceSeconds(String raw) {
  final s = raw.trim().replaceAll(',', '.');
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final mm = int.parse(m.group(1)!);
  final ss = int.parse(m.group(2)!);
  if (ss < 0 || ss > 59) return null;
  return mm * 60 + ss;
}

String _normalizePaceRaw(String raw) {
  var t = raw.trim();
  if (t.startsWith('(') && t.endsWith(')')) {
    t = t.substring(1, t.length - 1).trim();
  }
  const timePat = r'\d{1,2}:\d{2}(?:\s*[\/\-]\s*\d{1,2}:\d{2})?';
  return t
      .replaceAllMapped(
        RegExp('($timePat)\\s*pace\\s*\$', caseSensitive: false),
        (m) => m.group(1)!,
      )
      .replaceAllMapped(
        RegExp('($timePat)pace\\s*\$', caseSensitive: false),
        (m) => m.group(1)!,
      )
      .replaceAll(RegExp(r'\s+pace\s*$', caseSensitive: false), '')
      .replaceAllMapped(
        RegExp('($timePat)\\s*p\\s*\$', caseSensitive: false),
        (m) => m.group(1)!,
      )
      .replaceAllMapped(
        RegExp('($timePat)p\\s*\$', caseSensitive: false),
        (m) => m.group(1)!,
      )
      .replaceAll(RegExp(r'^@\s*'), '');
}

CoachPaceSpec? parsePaceSpec(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  var t = _normalizePaceRaw(raw).toLowerCase();
  final npace = RegExp(r'^([1-9])pace$').firstMatch(t);
  if (npace != null) t = '${npace.group(1)}:00';
  if (t == 'vdot') return const CoachPaceVdot();
  final rangeMatch = RegExp(
    r'^(\d{1,2}:\d{2})\s*[\/\-]\s*(\d{1,2}:\d{2})$',
  ).firstMatch(t);
  if (rangeMatch != null) {
    final a = parsePaceSeconds(rangeMatch.group(1)!);
    final b = parsePaceSeconds(rangeMatch.group(2)!);
    if (a == null || b == null) return null;
    return CoachPaceRange(a < b ? a : b, a < b ? b : a);
  }
  final single = parsePaceSeconds(t);
  if (single != null) return CoachPaceSingle(single);
  return null;
}

int _parseDistanceMeters(double value, String unit) {
  final u = unit.toLowerCase();
  if (u == 'm') return value.round();
  return (value * 1000).round();
}

Map<String, dynamic> _paceToSegmentFields(CoachPaceSpec? pace) {
  if (pace == null) return {};
  if (pace is CoachPaceVdot) return {'use_vdot_for_pace': true};
  if (pace is CoachPaceSingle) {
    return {
      'pace_seconds_per_km_min': pace.secPerKm,
      'pace_seconds_per_km_max': pace.secPerKm,
    };
  }
  if (pace is CoachPaceRange) {
    return {
      'pace_seconds_per_km_min': pace.minSec,
      'pace_seconds_per_km_max': pace.maxSec,
    };
  }
  return {};
}

String _performanceTargetFromRepTarget(CoachRepTarget? target) {
  if (target == null) return 'none';
  final hasPace = target.pace != null;
  final hasSplit = target.splitSec != null ||
      target.splitSecMin != null ||
      target.splitSecMax != null;
  if (hasPace) return 'pace';
  if (hasSplit) return 'time';
  return 'none';
}

Map<String, dynamic> _repTargetToSegmentFields(
  CoachRepTarget? target, {
  int? distanceMeters,
}) {
  if (target == null) return {};
  final out = <String, dynamic>{};
  if (target.splitSec != null) out['duration_seconds'] = target.splitSec;
  if (target.splitSecMin != null) out['duration_seconds_min'] = target.splitSecMin;
  if (target.splitSecMax != null) out['duration_seconds_max'] = target.splitSecMax;
  out.addAll(_paceToSegmentFields(target.pace));
  if (target.pace == null && distanceMeters != null && distanceMeters > 0) {
    final km = distanceMeters / 1000;
    if (target.splitSecMin != null && target.splitSecMax != null) {
      final minPace = (target.splitSecMax! / km).round();
      final maxPace = (target.splitSecMin! / km).round();
      out['pace_seconds_per_km_min'] = minPace < maxPace ? minPace : maxPace;
      out['pace_seconds_per_km_max'] = minPace < maxPace ? maxPace : minPace;
    } else if (target.splitSec != null) {
      final derived = (target.splitSec! / km).round();
      out['pace_seconds_per_km_min'] = derived;
      out['pace_seconds_per_km_max'] = derived;
    }
  }
  return out;
}

bool _isLikelySplitPlusPace(int splitSec, int paceSecPerKm, int distM) {
  if (distM <= 0) return false;
  if (paceSecPerKm < 120 || paceSecPerKm > 480) return false;
  if (splitSec < 30 || splitSec > 1800) return false;
  final expected = (paceSecPerKm * distM / 1000).round();
  if ((splitSec - expected).abs() <= 20) return true;
  return splitSec <= 600 && paceSecPerKm >= 150;
}

bool _isLikelyPaceRange(int aSec, int bSec) {
  return aSec >= 150 && bSec >= 150 && aSec <= 600 && bSec <= 600;
}

bool _isLikelySplitForDistance(int splitSec, int distM) {
  if (distM <= 0) return false;
  final km = distM / 1000;
  final minSplit = (120 * km).round();
  final maxSplit = (480 * km).round();
  return splitSec >= minSplit && splitSec <= maxSplit;
}

CoachRepTarget _parseBareTimeTarget(int sec, int distM) {
  if (_isLikelySplitForDistance(sec, distM)) {
    return CoachRepTarget(splitSec: sec);
  }
  if (sec >= 150 && sec <= 600) {
    return CoachRepTarget(pace: CoachPaceSingle(sec));
  }
  return CoachRepTarget(splitSec: sec);
}

CoachRepTarget? parseRepTarget(String? parenRaw, int distM) {
  final raw = parenRaw?.trim();
  if (raw == null || raw.isEmpty) return null;
  return _parseBareTarget(raw, distM);
}

CoachRepTarget? _parseBareTarget(String raw, int distM) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (RegExp(r'^vdot$', caseSensitive: false).hasMatch(trimmed)) {
    return const CoachRepTarget(pace: CoachPaceVdot());
  }

  final comboP = RegExp(
    r'^(\d{1,2}:\d{2})\s*(?:dk)?\s*-\s*(\d{1,2}:\d{2})\s*p?\s*$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (comboP != null) {
    final split = parsePaceSeconds(comboP.group(1)!);
    final paceSec = parsePaceSeconds(comboP.group(2)!);
    if (split != null && paceSec != null && !_isLikelyPaceRange(split, paceSec)) {
      return CoachRepTarget(splitSec: split, pace: CoachPaceSingle(paceSec));
    }
  }

  final paceRangeP = RegExp(
    r'^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*p?\s*$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (paceRangeP != null) {
    final a = parsePaceSeconds(paceRangeP.group(1)!);
    final b = parsePaceSeconds(paceRangeP.group(2)!);
    if (a != null && b != null) {
      return CoachRepTarget(
        pace: CoachPaceRange(a < b ? a : b, a < b ? b : a),
      );
    }
  }

  final timeRangeDk = RegExp(
    r'^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*dk\s*$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (timeRangeDk != null) {
    final a = parsePaceSeconds(timeRangeDk.group(1)!);
    final b = parsePaceSeconds(timeRangeDk.group(2)!);
    if (a != null && b != null) {
      return CoachRepTarget(
        splitSecMin: a < b ? a : b,
        splitSecMax: a < b ? b : a,
      );
    }
  }

  if (trimmed.contains('/') && !RegExp(r'dk\s*$', caseSensitive: false).hasMatch(trimmed)) {
    final p = parsePaceSpec(trimmed);
    if (p != null) return CoachRepTarget(pace: p);
  }

  final hyphenPair = RegExp(
    r'^(\d{1,2}:\d{2})\s*(?:dk)?\s*-\s*(\d{1,2}:\d{2})\s*(?:dk|p)?\s*$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (hyphenPair != null) {
    final a = parsePaceSeconds(hyphenPair.group(1)!);
    final b = parsePaceSeconds(hyphenPair.group(2)!);
    if (a != null && b != null) {
      if (RegExp(r'dk\s*$', caseSensitive: false).hasMatch(trimmed)) {
        return CoachRepTarget(
          splitSecMin: a < b ? a : b,
          splitSecMax: a < b ? b : a,
        );
      }
      if (_isLikelySplitPlusPace(a, b, distM) || (distM >= 200 && distM <= 5000)) {
        return CoachRepTarget(splitSec: a, pace: CoachPaceSingle(b));
      }
      if (_isLikelyPaceRange(a, b)) {
        return CoachRepTarget(
          pace: CoachPaceRange(a < b ? a : b, a < b ? b : a),
        );
      }
    }
  }

  final splitSingle = RegExp(
    r'^(\d{1,2}:\d{2})(?:dk)?\s*$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (splitSingle != null) {
    final sec = parsePaceSeconds(splitSingle.group(1)!);
    if (sec != null) {
      if (RegExp(r'dk\s*$', caseSensitive: false).hasMatch(trimmed)) {
        return CoachRepTarget(splitSec: sec);
      }
      return _parseBareTimeTarget(sec, distM);
    }
  }

  if (trimmed.contains('-')) {
    final p = parsePaceSpec(trimmed);
    if (p != null) return CoachRepTarget(pace: p);
  }

  final cleaned = _normalizePaceRaw(trimmed);
  final single = parsePaceSeconds(cleaned);
  if (single != null) return _parseBareTimeTarget(single, distM);

  final paceOnly = parsePaceSpec(trimmed);
  if (paceOnly != null) return CoachRepTarget(pace: paceOnly);

  return null;
}

_RecoverySpec? _parseRecoveryClause(String raw) {
  var remaining = raw.trim();
  if (remaining.isEmpty) return null;

  int? distanceM;
  int? durationSec;
  CoachPaceSpec? pace;

  final distMatch = RegExp(
    r'^(\d+(?:\.\d+)?)\s*(m|k|km)?(?:\s+|$)',
    caseSensitive: false,
  ).firstMatch(remaining);
  if (distMatch != null) {
    final val = double.parse(distMatch.group(1)!);
    final unitRaw = distMatch.group(2)?.toLowerCase();
    final unit = unitRaw ?? 'm';
    distanceM = _parseDistanceMeters(
      val,
      unit == 'k' || unit == 'km' ? 'k' : unit,
    );
    remaining = remaining.substring(distMatch.group(0)!.length).trim();
  }

  final dkMatch = RegExp(
    '^(\\d+(?:\\.\\d+)?)\\s*${durationUnitPattern}(?:\\s+|\$)',
    caseSensitive: false,
  ).firstMatch(remaining);
  if (dkMatch != null) {
    durationSec = (double.parse(dkMatch.group(1)!) * 60).round();
    remaining = remaining.substring(dkMatch.group(0)!.length).trim();
  }

  if (remaining.isNotEmpty) {
    final timeOnly = RegExp(
      r'^(\d{1,2}):(\d{2})(?:\s+pace|\s+p|p)?\s*$',
      caseSensitive: false,
    ).firstMatch(remaining);
    if (timeOnly != null) {
      final sec = parsePaceSeconds('${timeOnly.group(1)}:${timeOnly.group(2)}');
      if (sec != null) {
        final mm = int.parse(timeOnly.group(1)!);
        final ss = int.parse(timeOnly.group(2)!);
        final looksLikePace =
            (ss == 0 && mm >= 2 && mm <= 8) ||
            (sec >= 150 && sec <= 480 && !(mm <= 2 && ss > 0));

        if (durationSec != null) {
          pace = CoachPaceSingle(sec);
        } else if (distanceM != null && looksLikePace) {
          pace = CoachPaceSingle(sec);
        } else if (distanceM != null && !looksLikePace) {
          durationSec = sec;
        } else if (looksLikePace) {
          pace = CoachPaceSingle(sec);
        } else {
          durationSec = sec;
        }
        remaining = '';
      }
    }
  }

  if (remaining.isNotEmpty) {
    pace = parsePaceSpec(remaining);
  }

  if (distanceM == null && durationSec == null && pace == null) return null;
  return _RecoverySpec(distanceM: distanceM, durationSec: durationSec, pace: pace);
}

({String work, _RecoverySpec? recovery}) _splitOnRecovery(String block) {
  final match = RegExp(r'\s+R(?:\s|\d)', caseSensitive: false).firstMatch(block);
  if (match == null) return (work: block, recovery: null);
  final idx = match.start;
  final work = block.substring(0, idx).trim();
  final recRaw = block.substring(idx).replaceFirst(RegExp(r'^\s+R\s*', caseSensitive: false), '');
  return (work: work, recovery: _parseRecoveryClause(recRaw));
}

bool _hasRecovery(_RecoverySpec? spec) {
  if (spec == null) return false;
  return (spec.distanceM != null && spec.distanceM! > 0) ||
      (spec.durationSec != null && spec.durationSec! > 0) ||
      spec.pace != null;
}

Map<String, dynamic> buildDurationSegment(
  CoachSegmentKind kind,
  int durationSeconds,
  CoachPaceSpec? pace,
) {
  final kindStr = switch (kind) {
    CoachSegmentKind.warmup => 'warmup',
    CoachSegmentKind.main => 'main',
    CoachSegmentKind.recovery => 'recovery',
    CoachSegmentKind.cooldown => 'cooldown',
  };
  return {
    'type': 'segment',
    'segment': {
      'segment_type': kindStr,
      'target_type': 'duration',
      'target': pace != null ? 'pace' : 'none',
      'duration_seconds': durationSeconds,
      ..._paceToSegmentFields(pace),
    },
  };
}

Map<String, dynamic> buildDistanceSegment(
  CoachSegmentKind kind,
  int distanceMeters,
  CoachRepTarget? target,
) {
  final kindStr = switch (kind) {
    CoachSegmentKind.warmup => 'warmup',
    CoachSegmentKind.main => 'main',
    CoachSegmentKind.recovery => 'recovery',
    CoachSegmentKind.cooldown => 'cooldown',
  };
  return {
    'type': 'segment',
    'segment': {
      'segment_type': kindStr,
      'target_type': 'distance',
      'target': _performanceTargetFromRepTarget(target),
      'distance_meters': distanceMeters,
      ..._repTargetToSegmentFields(target, distanceMeters: distanceMeters),
    },
  };
}

Map<String, dynamic> _buildRecoveryStep(_RecoverySpec spec) {
  final pace = spec.pace;
  if (spec.durationSec != null && spec.durationSec! > 0) {
    return buildDurationSegment(CoachSegmentKind.recovery, spec.durationSec!, pace);
  }
  if (spec.distanceM != null && spec.distanceM! > 0) {
    return buildDistanceSegment(
      CoachSegmentKind.recovery,
      spec.distanceM!,
      pace != null ? CoachRepTarget(pace: pace) : null,
    );
  }
  if (pace != null) {
    return buildDurationSegment(CoachSegmentKind.recovery, 0, pace);
  }
  return buildDurationSegment(CoachSegmentKind.recovery, 60, null);
}

sealed class _ParsedBlock {}

class _IntervalBlock extends _ParsedBlock {
  final int repeat;
  final int? distanceM;
  final int? durationMinutes;
  final CoachRepTarget? target;
  final _RecoverySpec? recovery;
  _IntervalBlock({
    required this.repeat,
    this.distanceM,
    this.durationMinutes,
    this.target,
    this.recovery,
  });
}

class _DurationBlock extends _ParsedBlock {
  final int minutes;
  final CoachPaceSpec? pace;
  _DurationBlock({required this.minutes, this.pace});
}

class _DistanceBlock extends _ParsedBlock {
  final int distanceM;
  final CoachRepTarget? target;
  _DistanceBlock({required this.distanceM, this.target});
}

String _normalizeBlock(String block) {
  return block.trim().replaceFirstMapped(
    RegExp(r'^(\d+(?:\.\d+)?)\s*(k|km|m)\s*/\s*', caseSensitive: false),
    (m) => '${m.group(1)}${m.group(2)} ',
  );
}

int _distanceMetersFromValue(double distVal, String? unitRaw) {
  if (unitRaw != null) {
    final unit = unitRaw.toLowerCase();
    return _parseDistanceMeters(
      distVal,
      unit == 'k' || unit == 'km' ? 'k' : unit,
    );
  }
  if (distVal >= 100) return distVal.round();
  return _parseDistanceMeters(distVal, 'k');
}

CoachRepTarget? _parseWorkTarget(
  String? targetRaw,
  String? parenRaw,
  String? bareTimeRaw,
  int distM,
) {
  if (parenRaw != null) return parseRepTarget(parenRaw, distM);
  if (targetRaw != null && targetRaw.trim().isNotEmpty) {
    return _parseBareTarget(targetRaw.trim(), distM);
  }
  if (bareTimeRaw != null) return _parseBareTarget(bareTimeRaw, distM);
  return null;
}

_IntervalBlock? _parseIntervalBlock(String block) {
  final normalized = _normalizeBlock(block);
  final split = _splitOnRecovery(normalized);
  final work = split.work;

  final m = RegExp(
    '^(\\d+)\\s*x\\s*(\\d+(?:\\.\\d+)?)\\s*(${durationUnitPattern}|m|k|km)?(?:\\s*(?:\\(([^)]+)\\)|(\\d{1,2}:\\d{2})p?))?(?:\\s+(.+))?\$',
    caseSensitive: false,
  ).firstMatch(work);
  if (m == null) return null;

  final repeat = int.parse(m.group(1)!);
  final value = double.parse(m.group(2)!);
  final unit = m.group(3)?.toLowerCase();
  int? distanceM;
  int? durationMinutes;
  if (isDurationUnit(unit)) {
    durationMinutes = value.round();
  } else {
    distanceM = _distanceMetersFromValue(value, unit);
  }
  final target = _parseWorkTarget(m.group(6), m.group(4), m.group(5), distanceM ?? 0);

  return _IntervalBlock(
    repeat: repeat,
    distanceM: distanceM,
    durationMinutes: durationMinutes,
    target: target,
    recovery: split.recovery,
  );
}

_IntervalBlock? _parseStandaloneRepBlock(String block) {
  final normalized = _normalizeBlock(block);
  if (RegExp(r'^\d+\s*x\s*', caseSensitive: false).hasMatch(normalized)) {
    return null;
  }

  final split = _splitOnRecovery(normalized);
  final work = split.work;

  final parenMatch = RegExp(
    r'^(\d+(?:\.\d+)?)\s*(m|k|km)?\s*\(([^)]+)\)$',
    caseSensitive: false,
  ).firstMatch(work);
  if (parenMatch == null) return null;

  final distM = _distanceMetersFromValue(
    double.parse(parenMatch.group(1)!),
    parenMatch.group(2),
  );
  final target = parseRepTarget(parenMatch.group(3), distM);

  return _IntervalBlock(
    repeat: 1,
    distanceM: distM,
    durationMinutes: null,
    target: target,
    recovery: split.recovery,
  );
}

_IntervalBlock? _parseDistanceRepBlock(String block) {
  final normalized = _normalizeBlock(block);
  if (RegExp(r'^\d+\s*x\s*', caseSensitive: false).hasMatch(normalized)) {
    return null;
  }

  final split = _splitOnRecovery(normalized);
  if (!_hasRecovery(split.recovery)) return null;

  final m = RegExp(
    r'^(\d+(?:\.\d+)?)\s*(m|k|km)(?:\s+(.+))?$',
    caseSensitive: false,
  ).firstMatch(split.work);
  if (m == null) return null;

  final distM = _parseDistanceMeters(double.parse(m.group(1)!), m.group(2)!);
  final targetRaw = m.group(3)?.trim();
  final target = targetRaw != null ? _parseBareTarget(targetRaw, distM) : null;

  return _IntervalBlock(
    repeat: 1,
    distanceM: distM,
    durationMinutes: null,
    target: target,
    recovery: split.recovery,
  );
}

_DurationBlock? _parseDurationBlock(String block) {
  final m = RegExp(
    '^(\\d+(?:\\.\\d+)?)\\s*${durationUnitPattern}(?:\\s+(.+))?\$',
    caseSensitive: false,
  ).firstMatch(block.trim());
  if (m == null) return null;
  final minutes = double.parse(m.group(1)!).round();
  final paceRaw = m.group(2)?.trim();
  return _DurationBlock(
    minutes: minutes,
    pace: paceRaw != null ? parsePaceSpec(paceRaw) : null,
  );
}

_DistanceBlock? _parseDistanceBlock(String block) {
  final normalized = _normalizeBlock(block);
  if (RegExp(r'\s+R(?:\s|\d)', caseSensitive: false).hasMatch(normalized)) {
    return null;
  }

  final m = RegExp(
    r'^(\d+(?:\.\d+)?)\s*(k|km|m)(?:\s+(.+))?$',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (m == null) return null;
  final distM = _parseDistanceMeters(double.parse(m.group(1)!), m.group(2)!);
  final tail = m.group(3)?.trim();
  final target = tail != null ? _parseBareTarget(tail, distM) : null;
  return _DistanceBlock(distanceM: distM, target: target);
}

List<String> _splitChainLine(String normalized, {bool isLongRun = false}) {
  final longRunHeader = RegExp(r'^\d+(?:\.\d+)?\s*k\s*:\s*', caseSensitive: false);
  var line = normalized.trim();
  final lineIsLongRun = isLongRun || longRunHeader.hasMatch(line);
  line = line.replaceFirst(longRunHeader, '');

  final plusParts = line
      .split(RegExp(r'\s*\+\s*'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (plusParts.length > 1) return plusParts;

  if (lineIsLongRun && line.contains('/')) {
    final slashParts = line
        .split(RegExp(r'\s*/\s*'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (slashParts.length > 1) return slashParts;
  }

  line = plusParts.isNotEmpty ? plusParts.first : line;

  if (!RegExp(r'\d\s*dk', caseSensitive: false).hasMatch(line)) {
    final re = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:km|m|k)(?:\s+\d{1,2}:\d{2}(?:[\/\-]\d{1,2}:\d{2})?)?',
      caseSensitive: false,
    );
    final matches = re.allMatches(line).map((m) => m.group(0)!.trim()).toList();
    if (matches.length > 1 && !RegExp(r'\dx\d', caseSensitive: false).hasMatch(line)) {
      return matches;
    }
  }
  return [line];
}

List<String> _splitChain(String text) {
  final trimmed = text.trim();
  final lines = trimmed
      .split(RegExp(r'\r?\n+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  if (lines.length > 1) {
    return lines.expand((line) => _splitChainLine(line)).toList();
  }

  final longRunHeader = RegExp(r'^\d+(?:\.\d+)?\s*k\s*:\s*', caseSensitive: false);
  return _splitChainLine(trimmed, isLongRun: longRunHeader.hasMatch(trimmed));
}

List<Map<String, dynamic>> _blockToSteps(
  _ParsedBlock block,
  CoachSegmentKind kind,
) {
  if (block is _DurationBlock) {
    return [buildDurationSegment(kind, block.minutes * 60, block.pace)];
  }
  if (block is _DistanceBlock) {
    return [buildDistanceSegment(kind, block.distanceM, block.target)];
  }
  final b = block as _IntervalBlock;
  final main = b.distanceM != null
      ? buildDistanceSegment(CoachSegmentKind.main, b.distanceM!, b.target)
      : buildDurationSegment(
          CoachSegmentKind.main,
          (b.durationMinutes ?? 0) * 60,
          b.target?.pace,
        );
  final inner = <Map<String, dynamic>>[main];
  if (_hasRecovery(b.recovery)) {
    inner.add(_buildRecoveryStep(b.recovery!));
  }
  if (inner.length == 1 && b.repeat > 1) {
    return [
      {'type': 'repeat', 'repeat_count': b.repeat, 'steps': [main]},
    ];
  }
  return [
    {'type': 'repeat', 'repeat_count': b.repeat, 'steps': inner},
  ];
}

({CoachSegmentKind? kind, String body}) _splitExplicitSegmentLabel(String part) {
  final trimmed = part.trim();
  const warmupLabel = r'(ısınma|isinma|warmup|warm-up|warm\s+up|warm\s+ısınma|warm|wu)';
  const cooldownLabel = r'(soğuma|soguma|cooldown|cool-down|cool\s+down|cool|cd)';

  final prefixPatterns = <(CoachSegmentKind, RegExp)>[
    (
      CoachSegmentKind.warmup,
      RegExp('^$warmupLabel\\s*[:\\-]?\\s*(.+)\$', caseSensitive: false, unicode: true),
    ),
    (
      CoachSegmentKind.cooldown,
      RegExp('^$cooldownLabel\\s*[:\\-]?\\s*(.+)\$', caseSensitive: false, unicode: true),
    ),
  ];
  for (final (kind, pattern) in prefixPatterns) {
    final match = pattern.firstMatch(trimmed);
    if (match != null) {
      return (kind: kind, body: match.group(2)!.trim());
    }
  }

  final suffixPatterns = <(CoachSegmentKind, RegExp)>[
    (
      CoachSegmentKind.warmup,
      RegExp('^(.+?)\\s+$warmupLabel\\s*\$', caseSensitive: false, unicode: true),
    ),
    (
      CoachSegmentKind.cooldown,
      RegExp('^(.+?)\\s+$cooldownLabel\\s*\$', caseSensitive: false, unicode: true),
    ),
  ];
  for (final (kind, pattern) in suffixPatterns) {
    final match = pattern.firstMatch(trimmed);
    if (match != null) {
      return (kind: kind, body: match.group(1)!.trim());
    }
  }

  return (kind: null, body: trimmed);
}

CoachSegmentKind _resolveSegmentKind(
  _ParsedBlock block,
  CoachSegmentKind? explicitKind,
) {
  if (block is _IntervalBlock) return CoachSegmentKind.main;
  return explicitKind ?? CoachSegmentKind.main;
}

bool _hasRepeat(List<Map<String, dynamic>> steps) {
  for (final s in steps) {
    if (s['type'] == 'repeat') return true;
  }
  return false;
}

int _totalDistanceMeters(List<Map<String, dynamic>> steps) {
  var total = 0;
  void walk(List<Map<String, dynamic>> arr, [int repeat = 1]) {
    for (final s in arr) {
      if (s['type'] == 'repeat') {
        final rc = (s['repeat_count'] as num?)?.toInt() ?? 1;
        walk(List<Map<String, dynamic>>.from(s['steps'] as List), repeat * rc);
      } else if (s['type'] == 'segment') {
        final seg = s['segment'] as Map<String, dynamic>;
        final dm = (seg['distance_meters'] as num?)?.toInt() ?? 0;
        if (dm > 0) total += dm * repeat;
      }
    }
  }

  walk(steps);
  return total;
}

CoachTrainingTypeHint _inferTrainingType(
  List<Map<String, dynamic>> steps,
  String raw,
) {
  final lower = raw.toLowerCase();
  if (_hasRepeat(steps)) {
    for (final s in steps) {
      if (s['type'] != 'repeat') continue;
      final inner = s['steps'] as List;
      if (inner.isEmpty) continue;
      final main = (inner.first as Map)['segment'] as Map<String, dynamic>?;
      final d = (main?['distance_meters'] as num?)?.toInt() ?? 0;
      if (d > 0 && d <= 600) return CoachTrainingTypeHint.repetition;
    }
    return CoachTrainingTypeHint.interval;
  }
  if (RegExp(r'^\d+\s*k\s*:', caseSensitive: false).hasMatch(raw) ||
      _totalDistanceMeters(steps) >= 15000) {
    return CoachTrainingTypeHint.longRun;
  }
  if (lower.contains('threshold') || lower.contains('eşik')) {
    return CoachTrainingTypeHint.threshold;
  }
  return CoachTrainingTypeHint.easyRun;
}

String trainingTypeHintToName(CoachTrainingTypeHint hint) {
  return switch (hint) {
    CoachTrainingTypeHint.easyRun => 'easy_run',
    CoachTrainingTypeHint.longRun => 'long_run',
    CoachTrainingTypeHint.interval => 'interval',
    CoachTrainingTypeHint.repetition => 'repetition',
    CoachTrainingTypeHint.threshold => 'threshold',
  };
}

CoachParseResult parseCoachText(String rawInput) {
  final programContent = rawInput.trim();
  if (programContent.isEmpty) {
    return (
      ok: true,
      isRest: true,
      workoutDefinition: null,
      trainingTypeHint: null,
      error: null,
      programContent: '',
    );
  }
  final lower = programContent.toLowerCase();
  if (lower == 'rest' || lower == 'dinlenme') {
    return (
      ok: true,
      isRest: true,
      workoutDefinition: null,
      trainingTypeHint: null,
      error: null,
      programContent: programContent,
    );
  }

  final normalized = normalizeCoachInput(programContent);
  final chainParts = _splitChain(normalized);
  final allSteps = <Map<String, dynamic>>[];

  for (var i = 0; i < chainParts.length; i++) {
    final labeled = _splitExplicitSegmentLabel(chainParts[i]);
    final part = labeled.body;
    _ParsedBlock? block = _parseIntervalBlock(part);
    block ??= _parseStandaloneRepBlock(part);
    block ??= _parseDistanceRepBlock(part);
    block ??= _parseDurationBlock(part);
    block ??= _parseDistanceBlock(part);
    if (block == null) {
      return (
        ok: false,
        isRest: false,
        workoutDefinition: null,
        trainingTypeHint: null,
        error: 'Anlaşılamayan ifade: "$part"',
        programContent: programContent,
      );
    }
    if (block is _IntervalBlock) {
      if (block.repeat > 1 && !_hasRecovery(block.recovery)) {
        return (
          ok: false,
          isRest: false,
          workoutDefinition: null,
          trainingTypeHint: null,
          error: '${block.repeat}x tekrar için toparlanma (R) belirtilmeli',
          programContent: programContent,
        );
      }
      allSteps.addAll(_blockToSteps(block, CoachSegmentKind.main));
      continue;
    }
    final kind = _resolveSegmentKind(block, labeled.kind);
    allSteps.addAll(_blockToSteps(block, kind));
  }

  if (allSteps.isEmpty) {
    return (
      ok: false,
      isRest: false,
      workoutDefinition: null,
      trainingTypeHint: null,
      error: 'Antrenman adımı bulunamadı',
      programContent: programContent,
    );
  }

  final hint = _inferTrainingType(allSteps, programContent);
  return (
    ok: true,
    isRest: false,
    workoutDefinition: {'steps': allSteps},
    trainingTypeHint: hint,
    error: null,
    programContent: programContent,
  );
}
