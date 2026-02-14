// // Supabase Edge Function: notifications INSERT olduğunda FCM push gönderir.
// // Database Webhook: public.notifications, INSERT -> bu fonksiyonun URL'i.
// // Bildirim her zaman notifications tablosuna yazılır (053); push sadece kullanıcı
// // ayarında ilgili tür açıksa gönderilir (user_notification_settings).

// import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
// import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
// import * as jose from "https://deno.land/x/jose@v5.2.0/index.ts";

// const corsHeaders = {
//   "Access-Control-Allow-Origin": "*",
//   "Access-Control-Allow-Headers":
//     "authorization, x-client-info, apikey, content-type",
// };

// interface NotificationRecord {
//   id: string;
//   user_id: string;
//   type: string;
//   title: string;
//   body: string | null;
//   data: Record<string, unknown> | null;
// }

// interface WebhookPayload {
//   type: "INSERT" | "UPDATE" | "DELETE";
//   table?: string;
//   record?: NotificationRecord | null;
//   new?: NotificationRecord | null;
//   schema?: string;
//   old_record?: NotificationRecord | null;
// }

// interface ServiceAccount {
//   project_id: string;
//   client_email: string;
//   private_key: string;
// }

// async function getGoogleAccessToken(serviceAccount: ServiceAccount): Promise<string> {
//   const now = Math.floor(Date.now() / 1000);
//   const claimSet = {
//     iss: serviceAccount.client_email,
//     sub: serviceAccount.client_email,
//     aud: "https://oauth2.googleapis.com/token",
//     iat: now,
//     exp: now + 3600,
//     scope: "https://www.googleapis.com/auth/firebase.messaging",
//   };

//   const key = await jose.importPKCS8(
//     serviceAccount.private_key.replace(/\\n/g, "\n"),
//     "RS256"
//   );

//   const jwt = await new jose.SignJWT(claimSet as jose.JWTPayload)
//     .setProtectedHeader({ alg: "RS256", typ: "JWT" })
//     .sign(key);

//   const res = await fetch("https://oauth2.googleapis.com/token", {
//     method: "POST",
//     headers: { "Content-Type": "application/x-www-form-urlencoded" },
//     body: new URLSearchParams({
//       grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
//       assertion: jwt,
//     }),
//   });

//   if (!res.ok) {
//     const text = await res.text();
//     throw new Error(`Google OAuth failed: ${res.status} ${text}`);
//   }

//   const data = await res.json();
//   return data.access_token;
// }

// async function sendFcm(
//   accessToken: string,
//   projectId: string,
//   fcmToken: string,
//   record: NotificationRecord
// ): Promise<void> {
//   const dataPayload: Record<string, string> = {
//     type: record.type,
//     notification_id: record.id,
//   };
//   if (record.data && typeof record.data === "object") {
//     for (const [k, v] of Object.entries(record.data)) {
//       if (v != null) dataPayload[k] = String(v);
//     }
//   }

//   const body = {
//     message: {
//       token: fcmToken,
//       notification: {
//         title: record.title,
//         body: record.body ?? "",
//       },
//       data: dataPayload,
//       android: {
//         priority: "high" as const,
//       },
//       apns: {
//         payload: { aps: { sound: "default" } },
//         fcm_options: {},
//       },
//     },
//   };

//   const res = await fetch(
//     `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
//     {
//       method: "POST",
//       headers: {
//         "Content-Type": "application/json",
//         Authorization: `Bearer ${accessToken}`,
//       },
//       body: JSON.stringify(body),
//     }
//   );

//   if (!res.ok) {
//     const text = await res.text();
//     throw new Error(`FCM send failed: ${res.status} ${text}`);
//   }
// }

// /** settings JSONB'ı object'e çevirir (bazen string gelir). */
// function parseSettings(raw: unknown): Record<string, unknown> | null {
//   if (raw == null) return null;
//   if (typeof raw === "object" && !Array.isArray(raw)) return raw as Record<string, unknown>;
//   if (typeof raw === "string") {
//     try {
//       const parsed = JSON.parse(raw) as unknown;
//       return typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)
//         ? (parsed as Record<string, unknown>)
//         : null;
//     } catch {
//       return null;
//     }
//   }
//   return null;
// }

// /** Kullanıcının bu bildirim türü için push alıp almadığını kontrol eder. Ayar yoksa veya true ise push gider. */
// function isPushEnabledForType(settings: Record<string, unknown> | null, type: string): boolean {
//   if (!settings || typeof settings !== "object") return true;
//   const val = settings[type];
//   if (val === undefined || val === null) return true;
//   if (typeof val === "boolean") return val;
//   if (typeof val === "number") return val === 1;
//   if (typeof val === "string") return val === "true" || val === "1";
//   return false;
// }

