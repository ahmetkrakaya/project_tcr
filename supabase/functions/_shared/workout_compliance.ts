// Plan eşleştirici: o günün programındaki (monthly_program_entries.workout_definition)
// adımları aktivitenin turları / stream verisiyle hizalar ve uyum skorunu hesaplar.

import type { SupabaseClient } from './strava_client.ts';
import {
  indexAfterMovingSeconds,
  indexAtDistance,
  type IntervalSegment,
  segmentStats,
  type SegmentStats,
  type Streams,
} from './activity_metrics.ts';

type StepKind = 'warmup' | 'work' | 'rest' | 'cooldown';

interface TcrSegment {
  segment_type: string;
  target_type: string;
  target?: string;
  duration_seconds?: number;
  duration_seconds_min?: number;
  duration_seconds_max?: number;
  distance_meters?: number;
  pace_seconds_per_km?: number;
  pace_seconds_per_km_min?: number;
  pace_seconds_per_km_max?: number;
  custom_pace_seconds_per_km?: number;
  use_vdot_for_pace?: boolean;
  heart_rate_bpm_min?: number;
  heart_rate_bpm_max?: number;
  cadence_min?: number;
  cadence_max?: number;
}

interface TcrStep {
  type: string;
  segment?: TcrSegment;
  repeat_count?: number;
  steps?: TcrStep[];
}

interface VdotContext {
  vdot: number | null;
  offsetMin: number | null;
  offsetMax: number | null;
}

export interface FlatStep {
  index: number;
  kind: StepKind;
  segment_type: string;
  target_type: string;
  distance_meters: number | null;
  duration_seconds: number | null;
  pace_fast_seconds: number | null;
  pace_slow_seconds: number | null;
  hr_min: number | null;
  hr_max: number | null;
  cadence_min: number | null;
  cadence_max: number | null;
  rep: number | null;
  repeat_total: number | null;
}

export interface LapRow {
  lap_index: number;
  start_index: number | null;
  end_index: number | null;
  start_offset_seconds: number | null;
  elapsed_seconds: number | null;
  moving_seconds: number | null;
  distance_meters: number | null;
  average_pace_seconds: number | null;
  average_heart_rate: number | null;
  max_heart_rate: number | null;
  average_cadence: number | null;
}

// ---------- VDOT pace (garmin-push-workout ile aynı formül) ----------

function paceFromVdot(vdot: number, intensity: number): number {
  const vo2 = vdot * intensity;
  const a = 0.000104;
  const b = 0.182258;
  const c = -4.6 - vo2;
  const disc = b * b - 4 * a * c;
  if (disc < 0) return 0;
  const velocity = (-b + Math.sqrt(disc)) / (2 * a);
  return velocity > 0 ? (1000 / velocity) * 60 : 0;
}

function vdotPaceRange(ctx: VdotContext, segmentType: string): { fast: number; slow: number } | null {
  if (!ctx.vdot || ctx.vdot <= 0) return null;
  const threshold = Math.round(paceFromVdot(ctx.vdot, 0.88));
  if (threshold <= 0) return null;
  const lower = segmentType.toLowerCase();
  if (lower === 'main' && ctx.offsetMin != null && ctx.offsetMax != null) {
    return { fast: threshold + ctx.offsetMin, slow: threshold + ctx.offsetMax };
  }
  if (['warmup', 'recovery', 'cooldown', 'main'].includes(lower)) {
    return { fast: threshold + 45, slow: threshold + 75 };
  }
  return null;
}

