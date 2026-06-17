// Koç kısa notasyonu → workout_definition JSON (önizleme için).
// Sunucu tarafı: supabase/functions/weekly-program-upsert/coach_text_parser.ts

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

/// Parantez içi tekrar hedefi: süre (split), tempo veya ikisi birden
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

class CoachParseRest {
  final String programContent;
  const CoachParseRest(this.programContent);
}

class CoachParseSuccess {
  final Map<String, dynamic> workoutDefinition;
  final CoachTrainingTypeHint trainingTypeHint;
  final String programContent;
  const CoachParseSuccess({
    required this.workoutDefinition,
    required this.trainingTypeHint,
    required this.programContent,
  });
}

class CoachParseFailure {
  final String error;
  final String programContent;
  const CoachParseFailure({required this.error, required this.programContent});
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
  return t.replaceAll(RegExp(r'\s*p\s*$', caseSensitive: false), '');
}

CoachPaceSpec? parsePaceSpec(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final t = _normalizePaceRaw(raw).toLowerCase();
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
  if (RegExp(r'vdot', caseSensitive: false).hasMatch(raw)) {
    return const CoachRepTarget(pace: CoachPaceVdot());
  }

  // Süre + tempo: 1:51-4:38p
  final comboP = RegExp(
    r'^(\d{1,2}:\d{2})\s*(?:dk)?\s*-\s*(\d{1,2}:\d{2})\s*p\s*$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (comboP != null) {
    final split = parsePaceSeconds(comboP.group(1)!);
    final paceSec = parsePaceSeconds(comboP.group(2)!);
    if (split != null && paceSec != null && !_isLikelyPaceRange(split, paceSec)) {
      return CoachRepTarget(splitSec: split, pace: CoachPaceSingle(paceSec));
    }
  }

  // Tempo aralığı: 4:30-4:38p
  final paceRangeP = RegExp(
    r'^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*p\s*$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (paceRangeP != null) {
    final a = parsePaceSeconds(paceRangeP.group(1)!);
    final b = parsePaceSeconds(paceRangeP.group(2)!);
    if (a != null && b != null) {
      return CoachRepTarget(
        pace: CoachPaceRange(a < b ? a : b, a < b ? b : a),
      );
    }
  }

  // Süre aralığı: 1:50-1:55dk
  final timeRangeDk = RegExp(
    r'^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*dk\s*$',
    caseSensitive: false,
  ).firstMatch(raw);
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

  // Tek tempo: 4:38p
  final paceSingleP = RegExp(
    r'^(\d{1,2}:\d{2})\s*p\s*$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (paceSingleP != null) {
    final pace = parsePaceSpec(paceSingleP.group(1)!);
    if (pace != null) return CoachRepTarget(pace: pace);
  }

  // Tempo aralığı slash: 5:10/5:00
  if (raw.contains('/') && !RegExp(r'dk\s*$', caseSensitive: false).hasMatch(raw)) {
    final pace = parsePaceSpec(raw.replaceAll(RegExp(r'\s*p\s*$', caseSensitive: false), ''));
    if (pace != null) return CoachRepTarget(pace: pace);
  }

  // Tire ile iki değer: 1:51-4:38 (p yok)
  final hyphenPair = RegExp(
    r'^(\d{1,2}:\d{2})\s*(?:dk)?\s*-\s*(\d{1,2}:\d{2})\s*(?:dk|p)?\s*$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (hyphenPair != null) {
    final a = parsePaceSeconds(hyphenPair.group(1)!);
    final b = parsePaceSeconds(hyphenPair.group(2)!);
    if (a != null && b != null) {
      if (RegExp(r'dk\s*$', caseSensitive: false).hasMatch(raw)) {
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

  // Tek süre/split: 1:51 veya 1:51dk
  final splitSingle = RegExp(
    r'^(\d{1,2}:\d{2})(?:dk)?\s*$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (splitSingle != null) {
    final sec = parsePaceSeconds(splitSingle.group(1)!);
    if (sec != null) {
      if (RegExp(r'dk\s*$', caseSensitive: false).hasMatch(raw)) {
        return CoachRepTarget(splitSec: sec);
      }
      return _parseBareTimeTarget(sec, distM);
    }
  }

  // Geriye kalan tempo ifadesi
  if (raw.contains('-')) {
    final pace = parsePaceSpec(raw.replaceAll(RegExp(r'\s*p\s*$', caseSensitive: false), ''));
    if (pace != null) return CoachRepTarget(pace: pace);
  }

  final cleaned = _normalizePaceRaw(raw);
  final single = parsePaceSeconds(cleaned);
  if (single != null) {
    return _parseBareTimeTarget(single, distM);
  }

  return null;
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
      'target': 'pace',
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

sealed class _ParsedBlock {}

class _IntervalBlock extends _ParsedBlock {
  final int repeat;
  final int? distanceM;
  final int? durationMinutes;
  final CoachRepTarget? target;
  final int? recoveryM;
  final int? recoverySec;
  _IntervalBlock({
    required this.repeat,
    this.distanceM,
    this.durationMinutes,
    this.target,
    this.recoveryM,
    this.recoverySec,
  });
}

class _DurationBlock extends _ParsedBlock {
  final int minutes;
  final CoachPaceSpec? pace;
  _DurationBlock({required this.minutes, this.pace});
}

class _DistanceBlock extends _ParsedBlock {
  final int distanceM;
  final CoachRepTarget? pace;
  _DistanceBlock({required this.distanceM, this.pace});
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
  // Birim yoksa 100+ sayılar metre (1200, 800), küçükler km (5k gibi)
  if (distVal >= 100) return distVal.round();
  return _parseDistanceMeters(distVal, 'k');
}

_IntervalBlock? _parseIntervalBlock(String block) {
  final normalized = _normalizeBlock(block);
  final m = RegExp(
    r'^(\d+)\s*x\s*(\d+(?:\.\d+)?)\s*(dk|m|k|km)?(?:\s*(?:\(([^)]+)\)|(\d{1,2}:\d{2})p?))?(?:\s+R\s*(\d+(?:\.\d+)?)\s*(m|k|km)?)?(?:\s+(\d{1,2}:\d{2}))?',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (m == null) return null;

  final repeat = int.parse(m.group(1)!);
  final value = double.parse(m.group(2)!);
  final unit = m.group(3)?.toLowerCase();
  int? distanceM;
  int? durationMinutes;
  if (unit == 'dk') {
    durationMinutes = value.round();
  } else {
    distanceM = _distanceMetersFromValue(value, unit);
  }
  final target = parseRepTarget(m.group(4) ?? m.group(5), distanceM ?? 0);

  int? recoveryM;
  int? recoverySec;
  if (m.group(6) != null) {
    final rv = double.parse(m.group(6)!);
    final ru = (m.group(7) ?? 'm').toLowerCase();
    recoveryM = _parseDistanceMeters(
      rv,
      ru == 'k' || ru == 'km' ? 'k' : ru,
    );
  }
  if (m.group(8) != null) {
    recoverySec = parsePaceSeconds(m.group(8)!);
  }

  return _IntervalBlock(
    repeat: repeat,
    distanceM: distanceM,
    durationMinutes: durationMinutes,
    target: target,
    recoveryM: recoveryM,
    recoverySec: recoverySec,
  );
}

/// Tek tekrar: `1200 (2:08-5:20p) R400` veya `800(1:56-4:51p) R400`
_IntervalBlock? _parseStandaloneRepBlock(String block) {
  final normalized = _normalizeBlock(block);
  if (RegExp(r'^\d+\s*x\s*', caseSensitive: false).hasMatch(normalized)) {
    return null;
  }
  final m = RegExp(
    r'^(\d+(?:\.\d+)?)\s*(m|k|km)?\s*\(([^)]+)\)(?:\s+R\s*(\d+(?:\.\d+)?)\s*(m|k|km)?)?(?:\s+(\d{1,2}:\d{2}))?',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (m == null) return null;

  final distVal = double.parse(m.group(1)!);
  final distM = _distanceMetersFromValue(distVal, m.group(2));
  final target = parseRepTarget(m.group(3), distM);

  int? recoveryM;
  int? recoverySec;
  if (m.group(4) != null) {
    final rv = double.parse(m.group(4)!);
    final ru = (m.group(5) ?? 'm').toLowerCase();
    recoveryM = _parseDistanceMeters(
      rv,
      ru == 'k' || ru == 'km' ? 'k' : ru,
    );
  }
  if (m.group(6) != null) {
    recoverySec = parsePaceSeconds(m.group(6)!);
  }

  return _IntervalBlock(
    repeat: 1,
    distanceM: distM,
    durationMinutes: null,
    target: target,
    recoveryM: recoveryM,
    recoverySec: recoverySec,
  );
}

_DurationBlock? _parseDurationBlock(String block) {
  final m = RegExp(
    r'^(\d+)\s*dk(?:\s+(.+))?$',
    caseSensitive: false,
  ).firstMatch(block.trim());
  if (m == null) return null;
  final minutes = int.parse(m.group(1)!);
  final paceRaw = m.group(2)?.trim();
  return _DurationBlock(
    minutes: minutes,
    pace: paceRaw != null ? parsePaceSpec(paceRaw) : null,
  );
}

_DistanceBlock? _parseDistanceBlock(String block) {
  final normalized = _normalizeBlock(block);
  final m = RegExp(
    r'^(\d+(?:\.\d+)?)\s*(k|km|m)(?:\s+(.+))?$',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (m == null) return null;
  final distM = _parseDistanceMeters(double.parse(m.group(1)!), m.group(2)!);
  final paceRaw = m.group(3)?.trim();
  return _DistanceBlock(
    distanceM: distM,
    pace: paceRaw != null ? CoachRepTarget(pace: parsePaceSpec(paceRaw)) : null,
  );
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
    return [buildDistanceSegment(kind, block.distanceM, block.pace)];
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
  if (b.recoveryM != null && b.recoveryM! > 0) {
    inner.add(
      b.recoverySec != null
          ? buildDurationSegment(CoachSegmentKind.recovery, b.recoverySec!, null)
          : buildDistanceSegment(CoachSegmentKind.recovery, b.recoveryM!, null),
    );
  } else if (b.recoverySec != null && b.recoverySec! > 0) {
    inner.add(buildDurationSegment(CoachSegmentKind.recovery, b.recoverySec!, null));
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
  const warmupLabel = r'(ısınma|isinma|warmup|warm-up|warm\s+up)';
  const cooldownLabel = r'(soğuma|soguma|cooldown|cool-down|cool\s+down)';

  final prefixPatterns = <(CoachSegmentKind, RegExp)>[
    (
      CoachSegmentKind.warmup,
      RegExp(
        '^$warmupLabel\\s*[:\\-]?\\s*(.+)\$',
        caseSensitive: false,
        unicode: true,
      ),
    ),
    (
      CoachSegmentKind.cooldown,
      RegExp(
        '^$cooldownLabel\\s*[:\\-]?\\s*(.+)\$',
        caseSensitive: false,
        unicode: true,
      ),
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
      RegExp(
        '^(.+?)\\s+$warmupLabel\\s*\$',
        caseSensitive: false,
        unicode: true,
      ),
    ),
    (
      CoachSegmentKind.cooldown,
      RegExp(
        '^(.+?)\\s+$cooldownLabel\\s*\$',
        caseSensitive: false,
        unicode: true,
      ),
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
    return (ok: true, isRest: true, workoutDefinition: null, trainingTypeHint: null, error: null, programContent: '');
  }
  final lower = programContent.toLowerCase();
  if (lower == 'rest' || lower == 'dinlenme') {
    return (ok: true, isRest: true, workoutDefinition: null, trainingTypeHint: null, error: null, programContent: programContent);
  }

  final chainParts = _splitChain(programContent);
  final allSteps = <Map<String, dynamic>>[];

  for (var i = 0; i < chainParts.length; i++) {
    final labeled = _splitExplicitSegmentLabel(chainParts[i]);
    final part = labeled.body;
    _ParsedBlock? block = _parseIntervalBlock(part);
    block ??= _parseStandaloneRepBlock(part);
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
      if (block.repeat > 1 && block.recoveryM == null && block.recoverySec == null) {
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
