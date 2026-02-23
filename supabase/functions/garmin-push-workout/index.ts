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
  }
  if (lower === "main") {
    if (offsetMin != null && offsetMax != null) {
      return { paceMinSec: threshold + offsetMin, paceMaxSec: threshold + offsetMax };
    }
    return { paceMinSec: threshold + 45, paceMaxSec: threshold + 75 };
  }
  return null;
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

  if (seg.target === "pace" && seg.use_vdot_for_pace === true && vdotCtx.userVdot && vdotCtx.userVdot > 0) {
    const range = getVdotPaceRange(vdotCtx.userVdot, seg.segment_type, vdotCtx.offsetMin, vdotCtx.offsetMax);
    if (range) {
      effectivePace = range.paceMinSec;
      paceMaxSec = range.paceMaxSec;
    }
  }

  if (seg.target === "pace" && effectivePace && effectivePace > 0) {
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
  const garminSteps = convertStepsGlobal(definition.steps, vdotCtx);

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

// ---------- Garmin API Calls ----------

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
): Promise<{ sent: number; skipped: number }> {
  // 1. Integration bilgilerini al
  const { data: integration } = await supabase
    .from("user_integrations")
    .select("*")
    .eq("user_id", userId)
    .eq("provider", "garmin")
    .eq("sync_enabled", true)
    .single();

  if (!integration) {
    return { sent: 0, skipped: 0 };
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
    return { sent: 0, skipped: 0 };
  }

  // 4. Gelecek 7 günün training etkinliklerini al
  const now = new Date();
  const startDate = now.toISOString().split("T")[0];
  const endDate = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000)
    .toISOString()
    .split("T")[0];

  const { data: events } = await supabase
    .from("events")
    .select("id, title, start_time, end_time, event_type")
    .eq("event_type", "training")
    .gte("start_time", `${startDate}T00:00:00`)
    .lte("start_time", `${endDate}T23:59:59`)
    .order("start_time", { ascending: true });

  if (!events || events.length === 0) {
    return { sent: 0, skipped: 0 };
  }

  // 5. Event group programs (workout definition'ları)
  const eventIds = events.map((e: any) => e.id);
  const { data: programs } = await supabase
    .from("event_group_programs")
    .select("id, event_id, training_group_id, workout_definition, training_type_id, order_index")
    .in("event_id", eventIds)
    .in("training_group_id", groupIds)
    .not("workout_definition", "is", null);

  if (!programs || programs.length === 0) {
    return { sent: 0, skipped: 0 };
  }

  // 6. Zaten gönderilmiş olanları filtrele
  const { data: sentWorkouts } = await supabase
    .from("garmin_sent_workouts")
    .select("event_id, program_id")
    .eq("user_id", userId)
    .in("event_id", eventIds);

  const sentKeys = new Set(
    (sentWorkouts ?? []).map((s: any) => `${s.event_id}:${s.program_id}`)
  );

  // 7. Training type bilgilerini al (offset dahil)
  const trainingTypeIds = [...new Set(programs.map((p: any) => p.training_type_id).filter(Boolean))];
  let trainingTypes: Record<string, { name: string; displayName: string; offsetMin: number | null; offsetMax: number | null }> = {};
  if (trainingTypeIds.length > 0) {
    const { data: types } = await supabase
      .from("training_types")
      .select("id, name, display_name, threshold_offset_min_seconds, threshold_offset_max_seconds")
      .in("id", trainingTypeIds);
    for (const t of (types ?? [])) {
      trainingTypes[t.id] = {
        name: t.name,
        displayName: t.display_name ?? t.name,
        offsetMin: t.threshold_offset_min_seconds ?? null,
        offsetMax: t.threshold_offset_max_seconds ?? null,
      };
    }
  }

  const eventsById = Object.fromEntries(events.map((e: any) => [e.id, e]));

  let sent = 0;
  let skipped = 0;

  for (const program of programs) {
    const key = `${program.event_id}:${program.id}`;
    if (sentKeys.has(key)) {
      skipped++;
      continue;
    }

    const event = eventsById[program.event_id];
    if (!event) continue;

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

    const ttInfo = program.training_type_id ? trainingTypes[program.training_type_id] : null;
    const eventDate = new Date(event.start_time);
    const dayName = ["Pz", "Pt", "Sa", "Ça", "Pe", "Cu", "Ct"][eventDate.getDay()];
    const workoutName = `${dayName} - ${event.title ?? "Antrenman"}`;
    const workoutDescription = ttInfo?.displayName ?? "";

    const vdotCtx: VdotContext = {
      userVdot,
      offsetMin: ttInfo?.offsetMin ?? null,
      offsetMax: ttInfo?.offsetMax ?? null,
    };
    const garminJson = convertTcrToGarmin(definition, workoutName, workoutDescription, vdotCtx);

    const workoutId = await createGarminWorkout(accessToken, garminJson);
    if (!workoutId) continue;

    const scheduleDateStr = eventDate.toISOString().split("T")[0];
    const scheduleId = await createGarminSchedule(accessToken, workoutId, scheduleDateStr);

    // Takip tablosuna kaydet
    await supabase.from("garmin_sent_workouts").upsert(
      {
        user_id: userId,
        event_id: program.event_id,
        program_id: program.id,
        garmin_workout_id: workoutId,
        garmin_schedule_id: scheduleId,
        scheduled_date: scheduleDateStr,
        workout_name: workoutName,
      },
      { onConflict: "user_id,event_id,program_id" }
    );

    sent++;
  }

  // last_sync_at güncelle
  await supabase
    .from("user_integrations")
    .update({ last_sync_at: new Date().toISOString() })
    .eq("user_id", userId)
    .eq("provider", "garmin");

  return { sent, skipped };
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
    .select("id, event_id, workout_definition, training_type_id")
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
    .select("id, title, start_time")
    .eq("id", event_id)
    .single();

  if (!event) {
    return new Response(JSON.stringify({ error: "Event not found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let singleTypeDisplayName = "";
  let singleOffsetMin: number | null = null;
  let singleOffsetMax: number | null = null;
  if (program.training_type_id) {
    const { data: tt } = await supabase
      .from("training_types")
      .select("name, display_name, threshold_offset_min_seconds, threshold_offset_max_seconds")
      .eq("id", program.training_type_id)
      .single();
    singleTypeDisplayName = tt?.display_name ?? tt?.name ?? "";
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
  const garminJson = convertTcrToGarmin(singleDef, workoutName, singleTypeDisplayName, singleVdotCtx);
  const workoutId = await createGarminWorkout(accessToken, garminJson);

  if (!workoutId) {
    return new Response(JSON.stringify({ error: "Failed to create workout on Garmin" }), {
      status: 502,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const scheduleDateStr = eventDate.toISOString().split("T")[0];
  const scheduleId = await createGarminSchedule(accessToken, workoutId, scheduleDateStr);

  await supabase.from("garmin_sent_workouts").upsert(
    {
      user_id,
      event_id,
      program_id,
      garmin_workout_id: workoutId,
      garmin_schedule_id: scheduleId,
      scheduled_date: scheduleDateStr,
      workout_name: workoutName,
    },
    { onConflict: "user_id,event_id,program_id" }
  );

  return new Response(
    JSON.stringify({
      success: true,
      garmin_workout_id: workoutId,
      garmin_schedule_id: scheduleId,
    }),
    {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    }
  );
}
