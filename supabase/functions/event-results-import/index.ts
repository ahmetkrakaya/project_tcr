// import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
// import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";
// import ExcelJS from "https://esm.sh/exceljs@4.4.0";

// type ImportError = {
//   rowIndex: number;
//   message: string;
// };

// function parseTimeToSeconds(value: string): number | null {
//   const trimmed = value.trim();
//   if (!trimmed) return null;

//   // Beklenen format: HH:MM:SS veya MM:SS
//   const parts = trimmed.split(":").map((p) => p.trim());
//   if (parts.length < 2 || parts.length > 3) return null;

//   const nums = parts.map((p) => Number(p));
//   if (nums.some((n) => isNaN(n) || n < 0)) return null;

//   let hours = 0;
//   let minutes = 0;
//   let seconds = 0;

//   if (nums.length === 3) {
//     [hours, minutes, seconds] = nums;
//   } else {
//     [minutes, seconds] = nums;
//   }

//   return hours * 3600 + minutes * 60 + seconds;
// }

// // Saniyeyi kullanıcıya gösterilecek formata çevir (mm:ss veya hh:mm:ss)
// function formatTime(seconds: number | null): string | null {
//   if (seconds == null || seconds <= 0) return null;

//   const h = Math.floor(seconds / 3600);
//   const m = Math.floor((seconds % 3600) / 60);
//   const s = seconds % 60;

//   if (h > 0) {
//     return `${h.toString().padStart(2, "0")}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
//   }
//   return `${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
// }

// // Excel hücresindeki değeri (string / number / Date / rich text) saniyeye çevir
// function parseCellTimeToSeconds(value: unknown): number | null {
//   if (value == null) return null;

//   // Excel'de süreler çoğu zaman "gün kesri" olarak sayı tutulur (0–1 arası)
//   if (typeof value === "number") {
//     if (value >= 0 && value < 1) {
//       // 1 gün = 24*60*60 sn
//       return Math.round(value * 24 * 60 * 60);
//     }
//     // Yoksa doğrudan saniye olarak kabul et
//     return Math.round(value);
//   }

//   // Tarih/saat nesnesi olarak geldiyse
//   if (value instanceof Date) {
//     return (
//       value.getHours() * 3600 +
//       value.getMinutes() * 60 +
//       value.getSeconds()
//     );
//   }

//   // ExcelJS rich text / formula vs.
//   // @ts-ignore
//   if (typeof value === "object" && value !== null && value.text) {
//     // @ts-ignore
//     return parseTimeToSeconds(String(value.text));
//   }

//   // Diğer tüm durumlarda string'e çevirip normal parser'a gönder
//   return parseTimeToSeconds(String(value));
// }

// serve(async (req) => {
//   try {
//     if (req.method !== "POST") {
//       return new Response("Method not allowed", { status: 405 });
//     }

//     const body = await req.json().catch(() => null) as
//       | {
//         event_id?: string;
//         file_name?: string;
//         file_bytes?: number[];
//       }
//       | null;

//     console.log("[Import] Request received:", req.method, req.url);

//     const eventId = body?.event_id;
//     const fileBytes = body?.file_bytes;

//     if (!eventId) {
//       console.error("[Import] Missing event_id in body");
//       return new Response("event_id is required", { status: 400 });
//     }
//     if (!fileBytes || !Array.isArray(fileBytes) || fileBytes.length === 0) {
//       console.error("[Import] Missing or empty file_bytes in body");
//       return new Response("file_bytes is required", { status: 400 });
//     }

//     console.log("[Import] Body parsed - eventId:", eventId);
//     console.log("[Import] file_bytes length:", fileBytes.length);

//     const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
//     const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

//     if (!supabaseUrl || !supabaseAnonKey) {
//       return new Response("Supabase env vars missing", { status: 500 });
//     }

//     // Authorization header'ı al
//     const authHeader = req.headers.get("Authorization");
//     console.log("[Import] Auth header present:", !!authHeader);
    
//     if (!authHeader) {
//       return new Response("Authorization header required", { status: 401 });
//     }

//     // Token'ı Bearer prefix'inden ayır (getUser için Bearer olmadan gerekli)
//     const token = authHeader.replace(/^Bearer\s+/i, "").trim();
//     console.log("[Import] Token extracted, length:", token.length);
//     console.log("[Import] Token (first 50 chars):", token.substring(0, 50));

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
//     console.log("[Import] Validating user with token...");
//     const {
//       data: { user },
//       error: userError,
//     } = await supabase.auth.getUser(token);

