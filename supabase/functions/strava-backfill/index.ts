// Supabase Edge Function: Strava Backfill
// Tüm Strava kullanıcıları için geçmiş aktiviteleri (örn. son 2 ay) toplu olarak senkronize eder.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

interface BackfillRequestBody {
  days?: number;         // Kaç günlük geçmiş (default: 60)
  user_limit?: number;   // Test için maksimum kaç kullanıcı (opsiyonel)
  user_offset?: number;  // Kaç kullanıcıyı atlayarak başlasın (opsiyonel)
}

interface StravaIntegration {
  user_id: string;
  access_token: string;
  refresh_token: string | null;
  token_expires_at: string | null;
}

async function getStravaConfig(supabase: ReturnType<typeof createClient>): Promise<{ client_id: string; client_secret: string }> {
  const { data } = await supabase
    .from('integration_oauth_config')
    .select('client_id, client_secret')
    .eq('provider', 'strava')
    .maybeSingle();

  if (data?.client_id && data?.client_secret) {
    return { client_id: data.client_id, client_secret: data.client_secret };
  }

  return {
    client_id: Deno.env.get('STRAVA_CLIENT_ID') || '',
    client_secret: Deno.env.get('STRAVA_CLIENT_SECRET') || '',
  };
}

// Strava token yenileme (client_id/secret DB veya env'den)
async function refreshStravaToken(
  config: { client_id: string; client_secret: string },
  refreshToken: string
): Promise<string> {
  const response = await fetch('https://www.strava.com/oauth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id: config.client_id,
      client_secret: config.client_secret,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }),
  });

  if (!response.ok) {
    throw new Error(`Token refresh failed: ${response.statusText}`);
  }

  const data = await response.json();
  return data.access_token;
}

// Tekil Strava aktivitesini çek (webhook fonksiyonundakiyle aynı)
async function fetchStravaActivity(accessToken: string, activityId: number): Promise<any | null> {
  try {
    const response = await fetch(
      `https://www.strava.com/api/v3/activities/${activityId}`,
      {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
        },
      }
    );

    if (!response.ok) {
      console.error(`[Backfill] Failed to fetch activity ${activityId}: ${response.statusText}`);
      return null;
    }

    return await response.json();
  } catch (error) {
    console.error('[Backfill] Error fetching activity:', error);
    return null;
  }
}

// Belirli bir kullanıcı için verilen zaman aralığındaki aktiviteleri listele
async function fetchStravaActivitiesForRange(
  accessToken: string,
  afterUnixSeconds: number
): Promise<any[]> {
  const activities: any[] = [];
  let page = 1;
  const perPage = 100;

  while (true) {
    const url = new URL('https://www.strava.com/api/v3/athlete/activities');
    url.searchParams.set('after', String(afterUnixSeconds));
    url.searchParams.set('per_page', String(perPage));
    url.searchParams.set('page', String(page));

    const response = await fetch(url.toString(), {
      headers: {
        'Authorization': `Bearer ${accessToken}`,
      },
    });

    if (!response.ok) {
      console.error(`[Backfill] Failed to list activities (page ${page}): ${response.statusText}`);
      break;
    }

    const pageData = await response.json();
    if (!Array.isArray(pageData) || pageData.length === 0) {
      break;
    }

    activities.push(...pageData);

    if (pageData.length < perPage) {
      // Son sayfa
      break;
    }

    // Güvenlik için maksimum 10 sayfa (1000 aktivite)
    if (page >= 10) {
      console.log('[Backfill] Reached page limit (10), stopping pagination');
      break;
    }

    page += 1;
  }

  return activities;
}

