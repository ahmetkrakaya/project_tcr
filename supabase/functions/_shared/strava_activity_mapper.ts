// Strava aktivite yanıtını DB satırlarına çevirir ve yazar.
// Summary (liste) ve DetailedActivity (resource_state = 3) yanıtlarının ikisini de kabul eder.

import type { SupabaseClient } from './strava_client.ts';

const TYPE_MAP: Record<string, string> = {
  Run: 'running',
  TrailRun: 'running',
  VirtualRun: 'running',
  Walk: 'walking',
  Hike: 'walking',
  Ride: 'cycling',
  VirtualRide: 'cycling',
  EBikeRide: 'cycling',
  MountainBikeRide: 'cycling',
  GravelRide: 'cycling',
  Swim: 'swimming',
  WeightTraining: 'strength',
  Crossfit: 'strength',
  Yoga: 'yoga',
};

export function mapStravaTypeToActivityType(sportType: string | undefined, type?: string): string {
  return TYPE_MAP[sportType ?? ''] ?? TYPE_MAP[type ?? ''] ?? 'other';
}

/** Strava start_date_local ("2026-02-22T03:37:00") → UTC ISO; DB'de Strava'daki saat aynen görünsün. */
export function localTimeToUtcIso(startDateLocal: string): string {
  const m = startDateLocal.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/);
  if (!m) return startDateLocal;
  const [, y, mo, d, h, min, s] = m;
  return new Date(Date.UTC(+y, +mo - 1, +d, +h, +min, +s || 0, 0)).toISOString();
}

export function addSecondsToLocalIso(startDateLocal: string, elapsedSeconds: number): string {
  const ms = new Date(localTimeToUtcIso(startDateLocal)).getTime() + (elapsedSeconds || 0) * 1000;
  return new Date(ms).toISOString();
}

function round(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? Math.round(v) : null;
}

function num(v: unknown, digits = 1): number | null {
  if (typeof v !== 'number' || !Number.isFinite(v)) return null;
  const f = 10 ** digits;
  return Math.round(v * f) / f;
}

function paceFrom(seconds: number | null | undefined, meters: number | null | undefined): number | null {
  if (!seconds || !meters || meters < 50) return null;
  return Math.round(seconds / (meters / 1000));
}

function paceFromSpeed(speed: number | null | undefined): number | null {
  if (!speed || speed <= 0.3) return null;
  return Math.round(1000 / speed);
}

/** Koşu/yürüyüşte Strava kadansı tek bacak RPM'dir; adım/dakika = x2. */
export function cadenceToSpm(cadence: number | null | undefined, activityType: string): number | null {
  if (cadence == null) return null;
  return activityType === 'running' || activityType === 'walking'
    ? Math.round(cadence * 2)
    : Math.round(cadence);
}

export function isDetailed(activity: any): boolean {
  return activity?.resource_state === 3;
}

