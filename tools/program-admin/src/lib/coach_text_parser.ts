/**
 * Koç kısa notasyonu → workout_definition JSON
 * Dart: lib/features/events/utils/coach_text_parser.dart
 */

import { normalizeCoachInput } from "./coach_text_normalizer";

export type SegmentKind = "warmup" | "main" | "recovery" | "cooldown";

export type PaceSpec =
  | { mode: "vdot" }
  | { mode: "range"; minSec: number; maxSec: number }
  | { mode: "single"; secPerKm: number };

export type TrainingTypeHint =
  | "easy_run"
  | "long_run"
  | "interval"
  | "repetition"
  | "threshold";

export type ParseSuccess = {
  ok: true;
  isRest: false;
  workoutDefinition: { steps: Array<Record<string, unknown>> };
  trainingTypeHint: TrainingTypeHint;
  programContent: string;
};

export type ParseRest = {
  ok: true;
  isRest: true;
  programContent: string;
};

export type ParseFailure = {
  ok: false;
  error: string;
  programContent: string;
};

export type ParseResult = ParseSuccess | ParseRest | ParseFailure;

type RecoverySpec = {
  distanceM?: number;
  durationSec?: number;
  pace?: PaceSpec | null;
};

export function parsePaceSeconds(raw: string): number | null {
  const s = raw.trim().replace(",", ".");
  if (!s) return null;
  const m = s.match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return null;
  const mm = Number(m[1]);
  const ss = Number(m[2]);
  if (ss < 0 || ss > 59) return null;
  return mm * 60 + ss;
}

function normalizePaceRaw(raw: string): string {
  let t = raw.trim();
  if (t.startsWith("(") && t.endsWith(")")) {
    t = t.slice(1, -1).trim();
  }
  return t
    .replace(/(\d{1,2}:\d{2})pace\s*$/i, "$1")
    .replace(/\s+pace\s*$/i, "")
    .replace(/\s*p\s*$/i, "")
    .replace(/^@\s*/, "");
}

export function parsePaceSpec(raw: string | null | undefined): PaceSpec | null {
  if (!raw) return null;
  let t = normalizePaceRaw(raw).toLowerCase();
  // Npace güvenlik (normalizer'dan kaçan durumlar)
  const npace = t.match(/^([1-9])pace$/);
  if (npace) t = `${npace[1]}:00`;
  if (t === "vdot") return { mode: "vdot" };
  const rangeMatch = t.match(/^(\d{1,2}:\d{2})\s*[\/\-]\s*(\d{1,2}:\d{2})$/);
  if (rangeMatch) {
    const a = parsePaceSeconds(rangeMatch[1]);
    const b = parsePaceSeconds(rangeMatch[2]);
    if (a == null || b == null) return null;
    return { mode: "range", minSec: Math.min(a, b), maxSec: Math.max(a, b) };
  }
  const single = parsePaceSeconds(t);
  if (single != null) return { mode: "single", secPerKm: single };
  return null;
}

function parseDistanceMeters(value: number, unit: string): number {
  const u = unit.toLowerCase();
  if (u === "m") return value;
  return Math.round(value * 1000);
}

type RepTarget = {
  splitSec?: number | null;
  splitSecMin?: number | null;
  splitSecMax?: number | null;
  pace?: PaceSpec | null;
};

function paceToSegmentFields(pace: PaceSpec | null): Record<string, unknown> {
  if (!pace) return {};
  if (pace.mode === "vdot") return { use_vdot_for_pace: true };
  if (pace.mode === "single") {
    return {
      pace_seconds_per_km_min: pace.secPerKm,
      pace_seconds_per_km_max: pace.secPerKm,
    };
  }
  return {
    pace_seconds_per_km_min: pace.minSec,
    pace_seconds_per_km_max: pace.maxSec,
  };
}

function performanceTargetFromRepTarget(target: RepTarget | null): string {
  if (!target) return "none";
  const hasPace = target.pace != null;
  const hasSplit =
    target.splitSec != null ||
    target.splitSecMin != null ||
    target.splitSecMax != null;
  if (hasPace) return "pace";
  if (hasSplit) return "time";
  return "none";
}