// Strava aktivite tipini uygulama aktivite tipine çevir (webhook ile aynı)
function mapStravaTypeToActivityType(stravaType: string): string {
  const typeMap: Record<string, string> = {
    'Run': 'running',
    'Ride': 'cycling',
    'Walk': 'walking',
    'Hike': 'hiking',
    'Swim': 'swimming',
    // DB enum'da "workout" yoksa hata vermesin diye "other" olarak işaretliyoruz.
    'Workout': 'other',
    'VirtualRide': 'cycling',
    'VirtualRun': 'running',
  };

  return typeMap[stravaType] || 'other';
}

/** Strava start_date_local ("2026-02-22T03:37:00") → UTC ISO ("2026-02-22T03:37:00.000Z") so DB shows same time as Strava. */
function localTimeToUtcIso(startDateLocal: string): string {
  const m = startDateLocal.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/);
  if (!m) return startDateLocal;
  const [, y, mo, d, h, min, s] = m;
  const date = new Date(Date.UTC(+y, +mo - 1, +d, +h, +min, +s || 0, 0));
  return date.toISOString();
}

/** start_date_local + elapsed_seconds → end time as UTC ISO (same “local display” convention). */
function addSecondsToLocalIso(startDateLocal: string, elapsedSeconds: number): string {
  const m = startDateLocal.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/);
  if (!m) return startDateLocal;
  const [, y, mo, d, h, min, s] = m;
  const ms = new Date(Date.UTC(+y, +mo - 1, +d, +h, +min, +s || 0, 0)).getTime() + elapsedSeconds * 1000;
  return new Date(ms).toISOString();
}

// Aktiviteyi veritabanına kaydet (webhook fonksiyonundaki ile aynı mantık)
async function saveActivityToDatabase(supabase: any, userId: string, activity: any): Promise<void> {
  const activityType = mapStravaTypeToActivityType(activity.type);

  // Pace hesapla (saniye/km)
  let averagePaceSeconds: number | null = null;
  if (activity.average_speed && activity.average_speed > 0 && activityType === 'running') {
    const km = activity.distance / 1000;
    averagePaceSeconds = Math.round(activity.moving_time / km);
  }

  let bestPaceSeconds: number | null = null;
  if (activity.max_speed && activity.max_speed > 0 && activityType === 'running') {
    bestPaceSeconds = Math.round(1 / (activity.max_speed / 1000));
  }

  const localStart = activity.start_date_local ?? activity.start_date;
  const startTimeIso = localTimeToUtcIso(localStart);
  const endTimeIso = addSecondsToLocalIso(localStart, activity.elapsed_time);

  const metadata: any = {};
  if (activity.start_latlng && Array.isArray(activity.start_latlng) && activity.start_latlng.length >= 2) {
    metadata.start_latlng = activity.start_latlng[0];
  }
  if (activity.end_latlng && Array.isArray(activity.end_latlng) && activity.end_latlng.length >= 2) {
    metadata.end_latlng = activity.end_latlng[0];
  }

  let averageCadence: number | null = null;
  if (activity.average_cadence != null) {
    if (activityType === 'running' || activityType === 'walking') {
      averageCadence = Math.round(activity.average_cadence * 2);
    } else {
      averageCadence = Math.round(activity.average_cadence);
    }
  }

  const activityData = {
    user_id: userId,
    activity_type: activityType,
    source: 'strava',
    external_id: activity.id.toString(),
    title: activity.name || 'Strava Aktivitesi',
    start_time: startTimeIso,
    end_time: endTimeIso,
    duration_seconds: activity.moving_time,
    distance_meters: activity.distance,
    elevation_gain: activity.total_elevation_gain || 0,
    average_pace_seconds: averagePaceSeconds,
    best_pace_seconds: bestPaceSeconds,
    average_heart_rate: activity.average_heartrate ? Math.round(activity.average_heartrate) : null,
    max_heart_rate: activity.max_heartrate ? Math.round(activity.max_heartrate) : null,
    average_cadence: averageCadence,
    route_polyline: activity.map?.polyline || null,
    calories_burned: activity.calories ? Math.round(activity.calories) : null,
    is_public: true,
    weather_conditions: Object.keys(metadata).length > 0 ? metadata : null,
  };

  const { data: existingActivity, error: selectError } = await supabase
    .from('activities')
    .select('id')
    .eq('user_id', userId)
    .eq('source', 'strava')
    .eq('external_id', activity.id.toString())
    .maybeSingle();

  if (selectError) {
    console.error('[Backfill] Error checking existing activity:', selectError);
    throw selectError;
  }

  if (existingActivity) {
    const { error: updateError } = await supabase
      .from('activities')
      .update(activityData)
      .eq('id', existingActivity.id);

    if (updateError) {
      console.error('[Backfill] Error updating activity:', updateError);
      throw updateError;
    }
    console.log(`[Backfill] Activity ${activity.id} updated in database`);
  } else {
    const { error: insertError } = await supabase
      .from('activities')
      .insert(activityData);

    if (insertError) {
      console.error('[Backfill] Error inserting activity:', insertError);
      throw insertError;
    }
    console.log(`[Backfill] Activity ${activity.id} inserted into database`);
  }
}

