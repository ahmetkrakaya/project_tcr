// Supabase Edge Function: Strava Webhook Handler
// Bu fonksiyon Strava'dan gelen webhook'ları işler ve aktiviteleri otomatik olarak senkronize eder

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const STRAVA_WEBHOOK_VERIFY_TOKEN = Deno.env.get('STRAVA_WEBHOOK_VERIFY_TOKEN') || 'tcr_webhook_verify_token_2024';

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

interface StravaWebhookEvent {
  object_type: 'activity' | 'athlete';
  object_id: number;
  aspect_type: 'create' | 'update' | 'delete';
  owner_id: number;
  subscription_id: number;
  event_time: number;
}

serve(async (req) => {
  // CORS headers
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };

  // Handle OPTIONS request for CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // Strava Webhook Verification (GET request) - Authorization gerektirmez
  if (req.method === 'GET') {
    try {
      const url = new URL(req.url);
      const mode = url.searchParams.get('hub.mode');
      const token = url.searchParams.get('hub.verify_token');
      const challenge = url.searchParams.get('hub.challenge');

      console.log('[Webhook] Verification request:', { mode, token, challenge });

      if (mode === 'subscribe' && token === STRAVA_WEBHOOK_VERIFY_TOKEN) {
        console.log('[Webhook] Verification successful');
        return new Response(
          JSON.stringify({ 'hub.challenge': challenge }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          }
        );
      } else {
        console.log('[Webhook] Verification failed');
        return new Response('Verification failed', { 
          headers: corsHeaders,
          status: 403 
        });
      }
    } catch (error) {
      console.error('[Webhook] Verification error:', error);
      return new Response(
        JSON.stringify({ error: error.message }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 500,
        }
      );
    }
  }

  try {
    // Supabase client oluştur
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    
    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error('Supabase credentials missing');
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Strava Webhook Event (POST request)
    if (req.method === 'POST') {
      const body: StravaWebhookEvent = await req.json();
      console.log('[Webhook] Event received:', JSON.stringify(body, null, 2));

      // Sadece activity create/update eventlerini işle
      if (body.object_type !== 'activity') {
        console.log('[Webhook] Ignoring non-activity event');
        return new Response('OK', { headers: corsHeaders, status: 200 });
      }

      if (body.aspect_type !== 'create' && body.aspect_type !== 'update') {
        console.log('[Webhook] Ignoring delete event');
        return new Response('OK', { headers: corsHeaders, status: 200 });
      }

      const activityId = body.object_id;
      const athleteId = body.owner_id;

      console.log(`[Webhook] Processing activity ${activityId} for athlete ${athleteId}`);

      // Athlete ID'ye göre kullanıcıyı bul
      const { data: integration, error: integrationError } = await supabase
        .from('user_integrations')
        .select('user_id, access_token, refresh_token, token_expires_at')
        .eq('provider', 'strava')
        .eq('provider_user_id', athleteId.toString())
        .single();

      if (integrationError || !integration) {
        console.log(`[Webhook] No integration found for athlete ${athleteId}:`, integrationError);
        return new Response('OK', { headers: corsHeaders, status: 200 });
      }

      console.log(`[Webhook] Found integration for user ${integration.user_id}`);

      // Token süresi dolmuşsa yenile
      let accessToken = integration.access_token;
      const stravaConfig = await getStravaConfig(supabase);
      if (integration.token_expires_at) {
        const expiresAt = new Date(integration.token_expires_at);
        if (expiresAt < new Date()) {
          console.log('[Webhook] Token expired, refreshing...');
          accessToken = await refreshStravaToken(stravaConfig, integration.refresh_token);
          
          // Yeni token'ı kaydet
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

      // Aktiviteyi Strava'dan çek
      const activity = await fetchStravaActivity(accessToken, activityId);
      if (!activity) {
        console.log(`[Webhook] Failed to fetch activity ${activityId}`);
        return new Response('OK', { headers: corsHeaders, status: 200 });
      }

      // Aktiviteyi veritabanına kaydet
      const isNewActivity = await saveActivityToDatabase(supabase, integration.user_id, activity);

      // Yeni koşu ise strava watch sistemini tetikle
      if (isNewActivity && activity.type === 'Run') {
        await triggerStravaWatchNotifications(supabase, integration.user_id, body);
      }

      console.log(`[Webhook] Activity ${activityId} synced successfully`);
      return new Response('OK', { headers: corsHeaders, status: 200 });
    }

    return new Response('Method not allowed', { status: 405 });
  } catch (error) {
    console.error('[Webhook] Error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      }
    );
  }
});

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

// Strava aktivitesini çek
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
      console.error(`[Webhook] Failed to fetch activity: ${response.statusText}`);
      return null;
    }

    return await response.json();
  } catch (error) {
    console.error('[Webhook] Error fetching activity:', error);
    return null;
  }
}

