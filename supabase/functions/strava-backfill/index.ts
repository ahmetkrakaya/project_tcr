// Supabase Edge Function: Strava Backfill
// Tüm Strava kullanıcıları için geçmiş aktiviteleri (örn. son 2 ay) toplu olarak senkronize eder,
// ardından detay/stream eksik koşuları strava-enrich kuyruğuna düşük öncelikle ekler.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { isServiceRoleRequest } from '../_shared/service_auth.ts';
import {
  ensureValidAccessToken,
  stravaGet,
  StravaRateLimitError,
  type SupabaseClient,
} from '../_shared/strava_client.ts';
import { upsertActivitiesBulk } from '../_shared/strava_activity_mapper.ts';

interface BackfillRequestBody {
  days?: number;           // Kaç günlük geçmiş (default: 60)
  user_limit?: number;     // Test için maksimum kaç kullanıcı (opsiyonel)
  user_offset?: number;    // Kaç kullanıcıyı atlayarak başlasın (opsiyonel)
  enqueue_only?: boolean;  // Strava listesini çekmeden sadece eksik detayları kuyruğa ekle
  enqueue_limit?: number;  // Kuyruğa eklenecek maksimum aktivite (default: 2000)
}

interface StravaIntegration {
  user_id: string;
  access_token: string;
  refresh_token: string | null;
  token_expires_at: string | null;
}

// Belirli bir kullanıcı için verilen zaman aralığındaki aktiviteleri listele
async function fetchStravaActivitiesForRange(
  supabase: SupabaseClient,
  accessToken: string,
  afterUnixSeconds: number,
): Promise<any[]> {
  const activities: any[] = [];
  const perPage = 100;

  for (let page = 1; page <= 10; page++) {
    const pageData = await stravaGet<any[]>(supabase, accessToken, '/athlete/activities', {
      after: String(afterUnixSeconds),
      per_page: String(perPage),
      page: String(page),
    });
    if (!Array.isArray(pageData) || pageData.length === 0) break;
    activities.push(...pageData);
    if (pageData.length < perPage) break;
  }

  return activities;
}

serve(async (req) => {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error('Supabase credentials missing');
    }
    if (!isServiceRoleRequest(req, supabaseServiceKey)) {
      return json({ error: 'Unauthorized' }, 401);
    }

    const body = (await req.json().catch(() => ({}))) as BackfillRequestBody;
    const days = body.days && body.days > 0 ? body.days : 60;
    const userLimit = body.user_limit && body.user_limit > 0 ? body.user_limit : undefined;
    const userOffset = body.user_offset && body.user_offset > 0 ? body.user_offset : 0;
    const enqueueLimit = body.enqueue_limit && body.enqueue_limit > 0 ? body.enqueue_limit : 2000;

    const afterUnixSeconds = Math.floor((Date.now() - days * 24 * 60 * 60 * 1000) / 1000);
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    let usersProcessed = 0;
    let totalActivities = 0;
    let rateLimitedUntil: string | null = null;

    if (!body.enqueue_only) {
      const { data: integrations, error: integrationsError } = await supabase
        .from('user_integrations')
        .select('user_id, access_token, refresh_token, token_expires_at')
        .eq('provider', 'strava')
        .order('user_id', { ascending: true });

      if (integrationsError) {
        console.error('[Backfill] Error fetching integrations:', integrationsError);
        throw integrationsError;
      }

      const end = userLimit ? userOffset + userLimit : (integrations ?? []).length;
      const limitedIntegrations = (integrations ?? []).slice(userOffset, end) as StravaIntegration[];

      for (const integration of limitedIntegrations) {
        try {
          console.log(`[Backfill] Processing user ${integration.user_id}`);
          const accessToken = await ensureValidAccessToken(supabase, integration);
          const activities = await fetchStravaActivitiesForRange(supabase, accessToken, afterUnixSeconds);
          console.log(`[Backfill] Found ${activities.length} activities for user ${integration.user_id}`);

          for (let i = 0; i < activities.length; i += 100) {
            await upsertActivitiesBulk(supabase, integration.user_id, activities.slice(i, i + 100));
          }
          totalActivities += activities.length;
          usersProcessed += 1;
        } catch (err) {
          if (err instanceof StravaRateLimitError) {
            rateLimitedUntil = err.retryAt.toISOString();
            console.warn(`[Backfill] Rate limited until ${rateLimitedUntil}; continue with user_offset=${userOffset + usersProcessed}`);
            break;
          }
          console.error(`[Backfill] Error processing user ${integration.user_id}:`, err);
          usersProcessed += 1;
        }
      }
    }

    const { data: enqueued, error: enqueueError } = await supabase.rpc('enqueue_strava_backfill', {
      p_days: days,
      p_limit: enqueueLimit,
    });
    if (enqueueError) console.error('[Backfill] Enqueue failed:', enqueueError);

    return json({
      message: rateLimitedUntil ? 'Backfill paused (Strava rate limit)' : 'Backfill completed',
      days,
      users_processed: usersProcessed,
      next_user_offset: rateLimitedUntil ? userOffset + usersProcessed : null,
      rate_limited_until: rateLimitedUntil,
      activities_processed: totalActivities,
      enqueued_for_enrichment: enqueued ?? 0,
    });
  } catch (error: any) {
    console.error('[Backfill] Error:', error);
    return json({ error: error.message ?? 'Unknown error' }, 500);
  }
});