function repTargetToSegmentFields(
  target: RepTarget | null,
  distanceMeters?: number,
): Record<string, unknown> {
  if (!target) return {};
  const out: Record<string, unknown> = {};
  if (target.splitSec != null) out.duration_seconds = target.splitSec;
  if (target.splitSecMin != null) out.duration_seconds_min = target.splitSecMin;
  if (target.splitSecMax != null) out.duration_seconds_max = target.splitSecMax;
  Object.assign(out, paceToSegmentFields(target.pace ?? null));
  if (target.pace == null && distanceMeters != null && distanceMeters > 0) {
    const km = distanceMeters / 1000;
    if (target.splitSecMin != null && target.splitSecMax != null) {
      const minPace = Math.round(target.splitSecMax / km);
      const maxPace = Math.round(target.splitSecMin / km);
      out.pace_seconds_per_km_min = Math.min(minPace, maxPace);
      out.pace_seconds_per_km_max = Math.max(minPace, maxPace);
    } else if (target.splitSec != null) {
      const derived = Math.round(target.splitSec / km);
      out.pace_seconds_per_km_min = derived;
      out.pace_seconds_per_km_max = derived;
    }
  }
  return out;
}

function isLikelySplitPlusPace(
  splitSec: number,
  paceSecPerKm: number,
  distM: number,
): boolean {
  if (distM <= 0) return false;
  if (paceSecPerKm < 120 || paceSecPerKm > 480) return false;
  if (splitSec < 30 || splitSec > 1800) return false;
  const expected = Math.round((paceSecPerKm * distM) / 1000);
  if (Math.abs(splitSec - expected) <= 20) return true;
  return splitSec <= 600 && paceSecPerKm >= 150;
}

function isLikelyPaceRange(aSec: number, bSec: number): boolean {
  return aSec >= 150 && bSec >= 150 && aSec <= 600 && bSec <= 600;
}

function isLikelySplitForDistance(splitSec: number, distM: number): boolean {
  if (distM <= 0) return false;
  const km = distM / 1000;
  const minSplit = Math.round(120 * km);
  const maxSplit = Math.round(480 * km);
  return splitSec >= minSplit && splitSec <= maxSplit;
}

function parseBareTimeTarget(sec: number, distM: number): RepTarget {
  if (isLikelySplitForDistance(sec, distM)) {
    return { splitSec: sec };
  }
  if (sec >= 150 && sec <= 600) {
    return { pace: { mode: "single", secPerKm: sec } };
  }
  return { splitSec: sec };
}

function parseRepTarget(parenRaw: string | undefined, distM: number): RepTarget | null {
  const raw = parenRaw?.trim() ?? "";
  if (!raw) return null;
  return parseBareTarget(raw, distM);
}

