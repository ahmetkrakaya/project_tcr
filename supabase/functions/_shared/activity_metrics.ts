// Stream verisinden türetilmiş koşu metrikleri.
// Kaynaktan bağımsızdır: Strava dışında bir kaynak da aynı Streams yapısını doldurup kullanabilir.

export interface Streams {
  time: number[];
  distance?: number[];
  altitude?: number[];
  velocity?: number[];
  heartrate?: number[];
  /** adım/dakika */
  cadence?: number[];
  watts?: number[];
  temp?: number[];
  moving?: boolean[];
  /** yüzde */
  grade?: number[];
}

export interface SegmentStats {
  start_index: number;
  end_index: number;
  start_offset_seconds: number;
  elapsed_seconds: number;
  moving_seconds: number;
  distance_meters: number;
  average_pace_seconds: number | null;
  average_heart_rate: number | null;
  max_heart_rate: number | null;
  average_cadence: number | null;
}

export interface IntervalSegment extends SegmentStats {
  kind: 'warmup' | 'work' | 'rest' | 'cooldown';
}

export interface LapLike {
  lap_index: number;
  distance_meters: number | null;
  moving_seconds: number | null;
  elapsed_seconds: number | null;
  average_speed: number | null;
  start_index: number | null;
  end_index: number | null;
}

export interface SplitLike {
  split_number: number;
  distance_meters: number | null;
  duration_seconds: number | null;
  pace_seconds: number | null;
  gap_pace_seconds: number | null;
}

export interface MetricsContext {
  thresholdPaceSeconds: number | null;
  birthDate: string | null;
  gender: string | null;
  /** Strava /athlete/zones heart_rate.zones */
  athleteHrZones: { min: number; max: number }[] | null;
  movingSeconds: number | null;
  elapsedSeconds: number | null;
  averageHeartRate: number | null;
  splits: SplitLike[];
  laps: LapLike[];
}

export interface MetricsResult {
  row: Record<string, unknown>;
  splitUpdates: { split_number: number; gap_pace_seconds: number | null; average_cadence: number | null }[];
  lapKinds: Map<number, 'warmup' | 'work' | 'rest' | 'cooldown' | 'auto'>;
  segments: IntervalSegment[] | null;
}

const MOVING_SPEED = 0.5;
const MAX_DT = 30;

// ---------- Stream normalizasyonu ----------

/** Strava key_by_type=true yanıtını Streams yapısına çevirir (kadans RPM → SPM). */
export function normalizeStravaStreams(raw: any, activityType: string): Streams | null {
  const get = (k: string): any[] | undefined => (Array.isArray(raw?.[k]?.data) ? raw[k].data : undefined);
  const time = get('time');
  if (!time || time.length < 2) return null;
  const cadenceRaw = get('cadence');
  const cadMul = activityType === 'running' || activityType === 'walking' ? 2 : 1;
  return {
    time,
    distance: get('distance'),
    altitude: get('altitude'),
    velocity: get('velocity_smooth'),
    heartrate: get('heartrate'),
    cadence: cadenceRaw?.map((c: number) => (c == null ? c : Math.round(c * cadMul))),
    watts: get('watts'),
    temp: get('temp'),
    moving: get('moving'),
    grade: get('grade_smooth'),
  };
}

function dtAt(s: Streams, i: number): number {
  if (i === 0) return 0;
  const dt = s.time[i] - s.time[i - 1];
  return dt > 0 && dt <= MAX_DT ? dt : 0;
}

function isMoving(s: Streams, i: number): boolean {
  if (s.moving) return s.moving[i] === true;
  if (s.velocity) return (s.velocity[i] ?? 0) > MOVING_SPEED;
  return true;
}

function speedAt(s: Streams, i: number): number | null {
  if (s.velocity) return s.velocity[i] ?? null;
  if (s.distance && i > 0) {
    const dt = s.time[i] - s.time[i - 1];
    return dt > 0 ? (s.distance[i] - s.distance[i - 1]) / dt : null;
  }
  return null;
}