// serve(async (req) => {
//   if (req.method === "OPTIONS") {
//     return new Response("ok", { headers: corsHeaders });
//   }

//   if (req.method !== "POST") {
//     return new Response("Method not allowed", { status: 405, headers: corsHeaders });
//   }

//   try {
//     const body = await req.json();
//     console.log("[send-push] Webhook body keys:", Object.keys(body ?? {}));

//     const payload = body as WebhookPayload;
//     const tableName = payload.table ?? "";
//     const isNotificationsInsert =
//       payload.type === "INSERT" &&
//       (tableName === "notifications" || tableName.endsWith(".notifications"));
//     if (!isNotificationsInsert) {
//       console.log("[send-push] Skipped: type=", payload.type, "table=", payload.table);
//       return new Response(JSON.stringify({ ok: true, skipped: "not INSERT notifications" }), {
//         status: 200,
//         headers: { ...corsHeaders, "Content-Type": "application/json" },
//       });
//     }

//     const record = payload.record ?? payload.new ?? null;
//     if (!record?.user_id || !record?.type) {
//       console.log("[send-push] Skipped: missing record.user_id or record.type", record);
//       return new Response(JSON.stringify({ ok: true, skipped: "invalid record" }), {
//         status: 200,
//         headers: { ...corsHeaders, "Content-Type": "application/json" },
//       });
//     }
//     console.log("[send-push] Notification record:", record.id, "user_id:", record.user_id, "type:", record.type);
//     const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
//     const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
//     const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");

//     if (!supabaseUrl || !supabaseServiceKey) {
//       throw new Error("Supabase env vars missing");
//     }
//     if (!serviceAccountJson) {
//       console.error("FIREBASE_SERVICE_ACCOUNT_JSON not set");
//       return new Response(
//         JSON.stringify({ ok: false, error: "Firebase config missing" }),
//         { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
//       );
//     }

//     const serviceAccount = JSON.parse(serviceAccountJson) as ServiceAccount;
//     const supabase = createClient(supabaseUrl, supabaseServiceKey);

//     const { data: user, error: userError } = await supabase
//       .from("users")
//       .select("fcm_token")
//       .eq("id", record.user_id)
//       .maybeSingle();

//     if (userError) {
//       console.error("Users query error:", userError);
//       throw userError;
//     }

//     const fcmToken = user?.fcm_token;
//     if (!fcmToken || typeof fcmToken !== "string") {
//       console.log("[send-push] No fcm_token for user_id:", record.user_id);
//       return new Response(
//         JSON.stringify({ ok: true, skipped: "no fcm_token" }),
//         { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
//       );
//     }

//     // Ayar kapalıysa push gönderme; bildirim yine uygulama içi sekmede görünür
//     const { data: settingsRow, error: settingsError } = await supabase
//       .from("user_notification_settings")
//       .select("settings")
//       .eq("user_id", record.user_id)
//       .maybeSingle();

//     if (settingsError) {
//       console.error("[send-push] user_notification_settings query error:", settingsError);
//     }
//     const settings = parseSettings(settingsRow?.settings ?? null);
//     const pushEnabled = isPushEnabledForType(settings, record.type);
//     console.log(
//       "[send-push] user_id:",
//       record.user_id,
//       "type:",
//       record.type,
//       "has_settings:",
//       !!settingsRow,
//       "push_enabled:",
//       pushEnabled
//     );
//     if (!pushEnabled) {
//       console.log("[send-push] Skipped: user has disabled notification type:", record.type);
//       return new Response(
//         JSON.stringify({ ok: true, skipped: "notification type disabled by user" }),
//         { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
//       );
//     }

//     console.log("[send-push] Sending FCM to token (first 20 chars):", fcmToken.substring(0, 20) + "...");
//     const accessToken = await getGoogleAccessToken(serviceAccount);
//     await sendFcm(accessToken, serviceAccount.project_id, fcmToken, record);
//     console.log("[send-push] FCM sent successfully");

//     return new Response(
//       JSON.stringify({ ok: true, sent: true }),
//       { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
//     );
//   } catch (err) {
//     console.error("send-push-on-notification error:", err);
//     return new Response(
//       JSON.stringify({
//         ok: false,
//         error: err instanceof Error ? err.message : String(err),
//       }),
//       {
//         status: 500,
//         headers: { ...corsHeaders, "Content-Type": "application/json" },
//       }
//     );
//   }
// });
