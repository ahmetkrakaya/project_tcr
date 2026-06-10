/**
 * Koç kısa notasyonu → workout_definition JSON
 * Dart: lib/features/events/utils/coach_text_parser.dart
 */

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

export function parsePaceSpec(raw: string | null | undefined): PaceSpec | null {
  if (!raw) return null;
  const t = raw.trim().toLowerCase();
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
  const hasSplit = target.splitSec != null || target.splitSecMin != null || target.splitSecMax != null;
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

function isLikelySplitPlusPace(splitSec: number, paceSecPerKm: number, distM: number): boolean {
  if (distM <= 0) return false;
  if (paceSecPerKm < 120 || paceSecPerKm > 480) return false;
  if (splitSec < 30 || splitSec > 1800) return false;
  const expected = Math.round(paceSecPerKm * distM / 1000);
  if (Math.abs(splitSec - expected) <= 20) return true;
  return splitSec <= 600 && paceSecPerKm >= 150;
}

function isLikelyPaceRange(aSec: number, bSec: number): boolean {
  return aSec >= 150 && bSec >= 150 && aSec <= 600 && bSec <= 600;
}

function parseRepTarget(parenRaw: string | undefined, distM: number): RepTarget | null {
  const raw = parenRaw?.trim() ?? "";
  if (!raw) return null;
  if (/vdot/i.test(raw)) return { pace: { mode: "vdot" } };

  const comboP = raw.match(/^(\d{1,2}:\d{2})\s*(?:dk)?\s*-\s*(\d{1,2}:\d{2})\s*p\s*$/i);
  if (comboP) {
    const split = parsePaceSeconds(comboP[1]);
    const paceSec = parsePaceSeconds(comboP[2]);
    if (split != null && paceSec != null && !isLikelyPaceRange(split, paceSec)) {
      return { splitSec: split, pace: { mode: "single", secPerKm: paceSec } };
    }
  }

  const paceRangeP = raw.match(/^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*p\s*$/i);
  if (paceRangeP) {
    const a = parsePaceSeconds(paceRangeP[1]);
    const b = parsePaceSeconds(paceRangeP[2]);
    if (a != null && b != null) {
      return { pace: { mode: "range", minSec: Math.min(a, b), maxSec: Math.max(a, b) } };
    }
  }

  const timeRangeDk = raw.match(/^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*dk\s*$/i);
  if (timeRangeDk) {
    const a = parsePaceSeconds(timeRangeDk[1]);
    const b = parsePaceSeconds(timeRangeDk[2]);
    if (a != null && b != null) {
      return { splitSecMin: Math.min(a, b), splitSecMax: Math.max(a, b) };
    }
  }

  const paceSingleP = raw.match(/^(\d{1,2}:\d{2})\s*p\s*$/i);
  if (paceSingleP) {
    const pace = parsePaceSpec(paceSingleP[1]);
    if (pace != null) return { pace };
  }

  if (raw.includes("/") && !/dk\s*$/i.test(raw)) {
    const pace = parsePaceSpec(raw.replace(/\s*p\s*$/i, ""));
    if (pace != null) return { pace };
  }

  const hyphenPair = raw.match(/^(\d{1,2}:\d{2})\s*(?:dk)?\s*-\s*(\d{1,2}:\d{2})\s*(?:dk|p)?\s*$/i);
  if (hyphenPair) {
    const a = parsePaceSeconds(hyphenPair[1]);
    const b = parsePaceSeconds(hyphenPair[2]);
    if (a != null && b != null) {
      if (/dk\s*$/i.test(raw)) {
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

  const splitSingle = raw.match(/^(\d{1,2}:\d{2})(?:dk)?\s*$/i);
  if (splitSingle) {
    const sec = parsePaceSeconds(splitSingle[1]);
    if (sec != null) {
      return { splitSec: sec };
    }
  }

  if (raw.includes("-")) {
    const pace = parsePaceSpec(raw.replace(/\s*p\s*$/i, ""));
    if (pace != null) return { pace };
  }

  const cleaned = raw.replace(/\s*p\s*$/i, "");
  const single = parsePaceSeconds(cleaned);
  if (single != null) {
    return { splitSec: single };
  }

  return null;
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
      target: "pace",
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

type ParsedBlock =
  | { type: "interval"; repeat: number; distanceM: number; target: RepTarget | null; recoveryM: number | null; recoverySec: number | null }
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

function parseIntervalBlock(block: string): ParsedBlock | null {
  const normalized = normalizeBlock(block);
  const m = normalized.match(
    /^(\d+)\s*x\s*(\d+(?:\.\d+)?)\s*(m|k|km)?(?:\s*\(([^)]+)\))?(?:\s+R\s*(\d+(?:\.\d+)?)\s*(m|k|km)?)?(?:\s+(\d{1,2}:\d{2}))?/i,
  );
  if (!m) return null;
  const repeat = Number(m[1]);
  const distVal = Number(m[2]);
  const distM = distanceMetersFromValue(distVal, m[3]);
  const target = parseRepTarget(m[4], distM);
  let recoveryM: number | null = null;
  let recoverySec: number | null = null;
  if (m[5]) {
    const rv = Number(m[5]);
    const ru = (m[6] ?? "m").toLowerCase();
    recoveryM = parseDistanceMeters(rv, ru === "k" || ru === "km" ? "k" : ru);
  }
  if (m[7]) {
    recoverySec = parsePaceSeconds(m[7]);
  }
  return { type: "interval", repeat, distanceM: distM, target, recoveryM, recoverySec };
}

function parseStandaloneRepBlock(block: string): ParsedBlock | null {
  const normalized = normalizeBlock(block);
  if (/^\d+\s*x\s*/i.test(normalized)) return null;
  const m = normalized.match(
    /^(\d+(?:\.\d+)?)\s*(m|k|km)?\s*\(([^)]+)\)(?:\s+R\s*(\d+(?:\.\d+)?)\s*(m|k|km)?)?(?:\s+(\d{1,2}:\d{2}))?/i,
  );
  if (!m) return null;
  const distVal = Number(m[1]);
  const distM = distanceMetersFromValue(distVal, m[2]);
  const target = parseRepTarget(m[3], distM);
  let recoveryM: number | null = null;
  let recoverySec: number | null = null;
  if (m[4]) {
    const rv = Number(m[4]);
    const ru = (m[5] ?? "m").toLowerCase();
    recoveryM = parseDistanceMeters(rv, ru === "k" || ru === "km" ? "k" : ru);
  }
  if (m[6]) {
    recoverySec = parsePaceSeconds(m[6]);
  }
  return { type: "interval", repeat: 1, distanceM: distM, target, recoveryM, recoverySec };
}

function parseDurationBlock(block: string): ParsedBlock | null {
  const m = block.trim().match(/^(\d+)\s*dk(?:\s+(.+))?$/i);
  if (!m) return null;
  const minutes = Number(m[1]);
  const paceRaw = m[2]?.trim();
  const pace = paceRaw ? parsePaceSpec(paceRaw) : null;
  return { type: "duration", minutes, pace };
}

function parseDistanceBlock(block: string): ParsedBlock | null {
  const m = normalizeBlock(block).match(
    /^(\d+(?:\.\d+)?)\s*(k|km|m)(?:\s+(.+))?$/i,
  );
  if (!m) return null;
  const distM = parseDistanceMeters(Number(m[1]), m[2]);
  const paceRaw = m[3]?.trim();
  const target = paceRaw ? { pace: parsePaceSpec(paceRaw) } : null;
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
  const main = buildDistanceSegment("main", block.distanceM, block.target);
  const inner: Array<Record<string, unknown>> = [main];
  if (block.recoveryM != null && block.recoveryM > 0) {
    inner.push(
      block.recoverySec != null
        ? buildDurationSegment("recovery", block.recoverySec, null)
        : buildDistanceSegment("recovery", block.recoveryM, null),
    );
  } else if (block.recoverySec != null && block.recoverySec > 0) {
    inner.push(buildDurationSegment("recovery", block.recoverySec, null));
  }
  if (inner.length === 1 && block.repeat > 1) {
    return [{ type: "repeat", repeat_count: block.repeat, steps: [main] }];
  }
  return [{ type: "repeat", repeat_count: block.repeat, steps: inner }];
}

const WARMUP_LABEL = "(ısınma|isinma|warmup|warm-up|warm\\s+up)";
const COOLDOWN_LABEL = "(soğuma|soguma|cooldown|cool-down|cool\\s+down)";

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

  const chainParts = splitChain(programContent);
  const allSteps: Array<Record<string, unknown>> = [];

  for (let i = 0; i < chainParts.length; i++) {
    const labeled = splitExplicitSegmentLabel(chainParts[i]!);
    const part = labeled.body;
    let block: ParsedBlock | null = parseIntervalBlock(part);
    if (!block) block = parseStandaloneRepBlock(part);
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
      if (block.repeat > 1 && block.recoveryM == null && block.recoverySec == null) {
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