function paceFromSpeed(v: number | null | undefined): number | null {
  if (!v || v <= MOVING_SPEED) return null;
  return Math.round(1000 / v);
}

// ---------- Preview ----------

/** ~target noktalık, bucket ortalamalı çizim serisi. */
export function buildPreview(s: Streams, target = 500): Record<string, unknown> {
  const n = s.time.length;
  const bucket = Math.max(1, Math.ceil(n / target));
  const out: Record<string, (number | null)[]> = { t: [], d: [], pace: [], hr: [], alt: [], cad: [], w: [], grade: [] };

  const avg = (arr: number[] | undefined, a: number, b: number, digits = 0): number | null => {
    if (!arr) return null;
    let sum = 0;
    let cnt = 0;
    for (let i = a; i < b; i++) {
      const v = arr[i];
      if (v != null && Number.isFinite(v)) {
        sum += v;
        cnt++;
      }
    }
    if (cnt === 0) return null;
    const f = 10 ** digits;
    return Math.round((sum / cnt) * f) / f;
  };

  for (let a = 0; a < n; a += bucket) {
    const b = Math.min(n, a + bucket);
    const last = b - 1;
    out.t.push(s.time[last]);
    out.d.push(s.distance ? Math.round(s.distance[last]) : null);
    let movingCount = 0;
    for (let i = a; i < b; i++) if (isMoving(s, i)) movingCount++;
    const v = avg(s.velocity, a, b, 3);
    out.pace.push(movingCount * 2 >= b - a ? paceFromSpeed(v) : null);
    out.hr.push(avg(s.heartrate, a, b));
    out.alt.push(avg(s.altitude, a, b, 1));
    out.cad.push(avg(s.cadence, a, b));
    out.w.push(avg(s.watts, a, b));
    out.grade.push(avg(s.grade, a, b, 1));
  }

  const preview: Record<string, unknown> = { t: out.t };
  for (const k of ['d', 'pace', 'hr', 'alt', 'cad', 'w', 'grade']) {
    if (out[k].some((v) => v != null)) preview[k] = out[k];
  }
  return preview;
}

// ---------- Segment istatistikleri ----------

export function segmentStats(s: Streams, i0: number, i1: number): SegmentStats {
  const start = Math.max(0, Math.min(i0, s.time.length - 1));
  const end = Math.max(start, Math.min(i1, s.time.length - 1));
  let moving = 0;
  let hrSum = 0;
  let hrTime = 0;
  let hrMax: number | null = null;
  let cadSum = 0;
  let cadTime = 0;
  for (let i = start + 1; i <= end; i++) {
    const dt = dtAt(s, i);
    if (!isMoving(s, i)) continue;
    moving += dt;
    const hr = s.heartrate?.[i];
    if (hr != null && hr > 0) {
      hrSum += hr * dt;
      hrTime += dt;
      hrMax = hrMax == null ? hr : Math.max(hrMax, hr);
    }
    const cad = s.cadence?.[i];
    if (cad != null && cad > 0) {
      cadSum += cad * dt;
      cadTime += dt;
    }
  }
  const distance = s.distance ? Math.max(0, s.distance[end] - s.distance[start]) : 0;
  const timeBase = moving > 0 ? moving : s.time[end] - s.time[start];
  return {
    start_index: start,
    end_index: end,
    start_offset_seconds: Math.round(s.time[start] - s.time[0]),
    elapsed_seconds: Math.round(s.time[end] - s.time[start]),
    moving_seconds: Math.round(moving),
    distance_meters: Math.round(distance * 10) / 10,
    average_pace_seconds: distance >= 20 && timeBase > 0 ? Math.round(timeBase / (distance / 1000)) : null,
    average_heart_rate: hrTime > 0 ? Math.round(hrSum / hrTime) : null,
    max_heart_rate: hrMax,
    average_cadence: cadTime > 0 ? Math.round(cadSum / cadTime) : null,
  };
}