/** Parantezsiz veya parantezli hedef ifadesi */
function parseBareTarget(raw: string, distM: number): RepTarget | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  if (/^vdot$/i.test(trimmed)) return { pace: { mode: "vdot" } };

  const comboP = trimmed.match(/^(\d{1,2}:\d{2})\s*(?:dk)?\s*-\s*(\d{1,2}:\d{2})\s*p?\s*$/i);
  if (comboP) {
    const split = parsePaceSeconds(comboP[1]);
    const paceSec = parsePaceSeconds(comboP[2]);
    if (split != null && paceSec != null && !isLikelyPaceRange(split, paceSec)) {
      return { splitSec: split, pace: { mode: "single", secPerKm: paceSec } };
    }
  }

  const paceRangeP = trimmed.match(/^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*p?\s*$/i);
  if (paceRangeP) {
    const a = parsePaceSeconds(paceRangeP[1]);
    const b = parsePaceSeconds(paceRangeP[2]);
    if (a != null && b != null) {
      return { pace: { mode: "range", minSec: Math.min(a, b), maxSec: Math.max(a, b) } };
    }
  }

  const timeRangeDk = trimmed.match(/^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*dk\s*$/i);
  if (timeRangeDk) {
    const a = parsePaceSeconds(timeRangeDk[1]);
    const b = parsePaceSeconds(timeRangeDk[2]);
    if (a != null && b != null) {
      return { splitSecMin: Math.min(a, b), splitSecMax: Math.max(a, b) };
    }
  }

  if (trimmed.includes("/") && !/dk\s*$/i.test(trimmed)) {
    const p = parsePaceSpec(trimmed);
    if (p != null) return { pace: p };
  }

  const hyphenPair = trimmed.match(
    /^(\d{1,2}:\d{2})\s*(?:dk)?\s*-\s*(\d{1,2}:\d{2})\s*(?:dk|p)?\s*$/i,
  );
  if (hyphenPair) {
    const a = parsePaceSeconds(hyphenPair[1]);
    const b = parsePaceSeconds(hyphenPair[2]);
    if (a != null && b != null) {
      if (/dk\s*$/i.test(trimmed)) {
        return { splitSecMin: Math.min(a, b), splitSecMax: Math.max(a, b) };
      }
      if (isLikelySplitPlusPace(a, b, distM) || (distM >= 200 && distM <= 5000)) {
        return { splitSec: a, pace: { mode: "single", secPerKm: b } };
      }
      if (isLikelyPaceRange(a, b)) {
        return { pace: { mode: "range", minSec: Math.min(a, b), maxSec: Math.max(a, b) } };
      }
    }
  }

  const splitSingle = trimmed.match(/^(\d{1,2}:\d{2})(?:dk)?\s*$/i);
  if (splitSingle) {
    const sec = parsePaceSeconds(splitSingle[1]);
    if (sec != null) {
      if (/dk\s*$/i.test(trimmed)) return { splitSec: sec };
      return parseBareTimeTarget(sec, distM);
    }
  }

  if (trimmed.includes("-")) {
    const p = parsePaceSpec(trimmed);
    if (p != null) return { pace: p };
  }

  const cleaned = normalizePaceRaw(trimmed);
  const single = parsePaceSeconds(cleaned);
  if (single != null) return parseBareTimeTarget(single, distM);

  const paceOnly = parsePaceSpec(trimmed);
  if (paceOnly != null) return { pace: paceOnly };

  return null;
}

/** R sonrası toparlanma ifadesi */
function parseRecoveryClause(raw: string): RecoverySpec | null {
  let remaining = raw.trim();
  if (!remaining) return null;

  const spec: RecoverySpec = {};

  const distMatch = remaining.match(
    /^(\d+(?:\.\d+)?)\s*(m|k|km)?(?:\s+|$)/i,
  );
  if (distMatch) {
    const val = Number(distMatch[1]);
    const unitRaw = distMatch[2]?.toLowerCase();
    const unit = unitRaw ?? "m";
    spec.distanceM = parseDistanceMeters(
      val,
      unit === "k" || unit === "km" ? "k" : unit,
    );
    remaining = remaining.slice(distMatch[0].length).trim();
  }

  const dkMatch = remaining.match(/^(\d+(?:\.\d+)?)\s*dk(?:\s+|$)/i);
  if (dkMatch) {
    spec.durationSec = Math.round(Number(dkMatch[1]) * 60);
    remaining = remaining.slice(dkMatch[0].length).trim();
  }

  if (remaining) {
    const timeOnly = remaining.match(/^(\d{1,2}):(\d{2})(?:\s+pace)?\s*$/i);
    if (timeOnly) {
      const sec = parsePaceSeconds(`${timeOnly[1]}:${timeOnly[2]}`);
      if (sec != null) {
        const mm = Number(timeOnly[1]);
        const ss = Number(timeOnly[2]);
        const looksLikePace =
          (ss === 0 && mm >= 2 && mm <= 8) ||
          (sec >= 150 && sec <= 480 && !(mm <= 2 && ss > 0));

        if (spec.durationSec != null) {
          // R 1dk 3:00 → süre + pace
          spec.pace = { mode: "single", secPerKm: sec };
        } else if (spec.distanceM != null && looksLikePace) {
          spec.pace = { mode: "single", secPerKm: sec };
        } else if (spec.distanceM != null && !looksLikePace) {
          // legacy R400m 2:20
          spec.durationSec = sec;
        } else if (looksLikePace) {
          spec.pace = { mode: "single", secPerKm: sec };
        } else {
          spec.durationSec = sec;
        }
        remaining = "";
      }
    }
  }

  if (remaining) {
    spec.pace = parsePaceSpec(remaining);
  }

  if (
    spec.distanceM == null &&
    spec.durationSec == null &&
    spec.pace == null
  ) {
    return null;
  }
  return spec;
}