function resolvePaceRange(seg: TcrSegment, ctx: VdotContext): { fast: number; slow: number } | null {
  const target = seg.target ?? 'none';
  const hasPaceIntent = target === 'pace' || target === 'time' || seg.use_vdot_for_pace === true;

  if (hasPaceIntent && seg.use_vdot_for_pace === true) {
    const r = vdotPaceRange(ctx, seg.segment_type);
    if (r) return r;
  }

  const direct = seg.custom_pace_seconds_per_km ?? seg.pace_seconds_per_km ?? seg.pace_seconds_per_km_min;
  if (direct) {
    const slow = seg.pace_seconds_per_km_max ?? direct;
    return { fast: Math.min(direct, slow), slow: Math.max(direct, slow) };
  }

  // Split hedefi: "400 m (1:30)" → süre / mesafe
  if (seg.target_type === 'distance' && seg.distance_meters && seg.distance_meters > 0) {
    const km = seg.distance_meters / 1000;
    if (seg.duration_seconds_min != null && seg.duration_seconds_max != null) {
      const a = Math.round(seg.duration_seconds_min / km);
      const b = Math.round(seg.duration_seconds_max / km);
      return { fast: Math.min(a, b), slow: Math.max(a, b) };
    }
    if (seg.duration_seconds != null && target === 'time') {
      const p = Math.round(seg.duration_seconds / km);
      return { fast: p, slow: p };
    }
  }

  if (hasPaceIntent || (ctx.offsetMin != null && seg.segment_type === 'main')) {
    return vdotPaceRange(ctx, seg.segment_type);
  }
  return null;
}

function kindOf(segmentType: string): StepKind {
  switch (segmentType.toLowerCase()) {
    case 'warmup':
      return 'warmup';
    case 'cooldown':
      return 'cooldown';
    case 'recovery':
      return 'rest';
    default:
      return 'work';
  }
}

export function flattenWorkout(definition: any, ctx: VdotContext): FlatStep[] {
  const steps: TcrStep[] = Array.isArray(definition)
    ? definition
    : Array.isArray(definition?.steps)
      ? definition.steps
      : [];
  const out: FlatStep[] = [];

  const walk = (list: TcrStep[], rep: number | null, total: number | null) => {
    for (const step of list) {
      if (step.type === 'segment' && step.segment) {
        const seg = step.segment;
        const pace = resolvePaceRange(seg, ctx);
        const isDistance = seg.target_type === 'distance';
        const isDuration = seg.target_type === 'duration';
        out.push({
          index: out.length,
          kind: kindOf(seg.segment_type),
          segment_type: seg.segment_type,
          target_type: seg.target_type,
          distance_meters: isDistance ? seg.distance_meters ?? null : null,
          duration_seconds: isDuration ? seg.duration_seconds ?? seg.duration_seconds_max ?? null : null,
          pace_fast_seconds: pace?.fast ?? null,
          pace_slow_seconds: pace?.slow ?? null,
          hr_min: seg.heart_rate_bpm_min ?? null,
          hr_max: seg.heart_rate_bpm_max ?? null,
          cadence_min: seg.cadence_min ?? null,
          cadence_max: seg.cadence_max ?? null,
          rep,
          repeat_total: total,
        });
      } else if (step.type === 'repeat' && Array.isArray(step.steps) && (step.repeat_count ?? 0) > 0) {
        for (let r = 1; r <= step.repeat_count!; r++) walk(step.steps, r, step.repeat_count!);
      }
    }
  };
  walk(steps, null, null);
  return out;
}

// ---------- Planlanan antrenmanı bul ----------