/** Kümülatif mesafe için ilk index (>= meters). */
export function indexAtDistance(s: Streams, meters: number, from = 0): number {
  if (!s.distance) return s.time.length - 1;
  for (let i = Math.max(0, from); i < s.distance.length; i++) {
    if (s.distance[i] >= meters) return i;
  }
  return s.distance.length - 1;
}

/** Başlangıçtan itibaren hareketli süre için ilk index (>= seconds). */
export function indexAfterMovingSeconds(s: Streams, from: number, seconds: number): number {
  let acc = 0;
  for (let i = from + 1; i < s.time.length; i++) {
    acc += isMoving(s, i) ? dtAt(s, i) : 0;
    if (acc >= seconds) return i;
  }
  return s.time.length - 1;
}

// ---------- Nabız / pace parametreleri ----------

function ageFrom(birthDate: string | null): number | null {
  if (!birthDate) return null;
  const b = new Date(birthDate);
  if (Number.isNaN(b.getTime())) return null;
  const now = new Date();
  let age = now.getUTCFullYear() - b.getUTCFullYear();
  const m = now.getUTCMonth() - b.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < b.getUTCDate())) age--;
  return age > 5 && age < 100 ? age : null;
}

function resolveMaxHr(ctx: MetricsContext, s: Streams): { maxHr: number; source: string } {
  const zones = ctx.athleteHrZones;
  if (zones && zones.length >= 5) {
    // Strava zon 5 alt sınırı ≈ %90 HRmax
    const z5min = zones[4]?.min;
    if (z5min && z5min > 100) return { maxHr: Math.round(z5min / 0.9), source: 'strava_zones' };
  }
  const age = ageFrom(ctx.birthDate);
  let observed = 0;
  for (const v of s.heartrate ?? []) {
    if (v != null && v < 230 && v > observed) observed = v;
  }
  if (age != null) {
    const tanaka = Math.round(208 - 0.7 * age);
    return { maxHr: Math.max(tanaka, observed), source: 'tanaka' };
  }
  return { maxHr: Math.max(190, observed), source: 'default' };
}

function hrZoneBounds(ctx: MetricsContext, maxHr: number): { min: number; max: number }[] {
  if (ctx.athleteHrZones && ctx.athleteHrZones.length >= 5) {
    return ctx.athleteHrZones.map((z) => ({ min: z.min, max: z.max === -1 ? 999 : z.max }));
  }
  const p = [0, 0.6, 0.7, 0.8, 0.9];
  return p.map((pct, i) => ({
    min: Math.round(maxHr * pct),
    max: i < p.length - 1 ? Math.round(maxHr * p[i + 1]) - 1 : 999,
  }));
}

const PACE_ZONES: { name: string; slow: number; fast: number }[] = [
  { name: 'Toparlanma', slow: Infinity, fast: 1.29 },
  { name: 'Aerobik', slow: 1.29, fast: 1.14 },
  { name: 'Tempo', slow: 1.14, fast: 1.06 },
  { name: 'Eşik', slow: 1.06, fast: 0.99 },
  { name: 'VO2max', slow: 0.99, fast: 0.9 },
  { name: 'Anaerobik', slow: 0.9, fast: 0 },
];

/** Minetti eğim maliyeti (J/kg/m); düz zemin 3.6. */
function minettiCost(gradePct: number): number {
  const i = Math.max(-0.45, Math.min(0.45, gradePct / 100));
  return 155.4 * i ** 5 - 30.4 * i ** 4 - 43.3 * i ** 3 + 46.3 * i ** 2 + 19.5 * i + 3.6;
}

// ---------- Interval tespiti ----------

function percentile(values: number[], p: number): number {
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.round((sorted.length - 1) * p)));
  return sorted[idx];
}

function looksLikeAutoLaps(laps: LapLike[]): boolean {
  if (laps.length < 2) return true;
  const full = laps.slice(0, -1);
  return [1000, 1609.34].some((target) =>
    full.every((l) => l.distance_meters != null && Math.abs(l.distance_meters - target) / target < 0.03),
  );
}