// Strava watch: koşu bildirimi alan üç kişi
const STRAVA_WATCH_OMER_ID = '376cd156-abdd-4c2e-85a8-35dc88043cc1';
const STRAVA_WATCH_AHMET_ID = 'b30a2dbf-6c44-4cc9-b740-12ed0ed08e37';
const STRAVA_WATCH_AYCA_ID = 'a9cb8485-af1e-4299-a744-088bdadacbc9';
const STRAVA_WATCH_RUNNER_IDS = [STRAVA_WATCH_AHMET_ID, STRAVA_WATCH_AYCA_ID];
const STRAVA_WATCH_RECIPIENT_IDS = [
  STRAVA_WATCH_OMER_ID,
  STRAVA_WATCH_AHMET_ID,
  STRAVA_WATCH_AYCA_ID,
];

const STRAVA_ALARM_COUNT = 5;

function stravaAlarmSoundId(index: number): string {
  const i = ((index % STRAVA_ALARM_COUNT) + STRAVA_ALARM_COUNT) % STRAVA_ALARM_COUNT;
  return `strava_alarm_${i + 1}`;
}

function randomStravaAlarmSound(): string {
  return stravaAlarmSoundId(Math.floor(Math.random() * STRAVA_ALARM_COUNT));
}

const AYCA_WATCH_TITLES = [
  'Samsun fırtınası Ayça sahalarda! 🌊',
  'Diyarbakır\'ın gülü Ayça sahalarda! 🌹',
  'Denizli\'nin biricik kızı Ayça sahalarda! 🐓',
  'Çarşamba\'nın parlayan yıldızı Ayça sahalarda! 🌟',
  "Pace'in kraliçesi Ayça sahalarda!",
  'Yücelerin yücesi Ayça sahalarda! 👑',
  'TCR\'nin gurur kaynağı Ayça koştu!',
  'Adım adım destan yazan Ayça sahalarda!',
  'Rüzgar bile Ayça\'nın peşinden koşuyor!',
  'Her kilometresi şiire dönen Ayça koştu!',
  'Nefesi güç, adımları ritim — Ayça sahalarda!',
  'İlham veren Ayça sahalarda!',
  'Kondisyon değil, karakter koşuyor — Ayça koştu!',
  'Bu tempoya ancak Ayça yetişir!',
  'Bugün yine Ayça\'dan koşu dersi var!',
  'Moral depoları Ayça koşunca doluyor!',
  'Kilometreler onun için küçük bir detay — Ayça sahalarda!',
  'Sahalar onu görünce canlanıyor — Ayça koştu!',
];

function watchMessageBodies(watchedName: string, distanceKm: string): string[] {
  return [
    `${distanceKm} km koşmuş, acilen bakman lazım!`,
    `${distanceKm} km — Ömer, hemen bak, kaçırma!`,
    `${distanceKm} km koşmuş. Deli mi bunlar, bir göz at!`,
    `${distanceKm} km koştu. Acilen incele, sonra pişman olursun.`,
    `${distanceKm} km koşmuş — bakmadan geçme, merak etme sonra!`,
  ];
}

// İlk koşu bildirimi: koşucuya özel başlıklar + rastgele ses
function getFirstWatchMessage(
  watchedUserId: string,
  watchedName: string,
  distanceKm: string,
): { title: string; body: string; sound: string } {
  const genericTitles = [
    `${watchedName} harika bir koşu yaptı.`,
    `${watchedName} koştu! 🏃`,
    `Dikkat! ${watchedName} sahalarda!`,
    `${watchedName} yine koşmuş!`,
    `Ömer, ${watchedName} koştu!`,
  ];

  let titles = genericTitles;
  if (watchedUserId === STRAVA_WATCH_AYCA_ID) {
    titles = [...AYCA_WATCH_TITLES, ...genericTitles];
  }

  const bodies = watchMessageBodies(watchedName, distanceKm);
  const title = titles[Math.floor(Math.random() * titles.length)];
  const body = bodies[Math.floor(Math.random() * bodies.length)];

  return {
    title,
    body,
    sound: randomStravaAlarmSound(),
  };
}

