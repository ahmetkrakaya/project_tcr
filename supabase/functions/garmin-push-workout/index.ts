import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GARMIN_CLIENT_ID = Deno.env.get("GARMIN_CLIENT_ID")!;
const GARMIN_CLIENT_SECRET = Deno.env.get("GARMIN_CLIENT_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const GARMIN_TOKEN_URL = "https://diauth.garmin.com/di-oauth2-service/oauth/token";
const GARMIN_WORKOUT_URL = "https://apis.garmin.com/workoutportal/workout/v2";
const GARMIN_SCHEDULE_URL = "https://apis.garmin.com/training-api/schedule/";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ---------- Token Refresh ----------

async function ensureValidToken(
  supabase: ReturnType<typeof createClient>,
  integration: any
): Promise<string> {
  const expiresAt = new Date(integration.token_expires_at);
  const now = new Date();
  const bufferMs = 600 * 1000;

  if (expiresAt.getTime() - now.getTime() > bufferMs) {
    return integration.access_token;
  }

  const res = await fetch(GARMIN_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      client_id: GARMIN_CLIENT_ID,
      client_secret: GARMIN_CLIENT_SECRET,
      refresh_token: integration.refresh_token,
    }).toString(),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Token refresh failed: ${res.status} ${errText}`);
  }

  const data = await res.json();
  const newExpiresAt = new Date(Date.now() + ((data.expires_in ?? 86400) - 600) * 1000).toISOString();

  await supabase
    .from("user_integrations")
    .update({
      access_token: data.access_token,
      refresh_token: data.refresh_token ?? integration.refresh_token,
      token_expires_at: newExpiresAt,
    })
    .eq("id", integration.id);

  return data.access_token;
}

// ---------- VDOT Pace Calculation (Dart VdotCalculator port) ----------

function calculatePaceFromVdot(vdot: number, intensityPercent: number): number {
  const vo2 = vdot * intensityPercent;
  const a = 0.000104;
  const b = 0.182258;
  const c = -4.60 - vo2;
  const discriminant = b * b - 4 * a * c;
  if (discriminant < 0) return 0;
  const velocity = (-b + Math.sqrt(discriminant)) / (2 * a); // m/min
  if (velocity <= 0) return 0;
  return (1000 / velocity) * 60; // saniye/km
}

function getThresholdPace(vdot: number): number {
  if (vdot <= 0) return 0;
  return Math.round(calculatePaceFromVdot(vdot, 0.88));
}

function getVdotPaceRange(
  vdot: number,
  segmentType: string,
  offsetMin: number | null,
  offsetMax: number | null,
): { paceMinSec: number; paceMaxSec: number } | null {
  if (vdot <= 0) return null;
  const threshold = getThresholdPace(vdot);
  if (threshold <= 0) return null;

  const lower = segmentType.toLowerCase();
  if (lower === "warmup" || lower === "recovery" || lower === "cooldown") {
    return { paceMinSec: threshold + 45, paceMaxSec: threshold + 75 };
  };
  if (lower === "main") {
    if (offsetMin != null && offsetMax != null) {
      return { paceMinSec: threshold + offsetMin, paceMaxSec: threshold + offsetMax };
    }
    return { paceMinSec: threshold + 45, paceMaxSec: threshold + 75 };
  }
  return null;
}

interface PaceRangeOffsets {
  paceFastSec: number;
  paceSlowSec: number;
}

function getPaceRangeFromOffsets(
  vdot: number | null,
  offsetMin: number | null,
  offsetMax: number | null,
): PaceRangeOffsets | null {
  if (vdot == null || vdot <= 0) return null;
  if (offsetMin == null || offsetMax == null) return null;
  const threshold = getThresholdPace(vdot);
  if (threshold <= 0) return null;
  return {
    paceFastSec: threshold + offsetMin,
    paceSlowSec: threshold + offsetMax,
  };
}

// ---------- TCR -> Garmin Format Converter ----------
// DB'deki workout_definition snake_case kullanır (segment_type, target_type vb.)

interface TcrSegment {
  segment_type: string;
  target_type: string;
  target: string;
  duration_seconds?: number;
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
  power_watts_min?: number;
  power_watts_max?: number;
}

interface TcrStep {
  type: string;
  segment?: TcrSegment;
  repeat_count?: number;
  steps?: TcrStep[];
}

interface TcrWorkoutDefinition {
  steps: TcrStep[];
}

interface VdotContext {
  userVdot: number | null;
  offsetMin: number | null;
  offsetMax: number | null;
}

function segmentPaceSecFromSegment(seg: TcrSegment, vdotCtx: VdotContext): number | null {
  let paceSec =
    seg.custom_pace_seconds_per_km ??
    seg.pace_seconds_per_km ??
    seg.pace_seconds_per_km_min ??
    null;

  if (
    paceSec == null &&
    seg.target === "pace" &&
    seg.use_vdot_for_pace === true &&
    vdotCtx.userVdot != null &&
    vdotCtx.userVdot > 0
  ) {
    const range = getVdotPaceRange(
      vdotCtx.userVdot,
      seg.segment_type,
      vdotCtx.offsetMin,
      vdotCtx.offsetMax,
    );
    if (range) {
      paceSec = range.paceMinSec;
    }
  }

  return paceSec;
}

function pickRepresentativeSegments(definition: TcrWorkoutDefinition): {
  main?: TcrSegment;
  recovery?: TcrSegment;
} {
  let mainSeg: TcrSegment | undefined;
  let recoverySeg: TcrSegment | undefined;

  function walk(steps: TcrStep[]): boolean {
    for (const step of steps) {
      if (step.type === "segment" && step.segment) {
        const seg = step.segment;
        const typeLower = seg.segment_type.toLowerCase();
        if (!mainSeg && typeLower === "main") {
          mainSeg = seg;
        } else if (!recoverySeg && typeLower === "recovery") {
          recoverySeg = seg;
        }
        if (mainSeg && recoverySeg) return true;
      } else if (step.type === "repeat" && step.steps && step.steps.length > 0) {
        if (walk(step.steps)) return true;
      }
    }
    return false;
  }

  walk(definition.steps);
  return { main: mainSeg, recovery: recoverySeg };
}

interface LaneConfigLane {
  lane_number: number;
  pace_min_sec_per_km: number;
  pace_max_sec_per_km: number;
  label?: string;
}

interface LaneConfig {
  track_length_km?: number;
  lanes: LaneConfigLane[];
}

function parseLaneConfig(raw: any): LaneConfig | null {
  if (!raw || typeof raw !== "object") return null;
  const lanesRaw = Array.isArray(raw.lanes) ? raw.lanes : [];
  const lanes: LaneConfigLane[] = [];
  for (const l of lanesRaw) {
    if (!l) continue;
    const laneNum = typeof l.lane_number === "number" ? l.lane_number : null;
    const paceMin = typeof l.pace_min_sec_per_km === "number" ? l.pace_min_sec_per_km : null;
    const paceMax = typeof l.pace_max_sec_per_km === "number" ? l.pace_max_sec_per_km : null;
    if (laneNum == null || paceMin == null || paceMax == null) continue;
    lanes.push({
      lane_number: laneNum,
      pace_min_sec_per_km: paceMin,
      pace_max_sec_per_km: paceMax,
      label: typeof l.label === "string" ? l.label : undefined,
    });
  }
  if (lanes.length === 0) return null;
  const trackLen =
    typeof raw.track_length_km === "number"
      ? raw.track_length_km
      : undefined;
  return { track_length_km: trackLen, lanes };
}

function laneNumberForPace(laneConfig: LaneConfig | null, paceSecPerKm: number | null): number | null {
  if (!laneConfig || paceSecPerKm == null || paceSecPerKm <= 0) return null;
  for (const lane of laneConfig.lanes) {
    if (
      paceSecPerKm >= lane.pace_min_sec_per_km &&
      paceSecPerKm <= lane.pace_max_sec_per_km
    ) {
      return lane.lane_number;
    }
  }
  return null;
}

function trackLengthKmForLane(lane1TrackKm: number | null | undefined, laneNumber: number | null): number | null {
  if (!lane1TrackKm || lane1TrackKm <= 0) return null;
  if (!laneNumber || laneNumber <= 1) return lane1TrackKm;
  const laneWidthM = 1.22;
  const extraMetersPerLane = 2 * Math.PI * laneWidthM;
  return lane1TrackKm + (laneNumber - 1) * (extraMetersPerLane / 1000);
}

function formatDurationMinSec(totalSeconds: number): string {
  const seconds = Math.max(0, Math.round(totalSeconds));
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function computeLapTimesForGarmin(
  definition: TcrWorkoutDefinition,
  vdotCtx: VdotContext,
  laneConfigRaw: any,
  routeTotalKmRaw: any,
): { laneNumber?: number; mainLapSec?: number; recoveryLapSec?: number } {
  const laneConfig = parseLaneConfig(laneConfigRaw);
  if (!laneConfig) return {};

  const { main, recovery } = pickRepresentativeSegments(definition);
  if (!main) return {};

  const mainPaceSec = segmentPaceSecFromSegment(main, vdotCtx);
  if (!mainPaceSec || mainPaceSec <= 0) return {};

  const recoveryPaceSec = recovery
    ? segmentPaceSecFromSegment(recovery, vdotCtx)
    : null;

  let routeTotalKm: number | null = null;
  if (typeof routeTotalKmRaw === "number") {
    routeTotalKm = routeTotalKmRaw;
  } else if (typeof routeTotalKmRaw === "string") {
    const parsed = parseFloat(routeTotalKmRaw);
    if (!Number.isNaN(parsed)) routeTotalKm = parsed;
  }

  const baseTrackKm = laneConfig.track_length_km ?? routeTotalKm;
  if (!baseTrackKm || baseTrackKm <= 0) return {};

  const laneNumber =
    laneNumberForPace(laneConfig, mainPaceSec) ??
    (laneConfig.lanes.length > 0 ? laneConfig.lanes[0].lane_number : undefined);

  const trackKmForLane =
    trackLengthKmForLane(baseTrackKm, laneNumber ?? null) ?? baseTrackKm;

  const mainLapSec = trackKmForLane * mainPaceSec;
  const recoveryLapSec =
    recoveryPaceSec && recoveryPaceSec > 0
      ? trackKmForLane * recoveryPaceSec
      : undefined;

  return { laneNumber, mainLapSec, recoveryLapSec };
}

function buildGarminDescription(options: {
  laneNumber?: number;
  mainLapSec?: number;
  recoveryLapSec?: number;
}): string {
  const { laneNumber, mainLapSec, recoveryLapSec } = options;
  const parts: string[] = [];

  if (laneNumber != null) {
    parts.push(`Kulvar ${laneNumber}`);
  }
  if (mainLapSec != null && mainLapSec > 0) {
    parts.push(`Ana: 1 tur ≈ ${formatDurationMinSec(mainLapSec)}`);
  }
  if (recoveryLapSec != null && recoveryLapSec > 0) {
    parts.push(`Toparlanma: 1 tur ≈ ${formatDurationMinSec(recoveryLapSec)}`);
  }

  return parts.join(" · ");
}

function reorderStepsForGarmin(steps: TcrStep[]): TcrStep[] {
  const warmups: TcrStep[] = [];
  const cooldowns: TcrStep[] = [];
  const others: TcrStep[] = [];

  for (const step of steps) {
    if (step.type === "segment" && step.segment?.segment_type === "warmup") {
      warmups.push(step);
    } else if (step.type === "segment" && step.segment?.segment_type === "cooldown") {
      cooldowns.push(step);
    } else {
      others.push(step);
    }
  }

  return [...warmups, ...others, ...cooldowns];
}

function mapIntensity(segmentType: string): string {
  switch (segmentType) {
    case "warmup": return "WARMUP";
    case "cooldown": return "COOLDOWN";
    case "recovery": return "RECOVERY";
    case "main": return "ACTIVE";
    default: return "ACTIVE";
  }
}

function mapDuration(seg: TcrSegment): { durationType: string; durationValue: number | null } {
  if (seg.target_type === "duration" && seg.duration_seconds != null) {
    return { durationType: "TIME", durationValue: seg.duration_seconds };
  }
  if (seg.target_type === "distance" && seg.distance_meters != null) {
    return { durationType: "DISTANCE", durationValue: seg.distance_meters };
  }
  return { durationType: "OPEN", durationValue: null };
}

function mapTarget(seg: TcrSegment, vdotCtx: VdotContext): any {
  let effectivePace = seg.custom_pace_seconds_per_km ?? seg.pace_seconds_per_km ?? seg.pace_seconds_per_km_min;
  let paceMaxSec = seg.pace_seconds_per_km_max;

  // Segment'te VDOT modu açıksa VDOT'tan hesapla
  if (seg.target === "pace" && seg.use_vdot_for_pace === true && vdotCtx.userVdot && vdotCtx.userVdot > 0) {
    const range = getVdotPaceRange(vdotCtx.userVdot, seg.segment_type, vdotCtx.offsetMin, vdotCtx.offsetMax);
    if (range) {
      effectivePace = range.paceMinSec;
      paceMaxSec = range.paceMaxSec;
    }
  }

  // Fallback: segment'te VDOT modu açık değilse bile,
  // training type offset'leri + kullanıcı VDOT'u varsa pace hesapla.
  if (!effectivePace && vdotCtx.userVdot && vdotCtx.userVdot > 0 && (vdotCtx.offsetMin != null || vdotCtx.offsetMax != null)) {
    const range = getVdotPaceRange(vdotCtx.userVdot, seg.segment_type, vdotCtx.offsetMin, vdotCtx.offsetMax);
    if (range) {
      effectivePace = range.paceMinSec;
      paceMaxSec = range.paceMaxSec;
    }
  }

  if (effectivePace && effectivePace > 0 && (seg.target === "pace" || seg.use_vdot_for_pace === true || (vdotCtx.offsetMin != null && vdotCtx.userVdot))) {
    const speedMsHigh = 1000.0 / effectivePace;
    const speedMsLow = 1000.0 / (paceMaxSec ?? effectivePace);
    return {
      targetType: "PACE",
      targetValue: null,
      targetValueLow: speedMsLow,
      targetValueHigh: speedMsHigh,
      targetValueType: null,
    };
  }
  if ((seg.target === "heartRate" || seg.target === "heart_rate") &&
      (seg.heart_rate_bpm_min != null || seg.heart_rate_bpm_max != null)) {
    return {
      targetType: "HEART_RATE",
      targetValue: null,
      targetValueLow: seg.heart_rate_bpm_min ?? null,
      targetValueHigh: seg.heart_rate_bpm_max ?? null,
      targetValueType: null,
    };
  }
  if (seg.target === "cadence" && (seg.cadence_min != null || seg.cadence_max != null)) {
    return {
      targetType: "CADENCE",
      targetValue: null,
      targetValueLow: seg.cadence_min ?? null,
      targetValueHigh: seg.cadence_max ?? null,
      targetValueType: null,
    };
  }
  if (seg.target === "power" && (seg.power_watts_min != null || seg.power_watts_max != null)) {
    return {
      targetType: "POWER",
      targetValue: null,
      targetValueLow: seg.power_watts_min ?? null,
      targetValueHigh: seg.power_watts_max ?? null,
      targetValueType: null,
    };
  }
  return {
    targetType: "OPEN",
    targetValue: null,
    targetValueLow: null,
    targetValueHigh: null,
    targetValueType: null,
  };
}

function buildGarminStep(seg: TcrSegment, stepOrder: number, vdotCtx: VdotContext): any {
  const { durationType, durationValue } = mapDuration(seg);
  const target = mapTarget(seg, vdotCtx);
  return {
    type: "WorkoutStep",
    stepOrder,
    intensity: mapIntensity(seg.segment_type),
    description: null,
    durationType,
    durationValue,
    durationValueType: null,
    ...target,
    secondaryTargetType: null,
    secondaryTargetValue: null,
    secondaryTargetValueLow: null,
    secondaryTargetValueHigh: null,
    secondaryTargetValueType: null,
    strokeType: null,
    drillType: null,
    equipmentType: null,
    exerciseCategory: null,
    exerciseName: null,
    weightValue: null,
    weightDisplayUnit: null,
  };
}

let _globalStepOrder = 0;

function convertStepsGlobal(steps: TcrStep[], vdotCtx: VdotContext): any[] {
  const result: any[] = [];
  for (const step of steps) {
    if (step.type === "segment" && step.segment) {
      _globalStepOrder++;
      result.push(buildGarminStep(step.segment, _globalStepOrder, vdotCtx));
    } else if (step.type === "repeat" && (step.repeat_count ?? 0) > 0 && step.steps) {
      _globalStepOrder++;
      const repeatOrder = _globalStepOrder;
      const innerSteps = convertStepsGlobal(step.steps, vdotCtx);
      result.push({
        type: "WorkoutRepeatStep",
        stepOrder: repeatOrder,
        repeatType: "REPEAT_UNTIL_STEPS_CMPLT",
        repeatValue: step.repeat_count,
        steps: innerSteps,
      });
    }
  }
  return result;
}

function convertTcrToGarmin(
  definition: TcrWorkoutDefinition,
  workoutName: string,
  description: string,
  vdotCtx: VdotContext,
): any {
  _globalStepOrder = 0;
  const orderedSteps = reorderStepsForGarmin(definition.steps);
  const garminSteps = convertStepsGlobal(orderedSteps, vdotCtx);

  console.log(`convertTcrToGarmin: ${workoutName}, input steps: ${definition.steps.length}, output garmin steps: ${garminSteps.length}`);
  console.log("Garmin payload:", JSON.stringify(garminSteps));

  return {
    workoutName,
    description,
    sport: "RUNNING",
    workoutProvider: "TCR",
    workoutSourceId: "TCR",
    isSessionTransitionEnabled: false,
    poolLength: null,
    poolLengthUnit: null,
    segments: [
      {
        segmentOrder: 1,
        sport: "RUNNING",
        poolLength: null,
        poolLengthUnit: null,
        estimatedDurationInSecs: null,
        estimatedDistanceInMeters: null,
        steps: garminSteps,
      },
    ],
  };
}

// ---------- Definition Hash (değişiklik tespiti için) ----------

async function hashDefinition(def: any): Promise<string> {
  const text = JSON.stringify(def);
  const data = new TextEncoder().encode(text);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, "0")).join("").slice(0, 16);
}

// ---------- Garmin API Calls ----------

async function deleteGarminWorkout(accessToken: string, workoutId: number): Promise<boolean> {
  try {
    const res = await fetch(`${GARMIN_WORKOUT_URL}/${workoutId}`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${accessToken}` },
    });

    if (!res.ok) {
      const errText = await res.text();
      console.warn(`Delete workout ${workoutId} failed: ${res.status}`, errText);
      return false;
    }

    console.log(`Deleted old Garmin workout ${workoutId}`);
    return true;
  } catch (e) {
    console.warn(`Delete workout ${workoutId} error:`, e);
    return false;
  }
}

