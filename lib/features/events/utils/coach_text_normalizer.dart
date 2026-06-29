// Koç metnini parse öncesi kanonik forma getirir.
// TS: tools/program-admin/src/lib/coach_text_normalizer.ts

const kDurationUnitPattern = r'(?:dk|dakika|dak|min(?:ute)?s?)';

String get durationUnitPattern => kDurationUnitPattern;

bool isDurationUnit(String? unit) {
  if (unit == null) return false;
  final u = unit.toLowerCase();
  return u == 'dk' || u == 'dakika' || u == 'dak' || u.startsWith('min');
}

String _expandNpaceShorthand(String text) {
  return text
      .replaceAllMapped(
        RegExp(r'\b([1-9])\s+pace\b', caseSensitive: false),
        (m) => '${m.group(1)}:00',
      )
      .replaceAllMapped(
        RegExp(r'\b([1-9])pace\b', caseSensitive: false),
        (m) => '${m.group(1)}:00',
      )
      .replaceAllMapped(
        RegExp(r'\b([1-9])\s+p\b', caseSensitive: false),
        (m) => '${m.group(1)}:00',
      )
      .replaceAllMapped(
        RegExp(r'\b([1-9])p\b', caseSensitive: false),
        (m) => '${m.group(1)}:00',
      );
}

String _normalizeDecimals(String text) {
  return text.replaceAllMapped(
    RegExp(r'(\d),(\d)'),
    (m) => '${m.group(1)}.${m.group(2)}',
  );
}

String _normalizeHourUnits(String text) {
  var t = text;

  t = t.replaceAllMapped(
    RegExp(
      r'(\d+(?:\.\d+)?)(?:\s*)?(?:h|hr|hours?|sa|saat)(?:\s*)?(\d+(?:\.\d+)?)(?:\s*)?(?:dk|dakika|min(?:ute)?s?)\b',
      caseSensitive: false,
    ),
    (m) => '${(double.parse(m.group(1)!) * 60 + double.parse(m.group(2)!)).round()}dk',
  );

  t = t.replaceAllMapped(
    RegExp(r'\b(\d+):(\d{2}):(\d{2})\b'),
    (m) => '${int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)}dk',
  );

  t = t.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)(?:\s*)?(?:h|hr|hours?|sa(?:at)?)\b', caseSensitive: false),
    (m) => '${(double.parse(m.group(1)!) * 60).round()}dk',
  );

  t = t.replaceAllMapped(
    RegExp(r"\b(\d+)[''](?:\s*dk)?\b"),
    (m) => '${m.group(1)}dk',
  );

  return t;
}

String _normalizeWordUnits(String text) {
  var t = text;

  t = t.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)(?:\s*)?(?:dakika|minutes?|mins?)\b', caseSensitive: false),
    (m) => '${m.group(1)}dk',
  );
  t = t.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)(?:\s*)?dak\b', caseSensitive: false),
    (m) => '${m.group(1)}dk',
  );
  t = t.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)\s*dk\b', caseSensitive: false),
    (m) => '${m.group(1)}dk',
  );

  t = t.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)(?:\s*)?(?:metres?|meters?)\b', caseSensitive: false),
    (m) => '${m.group(1)}m',
  );
  t = t.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)(?:\s*)?(?:kilometres?|kilometers?)\b', caseSensitive: false),
    (m) => '${m.group(1)}km',
  );
  t = t.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)\s*km\b', caseSensitive: false),
    (m) => '${m.group(1)}km',
  );
  t = t.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)\s*k\b(?![m\/a-z])', caseSensitive: false),
    (m) => '${m.group(1)}k',
  );
  t = t.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)\s*m\b(?![a-z])', caseSensitive: false),
    (m) => '${m.group(1)}m',
  );

  return t;
}

String _normalizePaceSuffixes(String text) {
  var t = text;
  const timePat = r'\d{1,2}:\d{2}(?:\s*[\/\-]\s*\d{1,2}:\d{2})?';

  t = t.replaceAllMapped(
    RegExp(r'(\d{1,2}:\d{2})\s*/\s*km\b', caseSensitive: false),
    (m) => m.group(1)!,
  );
  t = t.replaceAllMapped(RegExp(r'@\s*(\d{1,2}:\d{2})'), (m) => m.group(1)!);
  t = t.replaceAllMapped(
    RegExp(r'\btempo\s+(\d{1,2}:\d{2}(?:\s*[\/\-]\s*\d{1,2}:\d{2})?)', caseSensitive: false),
    (m) => m.group(1)!,
  );

  t = t.replaceAllMapped(
    RegExp('($timePat)\\s*pace\\b', caseSensitive: false),
    (m) => m.group(1)!,
  );
  t = t.replaceAllMapped(
    RegExp('($timePat)pace\\b', caseSensitive: false),
    (m) => m.group(1)!,
  );
  t = t.replaceAllMapped(
    RegExp('($timePat)\\s*p\\b', caseSensitive: false),
    (m) => m.group(1)!,
  );
  t = t.replaceAllMapped(
    RegExp('($timePat)p\\b', caseSensitive: false),
    (m) => m.group(1)!,
  );

  t = t.replaceAll(RegExp(r'\s+pace\b', caseSensitive: false), '');
  return t;
}

String _insertBoundarySpaces(String text) {
  var t = text;

  t = t.replaceAllMapped(
    RegExp(r'(dk|km|m|k)(\d{1,2}:\d{2})', caseSensitive: false),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
  t = t.replaceAllMapped(
    RegExp(r'(dk|km|m|k)(vdot)\b', caseSensitive: false),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
  t = t.replaceAllMapped(
    RegExp(r'(dk|km|m|k|\d{1,2}:\d{2})(R)\b', caseSensitive: false),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
  t = t.replaceAllMapped(
    RegExp(r'(\d{1,2}:\d{2})(vdot)\b', caseSensitive: false),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
  t = t.replaceAllMapped(
    RegExp(r'\bR(\d)', caseSensitive: false),
    (m) => 'R ${m.group(1)}',
  );

  return t;
}

String _normalizeRepeatSyntax(String text) {
  var t = text;
  t = t.replaceAllMapped(
    RegExp(r'\b(\d+)\s*(?:tekrar|rep|reps)\s+', caseSensitive: false),
    (m) => '${m.group(1)}x',
  );
  t = t.replaceAllMapped(RegExp(r'\b(\d+)\s*[*×]\s*'), (m) => '${m.group(1)}x');
  t = t.replaceAllMapped(RegExp(r'\b(\d+)\s+x\s+', caseSensitive: false), (m) => '${m.group(1)}x');
  t = t.replaceAllMapped(
    RegExp(r'\b(\d+)\s+x\s*(\d)', caseSensitive: false),
    (m) => '${m.group(1)}x${m.group(2)}',
  );
  return t;
}

String _normalizeRecoveryLabels(String text) {
  return text.replaceAll(
    RegExp(r'\b(?:toparlanma|recovery|rec|float)\b', caseSensitive: false),
    'R',
  );
}

String _tightenSpacing(String text) {
  return text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}

String normalizeCoachInput(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return t;

  t = _normalizeDecimals(t);
  t = _expandNpaceShorthand(t);
  t = _normalizeHourUnits(t);
  t = _normalizeWordUnits(t);
  t = _insertBoundarySpaces(t);
  t = _normalizeRepeatSyntax(t);
  t = _normalizeRecoveryLabels(t);
  t = _normalizePaceSuffixes(t);
  t = _tightenSpacing(t);

  return t;
}