// Strava watch bildirimi: Ahmet veya Ayça koşunca Ömer + Ahmet + Ayça'ya bildirim
async function triggerStravaWatchNotifications(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  webhookEvent: StravaWebhookEvent,
): Promise<void> {
  try {
    if (!STRAVA_WATCH_RUNNER_IDS.includes(userId)) {
      console.log(`[Watch] User ${userId} is not a watched runner, skipping`);
      return;
    }

    // Aktivite kaydını veritabanından al (yeni eklenen)
    const { data: activityRecord, error: activityError } = await supabase
      .from('activities')
      .select('id, title, distance_meters, duration_seconds, average_pace_seconds, start_time')
      .eq('user_id', userId)
      .eq('source', 'strava')
      .eq('external_id', webhookEvent.object_id.toString())
      .maybeSingle();

    if (activityError || !activityRecord) {
      console.error('[Watch] Could not find activity record:', activityError);
      return;
    }

    // Koşuyu yapan kişinin adını al
    const { data: watchedUser } = await supabase
      .from('users')
      .select('first_name, last_name')
      .eq('id', userId)
      .maybeSingle();

    const watchedName = watchedUser
      ? `${watchedUser.first_name} ${watchedUser.last_name}`
      : 'Biri';

    const distanceKm = activityRecord.distance_meters
      ? (activityRecord.distance_meters / 1000).toFixed(1)
      : '?';

    for (const recipientUserId of STRAVA_WATCH_RECIPIENT_IDS) {
      // strava_watch_notifications: alıcı başına takip (viewed_at / hatırlatma)
      const { error: insertError } = await supabase
        .from('strava_watch_notifications')
        .insert({
          activity_id: activityRecord.id,
          watcher_user_id: recipientUserId,
          watched_user_id: userId,
          notification_count: 1,
        })
        .select()
        .maybeSingle();

      if (insertError && insertError.code !== '23505') {
        console.error('[Watch] Failed to insert watch notification:', insertError);
        continue;
      }

      if (insertError?.code === '23505') {
        console.log(`[Watch] Watch notification already exists for recipient ${recipientUserId}, skipping`);
        continue;
      }

      const { title, body, sound } = getFirstWatchMessage(
        userId,
        watchedName,
        distanceKm,
      );

      const { error: notifError } = await supabase
        .from('notifications')
        .insert({
          user_id: recipientUserId,
          type: 'strava_watch_run',
          title,
          body,
          data: {
            activity_id: activityRecord.id,
            watched_user_id: userId,
            sound,
          },
        });

      if (notifError) {
        console.error('[Watch] Failed to insert notification:', notifError);
      } else {
        console.log(`[Watch] Notification sent to ${recipientUserId} for activity ${activityRecord.id}`);
      }
    }
  } catch (err) {
    console.error('[Watch] triggerStravaWatchNotifications error:', err);
  }
}

// Aktiviteyi veritabanına kaydet; yeni kayıt ise true, güncelleme ise false döner
async function saveActivityToDatabase(supabase: any, userId: string, activity: any): Promise<boolean> {
  // Aktivite tipini belirle
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

  // Strava start_date UTC (00:37), start_date_local yerel saat (03:37). DB'de Strava'daki
  // saatin aynen görünmesi için start_date_local bileşenlerini UTC olarak yazıyoruz.
  const localStart = activity.start_date_local ?? activity.start_date;
  const startTimeIso = localTimeToUtcIso(localStart);
  const endTimeIso = addSecondsToLocalIso(localStart, activity.elapsed_time);

  // Metadata (start/end latlng)
  const metadata: any = {};
  if (activity.start_latlng && Array.isArray(activity.start_latlng) && activity.start_latlng.length >= 2) {
    metadata.start_latlng = activity.start_latlng[0];
  }
  if (activity.end_latlng && Array.isArray(activity.end_latlng) && activity.end_latlng.length >= 2) {
    metadata.end_latlng = activity.end_latlng[0];
  }

  // Strava API kadansı RPM (revolutions per minute - tek bacak) döndürür.
  // Koşu/yürüyüş için Garmin ve kullanıcılar SPM (steps per minute) bekler.
  // SPM = RPM * 2. Bisiklette RPM zaten doğru formatta.
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

  // Önce mevcut aktiviteyi kontrol et
  const { data: existingActivity, error: selectError } = await supabase
    .from('activities')
    .select('id')
    .eq('user_id', userId)
    .eq('source', 'strava')
    .eq('external_id', activity.id.toString())
    .maybeSingle();

  if (selectError) {
    console.error('[Webhook] Error checking existing activity:', selectError);
    throw selectError;
  }

  // Mevcut aktivite varsa güncelle, yoksa ekle
  if (existingActivity) {
    const { error: updateError } = await supabase
      .from('activities')
      .update(activityData)
      .eq('id', existingActivity.id);

    if (updateError) {
      console.error('[Webhook] Error updating activity:', updateError);
      throw updateError;
    }
    console.log(`[Webhook] Activity ${activity.id} updated in database`);
    return false;
  } else {
    const { error: insertError } = await supabase
      .from('activities')
      .insert(activityData);

    if (insertError) {
      console.error('[Webhook] Error inserting activity:', insertError);
      throw insertError;
    }
    console.log(`[Webhook] Activity ${activity.id} inserted into database`);
    return true;
  }
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

// Strava aktivite tipini uygulama aktivite tipine çevir
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