/** Tur hızlarından çalışma/dinlenme sınıflandırması. Anlamlı fark yoksa null. */
export function classifyLaps(laps: LapLike[]): Map<number, 'warmup' | 'work' | 'rest' | 'cooldown' | 'auto'> | null {
  const result = new Map<number, 'warmup' | 'work' | 'rest' | 'cooldown' | 'auto'>();
  if (laps.length < 3) return null;
  if (looksLikeAutoLaps(laps)) {
    for (const l of laps) result.set(l.lap_index, 'auto');
    return result;
  }
  const speeds = laps.map((l) => l.average_speed ?? 0).filter((v) => v > 0);
  if (speeds.length < 3) return null;
  const lo = percentile(speeds, 0.2);
  const hi = percentile(speeds, 0.85);
  if (lo <= 0 || hi / lo < 1.15) return null;
  const threshold = (lo + hi) / 2;
  const isWork = laps.map((l) => (l.average_speed ?? 0) > threshold);
  const firstWork = isWork.indexOf(true);
  const lastWork = isWork.lastIndexOf(true);
  if (firstWork < 0) return null;
  laps.forEach((l, i) => {
    if (isWork[i]) result.set(l.lap_index, 'work');
    else if (i < firstWork) result.set(l.lap_index, 'warmup');
    else if (i > lastWork) result.set(l.lap_index, 'cooldown');
    else result.set(l.lap_index, 'rest');
  });
  return result;
}

/** Hız serisinden çalışma/dinlenme bölümleri. En az 3 çalışma bölümü yoksa null. */
export function detectIntervals(s: Streams): IntervalSegment[] | null {
  const n = s.time.length;
  if (n < 120) return null;
  const raw = s.velocity ?? s.time.map((_, i) => speedAt(s, i) ?? 0);
  const win = 7;
  const smooth = raw.map((_, i) => {
    let sum = 0;
    let cnt = 0;
    for (let j = Math.max(0, i - win); j <= Math.min(n - 1, i + win); j++) {
      sum += raw[j] ?? 0;
      cnt++;
    }
    return cnt ? sum / cnt : 0;
  });
  const movingSpeeds = smooth.filter((v, i) => isMoving(s, i) && v > MOVING_SPEED);
  if (movingSpeeds.length < 60) return null;
  const lo = percentile(movingSpeeds, 0.2);
  const hi = percentile(movingSpeeds, 0.85);
  if (lo <= 0 || hi / lo < 1.25) return null;
  const threshold = (lo + hi) / 2;

  type Run = { work: boolean; a: number; b: number };
  const runs: Run[] = [];
  for (let i = 0; i < n; i++) {
    const work = smooth[i] > threshold;
    const last = runs[runs.length - 1];
    if (last && last.work === work) last.b = i;
    else runs.push({ work, a: i, b: i });
  }
  const dur = (r: Run) => s.time[r.b] - s.time[r.a];

  // Kısa dinlenmeleri birleştir, kısa çalışmaları dinlenmeye çevir
  const merge = (list: Run[]): Run[] => {
    const out: Run[] = [];
    for (const r of list) {
      const last = out[out.length - 1];
      if (last && last.work === r.work) last.b = r.b;
      else out.push({ ...r });
    }
    return out;
  };
  let merged = merge(runs.map((r) => (!r.work && dur(r) < 8 ? { ...r, work: true } : r)));
  merged = merge(merged.map((r) => (r.work && dur(r) < 20 ? { ...r, work: false } : r)));

  const workCount = merged.filter((r) => r.work).length;
  if (workCount < 3) return null;

  const firstWork = merged.findIndex((r) => r.work);
  let lastWork = -1;
  merged.forEach((r, i) => {
    if (r.work) lastWork = i;
  });

  return merged.map((r, i) => {
    const kind: IntervalSegment['kind'] = r.work
      ? 'work'
      : i < firstWork
        ? 'warmup'
        : i > lastWork
          ? 'cooldown'
          : 'rest';
    return { kind, ...segmentStats(s, r.a, r.b) };
  });
}

// ---------- Ana hesaplama ----------