export async function findPlannedEntry(
  supabase: SupabaseClient,
  userId: string,
  planDate: string,
): Promise<{ entry: any; ctx: VdotContext } | null> {
  const [{ data: memberships }, { data: user }] = await Promise.all([
    supabase.from('group_members').select('group_id').eq('user_id', userId),
    supabase.from('users').select('vdot').eq('id', userId).maybeSingle(),
  ]);
  const groupIds = (memberships ?? []).map((m: any) => m.group_id);

  const { data: rows } = await supabase
    .from('monthly_program_entries')
    .select(
      'id, plan_date, scope_type, training_group_id, user_id, workout_definition, sort_order, training_types(threshold_offset_min_seconds, threshold_offset_max_seconds)',
    )
    .eq('plan_date', planDate)
    .not('workout_definition', 'is', null)
    .order('sort_order', { ascending: true });

  const candidates = (rows ?? []).filter(
    (r: any) =>
      (r.scope_type === 'member' && r.user_id === userId) ||
      (r.scope_type === 'group' && groupIds.includes(r.training_group_id)),
  );
  if (candidates.length === 0) return null;
  const entry = candidates.find((r: any) => r.scope_type === 'member') ?? candidates[0];
  const tt = Array.isArray(entry.training_types) ? entry.training_types[0] : entry.training_types;

  return {
    entry,
    ctx: {
      vdot: user?.vdot != null ? Number(user.vdot) : null,
      offsetMin: tt?.threshold_offset_min_seconds ?? null,
      offsetMax: tt?.threshold_offset_max_seconds ?? null,
    },
  };
}

// ---------- Hizalama ----------

function lapToStats(lap: LapRow, streams: Streams | null): SegmentStats {
  if (streams && lap.start_index != null && lap.end_index != null) {
    return segmentStats(streams, lap.start_index, lap.end_index);
  }
  return {
    start_index: lap.start_index ?? 0,
    end_index: lap.end_index ?? 0,
    start_offset_seconds: lap.start_offset_seconds ?? 0,
    elapsed_seconds: lap.elapsed_seconds ?? 0,
    moving_seconds: lap.moving_seconds ?? 0,
    distance_meters: lap.distance_meters ?? 0,
    average_pace_seconds: lap.average_pace_seconds,
    average_heart_rate: lap.average_heart_rate,
    max_heart_rate: lap.max_heart_rate,
    average_cadence: lap.average_cadence,
  };
}

function alignByLaps(steps: FlatStep[], laps: LapRow[], streams: Streams | null): (SegmentStats | null)[] | null {
  let usable = laps;
  const last = usable[usable.length - 1];
  if (usable.length === steps.length + 1 && last && ((last.distance_meters ?? 0) < 60 || (last.elapsed_seconds ?? 0) < 20)) {
    usable = usable.slice(0, -1);
  }
  if (usable.length !== steps.length || steps.length < 2) return null;
  return usable.map((l) => lapToStats(l, streams));
}

function alignByIntervals(steps: FlatStep[], segments: IntervalSegment[], streams: Streams): (SegmentStats | null)[] | null {
  const workSteps = steps.filter((s) => s.kind === 'work').length;
  const works = segments.filter((s) => s.kind === 'work');
  if (workSteps < 2 || works.length !== workSteps) return null;

  const firstWorkSeg = segments.findIndex((s) => s.kind === 'work');
  const lastWorkSeg = segments.map((s) => s.kind).lastIndexOf('work');
  const result: (SegmentStats | null)[] = [];
  const lastIndex = streams.time.length - 1;
  let tailStart = segments[lastWorkSeg].end_index;
  let workNo = 0;

  for (const step of steps) {
    if (step.kind === 'work') {
      result.push(works[workNo] ?? null);
      workNo++;
    } else if (step.kind === 'rest') {
      // Son çalışmadan sonraki dinlenme bölümü
      const prevWork = works[workNo - 1];
      const segIdx = prevWork ? segments.indexOf(prevWork) + 1 : -1;
      const seg = segIdx > 0 && segIdx < segments.length && segments[segIdx].kind === 'rest' ? segments[segIdx] : null;
      if (seg || workNo < workSteps) {
        result.push(seg);
        continue;
      }
      // Son tekrardan sonraki dinlenme soğumayla aynı tempoda olduğundan ayrı bölüm olarak tespit edilmez;
      // planlanan mesafe/süre kadarı soğumadan ayrılır.
      let end: number | null = null;
      if (step.distance_meters != null && streams.distance) {
        end = indexAtDistance(streams, streams.distance[tailStart] + step.distance_meters, tailStart);
      } else if (step.duration_seconds != null) {
        end = indexAfterMovingSeconds(streams, tailStart, step.duration_seconds);
      }
      if (end == null || end <= tailStart) {
        result.push(null);
        continue;
      }
      result.push(segmentStats(streams, tailStart, end));
      tailStart = end;
    } else if (step.kind === 'warmup') {
      const end = segments[firstWorkSeg].start_index;
      result.push(end > 0 ? segmentStats(streams, 0, end) : null);
    } else {
      result.push(tailStart < lastIndex ? segmentStats(streams, tailStart, lastIndex) : null);
    }
  }
  return result;
}