function splitOnRecovery(block: string): { work: string; recovery: RecoverySpec | null } {
  const idx = block.search(/\s+R(?:\s|\d)/i);
  if (idx < 0) return { work: block, recovery: null };
  const work = block.slice(0, idx).trim();
  const recRaw = block.slice(idx).replace(/^\s+R\s*/i, "");
  return { work, recovery: parseRecoveryClause(recRaw) };
}

function hasRecovery(spec: RecoverySpec | null): boolean {
  if (!spec) return false;
  return (
    (spec.distanceM != null && spec.distanceM > 0) ||
    (spec.durationSec != null && spec.durationSec > 0) ||
    spec.pace != null
  );
}

export function buildDurationSegment(
  kind: SegmentKind,
  durationSeconds: number,
  pace: PaceSpec | null,
): Record<string, unknown> {
  return {
    type: "segment",
    segment: {
      segment_type: kind,
      target_type: "duration",
      target: pace ? "pace" : "none",
      duration_seconds: durationSeconds,
      ...paceToSegmentFields(pace),
    },
  };
}

export function buildDistanceSegment(
  kind: SegmentKind,
  distanceMeters: number,
  target: RepTarget | null,
): Record<string, unknown> {
  return {
    type: "segment",
    segment: {
      segment_type: kind,
      target_type: "distance",
      target: performanceTargetFromRepTarget(target),
      distance_meters: distanceMeters,
      ...repTargetToSegmentFields(target, distanceMeters),
    },
  };
}

function buildRecoveryStep(spec: RecoverySpec): Record<string, unknown> {
  const pace = spec.pace ?? null;
  if (spec.durationSec != null && spec.durationSec > 0) {
    return buildDurationSegment("recovery", spec.durationSec, pace);
  }
  if (spec.distanceM != null && spec.distanceM > 0) {
    return buildDistanceSegment(
      "recovery",
      spec.distanceM,
      pace ? { pace } : null,
    );
  }
  if (pace) {
    return buildDurationSegment("recovery", 0, pace);
  }
  return buildDurationSegment("recovery", 60, null);
}

type ParsedBlock =
  | {
      type: "interval";
      repeat: number;
      distanceM: number | null;
      durationMinutes: number | null;
      target: RepTarget | null;
      recovery: RecoverySpec | null;
    }
  | { type: "duration"; minutes: number; pace: PaceSpec | null }
  | { type: "distance"; distanceM: number; target: RepTarget | null };

function normalizeBlock(block: string): string {
  return block.trim().replace(
    /^(\d+(?:\.\d+)?)\s*(k|km|m)\s*\/\s*/i,
    (_all, n, u) => `${n}${u} `,
  );
}

function distanceMetersFromValue(distVal: number, unitRaw: string | undefined): number {
  if (unitRaw) {
    const unit = unitRaw.toLowerCase();
    return parseDistanceMeters(distVal, unit === "k" || unit === "km" ? "k" : unit);
  }
  if (distVal >= 100) return Math.round(distVal);
  return parseDistanceMeters(distVal, "k");
}

function parseWorkTarget(
  targetRaw: string | undefined,
  parenRaw: string | undefined,
  bareTimeRaw: string | undefined,
  distM: number,
): RepTarget | null {
  if (parenRaw) return parseRepTarget(parenRaw, distM);
  if (targetRaw?.trim()) return parseBareTarget(targetRaw.trim(), distM);
  if (bareTimeRaw) return parseBareTarget(bareTimeRaw, distM);
  return null;
}

