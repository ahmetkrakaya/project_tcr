// Public Strava config (client_id only). client_secret hiçbir zaman dönmez.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Supabase client.functions.invoke() her zaman POST ile çağırdığı için
  // hem GET hem POST isteklerine izin veriyoruz.
  if (req.method !== "GET" && req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  try {
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      throw new Error("Supabase credentials missing");
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data } = await supabase
      .from("integration_oauth_config")
      .select("client_id")
      .eq("provider", "strava")
      .maybeSingle();

    const clientId = (data?.client_id as string | undefined) || (Deno.env.get("STRAVA_CLIENT_ID") ?? "");
    if (!clientId) {
      throw new Error("Strava client_id missing (DB or env)");
    }

    return new Response(JSON.stringify({ client_id: clientId }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("strava-public-config error:", err);
    return new Response(JSON.stringify({ error: "Internal server error", details: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

