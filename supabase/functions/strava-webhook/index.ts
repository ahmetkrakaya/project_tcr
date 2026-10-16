// Supabase Edge Function: Strava Webhook Handler
// Bu fonksiyon Strava'dan gelen webhook'ları işler ve aktiviteleri otomatik olarak senkronize eder

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  ensureValidAccessToken,
  stravaGet,
  StravaNotFoundError,
  StravaRateLimitError,
  type SupabaseClient,
} from '../_shared/strava_client.ts';
import { saveActivityDetailChildren, upsertActivity } from '../_shared/strava_activity_mapper.ts';
import { recomputeActivityAnalysis } from '../_shared/strava_enrich.ts';

const STRAVA_WEBHOOK_VERIFY_TOKEN = Deno.env.get('STRAVA_WEBHOOK_VERIFY_TOKEN') || 'tcr_webhook_verify_token_2024';

interface StravaWebhookEvent {
  object_type: 'activity' | 'athlete';
  object_id: number;
  aspect_type: 'create' | 'update' | 'delete';
  owner_id: number;
  subscription_id: number;
  event_time: number;
  updates?: Record<string, string>;
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
        JSON.stringify({ error: error instanceof Error ? error.message : String(error) }),
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

      const activityId = body.object_id;
      const athleteId = body.owner_id;

      // Kullanıcı Strava'dan uygulamanın erişimini kaldırdı
      if (body.object_type === 'athlete') {
        if (body.updates?.authorized === 'false') {
          const { error: deauthError } = await supabase
            .from('user_integrations')
            .delete()
            .eq('provider', 'strava')
            .eq('provider_user_id', athleteId.toString());
          if (deauthError) console.error('[Webhook] Deauthorize cleanup failed:', deauthError);
          console.log(`[Webhook] Athlete ${athleteId} deauthorized, integration removed`);
        }
        return new Response('OK', { headers: corsHeaders, status: 200 });
      }

      if (body.object_type !== 'activity') {
        return new Response('OK', { headers: corsHeaders, status: 200 });
      }

      console.log(`[Webhook] Processing ${body.aspect_type} for activity ${activityId} (athlete ${athleteId})`);

      // Athlete ID'ye göre kullanıcıyı bul
      const { data: integration, error: integrationError } = await supabase
        .from('user_integrations')
        .select('user_id, access_token, refresh_token, token_expires_at, athlete_zones')
        .eq('provider', 'strava')
        .eq('provider_user_id', athleteId.toString())
        .maybeSingle();

      if (integrationError || !integration) {
        console.log(`[Webhook] No integration found for athlete ${athleteId}:`, integrationError);
        return new Response('OK', { headers: corsHeaders, status: 200 });
      }

      // Strava'da silinen aktivite bizde de silinir (detay tabloları cascade)
      if (body.aspect_type === 'delete') {
        const { error: deleteError } = await supabase
          .from('activities')
          .delete()
          .eq('user_id', integration.user_id)
          .eq('source', 'strava')
          .eq('external_id', activityId.toString());
        if (deleteError) console.error('[Webhook] Activity delete failed:', deleteError);
        await supabase.from('strava_enrichment_queue').delete().eq('strava_activity_id', activityId);
        return new Response('OK', { headers: corsHeaders, status: 200 });
      }

      const { data: userRow } = await supabase
        .from('users')
        .select('is_active, user_status')
        .eq('id', integration.user_id)
        .maybeSingle();

      if (!userRow || userRow.is_active !== true || userRow.user_status !== 'active') {
        console.log(`[Webhook] Skipping sync for inactive/banned user ${integration.user_id}`);
        return new Response('OK', { headers: corsHeaders, status: 200 });
      }

      console.log(`[Webhook] Found integration for user ${integration.user_id}`);

      const accessToken = await ensureValidAccessToken(supabase, integration);

      // DetailedActivity: özet + laps + splits + best efforts tek istekte gelir
      let activity: any;
      try {
        activity = await stravaGet(supabase, accessToken, `/activities/${activityId}`);
      } catch (e) {
        if (e instanceof StravaRateLimitError) {
          // Limit açılınca worker çeker
          await supabase.rpc('enqueue_strava_enrichment', {
            p_user_id: integration.user_id,
            p_strava_activity_id: activityId,
            p_mode: 'refresh',
            p_priority: 0,
          });
          console.log(`[Webhook] Rate limited, activity ${activityId} queued`);
        } else if (!(e instanceof StravaNotFoundError)) {
          console.error(`[Webhook] Failed to fetch activity ${activityId}:`, e);
        }
        return new Response('OK', { headers: corsHeaders, status: 200 });
      }

      // Yeni kayıtlar insert trigger'ı ile zenginleştirme kuyruğuna girer (streams vb.)
      const saved = await upsertActivity(supabase, integration.user_id, activity);
      await saveActivityDetailChildren(supabase, saved.id, activity);

      // Güncellemede (ör. tur/başlık düzenleme) kayıtlı stream ile analiz yenilenir; Strava'ya ek istek yok
      if (!saved.isNew && saved.activityType === 'running') {
        try {
          await recomputeActivityAnalysis(
            supabase,
            saved.id,
            integration.athlete_zones?.heart_rate?.zones ?? null,
          );
        } catch (e) {
          console.error(`[Webhook] Recompute failed for activity ${activityId}:`, e);
        }
      }

      // Yeni koşu ise strava watch sistemini tetikle
      if (saved.isNew && activity.type === 'Run') {
        await triggerStravaWatchNotifications(supabase, integration.user_id, body);
      }

      console.log(`[Webhook] Activity ${activityId} synced successfully`);
      return new Response('OK', { headers: corsHeaders, status: 200 });
    }

    return new Response('Method not allowed', { status: 405 });
  } catch (error) {
    console.error('[Webhook] Error:', error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      }
    );
  }
});

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
  'Yanındakilere güç veren Ayça sahalarda!',
  'Bir varlığıyla ortamı yükselten Ayça koştu!',
  'Duruşuyla örnek, temposuyla ilham — Ayça!',
  'Çevresine enerji saçan Ayça sahalarda!',
  'Hem güç katar hem yol gösterir — Ayça koştu!',
  'Onunla koşmak bile moral düzeltiyor!',
  'TCR\'nin en değerli enerjilerinden: Ayça!',
  'Varlığıyla herkesi ayakta tutan Ayça koştu!',
  'Güçlü, net, vazgeçilmez — Ayça sahalarda!',
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
  supabase: SupabaseClient,
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