function parseIntervalBlock(block: string): ParsedBlock | null {
  const normalized = normalizeBlock(block);
  const { work, recovery } = splitOnRecovery(normalized);

  const m = work.match(
    /^(\d+)\s*x\s*(\d+(?:\.\d+)?)\s*(dk|min|m|k|km)?(?:\s*(?:\(([^)]+)\)|(\d{1,2}:\d{2})p?))?(?:\s+(.+))?$/i,
  );
  if (!m) return null;

  const repeat = Number(m[1]);
  const value = Number(m[2]);
  const unit = m[3]?.toLowerCase();
  let distanceM: number | null = null;
  let durationMinutes: number | null = null;

  if (unit === "dk" || unit === "min") {
    durationMinutes = value;
  } else {
    distanceM = distanceMetersFromValue(value, unit);
  }

  const target = parseWorkTarget(m[6], m[4], m[5], distanceM ?? 0);

  return { type: "interval", repeat, distanceM, durationMinutes, target, recovery };
}

function parseStandaloneRepBlock(block: string): ParsedBlock | null {
  const normalized = normalizeBlock(block);
  if (/^\d+\s*x\s*/i.test(normalized)) return null;

  const { work, recovery } = splitOnRecovery(normalized);

  const parenMatch = work.match(
    /^(\d+(?:\.\d+)?)\s*(m|k|km)?\s*\(([^)]+)\)$/i,
  );
  if (parenMatch) {
    const distM = distanceMetersFromValue(Number(parenMatch[1]), parenMatch[2]);
    const target = parseRepTarget(parenMatch[3], distM);
    return {
      type: "interval",
      repeat: 1,
      distanceM: distM,
      durationMinutes: null,
      target,
      recovery,
    };
  }

  return null;
}

/** Mesafe + parantezsiz hedef + opsiyonel R: 400m vdot R 1dk */
function parseDistanceRepBlock(block: string): ParsedBlock | null {
  const normalized = normalizeBlock(block);
  if (/^\d+\s*x\s*/i.test(normalized)) return null;

  const { work, recovery } = splitOnRecovery(normalized);
  if (!hasRecovery(recovery)) return null;

  const m = work.match(/^(\d+(?:\.\d+)?)\s*(m|k|km)(?:\s+(.+))?$/i);
  if (!m) return null;

  const distM = parseDistanceMeters(Number(m[1]), m[2]);
  const targetRaw = m[3]?.trim();
  const target = targetRaw ? parseBareTarget(targetRaw, distM) : null;

  return {
    type: "interval",
    repeat: 1,
    distanceM: distM,
    durationMinutes: null,
    target,
    recovery,
  };
}

function parseDurationBlock(block: string): ParsedBlock | null {
  const m = block.trim().match(/^(\d+(?:\.\d+)?)\s*dk(?:\s+(.+))?$/i);
  if (!m) return null;
  const minutes = Number(m[1]);
  const paceRaw = m[2]?.trim();
  const pace = paceRaw ? parsePaceSpec(paceRaw) : null;
  return { type: "duration", minutes, pace };
}

function parseDistanceBlock(block: string): ParsedBlock | null {
  const normalized = normalizeBlock(block);
  if (/\s+R(?:\s|\d)/i.test(normalized)) return null;

  const m = normalized.match(/^(\d+(?:\.\d+)?)\s*(k|km|m)(?:\s+(.+))?$/i);
  if (!m) return null;
  const distM = parseDistanceMeters(Number(m[1]), m[2]);
  const tail = m[3]?.trim();
  const target = tail ? parseBareTarget(tail, distM) : null;
  return { type: "distance", distanceM: distM, target };
}