async function createGarminWorkout(accessToken: string, workoutJson: any): Promise<number | null> {
  const res = await fetch(GARMIN_WORKOUT_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(workoutJson),
  });

  if (!res.ok) {
    const errText = await res.text();
    console.error(`Create workout failed: ${res.status}`, errText);
    if (res.status === 429) throw new Error("RATE_LIMITED");
    return null;
  }

  const data = await res.json();
  return data.workoutId ?? null;
}

async function createGarminSchedule(
  accessToken: string,
  workoutId: number,
  dateStr: string
): Promise<number | null> {
  const res = await fetch(GARMIN_SCHEDULE_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ workoutId, date: dateStr }),
  });

  if (!res.ok) {
    const errText = await res.text();
    console.error(`Create schedule failed: ${res.status}`, errText);
    if (res.status === 429) throw new Error("RATE_LIMITED");
    return null;
  }

  const data = await res.json();
  return data.scheduleId ?? null;
}

// ---------- Expired Workout Cleanup ----------

async function cleanupExpiredWorkouts(
  supabase: ReturnType<typeof createClient>,
  accessToken: string,
  userId: string,
): Promise<number> {
  const cutoffDate = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
    .toISOString()
    .split("T")[0];

  const { data: expiredWorkouts } = await supabase
    .from("garmin_sent_workouts")
    .select("id, garmin_workout_id, scheduled_date, workout_name")
    .eq("user_id", userId)
    .lt("scheduled_date", cutoffDate);

  let cleaned = 0;
  for (const expired of (expiredWorkouts ?? [])) {
    if (expired.garmin_workout_id) {
      const deleted = await deleteGarminWorkout(accessToken, expired.garmin_workout_id);
      if (deleted) {
        console.log(`Cleaned up expired workout "${expired.workout_name}" (${expired.scheduled_date})`);
      }
    }
    await supabase
      .from("garmin_sent_workouts")
      .delete()
      .eq("id", expired.id);
    cleaned++;
  }

  if (cleaned > 0) {
    console.log(`Cleaned ${cleaned} expired workouts for user ${userId}`);
  }

  return cleaned;
}

