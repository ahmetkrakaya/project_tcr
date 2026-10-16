// Bir Strava aktivitesini zenginleştirir: detail + streams + athlete zones çeker,
// detay tablolarını yazar, metrikleri ve plan uyumunu hesaplar.

import {
  ensureValidAccessToken,
  StravaAuthError,
  stravaGet,
  StravaNotFoundError,
  StravaRateLimitError,
  type SupabaseClient,
} from './strava_client.ts';
import { saveActivityDetailChildren, upsertActivity } from './strava_activity_mapper.ts';
import {
  buildPreview,
  computeMetrics,
  normalizeStravaStreams,
  type Streams,
} from './activity_metrics.ts';
import { computeAndSaveCompliance, type LapRow } from './workout_compliance.ts';

export interface EnrichmentJob {
  id: number;
  user_id: string;
  strava_activity_id: number;
  mode: 'full' | 'refresh';
  attempts: number;
}

export type JobOutcome =
  | { status: 'done' }
  | { status: 'skipped'; reason: string }
  | { status: 'rate_limited'; retryAt: Date }
  | { status: 'failed'; error: string; retryable: boolean };

const STREAM_KEYS = 'time,distance,altitude,velocity_smooth,heartrate,cadence,watts,temp,moving,grade_smooth';
const ZONES_MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000;

function intArray(arr: number[] | undefined): (number | null)[] | null {
  return arr ? arr.map((v) => (v == null || !Number.isFinite(v) ? null : Math.round(v))) : null;
}

function realArray(arr: number[] | undefined, digits = 2): (number | null)[] | null {
  if (!arr) return null;
  const f = 10 ** digits;
  return arr.map((v) => (v == null || !Number.isFinite(v) ? null : Math.round(v * f) / f));
}

async function saveStreams(supabase: SupabaseClient, activityId: string, s: Streams): Promise<void> {
  const { error } = await supabase.from('activity_streams').upsert({
    activity_id: activityId,
    point_count: s.time.length,
    time_seconds: intArray(s.time),
    distance_meters: realArray(s.distance, 1),
    altitude: realArray(s.altitude, 1),
    velocity: realArray(s.velocity, 3),
    heartrate: intArray(s.heartrate),
    cadence: intArray(s.cadence),
    watts: intArray(s.watts),
    temp: intArray(s.temp),
    moving: s.moving ?? null,
    grade: realArray(s.grade, 1),
    preview: buildPreview(s),
    updated_at: new Date().toISOString(),
  });
  if (error) throw error;
}

async function loadStreams(supabase: SupabaseClient, activityId: string): Promise<Streams | null> {
  const { data } = await supabase
    .from('activity_streams')
    .select('time_seconds, distance_meters, altitude, velocity, heartrate, cadence, watts, temp, moving, grade')
    .eq('activity_id', activityId)
    .maybeSingle();
  if (!data?.time_seconds || data.time_seconds.length < 2) return null;
  return {
    time: data.time_seconds,
    distance: data.distance_meters ?? undefined,
    altitude: data.altitude ?? undefined,
    velocity: data.velocity ?? undefined,
    heartrate: data.heartrate ?? undefined,
    cadence: data.cadence ?? undefined,
    watts: data.watts ?? undefined,
    temp: data.temp ?? undefined,
    moving: data.moving ?? undefined,
    grade: data.grade ?? undefined,
  };
}

async function ensureAthleteZones(
  supabase: SupabaseClient,
  integration: any,
  accessToken: string,
): Promise<{ min: number; max: number }[] | null> {
  const cached = integration.athlete_zones?.heart_rate?.zones ?? null;
  const fetchedAt = integration.athlete_zones_fetched_at ? new Date(integration.athlete_zones_fetched_at).getTime() : 0;
  if (fetchedAt && Date.now() - fetchedAt < ZONES_MAX_AGE_MS) return cached;

  try {
    const zones = await stravaGet(supabase, accessToken, '/athlete/zones');
    await supabase
      .from('user_integrations')
      .update({ athlete_zones: zones, athlete_zones_fetched_at: new Date().toISOString() })
      .eq('user_id', integration.user_id)
      .eq('provider', 'strava');
    return zones?.heart_rate?.zones ?? null;
  } catch (e) {
    if (e instanceof StravaRateLimitError) throw e;
    // Zonlar opsiyonel: yetki/erişim yoksa bir daha 30 gün sorma
    await supabase
      .from('user_integrations')
      .update({ athlete_zones_fetched_at: new Date().toISOString() })
      .eq('user_id', integration.user_id)
      .eq('provider', 'strava');
    return cached;
  }
}

