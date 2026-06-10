import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  parseCoachText,
  resolveTrainingTypeName,
  type TrainingTypeHint,
} from "./coach_text_parser.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type DayInput = {
  plan_date?: string;
  text?: string;
  coach_notes?: string;
  training_type_override?: string | null;
};

async function getOrCreateWeeklyBatch(
  supabase: ReturnType<typeof createClient>,
  monthKey: string,
  userId: string,
): Promise<string> {
  const { data: existing } = await supabase
    .from("monthly_program_batches")
    .select("id")
    .eq("month_key", monthKey)
    .eq("source", "weekly_editor")
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existing?.id) return String(existing.id);

  const { data: created, error } = await supabase
    .from("monthly_program_batches")
    .insert({
      month_key: monthKey,
      title: `${monthKey} Haftalık Program`,
      status: "active",
      source: "weekly_editor",
      source_file_name: null,
      row_count: 0,
      error_count: 0,
      uploaded_by: userId,
    })
    .select("id")
    .single();

  if (error || !created) {
    throw new Error(`Batch oluşturulamadı: ${error?.message ?? "unknown"}`);
  }
  return String(created.id);
}

function buildTrainingTypeMap(
  rows: Array<{ id: string; name?: string | null; display_name?: string | null }>,
): Map<string, string> {
  const map = new Map<string, string>();
  for (const t of rows) {
    const keys = [
      String(t.name ?? "").toLowerCase().trim(),
      String(t.display_name ?? "").toLowerCase().trim(),
    ].filter((k) => k.length > 0);
    for (const k of keys) map.set(k, t.id);
  }
  return map;
}