//     if (userError) {
//       console.error("[Import] User auth error:", JSON.stringify(userError, null, 2));
//       return new Response(
//         JSON.stringify({ code: 401, message: `Invalid JWT: ${userError.message}` }),
//         { 
//           status: 401,
//           headers: { "Content-Type": "application/json" },
//         }
//       );
//     }

//     if (!user) {
//       console.error("[Import] User is null");
//       return new Response(
//         JSON.stringify({ code: 401, message: "User not found" }),
//         { 
//           status: 401,
//           headers: { "Content-Type": "application/json" },
//         }
//       );
//     }
    
//     console.log("[Import] User validated:", user.id);

//     // Admin veya coach kontrolü
//     const { data: roles, error: rolesError } = await supabase
//       .from("user_roles")
//       .select("role")
//       .eq("user_id", user.id)
//       .in("role", ["super_admin", "coach"]);

//     if (rolesError || !roles || roles.length === 0) {
//       console.error("Roles check error:", rolesError);
//       return new Response("Forbidden: Admin or coach role required", {
//         status: 403,
//       });
//     }

//     // Etkinlik var mı?
//     const { data: event, error: eventError } = await supabase
//       .from("events")
//       .select("id, title, created_by, banner_image_url")
//       .eq("id", eventId)
//       .single();

//     if (eventError || !event) {
//       return new Response("Event not found", { status: 404 });
//     }

//     // Katılımcı haritası (hızlı erişim için)
//     const { data: participants, error: participantsError } = await supabase
//       .from("event_participants")
//       .select("id, event_id, user_id")
//       .eq("event_id", eventId)
//       .eq("status", "going");

//     if (participantsError) {
//       console.error("[Import] Participants query error:", participantsError);
//       return new Response("Failed to fetch participants", { status: 500 });
//     }

//     const participantById = new Map<string, { id: string; user_id: string }>();
//     const participantByUserId = new Map<string, { id: string; user_id: string }>();

//     console.log("[Import] Participants found:", participants?.length ?? 0);

//     for (const p of participants ?? []) {
//       participantById.set(p.id, p);
//       participantByUserId.set(p.user_id, p);
//     }

//     // Excel oku
//     console.log("[Import] Loading workbook from bytes...");
//     const arrayBuffer = new Uint8Array(fileBytes).buffer;
//     const workbook = new ExcelJS.Workbook();
//     await workbook.xlsx.load(arrayBuffer);
//     const sheet = workbook.worksheets[0];
//     console.log("[Import] Worksheet name:", sheet?.name);

//     const headerRow = sheet.getRow(1);
//     const headers = headerRow.values as Array<string | null>;
//     console.log("[Import] Header values:", headers);

//     const findCol = (name: string): number | null => {
//       const idx = headers.findIndex((v) =>
//         typeof v === "string" && v.toLowerCase() === name.toLowerCase()
//       );
//       return idx === -1 ? null : idx;
//     };

//     const colParticipantId = findCol("participant_id");
//     const colUserId = findCol("user_id");
//     const colFullName = findCol("full_name");
//     const colFinishTime = findCol("finish_time");
//     const colGender = findCol("gender");
//     const colNotes = findCol("notes");

//     // Artık participant_id/user_id opsiyonel - guest kayıtları için full_name yeterli
//     if (!colFinishTime) {
//       return new Response("Sheet must contain finish_time column", {
//         status: 400,
//       });
//     }

//     const upserts: Array<{
//       event_id: string;
//       participant_id: string | null;
//       user_id: string;
//       gender?: string | null;
//       finish_time_seconds: number;
//       notes?: string | null;
//       guest_name?: string | null;
//       guest_gender?: string | null;
//     }> = [];
//     const errors: ImportError[] = [];

//     sheet.eachRow((row, rowNumber) => {
//       if (rowNumber === 1) return; // header

//       const get = (col: number | null): string => {
//         if (!col) return "";
//         const value = row.getCell(col).value;
//         if (value == null) return "";
//         if (typeof value === "string") return value;
//         if (typeof value === "number") return value.toString();
//         // ExcelJS rich value types
//         // @ts-ignore
//         if (value.text) return String(value.text);
//         return String(value);
//       };

//       const participantId = colParticipantId ? get(colParticipantId).trim() : "";
//       const userIdFromSheet = colUserId ? get(colUserId).trim() : "";
//       const fullName = colFullName ? get(colFullName).trim() : "";
//       const genderValue = colGender ? get(colGender).trim() : "";
//       const notesValue = colNotes ? get(colNotes).trim() : "";

