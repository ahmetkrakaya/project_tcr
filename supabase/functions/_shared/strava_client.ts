// Strava API istemcisi: OAuth config, token yenileme ve rate-limit takibi.
// strava-webhook, strava-backfill ve strava-enrich tarafından ortak kullanılır.

// Şema tipleri üretilmediği için generic client 'never' tablolara çözülüyor
// deno-lint-ignore no-explicit-any
export type SupabaseClient = any;

const STRAVA_API = 'https://www.strava.com/api/v3';

export class StravaRateLimitError extends Error {
  constructor(public retryAt: Date) {
    super(`Strava rate limit; retry at ${retryAt.toISOString()}`);
  }
}

export class StravaNotFoundError extends Error {
  constructor(path: string) {
    super(`Strava resource not found: ${path}`);
  }
}

export class StravaAuthError extends Error {
  constructor(message: string) {
    super(message);
  }
}

export async function getStravaConfig(
  supabase: SupabaseClient,
): Promise<{ client_id: string; client_secret: string }> {
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

interface IntegrationTokenRow {
  user_id: string;
  access_token: string;
  refresh_token: string | null;
  token_expires_at: string | null;
}

/** Süresi dolmuş (veya 2 dk içinde dolacak) token'ı yeniler ve DB'ye yazar. */
export async function ensureValidAccessToken(
  supabase: SupabaseClient,
  integration: IntegrationTokenRow,
): Promise<string> {
  const expiresAt = integration.token_expires_at ? new Date(integration.token_expires_at) : null;
  if (expiresAt && expiresAt.getTime() > Date.now() + 2 * 60 * 1000) {
    return integration.access_token;
  }
  if (!integration.refresh_token) {
    if (!expiresAt) return integration.access_token;
    throw new StravaAuthError('Strava token expired and no refresh token');
  }

  const config = await getStravaConfig(supabase);
  const response = await fetch('https://www.strava.com/oauth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id: config.client_id,
      client_secret: config.client_secret,
      refresh_token: integration.refresh_token,
      grant_type: 'refresh_token',
    }),
  });

  if (!response.ok) {
    throw new StravaAuthError(`Token refresh failed: ${response.status} ${response.statusText}`);
  }

  const data = await response.json();
  const update: Record<string, unknown> = {
    access_token: data.access_token,
    updated_at: new Date().toISOString(),
  };
  if (data.refresh_token) update.refresh_token = data.refresh_token;
  if (data.expires_at) update.token_expires_at = new Date(data.expires_at * 1000).toISOString();

  await supabase
    .from('user_integrations')
    .update(update)
    .eq('user_id', integration.user_id)
    .eq('provider', 'strava');

  return data.access_token as string;
}

function parsePair(value: string | null): [number, number] | null {
  if (!value) return null;
  const parts = value.split(',').map((p) => parseInt(p.trim(), 10));
  if (parts.length < 2 || parts.some((p) => Number.isNaN(p))) return null;
  return [parts[0], parts[1]];
}

function nextQuarterHour(now = new Date()): Date {
  const d = new Date(now);
  d.setUTCSeconds(0, 0);
  d.setUTCMinutes(Math.floor(d.getUTCMinutes() / 15) * 15 + 15);
  return d;
}

function nextUtcMidnight(now = new Date()): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1, 0, 0, 5));
}

const RATE_MARGIN = 5;

/** Header'lardaki kullanımı kaydeder; limite yaklaşıldıysa blocked_until döner. */
async function recordRateLimit(supabase: SupabaseClient, headers: Headers): Promise<Date | null> {
  const limit = parsePair(headers.get('x-ratelimit-limit'));
  const usage = parsePair(headers.get('x-ratelimit-usage'));
  const readLimit = parsePair(headers.get('x-readratelimit-limit'));
  const readUsage = parsePair(headers.get('x-readratelimit-usage'));
  if (!limit && !readLimit) return null;

  let blockedUntil: Date | null = null;
  const effectiveLimit = readLimit ?? limit;
  const effectiveUsage = readUsage ?? usage;
  if (effectiveLimit && effectiveUsage) {
    if (effectiveUsage[1] >= effectiveLimit[1] - RATE_MARGIN) {
      blockedUntil = nextUtcMidnight();
    } else if (effectiveUsage[0] >= effectiveLimit[0] - RATE_MARGIN) {
      blockedUntil = nextQuarterHour();
    }
  }

  await supabase
    .from('strava_api_rate_state')
    .update({
      limit_15m: limit?.[0] ?? null,
      limit_daily: limit?.[1] ?? null,
      usage_15m: usage?.[0] ?? null,
      usage_daily: usage?.[1] ?? null,
      read_limit_15m: readLimit?.[0] ?? null,
      read_limit_daily: readLimit?.[1] ?? null,
      read_usage_15m: readUsage?.[0] ?? null,
      read_usage_daily: readUsage?.[1] ?? null,
      blocked_until: blockedUntil?.toISOString() ?? null,
      updated_at: new Date().toISOString(),
    })
    .eq('id', 1);

  return blockedUntil;
}

/** Rate limit nedeniyle bekleniyorsa bekleme bitiş zamanını döner. */
export async function getRateLimitBlock(supabase: SupabaseClient): Promise<Date | null> {
  const { data } = await supabase
    .from('strava_api_rate_state')
    .select('blocked_until')
    .eq('id', 1)
    .maybeSingle();
  if (!data?.blocked_until) return null;
  const until = new Date(data.blocked_until);
  return until.getTime() > Date.now() ? until : null;
}

/** GET isteği; 429'da StravaRateLimitError, 404'te StravaNotFoundError fırlatır. */
export async function stravaGet<T = any>(
  supabase: SupabaseClient,
  accessToken: string,
  path: string,
  params?: Record<string, string>,
): Promise<T> {
  const url = new URL(`${STRAVA_API}${path}`);
  for (const [k, v] of Object.entries(params ?? {})) url.searchParams.set(k, v);

  const response = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  const blockedUntil = await recordRateLimit(supabase, response.headers).catch(() => null);

  if (response.status === 429) {
    const retryAt = blockedUntil ?? nextQuarterHour();
    await supabase
      .from('strava_api_rate_state')
      .update({ blocked_until: retryAt.toISOString(), updated_at: new Date().toISOString() })
      .eq('id', 1);
    throw new StravaRateLimitError(retryAt);
  }
  if (response.status === 404) {
    throw new StravaNotFoundError(path);
  }
  if (response.status === 401 || response.status === 403) {
    throw new StravaAuthError(`Strava ${response.status} for ${path}`);
  }
  if (!response.ok) {
    throw new Error(`Strava ${response.status} ${response.statusText} for ${path}`);
  }

  return (await response.json()) as T;
}
