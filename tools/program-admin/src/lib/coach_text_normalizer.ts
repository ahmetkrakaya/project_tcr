/**
 * Koç metnini parse öncesi kanonik forma getirir.
 * Dart: lib/features/events/utils/coach_text_normalizer.dart (eşdeğer)
 *
 * Tüm birimler (dk, m, km, pace, …) bitişik veya boşluklu yazılabilir.
 */

/** Npace → N:00 (1–9 arası tek haneli pace kısaltması) */
function expandNpaceShorthand(text: string): string {
  return text
    .replace(/\b([1-9])\s+pace\b/gi, "$1:00")
    .replace(/\b([1-9])pace\b/gi, "$1:00");
}

/** Virgül ondalık → nokta */
function normalizeDecimals(text: string): string {
  return text.replace(/(\d),(\d)/g, "$1.$2");
}

/** Süre birimlerini dk'ya indirger */
function normalizeDurationUnits(text: string): string {
  let t = text;

  t = t.replace(
    /\b(\d+)\s*(?:h|hr|hours?|sa|saat)\s*(\d+)\s*(?:dk|dakika|min(?:ute)?s?)\b/gi,
    (_m, h, m) => `${Number(h) * 60 + Number(m)}dk`,
  );

  t = t.replace(/\b(\d+):(\d{2}):(\d{2})\b/g, (_m, h, m, _s) => {
    return `${Number(h) * 60 + Number(m)}dk`;
  });

  t = t.replace(
    /\b(\d+(?:\.\d+)?)\s*(?:h|hr|hours?|sa(?:at)?)\b/gi,
    (_m, n) => `${Math.round(Number(n) * 60)}dk`,
  );

  t = t.replace(
    /\b(\d+(?:\.\d+)?)\s*(?:dakika|minutes?|mins?)\b/gi,
    (_m, n) => `${n}dk`,
  );

  t = t.replace(/\b(\d+)[''](?:\s*dk)?\b/g, (_m, n) => `${n}dk`);

  return t;
}

/** Mesafe birimlerini standartlaştır */
function normalizeDistanceUnits(text: string): string {
  return text
    .replace(/\b(\d+(?:\.\d+)?)\s*(?:metre|meter|meters|metres)\b/gi, "$1m")
    .replace(
      /\b(\d+(?:\.\d+)?)\s*(?:kilometre|kilometer|kilometers|kilometres)\b/gi,
      "$1km",
    );
}

/**
 * Bitişik yazılmış uzun birimleri kısalt; kısa birimlerde boşluğu kaldır.
 * 15 dk / 15dk / 15dakika → 15dk · 500 m / 500m / 500metre → 500m
 */
function normalizeUnitTokens(text: string): string {
  let t = text;

  // Bitişik uzun birimler
  t = t.replace(/(\d+(?:\.\d+)?)(dakika|minutes?|mins?)\b/gi, "$1dk");
  t = t.replace(/(\d+(?:\.\d+)?)(metres?|meters?)\b/gi, "$1m");
  t = t.replace(/(\d+(?:\.\d+)?)(kilometres?|kilometers?)\b/gi, "$1km");

  // Boşluklu veya bitişik kısa birimler → kanonik bitişik
  t = t.replace(/(\d+(?:\.\d+)?)\s*dk\b/gi, "$1dk");
  t = t.replace(/(\d+(?:\.\d+)?)\s*km\b/gi, "$1km");
  t = t.replace(/(\d+(?:\.\d+)?)\s*k\b(?![m\/a-z])/gi, "$1k");
  t = t.replace(/(\d+(?:\.\d+)?)\s*m\b(?![a-z])/gi, "$1m");

  return t;
}

/** Bitişik ifadeler arasına sınır boşluğu ekle */
function insertBoundarySpaces(text: string): string {
  let t = text;

  // Birim → tempo / vdot / R
  t = t.replace(/(dk|km|m|k)(\d{1,2}:\d{2})/gi, "$1 $2");
  t = t.replace(/(dk|km|m|k)(vdot)\b/gi, "$1 $2");
  t = t.replace(/(dk|km|m|k|\d{1,2}:\d{2})(R)\b/gi, "$1 $2");

  // Tempo → tempo (3:003:00 değil; pace range zaten ayırıcılı)
  t = t.replace(/(\d{1,2}:\d{2})(vdot)\b/gi, "$1 $2");

  // R bitişik recovery: R1dk, R200m
  t = t.replace(/\bR(\d)/gi, "R $1");

  return t;
}

/** Tekrar gösterimini x'e çevir */
function normalizeRepeatSyntax(text: string): string {
  let t = text;
  t = t.replace(/\b(\d+)\s*(?:tekrar|rep|reps)\s+/gi, "$1x");
  t = t.replace(/\b(\d+)\s*[*×]\s*/g, "$1x");
  t = t.replace(/\b(\d+)\s*x\s+/gi, "$1x");
  t = t.replace(/\b(\d+)\s*x\s*(\d)/gi, "$1x$2");
  return t;
}

/** Recovery etiketlerini R'ye çevir */
function normalizeRecoveryLabels(text: string): string {
  return text.replace(/\b(?:toparlanma|recovery|rec|float)\b/gi, "R");
}

/** Pace ifadelerini sadeleştir — bitişik veya boşluklu */
function normalizePaceKeywords(text: string): string {
  let t = text;

  t = t.replace(/(\d{1,2}:\d{2})\s*\/\s*km\b/gi, "$1");
  t = t.replace(/@\s*(\d{1,2}:\d{2})/g, "$1");
  t = t.replace(
    /\btempo\s+(\d{1,2}:\d{2}(?:\s*[\/\-]\s*\d{1,2}:\d{2})?)/gi,
    "$1",
  );

  // 3:00pace, 3:00 pace, 9:00-10:00pace
  t = t.replace(
    /(\d{1,2}:\d{2}(?:\s*[\/\-]\s*\d{1,2}:\d{2})?)pace\b/gi,
    "$1",
  );
  t = t.replace(
    /(\d{1,2}:\d{2}(?:\s*[\/\-]\s*\d{1,2}:\d{2})?)\s+pace\b/gi,
    "$1",
  );

  // 3:00p, 3:00 p (pace kısaltması; split 1:51p parantez içinde kalır)
  t = t.replace(
    /(\d{1,2}:\d{2}(?:\s*[\/\-]\s*\d{1,2}:\d{2})?)\s*p\b/gi,
    "$1",
  );

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
  t = normalizeUnitTokens(t);
  t = insertBoundarySpaces(t);
  t = normalizeRepeatSyntax(t);
  t = normalizeRecoveryLabels(t);
  t = normalizePaceKeywords(t);
  t = tightenSpacing(t);

  return t;
}