export function buildActivityRow(userId: string, activity: any): Record<string, unknown> {
  const activityType = mapStravaTypeToActivityType(activity.sport_type, activity.type);
  const localStart = activity.start_date_local ?? activity.start_date;

  const metadata: Record<string, unknown> = {};
  if (Array.isArray(activity.start_latlng) && activity.start_latlng.length >= 2) {
    metadata.start_latlng = activity.start_latlng[0];
  }
  if (Array.isArray(activity.end_latlng) && activity.end_latlng.length >= 2) {
    metadata.end_latlng = activity.end_latlng[0];
  }

  const isRun = activityType === 'running';
  const row: Record<string, unknown> = {
    user_id: userId,
    activity_type: activityType,
    source: 'strava',
    external_id: String(activity.id),
    title: activity.name || 'Strava Aktivitesi',
    start_time: localTimeToUtcIso(localStart),
    end_time: addSecondsToLocalIso(localStart, activity.elapsed_time),
    duration_seconds: activity.moving_time,
    elapsed_seconds: activity.elapsed_time ?? null,
    distance_meters: activity.distance,
    elevation_gain: activity.total_elevation_gain || 0,
    average_pace_seconds: isRun ? paceFrom(activity.moving_time, activity.distance) : null,
    best_pace_seconds: isRun ? paceFromSpeed(activity.max_speed) : null,
    average_heart_rate: round(activity.average_heartrate),
    max_heart_rate: round(activity.max_heartrate),
    average_cadence: cadenceToSpm(activity.average_cadence, activityType),
    route_polyline: activity.map?.polyline || activity.map?.summary_polyline || null,
    is_public: true,
    weather_conditions: Object.keys(metadata).length > 0 ? metadata : null,
  };

  // Hem summary hem detail'de olan alanlar: sadece geldiyse yaz (eski değeri null ile ezme)
  const optional: Record<string, unknown> = {
    sport_type: activity.sport_type,
    workout_type: activity.workout_type,
    average_temp: num(activity.average_temp),
    elev_high: num(activity.elev_high),
    elev_low: num(activity.elev_low),
    average_watts: num(activity.average_watts),
    weighted_average_watts: num(activity.weighted_average_watts),
    kilojoules: num(activity.kilojoules),
    suffer_score: round(activity.suffer_score),
    pr_count: activity.pr_count,
    achievement_count: activity.achievement_count,
    is_trainer: activity.trainer,
    is_manual: activity.manual,
    gear_id: activity.gear_id,
  };
  for (const [k, v] of Object.entries(optional)) {
    if (v !== undefined && v !== null) row[k] = v;
  }

  if (isDetailed(activity)) {
    row.calories_burned = round(activity.calories);
    row.device_name = activity.device_name ?? null;
    row.perceived_exertion = num(activity.perceived_exertion);
    if (activity.description != null) row.description = activity.description;
    if (activity.gear) {
      row.gear_name = activity.gear.name ?? activity.gear.nickname ?? null;
      row.gear_distance_meters = num(activity.gear.distance);
    }
    row.detail_synced_at = new Date().toISOString();
  } else if (activity.calories != null) {
    row.calories_burned = round(activity.calories);
  }

  return row;
}

/** Aktiviteyi ekler/günceller. Yeni kayıtsa isNew = true. */
export async function upsertActivity(
  supabase: SupabaseClient,
  userId: string,
  activity: any,
): Promise<{ id: string; isNew: boolean; activityType: string }> {
  const row = buildActivityRow(userId, activity);

  const { data: existing, error: selectError } = await supabase
    .from('activities')
    .select('id')
    .eq('user_id', userId)
    .eq('source', 'strava')
    .eq('external_id', String(activity.id))
    .maybeSingle();
  if (selectError) throw selectError;

  if (existing) {
    const { error } = await supabase.from('activities').update(row).eq('id', existing.id);
    if (error) throw error;
    return { id: existing.id as string, isNew: false, activityType: row.activity_type as string };
  }

  const { data: inserted, error } = await supabase
    .from('activities')
    .insert(row)
    .select('id')
    .single();
  if (error) throw error;
  return { id: inserted.id as string, isNew: true, activityType: row.activity_type as string };
}

/** Bir sayfa özet aktiviteyi toplu ekler/günceller (backfill). Eklenen ve güncellenen sayısını döner. */
export async function upsertActivitiesBulk(
  supabase: SupabaseClient,
  userId: string,
  activities: any[],
): Promise<{ inserted: number; updated: number }> {
  if (activities.length === 0) return { inserted: 0, updated: 0 };
  const rows = activities.map((a) => buildActivityRow(userId, a));

  const { data: existing, error: selectError } = await supabase
    .from('activities')
    .select('id, external_id')
    .eq('user_id', userId)
    .eq('source', 'strava')
    .in('external_id', rows.map((r) => r.external_id));
  if (selectError) throw selectError;
  const idByExternal = new Map<string, string>((existing ?? []).map((e: any) => [e.external_id, e.id]));

  const toUpdate = rows.filter((r) => idByExternal.has(r.external_id as string))
    .map((r) => ({ ...r, id: idByExternal.get(r.external_id as string) }));
  const toInsert = rows.filter((r) => !idByExternal.has(r.external_id as string));

  // defaultToNull: false → satırda olmayan kolonlar mevcut değeri ezmez / varsayılanı alır
  if (toUpdate.length > 0) {
    const { error } = await supabase.from('activities').upsert(toUpdate, { onConflict: 'id', defaultToNull: false });
    if (error) throw error;
  }
  if (toInsert.length > 0) {
    const { error } = await supabase.from('activities').insert(toInsert, { defaultToNull: false });
    if (error) throw error;
  }
  return { inserted: toInsert.length, updated: toUpdate.length };
}