serve(async (req) => {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: corsHeaders });
  }

  try {
    const body = (await req.json().catch(() => ({}))) as BackfillRequestBody;
    const days = body.days && body.days > 0 ? body.days : 60; // default 60 gün
    const userLimit = body.user_limit && body.user_limit > 0 ? body.user_limit : undefined;
    const userOffset = body.user_offset && body.user_offset > 0 ? body.user_offset : 0;

    const now = Date.now();
    const afterUnixSeconds = Math.floor((now - days * 24 * 60 * 60 * 1000) / 1000);

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error('Supabase credentials missing');
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const stravaConfig = await getStravaConfig(supabase);

    // Tüm Strava entegrasyonlarını çek
    const { data: integrations, error: integrationsError } = await supabase
      .from('user_integrations')
      .select('user_id, access_token, refresh_token, token_expires_at')
      .eq('provider', 'strava')
      .order('user_id', { ascending: true });

    if (integrationsError) {
      console.error('[Backfill] Error fetching integrations:', integrationsError);
      throw integrationsError;
    }

    if (!integrations || integrations.length === 0) {
      return new Response(
        JSON.stringify({ message: 'No Strava integrations found' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const start = userOffset;
    const end = userLimit ? userOffset + userLimit : integrations.length;
    const limitedIntegrations = integrations.slice(start, end) as StravaIntegration[];

    let totalActivities = 0;

    for (const integration of limitedIntegrations) {
      try {
        console.log(`[Backfill] Processing user ${integration.user_id}`);

        let accessToken = integration.access_token;

        if (integration.token_expires_at && integration.refresh_token) {
          const expiresAt = new Date(integration.token_expires_at);
          if (expiresAt < new Date()) {
            console.log('[Backfill] Token expired, refreshing...');
            accessToken = await refreshStravaToken(stravaConfig, integration.refresh_token);

            await supabase
              .from('user_integrations')
              .update({
                access_token: accessToken,
                updated_at: new Date().toISOString(),
              })
              .eq('user_id', integration.user_id)
              .eq('provider', 'strava');
          }
        }

        const activities = await fetchStravaActivitiesForRange(accessToken, afterUnixSeconds);
        console.log(`[Backfill] Found ${activities.length} activities for user ${integration.user_id}`);

        for (const activity of activities) {
          await saveActivityToDatabase(supabase, integration.user_id, activity);
          totalActivities += 1;
        }
      } catch (err) {
        console.error(`[Backfill] Error processing user ${integration.user_id}:`, err);
      }
    }

    return new Response(
      JSON.stringify({
        message: 'Backfill completed',
        days,
        users_processed: limitedIntegrations.length,
        activities_processed: totalActivities,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  } catch (error: any) {
    console.error('[Backfill] Error:', error);
    return new Response(
      JSON.stringify({ error: error.message ?? 'Unknown error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  }
});

