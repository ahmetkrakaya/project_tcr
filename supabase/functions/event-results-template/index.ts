// import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
// import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";
// import ExcelJS from "https://esm.sh/exceljs@4.4.0";

// serve(async (req) => {
//   if (req.method !== "GET") {
//     return new Response("Method not allowed", { status: 405 });
//   }

//   try {
//     console.log("[Template] Request received:", req.method, req.url);
    
//     const url = new URL(req.url);
//     const eventId = url.searchParams.get("event_id");
//     console.log("[Template] Event ID:", eventId);

//     if (!eventId) {
//       return new Response("event_id is required", { status: 400 });
//     }

//     const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
//     const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

//     if (!supabaseUrl || !supabaseAnonKey) {
//       console.error("[Template] Supabase env vars missing");
//       return new Response("Supabase env vars missing", { status: 500 });
//     }

//     // Authorization header'ı al
//     const authHeader = req.headers.get("Authorization");
//     console.log("[Template] Auth header present:", !!authHeader);
//     console.log("[Template] Auth header (first 50 chars):", authHeader?.substring(0, 50));
    
//     if (!authHeader) {
//       console.error("[Template] No authorization header");
//       return new Response("Authorization header required", { status: 401 });
//     }

//     // Token'ı Bearer prefix'inden ayır (getUser için Bearer olmadan gerekli)
//     const token = authHeader.replace(/^Bearer\s+/i, "").trim();
//     console.log("[Template] Token extracted, length:", token.length);
//     console.log("[Template] Token (first 50 chars):", token.substring(0, 50));

//     // Supabase client oluştur - Authorization header'ını direkt geç
//     const supabase = createClient(supabaseUrl, supabaseAnonKey, {
//       global: {
//         headers: { Authorization: authHeader },
//       },
//       auth: {
//         persistSession: false,
//         autoRefreshToken: false,
//       },
//     });

//     // Kullanıcıyı doğrula - token'ı Bearer olmadan geç
//     console.log("[Template] Validating user with token...");
//     const {
//       data: { user },
//       error: userError,
//     } = await supabase.auth.getUser(token);

//     if (userError) {
//       console.error("[Template] User auth error:", JSON.stringify(userError, null, 2));
//       return new Response(
//         JSON.stringify({ code: 401, message: `Invalid JWT: ${userError.message}` }),
//         { 
//           status: 401,
//           headers: { "Content-Type": "application/json" },
//         }
//       );
//     }

//     if (!user) {
//       console.error("[Template] User is null");
//       return new Response(
//         JSON.stringify({ code: 401, message: "User not found" }),
//         { 
//           status: 401,
//           headers: { "Content-Type": "application/json" },
//         }
//       );
//     }
    
//     console.log("[Template] User validated:", user.id);

//     // Admin veya coach kontrolü
//     console.log("[Template] Checking roles for user:", user.id);
//     const { data: roles, error: rolesError } = await supabase
//       .from("user_roles")
//       .select("role")
//       .eq("user_id", user.id)
//       .in("role", ["super_admin", "coach"]);

//     if (rolesError) {
//       console.error("[Template] Roles check error:", rolesError);
//       return new Response("Forbidden: Admin or coach role required", {
//         status: 403,
//       });
//     }
    
//     console.log("[Template] User roles:", roles);
    
//     if (!roles || roles.length === 0) {
//       console.error("[Template] User has no admin/coach role");
//       return new Response("Forbidden: Admin or coach role required", {
//         status: 403,
//       });
//     }

//     // Etkinliği ve katılımcıları çek
//     console.log("[Template] Fetching event:", eventId);
//     const { data: event, error: eventError } = await supabase
//       .from("events")
//       .select("id, title")
//       .eq("id", eventId)
//       .single();

//     if (eventError || !event) {
//       console.error("[Template] Event error:", eventError);
//       return new Response("Event not found", { status: 404 });
//     }
//     console.log("[Template] Event found:", event.title);