//       // finish_time hücresini ham haliyle al (string/number/Date olabilir)
//       const finishCellValue = colFinishTime
//         ? row.getCell(colFinishTime).value
//         : null;

//       if (
//         finishCellValue == null ||
//         (typeof finishCellValue === "string" &&
//           finishCellValue.trim().length === 0)
//       ) {
//         // Boş satırı atla (sonuç yok)
//         return;
//       }

//       const seconds = parseCellTimeToSeconds(finishCellValue);
//       if (seconds == null) {
//         const msg =
//           "finish_time formatı geçersiz (HH:MM:SS veya MM:SS olmalı)";
//         console.warn(
//           "[Import] Row",
//           rowNumber,
//           "- invalid finish_time value:",
//           finishCellValue,
//         );
//         errors.push({
//           rowIndex: rowNumber,
//           message: msg,
//         });
//         return;
//       }

//       // Katılımcı kaydı var mı kontrol et
//       let participantRecord:
//         | { id: string; user_id: string }
//         | undefined;

//       if (participantId) {
//         participantRecord = participantById.get(participantId);
//       } else if (userIdFromSheet) {
//         participantRecord = participantByUserId.get(userIdFromSheet);
//       }

//       if (participantRecord) {
//         // Mevcut katılımcı - normal kayıt
//         upserts.push({
//           event_id: eventId,
//           participant_id: participantRecord.id,
//           user_id: participantRecord.user_id,
//           gender: genderValue || null,
//           finish_time_seconds: seconds,
//           notes: notesValue || null,
//           guest_name: null,
//           guest_gender: null,
//         });
//       } else if (fullName && fullName.length > 0) {
//         // Guest kaydı - ID yok ama isim var
//         // Guest kayıtları için event'in sahibini (created_by) user_id olarak kullan
//         // Çünkü admin/coach bu sonuçları ekliyor
//         console.log(
//           "[Import] Row",
//           rowNumber,
//           "- guest record:",
//           fullName,
//           genderValue || "unknown",
//         );
//         upserts.push({
//           event_id: eventId,
//           participant_id: null, // Guest kayıtları için participant_id yok
//           user_id: event.created_by, // Event sahibini user_id olarak kullan
//           gender: null, // Guest kayıtları için gender guest_gender'de tutulacak
//           finish_time_seconds: seconds,
//           notes: notesValue || null,
//           guest_name: fullName,
//           guest_gender: genderValue || null,
//         });
//       } else {
//         // Ne katılımcı ne de guest bilgisi var
//         const msg =
//           "Katılımcı bulunamadı. Lütfen participant_id/user_id veya full_name bilgisini girin.";
//         console.warn("[Import] Row", rowNumber, "- no participant or guest info");
//         errors.push({
//           rowIndex: rowNumber,
//           message: msg,
//         });
//         return;
//       }
//     });

//     console.log("[Import] Upserts length:", upserts.length);
//     console.log("[Import] Collected errors length:", errors.length);

//     if (upserts.length === 0) {
//       return new Response(
//         JSON.stringify({
//           success: false,
//           processedCount: 0,
//           errors: errors,
//         }),
//         {
//           status: 200,
//           headers: { "Content-Type": "application/json" },
//         },
//       );
//     }

//     // Upsert event_results - Batch işlem ile optimize edilmiş
//     console.log("[Import] Upserting results to database (batch mode)...");
//     console.log("[Import] Total items to process:", upserts.length);
    
//     // Tüm mevcut kayıtları tek sorguda çek (performans optimizasyonu)
//     const { data: existingResults, error: existingError } = await supabase
//       .from("event_results")
//       .select("id, event_id, participant_id, guest_name")
//       .eq("event_id", eventId);
    
//     if (existingError) {
//       console.error("[Import] Error fetching existing results:", existingError);
//       return new Response(
//         JSON.stringify({
//           code: 500,
//           message: "Failed to fetch existing results",
//           error: existingError.message,
//         }),
//         {
//           status: 500,
//           headers: { "Content-Type": "application/json" },
//         }
//       );
//     }
    
//     // Mevcut kayıtları Map'e çevir (hızlı lookup için)
//     const existingMap = new Map<string, string>(); // key -> result_id
//     for (const existing of existingResults || []) {
//       let key: string;
//       if (existing.participant_id) {
//         key = `participant:${existing.participant_id}`;
//       } else if (existing.guest_name) {
//         key = `guest:${existing.guest_name}`;
//       } else {
//         continue; // Geçersiz kayıt
//       }
//       existingMap.set(key, existing.id);
//     }
    
