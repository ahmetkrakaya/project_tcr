// Strava OAuth: token exchange ve refresh. client_id/client_secret veritabanından okunur.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type StravaConfig = { client_id: string; client_secret: string };

async function getStravaConfig(supabase: ReturnType<typeof createClient>): Promise<StravaConfig> {
  const { data } = await supabase
    .from("integration_oauth_config")
    .select("client_id, client_secret")
    .eq("provider", "strava")
    .maybeSingle();

  if (data?.client_id && data?.client_secret) {
    return { client_id: data.client_id, client_secret: data.client_secret };
  }
  const fallbackId = Deno.env.get("STRAVA_CLIENT_ID") ?? "";
  const fallbackSecret = Deno.env.get("STRAVA_CLIENT_SECRET") ?? "";
  return { client_id: fallbackId, client_secret: fallbackSecret };
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const supabaseUser = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Invalid user token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json().catch(() => ({}));
    const action = body.action ?? "exchange";

    const config = await getStravaConfig(supabase);
    if (!config.client_id || !config.client_secret) {
      return new Response(
        JSON.stringify({ error: "Strava OAuth config missing (DB or env)" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (action === "exchange") {
      const { code, redirect_uri } = body;
      if (!code) {
        return new Response(JSON.stringify({ error: "Missing code" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const tokenRes = await fetch(STRAVA_TOKEN_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: config.client_id,
          client_secret: config.client_secret,
          code,
          grant_type: "authorization_code",
          ...(redirect_uri && { redirect_uri }),
        }),
      });
      if (!tokenRes.ok) {
        const err = await tokenRes.text();
        console.error("Strava token exchange failed:", tokenRes.status, err);
        return new Response(
          JSON.stringify({ error: "Strava token exchange failed", details: err }),
          { status: tokenRes.status, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      const tokenData = await tokenRes.json();
      const expiresAt = tokenData.expires_at
        ? new Date((tokenData.expires_at - 600) * 1000).toISOString()
        : new Date(Date.now() + 86400 * 1000).toISOString();
      const athlete = tokenData.athlete ?? {};
      const athleteData = {
        id: athlete.id,
        username: athlete.username,
        firstname: athlete.firstname,
        lastname: athlete.lastname,
        profile: athlete.profile,
        profile_medium: athlete.profile_medium,
      };
      const { data: integration, error: upsertError } = await supabase
        .from("user_integrations")
        .upsert(
          {
            user_id: user.id,
            provider: "strava",
            provider_user_id: String(athlete.id ?? ""),
            access_token: tokenData.access_token,
            refresh_token: tokenData.refresh_token ?? null,
            token_expires_at: expiresAt,
            scopes: ["activity:read", "activity:read_all", "profile:read_all"],
            athlete_data: athleteData,
            sync_enabled: true,
            connected_at: new Date().toISOString(),
          },
          { onConflict: "user_id,provider" },
        )
        .select("id, provider_user_id, athlete_data, connected_at, last_sync_at, sync_enabled")
        .single();

      if (upsertError) {
        console.error("Strava integration upsert error:", upsertError);
        return new Response(
          JSON.stringify({ error: "Failed to save integration", details: upsertError.message }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      return new Response(
        JSON.stringify({
          success: true,
          integration: {
            id: integration.id,
            provider_user_id: integration.provider_user_id,
            athlete_data: integration.athlete_data,
            connected_at: integration.connected_at,
            last_sync_at: integration.last_sync_at,
            sync_enabled: integration.sync_enabled,
          },
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (action === "refresh") {
      const refreshToken = body.refresh_token;
      if (!refreshToken) {
        return new Response(JSON.stringify({ error: "Missing refresh_token" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const tokenRes = await fetch(STRAVA_TOKEN_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: config.client_id,
          client_secret: config.client_secret,
          refresh_token: refreshToken,
          grant_type: "refresh_token",
        }),
      });
      if (!tokenRes.ok) {
        const err = await tokenRes.text();
        console.error("Strava refresh failed:", tokenRes.status, err);
        return new Response(
          JSON.stringify({ error: "Strava refresh failed", details: err }),
          { status: tokenRes.status, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      const tokenData = await tokenRes.json();
      const expiresAt = tokenData.expires_at
        ? new Date((tokenData.expires_at - 600) * 1000).toISOString()
        : new Date(Date.now() + 86400 * 1000).toISOString();
      return new Response(
        JSON.stringify({
          access_token: tokenData.access_token,
          refresh_token: tokenData.refresh_token ?? refreshToken,
          expires_at: expiresAt,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("strava-auth error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error", details: String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