function alignByStream(steps: FlatStep[], streams: Streams): (SegmentStats | null)[] {
  const n = streams.time.length;
  const totalDistance = streams.distance ? streams.distance[n - 1] : 0;
  const openSteps = steps.filter((s) => s.distance_meters == null && s.duration_seconds == null);

  // Açık adımlar (ör. "ısınma") kalan mesafeyi paylaşır
  let definedDistance = 0;
  for (const s of steps) {
    if (s.distance_meters != null) definedDistance += s.distance_meters;
    else if (s.duration_seconds != null && s.pace_slow_seconds) {
      definedDistance += (s.duration_seconds / s.pace_slow_seconds) * 1000;
    }
  }
  const openShare = openSteps.length > 0 ? Math.max(0, totalDistance - definedDistance) / openSteps.length : 0;

  const result: (SegmentStats | null)[] = [];
  let cursor = 0;
  for (const step of steps) {
    if (cursor >= n - 1) {
      result.push(null);
      continue;
    }
    let end: number;
    if (step.distance_meters != null) {
      const startDist = streams.distance ? streams.distance[cursor] : 0;
      end = indexAtDistance(streams, startDist + step.distance_meters, cursor);
    } else if (step.duration_seconds != null) {
      end = indexAfterMovingSeconds(streams, cursor, step.duration_seconds);
    } else if (openShare > 0 && streams.distance) {
      end = indexAtDistance(streams, streams.distance[cursor] + openShare, cursor);
    } else {
      result.push(null);
      continue;
    }
    result.push(segmentStats(streams, cursor, end));
    cursor = end;
  }
  return result;
}

// ---------- Değerlendirme ----------

type Status = 'ok' | 'warn' | 'miss' | 'done' | 'skipped';

function evaluateStep(step: FlatStep, actual: SegmentStats | null) {
  if (!actual || (actual.distance_meters < 10 && actual.elapsed_seconds < 5)) {
    return { status: 'skipped' as Status, completion_pct: 0, pace_delta_seconds: null, hr_status: null };
  }

  let completion: number | null = null;
  if (step.distance_meters) completion = actual.distance_meters / step.distance_meters;
  else if (step.duration_seconds) completion = (actual.moving_seconds || actual.elapsed_seconds) / step.duration_seconds;

  let status: Status = 'done';
  let paceDelta: number | null = null;
  const pace = actual.average_pace_seconds;
  if (step.pace_fast_seconds != null && step.pace_slow_seconds != null && pace != null) {
    const tol = Math.max(3, Math.round(step.pace_slow_seconds * 0.02));
    if (pace < step.pace_fast_seconds) paceDelta = pace - step.pace_fast_seconds;
    else if (pace > step.pace_slow_seconds) paceDelta = pace - step.pace_slow_seconds;
    else paceDelta = 0;
    const off = Math.abs(paceDelta);
    status = off <= tol ? 'ok' : off <= tol * 3 ? 'warn' : 'miss';
  }

  let hrStatus: Status | null = null;
  if ((step.hr_min != null || step.hr_max != null) && actual.average_heart_rate != null) {
    const lo = step.hr_min ?? 0;
    const hi = step.hr_max ?? 250;
    const hr = actual.average_heart_rate;
    const off = hr < lo ? lo - hr : hr > hi ? hr - hi : 0;
    hrStatus = off <= 2 ? 'ok' : off <= 6 ? 'warn' : 'miss';
    if (status === 'done') status = hrStatus;
  }

  if (completion != null && completion < 0.9) status = 'miss';

  return {
    status,
    completion_pct: completion != null ? Math.round(completion * 1000) / 10 : null,
    pace_delta_seconds: paceDelta,
    hr_status: hrStatus,
  };
}