//     // Insert ve update listelerini ayır
//     const toInsert: typeof upserts = [];
//     const toUpdate: Array<{ id: string; data: typeof upserts[0] }> = [];
    
//     for (const item of upserts) {
//       let key: string;
//       if (item.participant_id) {
//         key = `participant:${item.participant_id}`;
//       } else if (item.guest_name) {
//         key = `guest:${item.guest_name}`;
//       } else {
//         continue; // Geçersiz kayıt
//       }
      
//       const existingId = existingMap.get(key);
//       if (existingId) {
//         toUpdate.push({ id: existingId, data: item });
//       } else {
//         toInsert.push(item);
//       }
//     }
    
//     console.log(`[Import] To insert: ${toInsert.length}, To update: ${toUpdate.length}`);
    
//     // Batch insert
//     if (toInsert.length > 0) {
//       // Supabase batch insert limiti var (1000), ama biz küçük gruplar halinde yapabiliriz
//       const batchSize = 100;
//       for (let i = 0; i < toInsert.length; i += batchSize) {
//         const batch = toInsert.slice(i, i + batchSize);
//         const { error: insertError } = await supabase
//           .from("event_results")
//           .insert(batch);
        
//         if (insertError) {
//           console.error(`[Import] Batch insert error (batch ${i / batchSize + 1}):`, insertError);
//           // Hata olsa bile devam et, diğer batch'leri dene
//         }
//       }
//     }
    
//     // Batch update - paralel olarak çalıştır (Supabase batch update yok ama Promise.all ile hızlandır)
//     if (toUpdate.length > 0) {
//       // Update'leri paralel olarak çalıştır (batch size: 10 - çok fazla paralel sorgu database'i yormasın)
//       const updateBatchSize = 10;
//       for (let i = 0; i < toUpdate.length; i += updateBatchSize) {
//         const batch = toUpdate.slice(i, i + updateBatchSize);
//         await Promise.all(
//           batch.map(async (updateItem) => {
//             const updateData: any = {
//               user_id: updateItem.data.user_id,
//               finish_time_seconds: updateItem.data.finish_time_seconds,
//               notes: updateItem.data.notes,
//             };
            
//             if (updateItem.data.participant_id) {
//               updateData.gender = updateItem.data.gender;
//             } else {
//               updateData.guest_name = updateItem.data.guest_name;
//               updateData.guest_gender = updateItem.data.guest_gender;
//             }
            
//             return supabase
//               .from("event_results")
//               .update(updateData)
//               .eq("id", updateItem.id);
//           })
//         );
//       }
//     }
    
//     const successCount = toInsert.length + toUpdate.length;
//     console.log(`[Import] Upsert completed - success: ${successCount}`);

//     // Sıralamaları hesapla - optimize edilmiş (tek sorgu ile tüm sonuçları çek, memory'de hesapla, tek batch update)
//     const { data: allResults, error: resultsError } = await supabase
//       .from("event_results")
//       .select("id, event_id, user_id, gender, finish_time_seconds, guest_gender")
//       .eq("event_id", eventId)
//       .not("finish_time_seconds", "is", null);

//     if (!resultsError && allResults && allResults.length > 0) {
//       // Genel sıralama
//       const sortedOverall = [...allResults].sort((a, b) =>
//         (a.finish_time_seconds ?? 0) - (b.finish_time_seconds ?? 0)
//       );
      
//       // Rank map oluştur (id -> rank_overall)
//       const rankOverallMap = new Map<string, number>();
//       sortedOverall.forEach((r, index) => {
//         rankOverallMap.set(r.id, index + 1);
//       });

//       // Cinsiyete göre sıralama - gender veya guest_gender kullan
//       const byGender = new Map<string, any[]>();
//       for (const r of allResults) {
//         // Önce gender, yoksa guest_gender kullan
//         const g = (r.gender || r.guest_gender || "").toString().toLowerCase() || "unknown";
//         if (!byGender.has(g)) byGender.set(g, []);
//         byGender.get(g)!.push(r);
//       }

//       // Rank gender map oluştur
//       const rankGenderMap = new Map<string, number>();
//       for (const [_, list] of byGender.entries()) {
//         const sortedGender = list.sort((a, b) =>
//           (a.finish_time_seconds ?? 0) - (b.finish_time_seconds ?? 0)
//         );
//         sortedGender.forEach((r, index) => {
//           rankGenderMap.set(r.id, index + 1);
//         });
//       }