function resolveTrainingTypeId(
  hint: TrainingTypeHint,
  override: string | null | undefined,
  typeMap: Map<string, string>,
): string | null {
  if (override?.trim()) {
    const key = override.trim().toLowerCase();
    const direct = typeMap.get(key);
    if (direct) return direct;
  }
  const name = resolveTrainingTypeName(hint);
  return typeMap.get(name) ?? typeMap.get("easy_run") ?? null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response("Authorization required", { status: 401, headers: corsHeaders });
    }

    const body = (await req.json().catch(() => null)) as {
      week_start?: string;
      scope_type?: string;
      training_group_id?: string;
      user_id?: string | null;
      days?: DayInput[];
    } | null;

    const scopeType = body?.scope_type?.trim();
    const trainingGroupId = body?.training_group_id?.trim();
    const memberUserId = body?.user_id?.trim() || null;
    const days = body?.days ?? [];

    if (!scopeType || !["group", "member"].includes(scopeType)) {
      return new Response("scope_type must be group or member", {
        status: 400,
        headers: corsHeaders,
      });
    }
    if (!trainingGroupId) {
      return new Response("training_group_id required", { status: 400, headers: corsHeaders });
    }
    if (scopeType === "member" && !memberUserId) {
      return new Response("user_id required for member scope", {
        status: 400,
        headers: corsHeaders,
      });
    }
    if (days.length === 0) {
      return new Response("days required", { status: 400, headers: corsHeaders });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    if (!supabaseUrl || !supabaseAnon) {
      return new Response("Env missing", { status: 500, headers: corsHeaders });
    }

    const supabase = createClient(supabaseUrl, supabaseAnon, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    const { data: userData, error: userErr } = await supabase.auth.getUser(token);
    if (userErr || !userData.user) {
      return new Response("Unauthorized", { status: 401, headers: corsHeaders });
    }
    const adminUserId = userData.user.id;

    const { data: roles } = await supabase
      .from("user_roles")
      .select("role")
      .eq("user_id", adminUserId)
      .eq("role", "super_admin");
    if (!roles || roles.length === 0) {
      return new Response("Forbidden", { status: 403, headers: corsHeaders });
    }

    const { data: groupRow } = await supabase
      .from("training_groups")
      .select("id, group_type")
      .eq("id", trainingGroupId)
      .maybeSingle();
    if (!groupRow) {
      return new Response("Training group not found", { status: 400, headers: corsHeaders });
    }

    if (scopeType === "member") {
      if (groupRow.group_type !== "performance") {
        return new Response("Member scope requires performance group", {
          status: 400,
          headers: corsHeaders,
        });
      }
      const { data: membership } = await supabase
        .from("group_members")
        .select("user_id")
        .eq("group_id", trainingGroupId)
        .eq("user_id", memberUserId)
        .maybeSingle();
      if (!membership) {
        return new Response("User is not a member of this group", {
          status: 400,
          headers: corsHeaders,
        });
      }
    }

    const { data: trainingTypes } = await supabase
      .from("training_types")
      .select("id, name, display_name")
      .eq("is_active", true);
    const typeMap = buildTrainingTypeMap(trainingTypes ?? []);

    const errors: Array<{ plan_date: string; message: string }> = [];
    const savedDays: string[] = [];
    const deletedDays: string[] = [];
    const batchCache = new Map<string, string>();

    for (const day of days) {
      const planDate = day.plan_date?.trim() ?? "";
      if (!/^\d{4}-\d{2}-\d{2}$/.test(planDate)) {
        errors.push({ plan_date: planDate || "?", message: "Geçersiz tarih" });
        continue;
      }

      const text = day.text ?? "";
      const parsed = parseCoachText(text);

      if (!parsed.ok) {
        errors.push({ plan_date: planDate, message: parsed.error });
        continue;
      }

      let existingQuery = supabase
        .from("monthly_program_entries")
        .select("id")
        .eq("plan_date", planDate)
        .eq("scope_type", scopeType)
        .eq("training_group_id", trainingGroupId);

      existingQuery = scopeType === "member"
        ? existingQuery.eq("user_id", memberUserId!)
        : existingQuery.is("user_id", null);

      const { data: existing } = await existingQuery.maybeSingle();

      if (parsed.isRest) {
        if (existing?.id) {
          const { error: delErr } = await supabase
            .from("monthly_program_entries")
            .delete()
            .eq("id", existing.id);
          if (delErr) {
            errors.push({ plan_date: planDate, message: delErr.message });
          } else {
            deletedDays.push(planDate);
          }
        }
        continue;
      }

      const monthKey = planDate.slice(0, 7);
      let batchId = batchCache.get(monthKey);
      if (!batchId) {
        batchId = await getOrCreateWeeklyBatch(supabase, monthKey, adminUserId);
        batchCache.set(monthKey, batchId);
      }

      const trainingTypeId = resolveTrainingTypeId(
        parsed.trainingTypeHint,
        day.training_type_override,
        typeMap,
      );
      if (!trainingTypeId) {
        errors.push({ plan_date: planDate, message: "Antrenman türü bulunamadı" });
        continue;
      }

      const row = {
        batch_id: batchId,
        plan_date: planDate,
        scope_type: scopeType,
        training_group_id: trainingGroupId,
        user_id: scopeType === "member" ? memberUserId : null,
        training_type_id: trainingTypeId,
        program_content: parsed.programContent,
        workout_definition: parsed.workoutDefinition,
        coach_notes: day.coach_notes?.trim() || null,
        source: "weekly_editor",
        sort_order: 0,
      };

      if (existing?.id) {
        const { error: upErr } = await supabase
          .from("monthly_program_entries")
          .update(row)
          .eq("id", existing.id);
        if (upErr) {
          errors.push({ plan_date: planDate, message: upErr.message });
        } else {
          savedDays.push(planDate);
        }
      } else {
        const { error: insErr } = await supabase
          .from("monthly_program_entries")
          .insert(row);
        if (insErr) {
          errors.push({ plan_date: planDate, message: insErr.message });
        } else {
          savedDays.push(planDate);
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: errors.length === 0,
        saved_days: savedDays,
        deleted_days: deletedDays,
        errors,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, message: String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
