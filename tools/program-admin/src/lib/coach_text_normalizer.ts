/**
 * Koç metnini parse öncesi kanonik forma getirir.
 * Dart: lib/features/events/utils/coach_text_normalizer.dart
 *
 * Tüm birimler bitişik veya boşluklu yazılabilir.
 */

/** Tek haneli pace kısaltması: 3pace, 3 pace, 3 p → 3:00 */
function expandNpaceShorthand(text: string): string {
  return text
    .replace(/\b([1-9])\s+pace\b/gi, "$1:00")
    .replace(/\b([1-9])pace\b/gi, "$1:00")
    .replace(/\b([1-9])\s+p\b/gi, "$1:00")
    .replace(/\b([1-9])p\b/gi, "$1:00");
}

function normalizeDecimals(text: string): string {
  return text.replace(/(\d),(\d)/g, "$1.$2");
}

/** Saat / birleşik saat+dakika */
function normalizeHourUnits(text: string): string {
  let t = text;

  t = t.replace(
    /(\d+(?:\.\d+)?)(?:\s*)?(?:h|hr|hours?|sa|saat)(?:\s*)?(\d+(?:\.\d+)?)(?:\s*)?(?:dk|dakika|min(?:ute)?s?)\b/gi,
    (_m, h, m) => `${Number(h) * 60 + Number(m)}dk`,
  );

  t = t.replace(/\b(\d+):(\d{2}):(\d{2})\b/g, (_m, h, m) => {
    return `${Number(h) * 60 + Number(m)}dk`;
  });

  t = t.replace(
    /(\d+(?:\.\d+)?)(?:\s*)?(?:h|hr|hours?|sa(?:at)?)\b/gi,
    (_m, n) => `${Math.round(Number(n) * 60)}dk`,
  );

  t = t.replace(/\b(\d+)[''](?:\s*dk)?\b/g, (_m, n) => `${n}dk`);

  return t;
}

/**
 * Sayı + birim (boşluklu veya bitişik) → kanonik kısa form.
 * Başta \b yok — 6x5 dakika gibi ifadeler de yakalanır.
 */
function normalizeWordUnits(text: string): string {
  let t = text;

  t = t.replace(
    /(\d+(?:\.\d+)?)(?:\s*)?(?:dakika|minutes?|mins?)\b/gi,
    "$1dk",
  );
  t = t.replace(/(\d+(?:\.\d+)?)(?:\s*)?dak\b/gi, "$1dk");
  t = t.replace(/(\d+(?:\.\d+)?)\s*dk\b/gi, "$1dk");

  t = t.replace(/(\d+(?:\.\d+)?)(?:\s*)?(?:metres?|meters?)\b/gi, "$1m");
  t = t.replace(
    /(\d+(?:\.\d+)?)(?:\s*)?(?:kilometres?|kilometers?)\b/gi,
    "$1km",
  );
  t = t.replace(/(\d+(?:\.\d+)?)\s*km\b/gi, "$1km");
  t = t.replace(/(\d+(?:\.\d+)?)\s*k\b(?![m\/a-z])/gi, "$1k");
  t = t.replace(/(\d+(?:\.\d+)?)\s*m\b(?![a-z])/gi, "$1m");

  return t;
}

/** Tempo: pace / p — bitişik veya boşluklu */
function normalizePaceSuffixes(text: string): string {
  let t = text;

  t = t.replace(/(\d{1,2}:\d{2})\s*\/\s*km\b/gi, "$1");
  t = t.replace(/@\s*(\d{1,2}:\d{2})/g, "$1");
  t = t.replace(
    /\btempo\s+(\d{1,2}:\d{2}(?:\s*[\/\-]\s*\d{1,2}:\d{2})?)/gi,
    "$1",
  );

  const timePat = String.raw`\d{1,2}:\d{2}(?:\s*[\/\-]\s*\d{1,2}:\d{2})?`;

  t = t.replace(new RegExp(`(${timePat})\\s*pace\\b`, "gi"), "$1");
  t = t.replace(new RegExp(`(${timePat})pace\\b`, "gi"), "$1");
  t = t.replace(new RegExp(`(${timePat})\\s*p\\b`, "gi"), "$1");
  t = t.replace(new RegExp(`(${timePat})p\\b`, "gi"), "$1");

  t = t.replace(/\s+pace\b/gi, "");

  return t;
}

function insertBoundarySpaces(text: string): string {
  let t = text;

  t = t.replace(/(dk|km|m|k)(\d{1,2}:\d{2})/gi, "$1 $2");
  t = t.replace(/(dk|km|m|k)(vdot)\b/gi, "$1 $2");
  t = t.replace(/(dk|km|m|k|\d{1,2}:\d{2})(R)\b/gi, "$1 $2");
  t = t.replace(/(\d{1,2}:\d{2})(vdot)\b/gi, "$1 $2");
  t = t.replace(/\bR(\d)/gi, "R $1");
  t = t.replace(/(\d+m)(\d+(?:\.\d+)?dk\b)/gi, "$1 $2");
  t = t.replace(/(\d+m)(\d{1,2}:\d{2}dk\b)/gi, "$1 $2");

  return t;
}

function normalizeRepeatSyntax(text: string): string {
  let t = text;
  t = t.replace(/\b(\d+)\s*(?:tekrar|rep|reps)\s+/gi, "$1x");
  t = t.replace(/\b(\d+)\s*[*×]\s*/g, "$1x");
  t = t.replace(/\b(\d+)\s*x\s+/gi, "$1x");
  t = t.replace(/\b(\d+)\s*x\s*(\d)/gi, "$1x$2");
  return t;
}

function normalizeRecoveryLabels(text: string): string {
  return text.replace(/\b(?:toparlanma|recovery|rec|float)\b/gi, "R");
}

function tightenSpacing(text: string): string {
  return text.replace(/\s{2,}/g, " ").trim();
}

export function normalizeCoachInput(raw: string): string {
  let t = raw.trim();
  if (!t) return t;

  t = normalizeDecimals(t);
  t = expandNpaceShorthand(t);
  t = normalizeHourUnits(t);
  t = normalizeWordUnits(t);
  t = insertBoundarySpaces(t);
  t = normalizeRepeatSyntax(t);
  t = normalizeRecoveryLabels(t);
  t = normalizePaceSuffixes(t);
  t = tightenSpacing(t);

  return t;
}

/** Parser regex'lerinde süre birimi yedek kalıbı */
export const DURATION_UNIT_PATTERN = "(?:dk|dakika|dak|min(?:ute)?s?)";
