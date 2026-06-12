import { supabase } from "./supabase";
import { ymd } from "./dates";

export type TrainingGroup = {
  id: string;
  name: string;
  color: string | null;
  group_type: string;
  is_active: boolean;
};

export type GroupMember = {
  user_id: string;
  userName: string;
};

export type TrainingType = {
  id: string;
  name: string;
  display_name: string;
};

export type WorkoutDefinition = {
  steps?: unknown[];
};

export type DayDraft = {
  workout: string;
  coachNotes: string;
  trainingTypeOverride: string | null;
  /** Pist referans kulvarı (1-8). null = pist dışı. */
  trackLane: number | null;
  /** Kayıtlı yapılandırılmış antrenman; önizleme için (metin alanında gösterilmez). */
  workoutDefinition?: WorkoutDefinition | null;
  /** Sunucudaki kısa metin; UI'da gösterilmez, kayıtta antrenman korunması için. */
  persistedCoachText?: string | null;
};

export type ProgramEntryRow = {
  plan_date: string;
  program_content: string | null;
  coach_notes: string | null;
  workout_definition: WorkoutDefinition | null;
  track_lane: number | null;
  training_types: { name: string; display_name: string } | null;
};

export async function fetchTrainingGroups(): Promise<TrainingGroup[]> {
  const { data, error } = await supabase
    .from("training_groups")
    .select("id, name, color, group_type, is_active")
    .eq("is_active", true)
    .order("name");

  if (error) throw error;
  return (data ?? []) as TrainingGroup[];
}

export async function fetchGroupMembers(groupId: string): Promise<GroupMember[]> {
  const { data, error } = await supabase
    .from("group_members")
    .select("user_id, users(first_name, last_name)")
    .eq("group_id", groupId)
    .order("joined_at", { ascending: true });

  if (error) throw error;

  return (data ?? []).map((row) => {
    const rawUsers = row.users as
      | { first_name: string | null; last_name: string | null }
      | { first_name: string | null; last_name: string | null }[]
      | null
      | undefined;
    const users = Array.isArray(rawUsers) ? rawUsers[0] : rawUsers;
    const first = users?.first_name?.trim() ?? "";
    const last = users?.last_name?.trim() ?? "";
    const name = [first, last].filter(Boolean).join(" ") || "İsimsiz";
    return { user_id: row.user_id as string, userName: name };
  });
}

export async function fetchTrainingTypes(): Promise<TrainingType[]> {
  const { data, error } = await supabase
    .from("training_types")
    .select("id, name, display_name")
    .eq("is_active", true)
    .order("display_name");

  if (error) throw error;
  return (data ?? []) as TrainingType[];
}

export async function getWeeklyProgramEntries({
  weekStartMonday,
  trainingGroupId,
  memberUserId,
}: {
  weekStartMonday: Date;
  trainingGroupId: string;
  memberUserId?: string | null;
}): Promise<ProgramEntryRow[]> {
  const start = new Date(
    weekStartMonday.getFullYear(),
    weekStartMonday.getMonth(),
    weekStartMonday.getDate(),
  );
  const end = new Date(start);
  end.setDate(end.getDate() + 6);

  const scopeType = memberUserId ? "member" : "group";

  let query = supabase
    .from("monthly_program_entries")
    .select(
      "plan_date, program_content, coach_notes, workout_definition, track_lane, training_types(display_name, name)",
    )
    .gte("plan_date", ymd(start))
    .lte("plan_date", ymd(end))
    .eq("scope_type", scopeType)
    .eq("training_group_id", trainingGroupId);

  if (memberUserId) {
    query = query.eq("user_id", memberUserId);
  } else {
    query = query.is("user_id", null);
  }

  const { data, error } = await query.order("plan_date", { ascending: true });
  if (error) throw error;

  return (data ?? []).map((row) => {
    const rawTypes = row.training_types as
      | { name: string; display_name: string }
      | { name: string; display_name: string }[]
      | null
      | undefined;
    const training_types = Array.isArray(rawTypes) ? rawTypes[0] ?? null : rawTypes ?? null;
    const rawDef = row.workout_definition as WorkoutDefinition | WorkoutDefinition[] | null;
    const workout_definition = Array.isArray(rawDef) ? rawDef[0] ?? null : rawDef ?? null;

    return {
      plan_date: row.plan_date as string,
      program_content: row.program_content as string | null,
      coach_notes: row.coach_notes as string | null,
      workout_definition,
      track_lane: (row.track_lane as number | null) ?? null,
      training_types,
    };
  });
}

export function rowsToDayDrafts(
  rows: ProgramEntryRow[],
  weekStartMonday: Date,
): DayDraft[] {
  const byDate = new Map(rows.map((r) => [r.plan_date, r]));
  return Array.from({ length: 7 }, (_, i) => {
    const d = new Date(weekStartMonday);
    d.setDate(d.getDate() + i);
    const row = byDate.get(ymd(d));
    const hasStructuredWorkout =
      (row?.workout_definition?.steps?.length ?? 0) > 0;

    return {
      workout: row?.program_content ?? "",
      coachNotes: row?.coach_notes ?? "",
      trainingTypeOverride: row?.training_types?.name ?? null,
      trackLane: row?.track_lane ?? null,
      workoutDefinition: hasStructuredWorkout ? row?.workout_definition ?? null : null,
      persistedCoachText: null,
    };
  });
}

export function dayDraftsToPayload(days: DayDraft[], weekStartMonday: Date) {
  return days.map((day, i) => {
    const d = new Date(weekStartMonday);
    d.setDate(d.getDate() + i);
    const userText = day.workout.trim();
    const preserved = day.persistedCoachText?.trim() ?? "";
    const text = userText || preserved;
    const coachNotes = day.coachNotes.trim();
    return {
      plan_date: ymd(d),
      text: text.length === 0 ? "REST" : text,
      coach_notes: coachNotes.length > 0 ? coachNotes : undefined,
      training_type_override: day.trainingTypeOverride,
      track_lane: day.trackLane,
    };
  });
}

export async function upsertWeeklyProgram({
  weekStartMonday,
  scopeType,
  trainingGroupId,
  memberUserId,
  days,
}: {
  weekStartMonday: Date;
  scopeType: "group" | "member";
  trainingGroupId: string;
  memberUserId?: string | null;
  days: ReturnType<typeof dayDraftsToPayload>;
}): Promise<{ errors: Array<{ plan_date: string; message: string }> }> {
  const { data, error } = await supabase.functions.invoke(
    "weekly-program-upsert",
    {
      body: {
        week_start: ymd(weekStartMonday),
        scope_type: scopeType,
        training_group_id: trainingGroupId,
        user_id: memberUserId ?? null,
        days,
      },
    },
  );

  if (error) throw error;

  const result = data as {
    errors?: Array<{ plan_date: string; message: string }>;
  };

  return {
    errors: result?.errors ?? [],
  };
}
