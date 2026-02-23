import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GARMIN_CLIENT_ID = Deno.env.get("GARMIN_CLIENT_ID")!;
const GARMIN_CLIENT_SECRET = Deno.env.get("GARMIN_CLIENT_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const GARMIN_TOKEN_URL =
  "https://diauth.garmin.com/di-oauth2-service/oauth/token";
const GARMIN_USER_ID_URL =
  "https://apis.garmin.com/wellness-api/rest/user/id";
const GARMIN_PERMISSIONS_URL =
  "https://apis.garmin.com/wellness-api/rest/user/permissions";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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

    // JWT'den kullanıcı ID'si al
    const supabaseUser = createClient(
      SUPABASE_URL,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );
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

    const { code, code_verifier, redirect_uri } = await req.json();
    if (!code || !code_verifier) {
      return new Response(
        JSON.stringify({ error: "Missing code or code_verifier" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 1. Garmin token exchange
    const tokenParams = new URLSearchParams({
      grant_type: "authorization_code",
      client_id: GARMIN_CLIENT_ID,
      client_secret: GARMIN_CLIENT_SECRET,
      code,
      code_verifier,
    });
    if (redirect_uri) {
      tokenParams.set("redirect_uri", redirect_uri);
    }

    const tokenRes = await fetch(GARMIN_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: tokenParams.toString(),
    });

    if (!tokenRes.ok) {
      const errText = await tokenRes.text();
      console.error("Garmin token exchange failed:", tokenRes.status, errText);
      return new Response(
        JSON.stringify({
          error: "Garmin token exchange failed",
          details: errText,
        }),
        {
          status: tokenRes.status,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const tokenData = await tokenRes.json();
    const accessToken = tokenData.access_token;
    const refreshToken = tokenData.refresh_token;
    const expiresIn = tokenData.expires_in ?? 86400;
    const refreshTokenExpiresIn = tokenData.refresh_token_expires_in;
    const tokenExpiresAt = new Date(
      Date.now() + (expiresIn - 600) * 1000
    ).toISOString();

    // 2. Garmin User ID al
    const userIdRes = await fetch(GARMIN_USER_ID_URL, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    let garminUserId: string | null = null;
    if (userIdRes.ok) {
      const userIdData = await userIdRes.json();
      garminUserId = userIdData.userId ?? null;
    }

    // 3. Kullanıcı izinlerini kontrol et
    const permRes = await fetch(GARMIN_PERMISSIONS_URL, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    let permissions: string[] = [];
    if (permRes.ok) {
      const permData = await permRes.json();
      if (Array.isArray(permData)) {
        permissions = permData;
      } else if (permData?.permissions && Array.isArray(permData.permissions)) {
        permissions = permData.permissions;
      }
    }

    const hasWorkoutImport = permissions.includes("WORKOUT_IMPORT");
    if (!hasWorkoutImport) {
      console.warn(
        "User does not have WORKOUT_IMPORT permission. Permissions:",
        permissions
      );
    }

    // 4. user_integrations tablosuna kaydet (upsert)
    const { error: upsertError } = await supabase
      .from("user_integrations")
      .upsert(
        {
          user_id: user.id,
          provider: "garmin",
          provider_user_id: garminUserId,
          access_token: accessToken,
          refresh_token: refreshToken,
          token_expires_at: tokenExpiresAt,
          scopes: permissions,
          athlete_data: {
            garmin_user_id: garminUserId,
            permissions,
            refresh_token_expires_in: refreshTokenExpiresIn,
          },
          sync_enabled: true,
          connected_at: new Date().toISOString(),
        },
        { onConflict: "user_id,provider" }
      );

    if (upsertError) {
      console.error("Upsert error:", upsertError);
      return new Response(
        JSON.stringify({ error: "Failed to save integration", details: upsertError.message }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 5. İlk bağlantı sonrası hemen 7 günlük sync tetikle (arka planda)
    try {
      const pushUrl = `${SUPABASE_URL}/functions/v1/garmin-push-workout`;
      fetch(pushUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ mode: "single_user", user_id: user.id }),
      }).catch((e) => console.error("Initial sync trigger failed:", e));
    } catch (e) {
      console.error("Initial sync trigger error:", e);
    }

    return new Response(
      JSON.stringify({
        success: true,
        garmin_user_id: garminUserId,
        permissions,
        has_workout_import: hasWorkoutImport,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err) {
    console.error("garmin-auth error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error", details: String(err) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