// ---------- Main Handler ----------

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const body = await req.json();
    const mode = body.mode ?? "cron";

    let userIds: string[] = [];

    if (mode === "single_user" && body.user_id) {
      userIds = [body.user_id];
    } else if (mode === "single" && body.user_id && body.event_id && body.program_id) {
      // Tekil antrenman gönder
      return await handleSinglePush(supabase, body);
    } else {
      // Cron: tüm Garmin bağlı kullanıcılar
      const { data: integrations } = await supabase
        .from("user_integrations")
        .select("user_id")
        .eq("provider", "garmin")
        .eq("sync_enabled", true);

      userIds = (integrations ?? []).map((i: any) => i.user_id);
    }

    const results: any[] = [];

    for (const userId of userIds) {
      try {
        const result = await syncUserWorkouts(supabase, userId);
        results.push({ user_id: userId, ...result });
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error(`Sync failed for user ${userId}:`, msg);
        results.push({ user_id: userId, error: msg });
        if (msg === "RATE_LIMITED") {
          console.warn("Rate limited, stopping batch");
          break;
        }
      }
    }

    return new Response(JSON.stringify({ success: true, results }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("garmin-push-workout error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error", details: String(err) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});

async function syncUserWorkouts(
  supabase: ReturnType<typeof createClient>,
  userId: string
): Promise<{ sent: number; skipped: number; updated: number; cleaned: number }> {
  // 1. Integration bilgilerini al
  const { data: integration } = await supabase
    .from("user_integrations")
    .select("*")
    .eq("user_id", userId)
    .eq("provider", "garmin")
    .eq("sync_enabled", true)
    .single();

  if (!integration) {
    return { sent: 0, skipped: 0, updated: 0, cleaned: 0 };
  }

  // 2. Token yenile (gerekirse)
  const accessToken = await ensureValidToken(supabase, integration);

  // 2b. Kullanıcının VDOT değerini al
  const { data: userData } = await supabase
    .from("users")
    .select("vdot")
    .eq("id", userId)
    .single();
  const userVdot: number | null = userData?.vdot ?? null;

  // 3. Kullanıcının training group'larını bul
  const { data: memberships } = await supabase
    .from("group_members")
    .select("group_id")
    .eq("user_id", userId);

  const groupIds = (memberships ?? []).map((m: any) => m.group_id);
  if (groupIds.length === 0) {
    const cleaned = await cleanupExpiredWorkouts(supabase, accessToken, userId);
    return { sent: 0, skipped: 0, updated: 0, cleaned };
  }

  // 4. Gelecek 7 günün training etkinliklerini al
  const now = new Date();
  const startDate = now.toISOString().split("T")[0];
  const endDate = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000)
    .toISOString()
    .split("T")[0];

  const { data: events } = await supabase
    .from("events")
    .select("id, title, start_time, end_time, event_type, lane_config, route_id, routes(total_distance)")
    .eq("event_type", "training")
    .gte("start_time", `${startDate}T00:00:00`)
    .lte("start_time", `${endDate}T23:59:59`)
    .order("start_time", { ascending: true });

  if (!events || events.length === 0) {
    const cleaned = await cleanupExpiredWorkouts(supabase, accessToken, userId);
    return { sent: 0, skipped: 0, updated: 0, cleaned };
  }

  // 5. Event group programs (workout definition'ları)
  const eventIds = events.map((e: any) => e.id);
  const { data: programs } = await supabase
    .from("event_group_programs")
    .select("id, event_id, training_group_id, workout_definition, training_type_id, order_index, program_content")
    .in("event_id", eventIds)
    .in("training_group_id", groupIds)
    .not("workout_definition", "is", null);

  if (!programs || programs.length === 0) {
    const cleaned = await cleanupExpiredWorkouts(supabase, accessToken, userId);
    return { sent: 0, skipped: 0, updated: 0, cleaned };
  }

  // 6. Zaten gönderilmiş olanları al (hash karşılaştırması için)
  const { data: sentWorkouts } = await supabase
    .from("garmin_sent_workouts")
    .select("event_id, program_id, garmin_workout_id, definition_hash")
    .eq("user_id", userId)
    .in("event_id", eventIds);

  const sentMap = new Map<string, { garmin_workout_id: number | null; definition_hash: string | null }>(
    (sentWorkouts ?? []).map((s: any) => [
      `${s.event_id}:${s.program_id}`,
      { garmin_workout_id: s.garmin_workout_id, definition_hash: s.definition_hash },
    ])
  );

  // 7. Training type bilgilerini al (offset dahil)
  const trainingTypeIds = [...new Set(programs.map((p: any) => p.training_type_id).filter(Boolean))];
  let trainingTypes: Record<string, { name: string; displayName: string; description: string; offsetMin: number | null; offsetMax: number | null }> = {};
  if (trainingTypeIds.length > 0) {
    const { data: types } = await supabase
      .from("training_types")
      .select("id, name, display_name, description, threshold_offset_min_seconds, threshold_offset_max_seconds")
      .in("id", trainingTypeIds);
    for (const t of (types ?? [])) {
      trainingTypes[t.id] = {
        name: t.name,
        displayName: t.display_name ?? t.name,
        description: t.description ?? "",
        offsetMin: t.threshold_offset_min_seconds ?? null,
        offsetMax: t.threshold_offset_max_seconds ?? null,
      };
    }
  }

  const eventsById = Object.fromEntries(events.map((e: any) => [e.id, e]));

  let sent = 0;
  let skipped = 0;
  let updated = 0;

  for (const program of programs) {
    const key = `${program.event_id}:${program.id}`;
    const existing = sentMap.get(key);

    const rawDef = program.workout_definition;
    let definition: TcrWorkoutDefinition;
    if (Array.isArray(rawDef)) {
      definition = { steps: rawDef };
    } else if (rawDef?.steps && Array.isArray(rawDef.steps)) {
      definition = rawDef as TcrWorkoutDefinition;
    } else {
      console.warn(`Skipping program ${program.id}: invalid workout_definition format`);
      continue;
    }
    if (definition.steps.length === 0) continue;

    const currentHash = await hashDefinition(rawDef);

    if (existing) {
      if (existing.definition_hash === currentHash) {
        skipped++;
        continue;
      }
      // Definition değişmiş → eski workout'u Garmin'den sil
      if (existing.garmin_workout_id) {
        console.log(`Definition changed for program ${program.id}, deleting old Garmin workout ${existing.garmin_workout_id}`);
        await deleteGarminWorkout(accessToken, existing.garmin_workout_id);
      }
      updated++;
    }

    const event = eventsById[program.event_id];
    if (!event) continue;

    const ttInfo = program.training_type_id ? trainingTypes[program.training_type_id] : null;
    const eventDate = new Date(event.start_time);
    const dayName = ["Pz", "Pt", "Sa", "Ça", "Pe", "Cu", "Ct"][eventDate.getDay()];
    const workoutName = `${dayName} - ${event.title ?? "Antrenman"}`;

    const vdotCtx: VdotContext = {
      userVdot,
      offsetMin: ttInfo?.offsetMin ?? null,
      offsetMax: ttInfo?.offsetMax ?? null,
    };
    const routeTotalKm =
      event.routes && typeof event.routes.total_distance !== "undefined"
        ? Number(event.routes.total_distance)
        : null;

    const lapInfo = computeLapTimesForGarmin(
      definition,
      vdotCtx,
      event.lane_config ?? null,
      routeTotalKm,
    );

    const description = buildGarminDescription(lapInfo);

    const garminJson = convertTcrToGarmin(definition, workoutName, description, vdotCtx);

    const workoutId = await createGarminWorkout(accessToken, garminJson);
    if (!workoutId) continue;

    const scheduleDateStr = eventDate.toISOString().split("T")[0];
    const scheduleId = await createGarminSchedule(accessToken, workoutId, scheduleDateStr);

    await supabase.from("garmin_sent_workouts").upsert(
      {
        user_id: userId,
        event_id: program.event_id,
        program_id: program.id,
        garmin_workout_id: workoutId,
        garmin_schedule_id: scheduleId,
        scheduled_date: scheduleDateStr,
        workout_name: workoutName,
        definition_hash: currentHash,
      },
      { onConflict: "user_id,event_id,program_id" }
    );

    sent++;
  }

  // 8. 1 haftadan eski workout'ları Garmin'den temizle
  const cleaned = await cleanupExpiredWorkouts(supabase, accessToken, userId);

  // last_sync_at güncelle
  await supabase
    .from("user_integrations")
    .update({ last_sync_at: new Date().toISOString() })
    .eq("user_id", userId)
    .eq("provider", "garmin");

  return { sent, skipped, updated, cleaned };
}