//       // Tüm update'leri tek listede topla
//       const updates: Array<{ id: string; rank_overall: number | null; rank_gender: number | null }> = [];
//       for (const r of allResults) {
//         updates.push({
//           id: r.id,
//           rank_overall: rankOverallMap.get(r.id) || null,
//           rank_gender: rankGenderMap.get(r.id) || null,
//         });
//       }

//       // Tek batch update ile tüm sıralamaları güncelle
//       if (updates.length > 0) {
//         // Supabase upsert limiti var, küçük batch'ler halinde yap
//         const batchSize = 100;
//         for (let i = 0; i < updates.length; i += batchSize) {
//           const batch = updates.slice(i, i + batchSize);
//           await supabase.from("event_results").upsert(batch, {
//             onConflict: "id",
//           });
//         }
//       }
//     }

//     // Import sonrası otomatik post oluştur (eğer yoksa)
//     if (event) {
//       const { data: existingPost } = await supabase
//         .from("posts")
//         .select("id")
//         .eq("event_id", event.id)
//         .maybeSingle();

//       let postId: string | null = null;

//       if (!existingPost) {
//         const title = `${event.title} yarış sonuçları yayınlandı`;
//         const { data: newPost, error: postError } = await supabase
//           .from("posts")
//           .insert({
//             user_id: event.created_by,
//             title,
//             is_published: true,
//             event_id: event.id,
//             cover_image_url: event.banner_image_url || null, // Etkinliğin banner'ını kapak görseli olarak kullan
//           })
//           .select("id")
//           .single();

//         if (postError) {
//           console.error("Failed to create results post", postError);
//         } else {
//           postId = newPost?.id ?? null;
//         }
//       } else {
//         postId = existingPost.id;
//       }

//       // Post oluşturulduysa veya zaten varsa, sonuçları blok olarak ekle
//       if (postId) {
//         // Mevcut race_results bloğunu kontrol et ve sil (güncelleme için)
//         const { data: existingBlocks } = await supabase
//           .from("post_blocks")
//           .select("id")
//           .eq("post_id", postId)
//           .eq("type", "race_results");

//         if (existingBlocks && existingBlocks.length > 0) {
//           await supabase
//             .from("post_blocks")
//             .delete()
//             .eq("post_id", postId)
//             .eq("type", "race_results");
//         }

//         // Sonuçları getir
//         const { data: results, error: resultsError } = await supabase.rpc(
//           "get_event_results",
//           { event_uuid: event.id }
//         );

//         if (!resultsError && results && results.length > 0) {
//           // Sonuçları sırala (genel sıralamaya göre)
//           const sortedResults = [...results].sort((a, b) => {
//             const aTime = a.finish_time_seconds ?? 999999;
//             const bTime = b.finish_time_seconds ?? 999999;
//             return aTime - bTime;
//           });

//           // Sonuçları JSON formatında hazırla
//           const resultsData = sortedResults.map((r, index) => ({
//             rank: index + 1,
//             fullName: r.full_name || "Anonim",
//             avatarUrl: r.avatar_url || null,
//             gender: r.gender || null,
//             finishTimeSeconds: r.finish_time_seconds || null,
//             formattedFinishTime: formatTime(r.finish_time_seconds),
//             rankOverall: r.rank_overall || index + 1,
//             rankGender: r.rank_gender || null,
//           }));

//           // race_results bloğunu ekle
//           const { error: blockError } = await supabase
//             .from("post_blocks")
//             .insert({
//               post_id: postId,
//               type: "race_results",
//               content: JSON.stringify(resultsData),
//               order_index: 0,
//             });

//           if (blockError) {
//             console.error("Failed to create race_results block", blockError);
//           }
//         }
//       }
//     }

//     return new Response(JSON.stringify({
//       success: true,
//       processedCount: upserts.length,
//       errors,
//     }), {
//       status: 200,
//       headers: { "Content-Type": "application/json" },
//     });
//   } catch (error) {
//     console.error("[Import] Unhandled exception:", error);
//     const errorMessage = error instanceof Error ? error.message : String(error);
//     const errorStack = error instanceof Error ? error.stack : undefined;
//     console.error("[Import] Error message:", errorMessage);
//     console.error("[Import] Error stack:", errorStack);
    
//     return new Response(
//       JSON.stringify({
//         code: 500,
//         message: "Internal Server Error",
//         error: errorMessage,
//         stack: errorStack,
//       }),
//       {
//         status: 500,
//         headers: { "Content-Type": "application/json" },
//       }
//     );
//   }
// });

