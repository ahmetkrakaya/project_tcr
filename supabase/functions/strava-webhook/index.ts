// // Supabase Edge Function: Strava Webhook Handler
// // Bu fonksiyon Strava'dan gelen webhook'ları işler ve aktiviteleri otomatik olarak senkronize eder

// import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
// import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// const STRAVA_CLIENT_ID = Deno.env.get('STRAVA_CLIENT_ID') || '';
// const STRAVA_CLIENT_SECRET = Deno.env.get('STRAVA_CLIENT_SECRET') || '';
// const STRAVA_WEBHOOK_VERIFY_TOKEN = Deno.env.get('STRAVA_WEBHOOK_VERIFY_TOKEN') || 'tcr_webhook_verify_token_2024';

// interface StravaWebhookEvent {
//   object_type: 'activity' | 'athlete';
//   object_id: number;
//   aspect_type: 'create' | 'update' | 'delete';
//   owner_id: number;
//   subscription_id: number;
//   event_time: number;
// }

// serve(async (req) => {
//   // CORS headers
//   const corsHeaders = {
//     'Access-Control-Allow-Origin': '*',
//     'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
//   };

//   // Handle OPTIONS request for CORS
//   if (req.method === 'OPTIONS') {
//     return new Response('ok', { headers: corsHeaders });
//   }

//   // Strava Webhook Verification (GET request) - Authorization gerektirmez
//   if (req.method === 'GET') {
//     try {
//       const url = new URL(req.url);
//       const mode = url.searchParams.get('hub.mode');
//       const token = url.searchParams.get('hub.verify_token');
//       const challenge = url.searchParams.get('hub.challenge');

//       console.log('[Webhook] Verification request:', { mode, token, challenge });

//       if (mode === 'subscribe' && token === STRAVA_WEBHOOK_VERIFY_TOKEN) {
//         console.log('[Webhook] Verification successful');
//         return new Response(
//           JSON.stringify({ 'hub.challenge': challenge }),
//           {
//             headers: { ...corsHeaders, 'Content-Type': 'application/json' },
//             status: 200,
//           }
//         );
//       } else {
//         console.log('[Webhook] Verification failed');
//         return new Response('Verification failed', { 
//           headers: corsHeaders,
//           status: 403 
//         });
//       }
//     } catch (error) {
//       console.error('[Webhook] Verification error:', error);
//       return new Response(
//         JSON.stringify({ error: error.message }),
//         {
//           headers: { ...corsHeaders, 'Content-Type': 'application/json' },
//           status: 500,
//         }
//       );
//     }
//   }

//   try {
//     // Supabase client oluştur
//     const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
//     const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    
//     if (!supabaseUrl || !supabaseServiceKey) {
//       throw new Error('Supabase credentials missing');
//     }

//     const supabase = createClient(supabaseUrl, supabaseServiceKey);

//     // Strava Webhook Event (POST request)
//     if (req.method === 'POST') {
//       const body: StravaWebhookEvent = await req.json();
//       console.log('[Webhook] Event received:', JSON.stringify(body, null, 2));

//       // Sadece activity create/update eventlerini işle
//       if (body.object_type !== 'activity') {
//         console.log('[Webhook] Ignoring non-activity event');
//         return new Response('OK', { headers: corsHeaders, status: 200 });
//       }

//       if (body.aspect_type !== 'create' && body.aspect_type !== 'update') {
//         console.log('[Webhook] Ignoring delete event');
//         return new Response('OK', { headers: corsHeaders, status: 200 });
//       }

//       const activityId = body.object_id;
//       const athleteId = body.owner_id;

//       console.log(`[Webhook] Processing activity ${activityId} for athlete ${athleteId}`);

//       // Athlete ID'ye göre kullanıcıyı bul
//       const { data: integration, error: integrationError } = await supabase
//         .from('user_integrations')
//         .select('user_id, access_token, refresh_token, token_expires_at')
//         .eq('provider', 'strava')
//         .eq('provider_user_id', athleteId.toString())
//         .single();

//       if (integrationError || !integration) {
//         console.log(`[Webhook] No integration found for athlete ${athleteId}:`, integrationError);
//         return new Response('OK', { headers: corsHeaders, status: 200 });
//       }

//       console.log(`[Webhook] Found integration for user ${integration.user_id}`);

//       // Token süresi dolmuşsa yenile
//       let accessToken = integration.access_token;
//       if (integration.token_expires_at) {
//         const expiresAt = new Date(integration.token_expires_at);
//         if (expiresAt < new Date()) {
//           console.log('[Webhook] Token expired, refreshing...');
//           accessToken = await refreshStravaToken(integration.refresh_token);
          
//           // Yeni token'ı kaydet
//           await supabase
//             .from('user_integrations')
//             .update({
//               access_token: accessToken,
//               updated_at: new Date().toISOString(),
//             })
//             .eq('user_id', integration.user_id)
//             .eq('provider', 'strava');
//         }
//       }

//       // Aktiviteyi Strava'dan çek
//       const activity = await fetchStravaActivity(accessToken, activityId);
//       if (!activity) {
//         console.log(`[Webhook] Failed to fetch activity ${activityId}`);
//         return new Response('OK', { headers: corsHeaders, status: 200 });
//       }

//       // Aktiviteyi veritabanına kaydet
//       await saveActivityToDatabase(supabase, integration.user_id, activity);

//       console.log(`[Webhook] Activity ${activityId} synced successfully`);
//       return new Response('OK', { headers: corsHeaders, status: 200 });
//     }