async function handleSinglePush(
  supabase: ReturnType<typeof createClient>,
  body: any
): Promise<Response> {
  const { user_id, event_id, program_id } = body;

  const { data: integration } = await supabase
    .from("user_integrations")
    .select("*")
    .eq("user_id", user_id)
    .eq("provider", "garmin")
    .single();

  if (!integration) {
    return new Response(JSON.stringify({ error: "Garmin not connected" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const accessToken = await ensureValidToken(supabase, integration);

  const { data: userData } = await supabase
    .from("users")
    .select("vdot")
    .eq("id", user_id)
    .single();
  const singleUserVdot: number | null = userData?.vdot ?? null;

  const { data: program } = await supabase
    .from("event_group_programs")
    .select("id, event_id, workout_definition, training_type_id, program_content")
    .eq("id", program_id)
    .eq("event_id", event_id)
    .single();

  if (!program?.workout_definition) {
    return new Response(JSON.stringify({ error: "No workout definition" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const { data: event } = await supabase
    .from("events")
    .select("id, title, start_time, lane_config, route_id, routes(total_distance)")
    .eq("id", event_id)
    .single();

  if (!event) {
    return new Response(JSON.stringify({ error: "Event not found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let singleTypeDisplayName = "";
  let singleTypeDescription = "";
  let singleOffsetMin: number | null = null;
  let singleOffsetMax: number | null = null;
  if (program.training_type_id) {
    const { data: tt } = await supabase
      .from("training_types")
      .select("name, display_name, description, threshold_offset_min_seconds, threshold_offset_max_seconds")
      .eq("id", program.training_type_id)
      .single();
    singleTypeDisplayName = tt?.display_name ?? tt?.name ?? "";
    singleTypeDescription = tt?.description ?? "";
    singleOffsetMin = tt?.threshold_offset_min_seconds ?? null;
    singleOffsetMax = tt?.threshold_offset_max_seconds ?? null;
  }

  const eventDate = new Date(event.start_time);
  const dayName = ["Pz", "Pt", "Sa", "Ça", "Pe", "Cu", "Ct"][eventDate.getDay()];
  const workoutName = `${dayName} - ${event.title ?? "Antrenman"}`;

  const singleRawDef = program.workout_definition;
  let singleDef: TcrWorkoutDefinition;
  if (Array.isArray(singleRawDef)) {
    singleDef = { steps: singleRawDef };
  } else if (singleRawDef?.steps && Array.isArray(singleRawDef.steps)) {
    singleDef = singleRawDef as TcrWorkoutDefinition;
  } else {
    return new Response(JSON.stringify({ error: "Invalid workout definition format" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const singleVdotCtx: VdotContext = {
    userVdot: singleUserVdot,
    offsetMin: singleOffsetMin,
    offsetMax: singleOffsetMax,
  };
  const singleRouteTotalKm =
    event.routes && typeof event.routes.total_distance !== "undefined"
      ? Number(event.routes.total_distance)
      : null;

  const singleLapInfo = computeLapTimesForGarmin(
    singleDef,
    singleVdotCtx,
    event.lane_config ?? null,
    singleRouteTotalKm,
  );

  const singleDescription = buildGarminDescription(singleLapInfo);

  // Daha önce gönderilmiş bir workout varsa Garmin'den sil
  const { data: existingSent } = await supabase
    .from("garmin_sent_workouts")
    .select("garmin_workout_id")
    .eq("user_id", user_id)
    .eq("event_id", event_id)
    .eq("program_id", program_id)
    .single();

  if (existingSent?.garmin_workout_id) {
    await deleteGarminWorkout(accessToken, existingSent.garmin_workout_id);
  }

  const garminJson = convertTcrToGarmin(singleDef, workoutName, singleDescription, singleVdotCtx);
  const workoutId = await createGarminWorkout(accessToken, garminJson);

  if (!workoutId) {
    return new Response(JSON.stringify({ error: "Failed to create workout on Garmin" }), {
      status: 502,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const scheduleDateStr = eventDate.toISOString().split("T")[0];
  const scheduleId = await createGarminSchedule(accessToken, workoutId, scheduleDateStr);

  const singleDefHash = await hashDefinition(program.workout_definition);

  await supabase.from("garmin_sent_workouts").upsert(
    {
      user_id,
      event_id,
      program_id,
      garmin_workout_id: workoutId,
      garmin_schedule_id: scheduleId,
      scheduled_date: scheduleDateStr,
      workout_name: workoutName,
      definition_hash: singleDefHash,
    },
    { onConflict: "user_id,event_id,program_id" }
  );

  return new Response(
    JSON.stringify({
      success: true,
      garmin_workout_id: workoutId,
      garmin_schedule_id: scheduleId,
      replaced_old_workout: existingSent?.garmin_workout_id ?? null,
    }),
    {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    }
  );
}
