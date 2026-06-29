/**
 * Koç metnini parse öncesi kanonik forma getirir.
 * Dart: lib/features/events/utils/coach_text_normalizer.dart (eşdeğer)
 */

/** Npace → N:00 (1–9 arası tek haneli pace kısaltması) */
function expandNpaceShorthand(text: string): string {
  return text.replace(/\b([1-9])pace\b/gi, "$1:00");
}

/** Virgül ondalık → nokta */
function normalizeDecimals(text: string): string {
  return text.replace(/(\d),(\d)/g, "$1.$2");
}

/** Süre birimlerini dk'ya indirger */
function normalizeDurationUnits(text: string): string {
  let t = text;

  // 1h30dk, 1saat30dk → 90dk
  t = t.replace(
    /\b(\d+)\s*(?:h|hr|hours?|sa|saat)\s*(\d+)\s*(?:dk|dakika|min(?:ute)?s?)\b/gi,
    (_m, h, m) => `${Number(h) * 60 + Number(m)}dk`,
  );

  // 1:30:00 → 90dk (sa:dk:sn)
  t = t.replace(/\b(\d+):(\d{2}):(\d{2})\b/g, (_m, h, m, _s) => {
    return `${Number(h) * 60 + Number(m)}dk`;
  });

  // Saat → dk
  t = t.replace(
    /\b(\d+(?:\.\d+)?)\s*(?:h|hr|hours?|sa(?:at)?)\b/gi,
    (_m, n) => `${Math.round(Number(n) * 60)}dk`,
  );

  // dakika, min, minute → dk
  t = t.replace(
    /\b(\d+(?:\.\d+)?)\s*(?:dakika|minutes?|mins?)\b/gi,
    (_m, n) => `${n}dk`,
  );

  // 45' veya 45'dakika
  t = t.replace(/\b(\d+)[''](?:\s*dk)?\b/g, (_m, n) => `${n}dk`);

  return t;
}

/** Mesafe birimlerini standartlaştır */
function normalizeDistanceUnits(text: string): string {
  return text
    .replace(/\b(\d+(?:\.\d+)?)\s*(?:metre|meter|meters|metres)\b/gi, "$1m")
    .replace(/\b(\d+(?:\.\d+)?)\s*(?:kilometre|kilometer|kilometers|kilometres)\b/gi, "$1km");
}

/** Tekrar gösterimini x'e çevir */
function normalizeRepeatSyntax(text: string): string {
  let t = text;
  t = t.replace(/\b(\d+)\s*(?:tekrar|rep|reps)\s+/gi, "$1x");
  t = t.replace(/\b(\d+)\s*[*×]\s*/g, "$1x");
  t = t.replace(/\b(\d+)\s+x\s+/gi, "$1x");
  t = t.replace(/\b(\d+)\s+x\s*(\d)/gi, "$1x$2");
  return t;
}

/** Recovery etiketlerini R'ye çevir */
function normalizeRecoveryLabels(text: string): string {
  return text.replace(
    /\b(?:toparlanma|recovery|rec|float)\b/gi,
    "R",
  );
}

/** Pace ifadelerini sadeleştir */
function normalizePaceKeywords(text: string): string {
  let t = text;
  // 6:00/km → 6:00
  t = t.replace(/(\d{1,2}:\d{2})\s*\/\s*km\b/gi, "$1");
  // @6:00 → 6:00
  t = t.replace(/@\s*(\d{1,2}:\d{2})/g, "$1");
  // tempo 5:20 → 5:20
  t = t.replace(/\btempo\s+(\d{1,2}:\d{2}(?:\s*[\/\-]\s*\d{1,2}:\d{2})?)/gi, "$1");
  // 3:00pace, 7:00 pace, 9:00-10:00pace → strip pace
  t = t.replace(
    /(\d{1,2}:\d{2}(?:\s*[\/\-]\s*\d{1,2}:\d{2})?)pace\b/gi,
    "$1",
  );
  t = t.replace(
    /(\d{1,2}:\d{2}(?:\s*[\/\-]\s*\d{1,2}:\d{2})?)\s+pace\b/gi,
    "$1",
  );
  // Sondaki pace (ayrı kelime)
  t = t.replace(/\s+pace\b/gi, "");
  return t;
}

/** Boşlukları sıkılaştır */
function tightenSpacing(text: string): string {
  return text.replace(/\s{2,}/g, " ").trim();
}

/** Giriş metnini normalize eder */
export function normalizeCoachInput(raw: string): string {
  let t = raw.trim();
  if (!t) return t;

  t = normalizeDecimals(t);
  t = expandNpaceShorthand(t);
  t = normalizeDurationUnits(t);
  t = normalizeDistanceUnits(t);
  t = normalizeRepeatSyntax(t);
  t = normalizeRecoveryLabels(t);
  t = normalizePaceKeywords(t);
  t = tightenSpacing(t);

  return t;
}
