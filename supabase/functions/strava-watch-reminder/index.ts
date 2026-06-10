// Supabase Edge Function: strava-watch-reminder
// Saatlik cron job ile çalışır. Ömer, Ahmet/Ayça'nın koşusunu görmediyse
// espirili hatırlatma bildirimleri gönderir.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const STRAVA_ALARM_COUNT = 5;

function stravaAlarmSoundId(index: number): string {
  const i = ((index % STRAVA_ALARM_COUNT) + STRAVA_ALARM_COUNT) % STRAVA_ALARM_COUNT;
  return `strava_alarm_${i + 1}`;
}

// Notification count'a göre espirili başlık ve içerik seçici
// count: şimdiye kadar kaç bildirim gönderildi (1 = ilk bildirim zaten gitti, bu 2. hatırlatma)
function getReminderMessage(
  count: number,
  watchedName: string,
  distanceKm: string,
): { title: string; body: string; sound: string } {
  const messages: Array<{ title: string; body: string }> = [
    // 2. bildirim (count === 1 iken bu çalışır, 1 hatırlatma önceden gitmişti)
    {
      title: `Hala bakmadın! ${watchedName} bekliyorr 👀`,
      body: `${watchedName} ${distanceKm} km koşmuş, sen hala bakmadın. Ne bekliyorsun?`,
    },
    // 3. bildirim
    {
      title: `Baksana bir zahmet! 🏃‍♂️`,
      body: `${watchedName}'ın koşusunu görmeden geçme! ${distanceKm} km bu!`,
    },
    // 4. bildirim
    {
      title: `Ömer! Duydun mu? ${watchedName} koştu!`,
      body: `Saatler geçiyor, ${watchedName} ${distanceKm} km koşmuş sen hala bakmıyorsun 😤`,
    },
    // 5. bildirim
    {
      title: `ÖMER! NEDEN BAKMIYORSUN?! 😡`,
      body: `${watchedName} ${distanceKm} km koştu. Bu kadar ilgisizlik olmaz ya!`,
    },
    // 6. bildirim ve sonrası
    {
      title: `Tamam artık bu alay konusu oldu 🤦`,
      body: `${watchedName} ${distanceKm} km, sen hala yok. Sana özel bildirim patlaması devam edecek...`,
    },
  ];

  const index = Math.min(Math.max(0, count - 1), messages.length - 1);
  return {
    ...messages[index],
    sound: stravaAlarmSoundId(index),
  };
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error('Supabase credentials missing');
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Görülmemiş ve son 1 saat içinde bildirim gönderilmemiş koşuları bul
    const { data: pendingNotifications, error: fetchError } = await supabase
      .from('strava_watch_notifications')
      .select(`
        id,
        activity_id,
        watcher_user_id,
        watched_user_id,
        notification_count,
        last_notified_at
      `)
      .is('viewed_at', null)
      .lt('last_notified_at', new Date(Date.now() - 60 * 60 * 1000).toISOString());

    if (fetchError) {
      console.error('[Reminder] Fetch error:', fetchError);
      throw fetchError;
    }

    if (!pendingNotifications || pendingNotifications.length === 0) {
      console.log('[Reminder] No pending notifications to send');
      return new Response(
        JSON.stringify({ ok: true, sent: 0 }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    console.log(`[Reminder] Processing ${pendingNotifications.length} pending notifications`);

    let sentCount = 0;

    for (const pending of pendingNotifications) {
      try {
        // Aktivite bilgilerini al
        const { data: activity } = await supabase
          .from('activities')
          .select('id, title, distance_meters, start_time')
          .eq('id', pending.activity_id)
          .maybeSingle();

        if (!activity) {
          console.log(`[Reminder] Activity ${pending.activity_id} not found, skipping`);
          continue;
        }

        // Koşuyu yapan kişinin adını al
        const { data: watchedUser } = await supabase
          .from('users')
          .select('first_name, last_name')
          .eq('id', pending.watched_user_id)
          .maybeSingle();

        const watchedName = watchedUser
          ? `${watchedUser.first_name} ${watchedUser.last_name}`
          : 'Biri';

        const distanceKm = activity.distance_meters
          ? (activity.distance_meters / 1000).toFixed(1)
          : '?';

        const { title, body, sound } = getReminderMessage(
          pending.notification_count,
          watchedName,
          distanceKm,
        );

        // notifications tablosuna yeni kayıt → send-push-on-notification tetiklenir
        const { error: notifError } = await supabase
          .from('notifications')
          .insert({
            user_id: pending.watcher_user_id,
            type: 'strava_watch_run',
            title,
            body,
            data: {
              activity_id: pending.activity_id,
              watched_user_id: pending.watched_user_id,
              sound,
            },
          });

        if (notifError) {
          console.error('[Reminder] Failed to insert notification:', notifError);
          continue;
        }

        // strava_watch_notifications güncelle
        const { error: updateError } = await supabase
          .from('strava_watch_notifications')
          .update({
            last_notified_at: new Date().toISOString(),
            notification_count: pending.notification_count + 1,
          })
          .eq('id', pending.id);

        if (updateError) {
          console.error('[Reminder] Failed to update watch notification:', updateError);
        } else {
          sentCount++;
          console.log(`[Reminder] Sent reminder #${pending.notification_count + 1} for activity ${pending.activity_id}`);
        }
      } catch (err) {
        console.error('[Reminder] Error processing notification:', pending.id, err);
      }
    }

    return new Response(
      JSON.stringify({ ok: true, sent: sentCount, total: pendingNotifications.length }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (error) {
    console.error('[Reminder] Error:', error);
    return new Response(
      JSON.stringify({ ok: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