function splitChainLine(normalized: string, isLongRun = false): string[] {
  const longRunHeader = /^\d+(?:\.\d+)?\s*k\s*:\s*/i;
  let line = normalized.trim();
  const lineIsLongRun = isLongRun || longRunHeader.test(line);
  line = line.replace(longRunHeader, "");

  const plusParts = line.split(/\s*\+\s*/).map((p) => p.trim()).filter(Boolean);
  if (plusParts.length > 1) return plusParts;

  if (lineIsLongRun && line.includes("/")) {
    const slashParts = line.split(/\s*\/\s*/).map((p) => p.trim()).filter(Boolean);
    if (slashParts.length > 1) return slashParts;
  }

  line = plusParts.length > 0 ? plusParts[0]! : line;

  if (!/\d\s*dk/i.test(line)) {
    const re = /(\d+(?:\.\d+)?)\s*(?:km|m|k)(?:\s+\d{1,2}:\d{2}(?:[\/\-]\d{1,2}:\d{2})?)?/gi;
    const matches: string[] = [];
    let match: RegExpExecArray | null;
    while ((match = re.exec(line)) !== null) {
      matches.push(match[0].trim());
    }
    if (matches.length > 1 && !/\dx\d/i.test(line)) {
      return matches;
    }
  }
  return [line];
}

function splitChain(text: string): string[] {
  const trimmed = text.trim();
  const lines = trimmed.split(/\r?\n+/).map((l) => l.trim()).filter(Boolean);
  if (lines.length > 1) {
    return lines.flatMap((line) => splitChainLine(line));
  }
  const longRunHeader = /^\d+(?:\.\d+)?\s*k\s*:\s*/i;
  return splitChainLine(trimmed, longRunHeader.test(trimmed));
}

function blockToSteps(
  block: ParsedBlock,
  kind: SegmentKind,
): Array<Record<string, unknown>> {
  if (block.type === "duration") {
    return [buildDurationSegment(kind, block.minutes * 60, block.pace)];
  }
  if (block.type === "distance") {
    return [buildDistanceSegment(kind, block.distanceM, block.target)];
  }

  const main =
    block.distanceM != null
      ? buildDistanceSegment("main", block.distanceM, block.target)
      : buildDurationSegment(
          "main",
          (block.durationMinutes ?? 0) * 60,
          block.target?.pace ?? null,
        );

  const inner: Array<Record<string, unknown>> = [main];
  if (hasRecovery(block.recovery)) {
    inner.push(buildRecoveryStep(block.recovery!));
  }

  if (inner.length === 1 && block.repeat > 1) {
    return [{ type: "repeat", repeat_count: block.repeat, steps: [main] }];
  }
  return [{ type: "repeat", repeat_count: block.repeat, steps: inner }];
}

const WARMUP_LABEL =
  "(ısınma|isinma|warmup|warm-up|warm\\s+up|warm\\s+ısınma|warm|wu)";
const COOLDOWN_LABEL = "(soğuma|soguma|cooldown|cool-down|cool\\s+down|cool|cd)";

function splitExplicitSegmentLabel(part: string): {
  kind: SegmentKind | null;
  body: string;
} {
  const trimmed = part.trim();
  const prefixPatterns: Array<{ kind: SegmentKind; re: RegExp }> = [
    {
      kind: "warmup",
      re: new RegExp(`^${WARMUP_LABEL}\\s*[:\\-]?\\s*(.+)$`, "iu"),
    },
    {
      kind: "cooldown",
      re: new RegExp(`^${COOLDOWN_LABEL}\\s*[:\\-]?\\s*(.+)$`, "iu"),
    },
  ];
  for (const { kind, re } of prefixPatterns) {
    const match = trimmed.match(re);
    if (match?.[2]) {
      return { kind, body: match[2].trim() };
    }
  }

  const suffixPatterns: Array<{ kind: SegmentKind; re: RegExp }> = [
    {
      kind: "warmup",
      re: new RegExp(`^(.+?)\\s+${WARMUP_LABEL}\\s*$`, "iu"),
    },
    {
      kind: "cooldown",
      re: new RegExp(`^(.+?)\\s+${COOLDOWN_LABEL}\\s*$`, "iu"),
    },
  ];
  for (const { kind, re } of suffixPatterns) {
    const match = trimmed.match(re);
    if (match?.[1]) {
      return { kind, body: match[1].trim() };
    }
  }

  return { kind: null, body: trimmed };
}

