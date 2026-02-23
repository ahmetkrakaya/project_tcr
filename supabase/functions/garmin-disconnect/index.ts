import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const GARMIN_DELETE_REGISTRATION_URL =
  "https://apis.garmin.com/wellness-api/rest/user/registration";

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

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

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

    // Mevcut Garmin token'ı al
    const { data: integration } = await supabaseAdmin
      .from("user_integrations")
      .select("id, access_token")
      .eq("user_id", user.id)
      .eq("provider", "garmin")
      .single();

    if (integration?.access_token) {
      // Garmin tarafında bağlantıyı kaldır
      try {
        const res = await fetch(GARMIN_DELETE_REGISTRATION_URL, {
          method: "DELETE",
          headers: {
            Authorization: `Bearer ${integration.access_token}`,
          },
        });
        if (!res.ok && res.status !== 404) {
          console.warn("Garmin deregistration returned:", res.status);
        }
      } catch (e) {
        console.warn("Garmin deregistration request failed:", e);
      }
    }

    // user_integrations tablosundan sil
    await supabaseAdmin
      .from("user_integrations")
      .delete()
      .eq("user_id", user.id)
      .eq("provider", "garmin");

    // garmin_sent_workouts kayıtlarını temizle
    await supabaseAdmin
      .from("garmin_sent_workouts")
      .delete()
      .eq("user_id", user.id);

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("garmin-disconnect error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error", details: String(err) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