//     return new Response('Method not allowed', { status: 405 });
//   } catch (error) {
//     console.error('[Webhook] Error:', error);
//     return new Response(
//       JSON.stringify({ error: error.message }),
//       {
//         headers: { ...corsHeaders, 'Content-Type': 'application/json' },
//         status: 500,
//       }
//     );
//   }
// });

// // Strava token yenileme
// async function refreshStravaToken(refreshToken: string): Promise<string> {
//   const response = await fetch('https://www.strava.com/oauth/token', {
//     method: 'POST',
//     headers: { 'Content-Type': 'application/json' },
//     body: JSON.stringify({
//       client_id: STRAVA_CLIENT_ID,
//       client_secret: STRAVA_CLIENT_SECRET,
//       refresh_token: refreshToken,
//       grant_type: 'refresh_token',
//     }),
//   });

//   if (!response.ok) {
//     throw new Error(`Token refresh failed: ${response.statusText}`);
//   }

//   const data = await response.json();
//   return data.access_token;
// }

// // Strava aktivitesini çek
// async function fetchStravaActivity(accessToken: string, activityId: number): Promise<any | null> {
//   try {
//     const response = await fetch(
//       `https://www.strava.com/api/v3/activities/${activityId}`,
//       {
//         headers: {
//           'Authorization': `Bearer ${accessToken}`,
//         },
//       }
//     );

//     if (!response.ok) {
//       console.error(`[Webhook] Failed to fetch activity: ${response.statusText}`);
//       return null;
//     }

//     return await response.json();
//   } catch (error) {
//     console.error('[Webhook] Error fetching activity:', error);
//     return null;
//   }
// }

// // Aktiviteyi veritabanına kaydet
// async function saveActivityToDatabase(supabase: any, userId: string, activity: any): Promise<void> {
//   // Aktivite tipini belirle
//   const activityType = mapStravaTypeToActivityType(activity.type);

//   // Pace hesapla (saniye/km)
//   let averagePaceSeconds: number | null = null;
//   if (activity.average_speed && activity.average_speed > 0 && activityType === 'running') {
//     const km = activity.distance / 1000;
//     averagePaceSeconds = Math.round(activity.moving_time / km);
//   }

//   let bestPaceSeconds: number | null = null;
//   if (activity.max_speed && activity.max_speed > 0 && activityType === 'running') {
//     bestPaceSeconds = Math.round(1 / (activity.max_speed / 1000));
//   }

//   const endTime = new Date(new Date(activity.start_date).getTime() + activity.elapsed_time * 1000);

//   // Metadata (start/end latlng)
//   const metadata: any = {};
//   if (activity.start_latlng && Array.isArray(activity.start_latlng) && activity.start_latlng.length >= 2) {
//     metadata.start_latlng = activity.start_latlng[0];
//   }
//   if (activity.end_latlng && Array.isArray(activity.end_latlng) && activity.end_latlng.length >= 2) {
//     metadata.end_latlng = activity.end_latlng[0];
//   }

//   const activityData = {
//     user_id: userId,
//     activity_type: activityType,
//     source: 'strava',
//     external_id: activity.id.toString(),
//     title: activity.name || 'Strava Aktivitesi',
//     start_time: activity.start_date,
//     end_time: endTime.toISOString(),
//     duration_seconds: activity.moving_time,
//     distance_meters: activity.distance,
//     elevation_gain: activity.total_elevation_gain || 0,
//     average_pace_seconds: averagePaceSeconds,
//     best_pace_seconds: bestPaceSeconds,
//     average_heart_rate: activity.average_heartrate ? Math.round(activity.average_heartrate) : null,
//     max_heart_rate: activity.max_heartrate ? Math.round(activity.max_heartrate) : null,
//     average_cadence: activity.average_cadence ? Math.round(activity.average_cadence) : null,
//     route_polyline: activity.map?.polyline || null,
//     calories_burned: activity.calories ? Math.round(activity.calories) : null,
//     is_public: true,
//     weather_conditions: Object.keys(metadata).length > 0 ? metadata : null,
//   };

//   // Önce mevcut aktiviteyi kontrol et
//   const { data: existingActivity, error: selectError } = await supabase
//     .from('activities')
//     .select('id')
//     .eq('user_id', userId)
//     .eq('source', 'strava')
//     .eq('external_id', activity.id.toString())
//     .maybeSingle();

//   if (selectError) {
//     console.error('[Webhook] Error checking existing activity:', selectError);
//     throw selectError;
//   }

//   // Mevcut aktivite varsa güncelle, yoksa ekle
//   if (existingActivity) {
//     const { error: updateError } = await supabase
//       .from('activities')
//       .update(activityData)
//       .eq('id', existingActivity.id);

//     if (updateError) {
//       console.error('[Webhook] Error updating activity:', updateError);
//       throw updateError;
//     }
//     console.log(`[Webhook] Activity ${activity.id} updated in database`);
//   } else {
//     const { error: insertError } = await supabase
//       .from('activities')
//       .insert(activityData);

//     if (insertError) {
//       console.error('[Webhook] Error inserting activity:', insertError);
//       throw insertError;
//     }
//     console.log(`[Webhook] Activity ${activity.id} inserted into database`);
//   }
// }

// // Strava aktivite tipini uygulama aktivite tipine çevir
// function mapStravaTypeToActivityType(stravaType: string): string {
//   const typeMap: Record<string, string> = {
//     'Run': 'running',
//     'Ride': 'cycling',
//     'Walk': 'walking',
//     'Hike': 'hiking',
//     'Swim': 'swimming',
//     'Workout': 'workout',
//     'VirtualRide': 'cycling',
//     'VirtualRun': 'running',
//   };

//   return typeMap[stravaType] || 'other';
// }