//     console.log("[Template] Fetching participants...");
//     const { data: participants, error: participantsError } = await supabase
//       .from("event_participants")
//       .select(
//         `
//         id,
//         user_id,
//         users!inner(
//           first_name,
//           last_name,
//           gender
//         )
//       `,
//       )
//       .eq("event_id", eventId)
//       .eq("status", "going");

//     if (participantsError) {
//       console.error("[Template] Participants error:", participantsError);
//       return new Response("Failed to fetch participants", { status: 500 });
//     }
//     console.log("[Template] Participants found:", participants?.length ?? 0);

//     const workbook = new ExcelJS.Workbook();
//     const sheet = workbook.addWorksheet("Results");

//     // Header row
//     sheet.columns = [
//       { header: "participant_id", key: "participant_id", width: 36 },
//       { header: "user_id", key: "user_id", width: 36 },
//       { header: "full_name", key: "full_name", width: 30 },
//       { header: "gender", key: "gender", width: 10 },
//       { header: "bib_number", key: "bib_number", width: 12 },
//       {
//         header: "finish_time",
//         key: "finish_time",
//         width: 12,
//       },
//       { header: "notes", key: "notes", width: 30 },
//     ];

//     // finish_time sütununu TEXT olarak işaretle ki Excel otomatik zaman tipine çevirmesin
//     const finishTimeColumn = sheet.getColumn("finish_time");
//     // '@' = Text formatı
//     // @ts-ignore - ExcelJS numFmt özelliği
//     finishTimeColumn.numFmt = "@";

//     const rows =
//       participants?.map((p: any) => {
//         const user = p.users ?? {};
//         const fullName =
//           [user.first_name, user.last_name].filter(Boolean).join(" ") ||
//           "";
//         return {
//           participant_id: p.id,
//           user_id: p.user_id,
//           full_name: fullName,
//           gender: user.gender ?? "",
//           bib_number: "",
//           finish_time: "",
//           notes: "",
//         };
//       }) ?? [];

//     sheet.addRows(rows);
//     console.log("[Template] Excel rows added:", rows.length);

//     // Başlık satırını bold yap
//     const headerRow = sheet.getRow(1);
//     headerRow.font = { bold: true };
//     console.log("[Template] Header row styled as bold");

//     const buffer = await workbook.xlsx.writeBuffer();
//     console.log("[Template] Excel buffer created, size:", buffer.byteLength);

//     // Dosya adını temizle - HTTP header'larında sadece ASCII (ByteString) kullanılabilir.
//     // Bu yüzden başlığı ASCII slug'a çeviriyoruz.
//     const rawTitle = (event.title ?? "Etkinlik").toString();

//     // 1) Unicode accent'leri kaldır (örn: İstanbul -> Istanbul)
//     const noAccents = rawTitle.normalize("NFD").replace(/[\u0300-\u036f]/g, "");

//     // 2) Sadece güvenli karakterleri bırak (harf/rakam/boşluk/._-)
//     const asciiSafe = noAccents
//       .replace(/[^A-Za-z0-9 _.-]/g, " ")
//       .replace(/\s+/g, " ")
//       .trim();

//     const baseName = asciiSafe || "event";
//     const headerFileName = `${baseName} - Yaris Sonuclari Sablonu.xlsx`; // Header için sadece ASCII

//     console.log("[Template] Returning file with header filename:", headerFileName);

//     return new Response(buffer, {
//       status: 200,
//       headers: {
//         "Content-Type":
//           "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
//         // Content-Disposition header'ında sadece ASCII karakterler kullanılmalı
//         "Content-Disposition": `attachment; filename="${headerFileName}"`,
//       },
//     });
//   } catch (error) {
//     console.error("[Template] Error:", error);
//     const errorMessage = error instanceof Error ? error.message : String(error);
//     const errorStack = error instanceof Error ? error.stack : undefined;
//     console.error("[Template] Error message:", errorMessage);
//     console.error("[Template] Error stack:", errorStack);
//     return new Response(
//       JSON.stringify({ 
//         code: 500, 
//         message: "Internal Server Error",
//         error: errorMessage,
//         stack: errorStack 
//       }),
//       { 
//         status: 500,
//         headers: { "Content-Type": "application/json" },
//       }
//     );
//   }
// });