/** Kayıtlı veriden metrikleri ve plan uyumunu yeniden hesaplar (Strava'ya istek atmaz). */
export async function recomputeActivityAnalysis(
  supabase: SupabaseClient,
  activityId: string,
  athleteHrZones: { min: number; max: number }[] | null,
  streamsInput?: Streams | null,
): Promise<void> {
  const { data: activity } = await supabase
    .from('activities')
    .select('id, user_id, activity_type, start_time, duration_seconds, elapsed_seconds, average_heart_rate')
    .eq('id', activityId)
    .single();
  if (!activity) return;

  const [{ data: user }, { data: lapRows }, { data: splitRows }] = await Promise.all([
    supabase.from('users').select('threshold_pace_seconds, birth_date, gender').eq('id', activity.user_id).maybeSingle(),
    supabase.from('activity_laps').select('*').eq('activity_id', activityId).order('lap_index'),
    supabase
      .from('activity_splits')
      .select('split_number, distance_meters, duration_seconds, pace_seconds, gap_pace_seconds')
      .eq('activity_id', activityId)
      .order('split_number'),
  ]);

  const streams = streamsInput !== undefined ? streamsInput : await loadStreams(supabase, activityId);
  const laps: LapRow[] = (lapRows ?? []).map((l: any) => ({
    ...l,
    distance_meters: l.distance_meters != null ? Number(l.distance_meters) : null,
    average_speed: l.average_speed != null ? Number(l.average_speed) : null,
  }));
  const splits = (splitRows ?? []).map((s: any) => ({
    ...s,
    distance_meters: s.distance_meters != null ? Number(s.distance_meters) : null,
  }));

  let segments = null;
  if (streams) {
    const result = computeMetrics(streams, {
      thresholdPaceSeconds: user?.threshold_pace_seconds ?? null,
      birthDate: user?.birth_date ?? null,
      gender: user?.gender ?? null,
      athleteHrZones,
      movingSeconds: activity.duration_seconds,
      elapsedSeconds: activity.elapsed_seconds,
      averageHeartRate: activity.average_heart_rate,
      splits,
      laps: laps.map((l: any) => ({
        lap_index: l.lap_index,
        distance_meters: l.distance_meters,
        moving_seconds: l.moving_seconds,
        elapsed_seconds: l.elapsed_seconds,
        average_speed: l.average_speed,
        start_index: l.start_index,
        end_index: l.end_index,
      })),
    });
    segments = result.segments;

    const { error } = await supabase.from('activity_metrics').upsert({ activity_id: activityId, ...result.row });
    if (error) throw error;

    for (const u of result.splitUpdates) {
      await supabase
        .from('activity_splits')
        .update({ gap_pace_seconds: u.gap_pace_seconds, average_cadence: u.average_cadence })
        .eq('activity_id', activityId)
        .eq('split_number', u.split_number);
    }
    for (const [lapIndex, kind] of result.lapKinds) {
      await supabase
        .from('activity_laps')
        .update({ kind })
        .eq('activity_id', activityId)
        .eq('lap_index', lapIndex);
    }
  }

  await computeAndSaveCompliance(supabase, {
    activityId,
    userId: activity.user_id,
    startTime: activity.start_time,
    activityType: activity.activity_type,
    streams,
    laps,
    segments,
  });
}

export async function enrichActivity(supabase: SupabaseClient, job: EnrichmentJob): Promise<JobOutcome> {
  try {
    const { data: integration } = await supabase
      .from('user_integrations')
      .select('user_id, access_token, refresh_token, token_expires_at, athlete_zones, athlete_zones_fetched_at')
      .eq('user_id', job.user_id)
      .eq('provider', 'strava')
      .maybeSingle();
    if (!integration) return { status: 'skipped', reason: 'no_integration' };

    const { data: userRow } = await supabase
      .from('users')
      .select('is_active, user_status')
      .eq('id', job.user_id)
      .maybeSingle();
    if (!userRow || userRow.is_active !== true || userRow.user_status !== 'active') {
      return { status: 'skipped', reason: 'inactive_user' };
    }

    const accessToken = await ensureValidAccessToken(supabase, integration);
    const externalId = String(job.strava_activity_id);

    const { data: existing } = await supabase
      .from('activities')
      .select('id, activity_type, detail_synced_at, streams_synced_at')
      .eq('user_id', job.user_id)
      .eq('source', 'strava')
      .eq('external_id', externalId)
      .maybeSingle();

    let activityId: string | null = existing?.id ?? null;
    let activityType: string | null = existing?.activity_type ?? null;
    const refresh = job.mode === 'refresh';

    if (refresh || !existing?.detail_synced_at) {
      let detail: any;
      try {
        detail = await stravaGet(supabase, accessToken, `/activities/${externalId}`);
      } catch (e) {
        if (e instanceof StravaNotFoundError) {
          if (activityId) await supabase.from('activities').delete().eq('id', activityId);
          return { status: 'skipped', reason: 'deleted_on_strava' };
        }
        throw e;
      }
      const saved = await upsertActivity(supabase, job.user_id, detail);
      activityId = saved.id;
      activityType = saved.activityType;
      await saveActivityDetailChildren(supabase, saved.id, detail);
    }

    if (!activityId) return { status: 'skipped', reason: 'activity_missing' };
    if (activityType !== 'running') return { status: 'done' };

    let streams: Streams | null | undefined = undefined;
    if (refresh || !existing?.streams_synced_at) {
      try {
        const raw = await stravaGet(supabase, accessToken, `/activities/${externalId}/streams`, {
          keys: STREAM_KEYS,
          key_by_type: 'true',
        });
        streams = normalizeStravaStreams(raw, activityType);
        if (streams) await saveStreams(supabase, activityId, streams);
      } catch (e) {
        if (!(e instanceof StravaNotFoundError)) throw e;
        streams = null;
      }
      await supabase
        .from('activities')
        .update({ streams_synced_at: new Date().toISOString() })
        .eq('id', activityId);
    }

    const zones = await ensureAthleteZones(supabase, integration, accessToken);
    await recomputeActivityAnalysis(supabase, activityId, zones, streams);
    return { status: 'done' };
  } catch (e) {
    if (e instanceof StravaRateLimitError) return { status: 'rate_limited', retryAt: e.retryAt };
    const message = e instanceof Error ? e.message : String(e);
    return { status: 'failed', error: message, retryable: !(e instanceof StravaAuthError) };
  }
}
