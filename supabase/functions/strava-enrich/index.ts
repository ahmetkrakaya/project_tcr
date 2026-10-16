// Supabase Edge Function: Strava Enrich Worker
// pg_cron (her 2 dk) tarafından tetiklenir. strava_enrichment_queue'dan iş alır,
// Strava rate limit'ine uyarak aktivite detayını / stream'lerini çeker ve analizleri hesaplar.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { isServiceRoleRequest } from '../_shared/service_auth.ts';
import { getRateLimitBlock } from '../_shared/strava_client.ts';
import { enrichActivity, type EnrichmentJob } from '../_shared/strava_enrich.ts';

const DEFAULT_BATCH = 5;
const MAX_BATCH = 20;
const MAX_ATTEMPTS = 5;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (!supabaseUrl || !serviceKey) return json({ error: 'Supabase credentials missing' }, 500);

  if (!isServiceRoleRequest(req, serviceKey)) return json({ error: 'Unauthorized' }, 401);

  const supabase = createClient(supabaseUrl, serviceKey);
  const body = await req.json().catch(() => ({}));
  const batch = Math.min(MAX_BATCH, Math.max(1, Number(body?.batch) || DEFAULT_BATCH));

  const blockedUntil = await getRateLimitBlock(supabase);
  if (blockedUntil) {
    return json({ message: 'rate_limited', blocked_until: blockedUntil.toISOString() });
  }

  const { data: jobs, error } = await supabase.rpc('claim_strava_enrichment_jobs', { p_limit: batch });
  if (error) return json({ error: error.message }, 500);

  const results: Record<string, number> = { done: 0, skipped: 0, failed: 0, rate_limited: 0, requeued: 0 };
  const claimed = (jobs ?? []) as EnrichmentJob[];

  for (let i = 0; i < claimed.length; i++) {
    const job = claimed[i];
    const outcome = await enrichActivity(supabase, job);

    if (outcome.status === 'rate_limited') {
      // Bu ve kalan işler limit açılınca tekrar denenir; deneme sayısı yanmaz
      const pending = claimed.slice(i);
      for (const j of pending) {
        await supabase
          .from('strava_enrichment_queue')
          .update({
            status: 'pending',
            attempts: Math.max(0, j.attempts - 1),
            next_attempt_at: outcome.retryAt.toISOString(),
            locked_at: null,
          })
          .eq('id', j.id);
      }
      results.rate_limited += 1;
      results.requeued += pending.length - 1;
      break;
    }

    if (outcome.status === 'done' || outcome.status === 'skipped') {
      await supabase
        .from('strava_enrichment_queue')
        .update({
          status: outcome.status,
          last_error: outcome.status === 'skipped' ? outcome.reason : null,
          locked_at: null,
        })
        .eq('id', job.id);
      results[outcome.status] += 1;
      continue;
    }

    const giveUp = !outcome.retryable || job.attempts >= MAX_ATTEMPTS;
    const backoffMinutes = 2 ** Math.min(job.attempts, 6);
    await supabase
      .from('strava_enrichment_queue')
      .update({
        status: giveUp ? 'failed' : 'pending',
        last_error: outcome.error.slice(0, 1000),
        next_attempt_at: new Date(Date.now() + backoffMinutes * 60 * 1000).toISOString(),
        locked_at: null,
      })
      .eq('id', job.id);
    console.error(`[Enrich] Job ${job.id} (activity ${job.strava_activity_id}) failed: ${outcome.error}`);
    results.failed += 1;
  }

  return json({ message: 'ok', claimed: claimed.length, ...results });
});