export interface ComplianceInput {
  activityId: string;
  userId: string;
  /** activities.start_time (yerel saat UTC olarak yazılı) */
  startTime: string;
  activityType: string;
  streams: Streams | null;
  laps: LapRow[];
  segments: IntervalSegment[] | null;
}

/** Programı bulur, hizalar, sonucu yazar. Program yoksa false döner. */
export async function computeAndSaveCompliance(supabase: SupabaseClient, input: ComplianceInput): Promise<boolean> {
  if (input.activityType !== 'running') return false;
  const planDate = input.startTime.slice(0, 10);
  const planned = await findPlannedEntry(supabase, input.userId, planDate);

  if (!planned) {
    await supabase.from('activity_workout_compliance').delete().eq('activity_id', input.activityId);
    await supabase.from('activities').update({ planned_entry_id: null }).eq('id', input.activityId);
    return false;
  }

  const steps = flattenWorkout(planned.entry.workout_definition, planned.ctx);
  if (steps.length === 0) return false;

  let method: 'laps' | 'intervals' | 'stream' | null = null;
  let aligned = alignByLaps(steps, input.laps, input.streams);
  if (aligned) method = 'laps';
  if (!aligned && input.streams && input.segments) {
    aligned = alignByIntervals(steps, input.segments, input.streams);
    if (aligned) method = 'intervals';
  }
  if (!aligned && input.streams) {
    aligned = alignByStream(steps, input.streams);
    method = 'stream';
  }
  if (!aligned) return false;

  const evaluated = steps.map((step, i) => {
    const actual = aligned![i];
    const ev = evaluateStep(step, actual);
    return {
      index: step.index,
      kind: step.kind,
      segment_type: step.segment_type,
      rep: step.rep,
      repeat_total: step.repeat_total,
      target: {
        target_type: step.target_type,
        distance_meters: step.distance_meters,
        duration_seconds: step.duration_seconds,
        pace_fast_seconds: step.pace_fast_seconds,
        pace_slow_seconds: step.pace_slow_seconds,
        hr_min: step.hr_min,
        hr_max: step.hr_max,
        cadence_min: step.cadence_min,
        cadence_max: step.cadence_max,
      },
      actual,
      ...ev,
    };
  });

  const scoreValue = (s: Status) => (s === 'ok' || s === 'done' ? 1 : s === 'warn' ? 0.5 : 0);
  const scored = evaluated.filter((e) => e.kind === 'work' || e.kind === 'rest');
  const base = scored.length > 0 ? scored : evaluated;
  const score = Math.round((base.reduce((a, e) => a + scoreValue(e.status), 0) / base.length) * 1000) / 10;
  const work = evaluated.filter((e) => e.kind === 'work');
  const completedReps = work.filter((e) => e.status !== 'skipped' && (e.completion_pct == null || e.completion_pct >= 90)).length;

  const { error } = await supabase.from('activity_workout_compliance').upsert({
    activity_id: input.activityId,
    planned_entry_id: planned.entry.id,
    match_method: method,
    steps: evaluated,
    score,
    completed_reps: completedReps,
    planned_reps: work.length,
    computed_at: new Date().toISOString(),
  });
  if (error) throw error;

  await supabase.from('activities').update({ planned_entry_id: planned.entry.id }).eq('id', input.activityId);

  if (method === 'laps') {
    const usable = input.laps.slice(0, steps.length);
    for (let i = 0; i < usable.length; i++) {
      await supabase
        .from('activity_laps')
        .update({ kind: steps[i].kind })
        .eq('activity_id', input.activityId)
        .eq('lap_index', usable[i].lap_index);
    }
  }
  return true;
}