export function computeMetrics(s: Streams, ctx: MetricsContext): MetricsResult {
  const n = s.time.length;
  const { maxHr, source: maxHrSource } = resolveMaxHr(ctx, s);
  const restHr = 60;
  const female = ctx.gender === 'female';
  const zones = hrZoneBounds(ctx, maxHr);
  const hrZoneSeconds = zones.map(() => 0);
  const threshold = ctx.thresholdPaceSeconds && ctx.thresholdPaceSeconds > 0 ? ctx.thresholdPaceSeconds : null;
  const paceZoneSeconds = PACE_ZONES.map(() => 0);

  let movingTime = 0;
  let movingDistance = 0;
  let eqDistance = 0;
  let hasGrade = false;
  let trimp = 0;
  let steps = 0;
  let stopCount = 0;
  let stoppedSeconds = 0;
  let stopRun = 0;

  for (let i = 1; i < n; i++) {
    const dt = dtAt(s, i);
    const moving = isMoving(s, i);
    if (!moving) {
      stoppedSeconds += s.time[i] - s.time[i - 1];
      stopRun += s.time[i] - s.time[i - 1];
      continue;
    }
    if (stopRun >= 5) stopCount++;
    stopRun = 0;
    if (dt === 0) continue;

    movingTime += dt;
    const v = speedAt(s, i) ?? 0;
    const segDist = s.distance ? Math.max(0, s.distance[i] - s.distance[i - 1]) : v * dt;
    movingDistance += segDist;

    const g = s.grade?.[i];
    if (g != null) {
      hasGrade = true;
      eqDistance += segDist * (minettiCost(g) / 3.6);
    } else {
      eqDistance += segDist;
    }

    const hr = s.heartrate?.[i];
    if (hr != null && hr > 0) {
      const zi = zones.findIndex((z) => hr >= z.min && hr <= z.max);
      hrZoneSeconds[zi >= 0 ? zi : hr < zones[0].min ? 0 : zones.length - 1] += dt;
      const hrr = Math.max(0, Math.min(1, (hr - restHr) / (maxHr - restHr)));
      trimp += (dt / 60) * hrr * (female ? 0.86 * Math.exp(1.67 * hrr) : 0.64 * Math.exp(1.92 * hrr));
    }

    if (threshold && v > MOVING_SPEED) {
      const ratio = 1000 / v / threshold;
      const zi = PACE_ZONES.findIndex((z) => ratio <= z.slow && ratio > z.fast);
      paceZoneSeconds[zi >= 0 ? zi : PACE_ZONES.length - 1] += dt;
    }

    const cad = s.cadence?.[i];
    if (cad != null && cad > 0) steps += (cad / 60) * dt;
  }
  if (stopRun >= 5) stopCount++;

  const gapPace = hasGrade && eqDistance > 100 ? Math.round(movingTime / (eqDistance / 1000)) : null;
  const avgPace = movingDistance > 100 ? Math.round(movingTime / (movingDistance / 1000)) : null;

  // Decoupling + HR drift (hareketli sürenin yarıları)
  let decoupling: number | null = null;
  let hrDrift: number | null = null;
  if (s.heartrate && movingTime >= 1200) {
    const half = movingTime / 2;
    const acc = [
      { t: 0, d: 0, hr: 0, hrt: 0 },
      { t: 0, d: 0, hr: 0, hrt: 0 },
    ];
    let elapsedMoving = 0;
    for (let i = 1; i < n; i++) {
      const dt = dtAt(s, i);
      if (!isMoving(s, i) || dt === 0) continue;
      elapsedMoving += dt;
      const h = elapsedMoving <= half ? 0 : 1;
      const segDist = s.distance ? Math.max(0, s.distance[i] - s.distance[i - 1]) : (speedAt(s, i) ?? 0) * dt;
      acc[h].t += dt;
      acc[h].d += segDist;
      const hr = s.heartrate[i];
      if (hr != null && hr > 0) {
        acc[h].hr += hr * dt;
        acc[h].hrt += dt;
      }
    }
    if (acc[0].hrt > 0 && acc[1].hrt > 0 && acc[0].t > 0 && acc[1].t > 0) {
      const hr1 = acc[0].hr / acc[0].hrt;
      const hr2 = acc[1].hr / acc[1].hrt;
      const ef1 = acc[0].d / acc[0].t / hr1;
      const ef2 = acc[1].d / acc[1].t / hr2;
      decoupling = Math.round(((ef1 - ef2) / ef1) * 1000) / 10;
      hrDrift = Math.round(((hr2 - hr1) / hr1) * 1000) / 10;
    }
  }

  // Yarı mesafe pace karşılaştırması
  let firstHalfPace: number | null = null;
  let secondHalfPace: number | null = null;
  let splitType: string | null = null;
  if (s.distance && movingDistance > 1000) {
    const total = s.distance[n - 1];
    const mid = indexAtDistance(s, total / 2);
    const a = segmentStats(s, 0, mid);
    const b = segmentStats(s, mid, n - 1);
    firstHalfPace = a.average_pace_seconds;
    secondHalfPace = b.average_pace_seconds;
    if (firstHalfPace && secondHalfPace) {
      const diff = (secondHalfPace - firstHalfPace) / firstHalfPace;
      splitType = diff < -0.01 ? 'negative' : diff > 0.01 ? 'positive' : 'even';
    }
  }

  // Km split istikrarı + split başına GAP / kadans
  const fullSplits = ctx.splits.filter((sp) => (sp.distance_meters ?? 0) >= 900 && sp.pace_seconds);
  let paceCv: number | null = null;
  let fastestSplit: number | null = null;
  let slowestSplit: number | null = null;
  if (fullSplits.length >= 2) {
    const paces = fullSplits.map((sp) => sp.pace_seconds!);
    const mean = paces.reduce((a, b) => a + b, 0) / paces.length;
    const std = Math.sqrt(paces.reduce((a, b) => a + (b - mean) ** 2, 0) / paces.length);
    paceCv = Math.round((std / mean) * 1000) / 1000;
    fastestSplit = fullSplits.reduce((a, b) => (b.pace_seconds! < a.pace_seconds! ? b : a)).split_number;
    slowestSplit = fullSplits.reduce((a, b) => (b.pace_seconds! > a.pace_seconds! ? b : a)).split_number;
  }

  const splitUpdates: MetricsResult['splitUpdates'] = [];
  if (s.distance) {
    let cursor = 0;
    let startDist = 0;
    for (const sp of [...ctx.splits].sort((a, b) => a.split_number - b.split_number)) {
      const endDist = startDist + (sp.distance_meters ?? 1000);
      const i0 = indexAtDistance(s, startDist, cursor);
      const i1 = indexAtDistance(s, endDist, i0);
      let t = 0;
      let eq = 0;
      for (let i = i0 + 1; i <= i1; i++) {
        const dt = dtAt(s, i);
        if (!isMoving(s, i) || dt === 0) continue;
        t += dt;
        const seg = Math.max(0, s.distance[i] - s.distance[i - 1]);
        const g = s.grade?.[i];
        eq += g != null ? seg * (minettiCost(g) / 3.6) : seg;
      }
      const stats = segmentStats(s, i0, i1);
      splitUpdates.push({
        split_number: sp.split_number,
        gap_pace_seconds: sp.gap_pace_seconds ?? (hasGrade && eq > 50 ? Math.round(t / (eq / 1000)) : null),
        average_cadence: stats.average_cadence,
      });
      cursor = i1;
      startDist = endDist;
    }
  }

  // Tur sınıflandırması veya stream'den interval tespiti
  const lapKinds = classifyLaps(ctx.laps);
  const lapsInformative = lapKinds != null && [...lapKinds.values()].some((k) => k === 'work');
  let segments: IntervalSegment[] | null = null;
  if (lapsInformative) {
    segments = ctx.laps
      .filter((l) => l.start_index != null && l.end_index != null)
      .map((l) => ({
        kind: (lapKinds!.get(l.lap_index) ?? 'rest') as IntervalSegment['kind'],
        ...segmentStats(s, l.start_index!, l.end_index!),
      }));
  } else {
    segments = detectIntervals(s);
  }

  // Dinlenmede nabız düşüşü (60 sn veya dinlenme sonu)
  const hrRecovery: Record<string, unknown>[] = [];
  if (segments && s.heartrate) {
    let rep = 0;
    segments.forEach((seg, i) => {
      if (seg.kind === 'work') rep++;
      if (seg.kind !== 'rest' || segments![i - 1]?.kind !== 'work') return;
      const t0 = s.time[seg.start_index];
      let j = seg.start_index;
      while (j < seg.end_index && s.time[j] - t0 < 60) j++;
      const hrStart = s.heartrate![seg.start_index];
      const hrEnd = s.heartrate![j];
      if (hrStart && hrEnd) {
        hrRecovery.push({
          after_rep: rep,
          hr_start: hrStart,
          hr_end: hrEnd,
          seconds: Math.round(s.time[j] - t0),
          drop: hrStart - hrEnd,
        });
      }
    });
  }

  // TSS: eşik pace varsa GAP/pace tabanlı rTSS, yoksa hrTSS
  let tss: number | null = null;
  const hours = movingTime / 3600;
  const tssPace = gapPace ?? avgPace;
  if (threshold && tssPace) {
    const intensity = Math.min(threshold / tssPace, 1.5);
    tss = Math.round(intensity * intensity * hours * 1000) / 10;
  } else if (ctx.averageHeartRate) {
    const intensity = Math.min(ctx.averageHeartRate / (0.88 * maxHr), 1.3);
    tss = Math.round(intensity * intensity * hours * 1000) / 10;
  }

  const hasHr = hrZoneSeconds.some((v) => v > 0);
  const row: Record<string, unknown> = {
    hr_zones: hasHr
      ? zones.map((z, i) => ({ zone: i + 1, min: z.min, max: z.max === 999 ? -1 : z.max, seconds: Math.round(hrZoneSeconds[i]) }))
      : null,
    pace_zones: threshold && paceZoneSeconds.some((v) => v > 0)
      ? PACE_ZONES.map((z, i) => ({
          zone: i + 1,
          name: z.name,
          slow_pace_seconds: Number.isFinite(z.slow) ? Math.round(threshold * z.slow) : null,
          fast_pace_seconds: z.fast > 0 ? Math.round(threshold * z.fast) : null,
          seconds: Math.round(paceZoneSeconds[i]),
        }))
      : null,
    gap_pace_seconds: gapPace,
    decoupling_pct: decoupling,
    hr_drift_pct: hrDrift,
    trimp: hasHr ? Math.round(trimp * 10) / 10 : null,
    tss,
    stopped_seconds:
      ctx.elapsedSeconds != null && ctx.movingSeconds != null
        ? Math.max(0, ctx.elapsedSeconds - ctx.movingSeconds)
        : Math.round(stoppedSeconds),
    stop_count: stopCount,
    pace_cv: paceCv,
    split_type: splitType,
    first_half_pace_seconds: firstHalfPace,
    second_half_pace_seconds: secondHalfPace,
    fastest_split: fastestSplit,
    slowest_split: slowestSplit,
    average_stride_meters: steps > 50 ? Math.round((movingDistance / steps) * 100) / 100 : null,
    hr_recovery: hrRecovery.length > 0 ? hrRecovery : null,
    intervals: !lapsInformative && segments ? segments : null,
    assumptions: {
      max_hr: maxHr,
      max_hr_source: maxHrSource,
      rest_hr: restHr,
      threshold_pace_seconds: threshold,
      hr_zone_source: ctx.athleteHrZones && ctx.athleteHrZones.length >= 5 ? 'strava' : 'max_hr_percent',
    },
    computed_at: new Date().toISOString(),
  };

  return {
    row,
    splitUpdates,
    lapKinds: lapKinds ?? new Map(),
    segments,
  };
}