function resolveSegmentKind(
  block: ParsedBlock,
  explicitKind: SegmentKind | null,
): SegmentKind {
  if (block.type === "interval") return "main";
  return explicitKind ?? "main";
}

function totalDistanceMeters(steps: Array<Record<string, unknown>>): number {
  let total = 0;
  const walk = (arr: Array<Record<string, unknown>>, repeat = 1) => {
    for (const s of arr) {
      if (s.type === "repeat") {
        const rc = Number(s.repeat_count ?? 1);
        walk(s.steps as Array<Record<string, unknown>>, repeat * rc);
      } else if (s.type === "segment") {
        const seg = s.segment as Record<string, unknown>;
        const dm = Number(seg.distance_meters ?? 0);
        if (dm > 0) total += dm * repeat;
      }
    }
  };
  walk(steps);
  return total;
}

function hasRepeat(steps: Array<Record<string, unknown>>): boolean {
  for (const s of steps) {
    if (s.type === "repeat") return true;
  }
  return false;
}

function inferTrainingType(
  steps: Array<Record<string, unknown>>,
  raw: string,
): TrainingTypeHint {
  const lower = raw.toLowerCase();
  if (hasRepeat(steps)) {
    const mainDist = steps.flatMap((s) => {
      if (s.type !== "repeat") return [];
      const inner = s.steps as Array<Record<string, unknown>>;
      const main = inner[0]?.segment as Record<string, unknown> | undefined;
      return [Number(main?.distance_meters ?? 0)];
    });
    if (mainDist.some((d) => d > 0 && d <= 600)) return "repetition";
    return "interval";
  }
  if (/^\d+\s*k\s*:/i.test(raw) || totalDistanceMeters(steps) >= 15000) {
    return "long_run";
  }
  if (lower.includes("threshold") || lower.includes("eşik")) {
    return "threshold";
  }
  return "easy_run";
}

export function parseCoachText(rawInput: string): ParseResult {
  const programContent = rawInput.trim();
  if (!programContent) {
    return { ok: true, isRest: true, programContent: "" };
  }
  const lower = programContent.toLowerCase();
  if (lower === "rest" || lower === "dinlenme") {
    return { ok: true, isRest: true, programContent };
  }

  const normalized = normalizeCoachInput(programContent);
  const chainParts = splitChain(normalized);
  const allSteps: Array<Record<string, unknown>> = [];

  for (let i = 0; i < chainParts.length; i++) {
    const labeled = splitExplicitSegmentLabel(chainParts[i]!);
    const part = labeled.body;
    let block: ParsedBlock | null = parseIntervalBlock(part);
    if (!block) block = parseStandaloneRepBlock(part);
    if (!block) block = parseDistanceRepBlock(part);
    if (!block) block = parseDurationBlock(part);
    if (!block) block = parseDistanceBlock(part);
    if (!block) {
      return {
        ok: false,
        error: `Anlaşılamayan ifade: "${part}"`,
        programContent,
      };
    }
    if (block.type === "interval") {
      if (block.repeat > 1 && !hasRecovery(block.recovery)) {
        return {
          ok: false,
          error: `${block.repeat}x tekrar için toparlanma (R) belirtilmeli`,
          programContent,
        };
      }
      allSteps.push(...blockToSteps(block, "main"));
      continue;
    }
    const kind = resolveSegmentKind(block, labeled.kind);
    allSteps.push(...blockToSteps(block, kind));
  }

  if (allSteps.length === 0) {
    return { ok: false, error: "Antrenman adımı bulunamadı", programContent };
  }

  return {
    ok: true,
    isRest: false,
    workoutDefinition: { steps: allSteps },
    trainingTypeHint: inferTrainingType(allSteps, programContent),
    programContent,
  };
}

export function resolveTrainingTypeName(hint: TrainingTypeHint): string {
  return hint;
}