async function replaceRows(
  supabase: SupabaseClient,
  table: string,
  activityId: string,
  rows: Record<string, unknown>[],
): Promise<void> {
  const { error: delError } = await supabase.from(table).delete().eq('activity_id', activityId);
  if (delError) throw delError;
  if (rows.length === 0) return;
  const { error } = await supabase.from(table).insert(rows);
  if (error) throw error;
}

/** DetailedActivity içindeki laps / splits_metric / best_efforts'u yazar. */
export async function saveActivityDetailChildren(
  supabase: SupabaseClient,
  activityId: string,
  activity: any,
): Promise<void> {
  if (!isDetailed(activity)) return;
  const activityType = mapStravaTypeToActivityType(activity.sport_type, activity.type);
  const activityStartMs = activity.start_date ? new Date(activity.start_date).getTime() : null;

  const laps = (Array.isArray(activity.laps) ? activity.laps : []).map((lap: any, i: number) => {
    const lapStartMs = lap.start_date ? new Date(lap.start_date).getTime() : null;
    return {
      activity_id: activityId,
      lap_index: lap.lap_index ?? i + 1,
      name: lap.name ?? null,
      start_offset_seconds:
        activityStartMs != null && lapStartMs != null
          ? Math.max(0, Math.round((lapStartMs - activityStartMs) / 1000))
          : null,
      elapsed_seconds: lap.elapsed_time ?? null,
      moving_seconds: lap.moving_time ?? null,
      distance_meters: num(lap.distance, 2),
      average_pace_seconds: paceFrom(lap.moving_time || lap.elapsed_time, lap.distance),
      average_speed: num(lap.average_speed, 3),
      max_speed: num(lap.max_speed, 3),
      average_heart_rate: round(lap.average_heartrate),
      max_heart_rate: round(lap.max_heartrate),
      average_cadence: cadenceToSpm(lap.average_cadence, activityType),
      average_watts: num(lap.average_watts),
      elevation_gain: num(lap.total_elevation_gain),
      start_index: lap.start_index ?? null,
      end_index: lap.end_index ?? null,
      kind: null,
    };
  });

  const splits = (Array.isArray(activity.splits_metric) ? activity.splits_metric : []).map((s: any) => ({
    activity_id: activityId,
    split_number: s.split,
    distance_meters: num(s.distance, 2),
    duration_seconds: s.moving_time ?? null,
    elapsed_seconds: s.elapsed_time ?? null,
    pace_seconds: paceFrom(s.moving_time, s.distance),
    gap_pace_seconds: paceFromSpeed(s.average_grade_adjusted_speed),
    elevation_change: num(s.elevation_difference),
    average_heart_rate: round(s.average_heartrate),
    pace_zone: s.pace_zone ?? null,
  }));

  const seen = new Set<string>();
  const bestEfforts = (Array.isArray(activity.best_efforts) ? activity.best_efforts : [])
    .filter((b: any) => {
      if (!b?.name || seen.has(b.name)) return false;
      seen.add(b.name);
      return true;
    })
    .map((b: any) => ({
      activity_id: activityId,
      name: b.name,
      distance_meters: num(b.distance, 2),
      elapsed_seconds: b.elapsed_time ?? null,
      moving_seconds: b.moving_time ?? null,
      pr_rank: b.pr_rank ?? null,
      start_index: b.start_index ?? null,
      end_index: b.end_index ?? null,
    }));

  await replaceRows(supabase, 'activity_laps', activityId, laps);
  await replaceRows(supabase, 'activity_splits', activityId, splits);
  await replaceRows(supabase, 'activity_best_efforts', activityId, bestEfforts);
}
