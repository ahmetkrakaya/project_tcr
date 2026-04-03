import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import ExcelJS from "https://esm.sh/exceljs@4.4.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const ADIM_COUNT = 8;

/** Edge worker bellek limiti: tüm sekmelerde 500 satır × çoklu doğrulama ExcelJS’i patlatıyor */
const PROGRAM_VALIDATION_MAX_ROW = 120;
const PROGRAM_VALIDATION_EXTRA_ROWS = 24;

function programValidationEndRow(lastDataRow: number): number {
  const need = Math.max(lastDataRow + PROGRAM_VALIDATION_EXTRA_ROWS, 24);
  return Math.min(Math.max(need, 2), PROGRAM_VALIDATION_MAX_ROW);
}

function uint8ToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    const sub = bytes.subarray(i, i + chunk);
    binary += String.fromCharCode(...sub);
  }
  return btoa(binary);
}

/** Excel sayfa adı: 31 karakter, \ / * ? : [ ] yasak */
function sanitizeSheetTitle(name: string): string {
  let s = name.replace(/[\\/*?:[\]]/g, " ").replace(/\s+/g, " ").trim();
  if (s.length > 31) s = s.slice(0, 31).trim();
  return s.length > 0 ? s : "Grup";
}

/** grup tam adı → benzersiz sekme adı */
function uniqueSheetTitles(names: string[]): Map<string, string> {
  const map = new Map<string, string>();
  const used = new Set<string>();
  for (const n of names) {
    let base = sanitizeSheetTitle(n);
    let candidate = base;
    let i = 2;
    while (used.has(candidate)) {
      const suffix = ` (${i})`;
      candidate = (base.slice(0, Math.max(0, 31 - suffix.length)) + suffix).trim();
      i++;
    }
    used.add(candidate);
    map.set(n, candidate);
  }
  return map;
}

/** Tek satırdaki tüm plan alanları (klasik + isteğe bağlı adımlar) */
type ProgramRow = Record<string, string | number | Date | "">;

type TrainingTypeLabels = {
  easy: string;
  long: string;
  threshold: string;
  interval: string;
};

function dateAtLocalMidnight(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function buildTrainingTypeLabels(
  trainingTypesData: Array<{ name?: string; display_name?: string }> | null,
): TrainingTypeLabels {
  const rows = trainingTypesData ?? [];
  const byName = (n: string): string =>
    String(rows.find((t) => String(t.name ?? "").toLowerCase() === n)?.display_name ?? "");
  return {
    easy: byName("easy_run") || "Easy Run",
    long: byName("long_run") || "Long Run",
    threshold: byName("threshold") || "Threshold (Tempo)",
    interval: byName("interval") || "Interval",
  };
}

function getNextMonthBounds(now = new Date()): { start: Date; end: Date } {
  const start = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  const end = new Date(now.getFullYear(), now.getMonth() + 2, 0);
  return { start, end };
}

function datesOfWeekdayInRange(start: Date, end: Date, weekday: number): Date[] {
  const dates: Date[] = [];
  const current = new Date(start);
  while (current <= end) {
    if (current.getDay() === weekday) {
      dates.push(new Date(current));
    }
    current.setDate(current.getDate() + 1);
  }
  return dates;
}

function pickCycle<T>(items: T[], index: number): T {
  return items[index % items.length];
}

function emptyAdimFields(): Record<string, string | ""> {
  const o: Record<string, string | ""> = {};
  for (let k = 1; k <= ADIM_COUNT; k++) {
    o[`adim${k}_tur`] = "";
    o[`adim${k}_sure`] = "";
    o[`adim${k}_pace_tip`] = "";
    o[`adim${k}_pace_min`] = "";
    o[`adim${k}_pace_max`] = "";
  }
  return o;
}

/** Sadece Adım sütunları + Tekrar + tür (klasik Isınma/Ana blokları yok) */
function baseStepRow(
  date: Date,
  groupName: string,
  ttName: string,
  repeat: number,
): ProgramRow {
  return {
    date: dateAtLocalMidnight(date),
    target_type: "Grup",
    training_group: groupName,
    performance_user: "",
    repeat_count: repeat,
    training_type: ttName,
    ...emptyAdimFields(),
  };
}

/** Örnek satırlar: günlere göre Isınma→Ana→… zinciri (Adım türünden seçilir) */
function buildGroupRow(
  date: Date,
  groupName: string,
  tt: TrainingTypeLabels,
): ProgramRow {
  const dow = date.getDay();
  const qualityTue = [
    { main: 15, rec: 1.5, rpt: 3, mainMin: "04:45", mainMax: "05:00" },
    { main: 10, rec: 1.5, rpt: 4, mainMin: "04:40", mainMax: "04:55" },
    { main: 15, rec: 1.5, rpt: 3, mainMin: "04:45", mainMax: "05:00" },
    { main: 10, rec: 1.0, rpt: 6, mainMin: "04:35", mainMax: "04:50" },
  ];
  const qualityThu = { main: 4, rec: 1, rpt: 6, mainMin: "04:30", mainMax: "04:45" };

  let row = baseStepRow(date, groupName, tt.easy, 1);
  row.adim1_tur = "Isınma";
  row.adim1_sure = 10;
  row.adim1_pace_tip = "Vdot";
  row.adim1_pace_min = "";
  row.adim1_pace_max = "";
  row.adim2_tur = "Ana";
  row.adim2_sure = 30;
  row.adim2_pace_tip = "Vdot";
  row.adim2_pace_min = "";
  row.adim2_pace_max = "";
  row.adim3_tur = "Toparlanma";
  row.adim3_sure = 1;
  row.adim3_pace_tip = "Aralık";
  row.adim3_pace_min = "09:00";
  row.adim3_pace_max = "10:00";
  row.adim4_tur = "Soğuma";
  row.adim4_sure = 10;
  row.adim4_pace_tip = "Vdot";
  row.adim4_pace_min = "";
  row.adim4_pace_max = "";

  if (dow === 2) {
    const weekIdx = Math.floor((date.getDate() - 1) / 7);
    const q = pickCycle(qualityTue, weekIdx);
    row = baseStepRow(date, groupName, tt.threshold, q.rpt);
    row.adim1_tur = "Isınma";
    row.adim1_sure = 15;
    row.adim1_pace_tip = "Aralık";
    row.adim1_pace_min = "06:30";
    row.adim1_pace_max = "07:00";
    row.adim2_tur = "Ana";
    row.adim2_sure = q.main;
    row.adim2_pace_tip = "Aralık";
    row.adim2_pace_min = q.mainMin;
    row.adim2_pace_max = q.mainMax;
    row.adim3_tur = "Toparlanma";
    row.adim3_sure = q.rec;
    row.adim3_pace_tip = "Aralık";
    row.adim3_pace_min = "09:00";
    row.adim3_pace_max = "10:00";
    row.adim4_tur = "Soğuma";
    row.adim4_sure = 10;
    row.adim4_pace_tip = "Vdot";
    row.adim4_pace_min = "";
    row.adim4_pace_max = "";
  } else if (dow === 4) {
    const weekIdx = Math.floor((date.getDate() - 1) / 7);
    if (weekIdx % 3 === 1) {
      row = baseStepRow(date, groupName, tt.threshold, qualityThu.rpt);
      row.adim1_tur = "Isınma";
      row.adim1_sure = 12;
      row.adim1_pace_tip = "Aralık";
      row.adim1_pace_min = "06:30";
      row.adim1_pace_max = "07:00";
      row.adim2_tur = "Ana";
      row.adim2_sure = qualityThu.main;
      row.adim2_pace_tip = "Aralık";
      row.adim2_pace_min = qualityThu.mainMin;
      row.adim2_pace_max = qualityThu.mainMax;
      row.adim3_tur = "Toparlanma";
      row.adim3_sure = qualityThu.rec;
      row.adim3_pace_tip = "Aralık";
      row.adim3_pace_min = "09:00";
      row.adim3_pace_max = "10:00";
      row.adim4_tur = "Soğuma";
      row.adim4_sure = 10;
      row.adim4_pace_tip = "Vdot";
      row.adim4_pace_min = "";
      row.adim4_pace_max = "";
    }
  } else if (dow === 6) {
    row = baseStepRow(date, groupName, tt.easy, 1);
    row.adim1_tur = "Isınma";
    row.adim1_sure = 8;
    row.adim1_pace_tip = "Vdot";
    row.adim2_tur = "Ana";
    row.adim2_sure = 20;
    row.adim2_pace_tip = "Vdot";
    row.adim3_tur = "Toparlanma";
    row.adim3_sure = 1;
    row.adim3_pace_tip = "Aralık";
    row.adim3_pace_min = "09:00";
    row.adim3_pace_max = "10:00";
    row.adim4_tur = "Soğuma";
    row.adim4_sure = 8;
    row.adim4_pace_tip = "Vdot";
  } else if (dow === 0) {
    row = baseStepRow(date, groupName, tt.long, 1);
    row.adim1_tur = "Isınma";
    row.adim1_sure = 12;
    row.adim1_pace_tip = "Vdot";
    row.adim2_tur = "Ana";
    row.adim2_sure = 90;
    row.adim2_pace_tip = "Vdot";
    row.adim3_tur = "Toparlanma";
    row.adim3_sure = 1;
    row.adim3_pace_tip = "Aralık";
    row.adim3_pace_min = "09:00";
    row.adim3_pace_max = "10:00";
    row.adim4_tur = "Soğuma";
    row.adim4_sure = 8;
    row.adim4_pace_tip = "Vdot";
  }

  return row;
}

/** Örnek: aynı satırda iki Ana segmenti (farklı süre/pace) */
function exampleDoubleMainStepRow(
  date: Date,
  groupName: string,
  tt: TrainingTypeLabels,
): ProgramRow {
  const row = baseStepRow(date, groupName, tt.threshold, 1);
  row.adim1_tur = "Ana";
  row.adim1_sure = 45;
  row.adim1_pace_tip = "Aralık";
  row.adim1_pace_min = "06:00";
  row.adim1_pace_max = "07:00";
  row.adim2_tur = "Ana";
  row.adim2_sure = 30;
  row.adim2_pace_tip = "Vdot";
  row.adim2_pace_min = "";
  row.adim2_pace_max = "";
  return row;
}

function colIndexByHeader(sheet: ExcelJS.Worksheet, header: string): number {
  const want = header.trim().toLocaleLowerCase("tr-TR");
  const row = sheet.getRow(1);
  for (let i = 1; i <= Math.max(sheet.columnCount, 120); i++) {
    const v = row.getCell(i).value;
    if (typeof v === "string" && v.trim().toLocaleLowerCase("tr-TR") === want) return i;
  }
  return -1;
}

function programColumnDefinitions(): { header: string; key: string; width: number }[] {
  const metaCols: { header: string; key: string; width: number }[] = [
    { header: "Antrenman Tarihi", key: "date", width: 18 },
    { header: "Hedef Türü", key: "target_type", width: 16 },
    { header: "Antrenman Grubu", key: "training_group", width: 24 },
    { header: "Performans Sporcuları", key: "performance_user", width: 34 },
  ];
  const adimCols: { header: string; key: string; width: number }[] = [];
  for (let k = 1; k <= ADIM_COUNT; k++) {
    adimCols.push(
      { header: `Adım ${k} Tür`, key: `adim${k}_tur`, width: 14 },
      { header: `Adım ${k} Süre (dk)`, key: `adim${k}_sure`, width: 14 },
      { header: `Adım ${k} Pace Tipi`, key: `adim${k}_pace_tip`, width: 14 },
      { header: `Adım ${k} Pace Min`, key: `adim${k}_pace_min`, width: 12 },
      { header: `Adım ${k} Pace Max`, key: `adim${k}_pace_max`, width: 12 },
    );
  }
  const tailCols: { header: string; key: string; width: number }[] = [
    { header: "Tekrar", key: "repeat_count", width: 10 },
    { header: "Antrenman Türü", key: "training_type", width: 20 },
  ];
  return [...metaCols, ...adimCols, ...tailCols];
}

function applyProgramSheetFormatting(
  sheet: ExcelJS.Worksheet,
  lastDataRow: number,
): void {
  const idx = (h: string) => colIndexByHeader(sheet, h);
  const dateCol = idx("Antrenman Tarihi");
  const textT = [idx("Hedef Türü"), idx("Antrenman Grubu"), idx("Performans Sporcuları")];
  const trainingTypeCol = idx("Antrenman Türü");
  const repeatCol = idx("Tekrar");

  for (let r = 2; r <= lastDataRow; r++) {
    if (dateCol > 0) sheet.getCell(r, dateCol).numFmt = "dd.mm.yyyy";
    for (const c of textT) {
      if (c > 0) sheet.getCell(r, c).numFmt = "@";
    }
    if (trainingTypeCol > 0) sheet.getCell(r, trainingTypeCol).numFmt = "@";
    if (repeatCol > 0) sheet.getCell(r, repeatCol).numFmt = "0";

    for (let k = 1; k <= ADIM_COUNT; k++) {
      const ct = idx(`Adım ${k} Tür`);
      const cs = idx(`Adım ${k} Süre (dk)`);
      const cp = idx(`Adım ${k} Pace Tipi`);
      const cmn = idx(`Adım ${k} Pace Min`);
      const cmx = idx(`Adım ${k} Pace Max`);
      if (ct > 0) sheet.getCell(r, ct).numFmt = "@";
      if (cp > 0) sheet.getCell(r, cp).numFmt = "@";
      if (cs > 0) sheet.getCell(r, cs).numFmt = "0.###";
      if (cmn > 0) sheet.getCell(r, cmn).numFmt = "@";
      if (cmx > 0) sheet.getCell(r, cmx).numFmt = "@";
    }
  }
}

function applyProgramSheetValidations(
  sheet: ExcelJS.Worksheet,
  opts: {
    groupCellRef: string;
    perfMaxRow: number;
    typeMaxRow: number;
    lastDataRow: number;
  },
): void {
  const idx = (h: string) => colIndexByHeader(sheet, h);
  const bc = idx("Hedef Türü");
  const cc = idx("Antrenman Grubu");
  const dc = idx("Performans Sporcuları");
  const trainingTypeCol = idx("Antrenman Türü");
  const repeatCol = idx("Tekrar");
  const adimPairs: Array<{ ct: number; cp: number }> = [];
  for (let k = 1; k <= ADIM_COUNT; k++) {
    adimPairs.push({
      ct: idx(`Adım ${k} Tür`),
      cp: idx(`Adım ${k} Pace Tipi`),
    });
  }
  const paceListFormula = '"Vdot,Aralık"';
  const adimTurFormula = '"Isınma,Ana,Toparlanma,Soğuma"';
  const endRow = programValidationEndRow(opts.lastDataRow);

  for (let r = 2; r <= endRow; r++) {
    if (bc > 0) {
      sheet.getCell(r, bc).dataValidation = {
        type: "list",
        allowBlank: false,
        formulae: ['"Grup,Performans"'],
      };
    }
    if (cc > 0) {
      sheet.getCell(r, cc).dataValidation = {
        type: "list",
        allowBlank: false,
        formulae: [opts.groupCellRef],
      };
    }
    if (dc > 0) {
      sheet.getCell(r, dc).dataValidation = {
        type: "list",
        allowBlank: true,
        formulae: [`'Listeler'!$E$2:$E$${opts.perfMaxRow}`],
      };
    }
    if (repeatCol > 0) {
      sheet.getCell(r, repeatCol).dataValidation = {
        type: "whole",
        operator: "greaterThanOrEqual",
        formulae: ["1"],
        allowBlank: true,
      };
    }
    if (trainingTypeCol > 0) {
      sheet.getCell(r, trainingTypeCol).dataValidation = {
        type: "list",
        allowBlank: false,
        formulae: [`'Listeler'!$D$2:$D$${opts.typeMaxRow}`],
      };
    }

    for (const { ct, cp } of adimPairs) {
      if (ct > 0) {
        sheet.getCell(r, ct).dataValidation = {
          type: "list",
          allowBlank: true,
          formulae: [adimTurFormula],
        };
      }
      if (cp > 0) {
        sheet.getCell(r, cp).dataValidation = {
          type: "list",
          allowBlank: true,
          formulae: [paceListFormula],
        };
      }
    }
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "GET" && req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response("Authorization required", {
        status: 401,
        headers: corsHeaders,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    if (!supabaseUrl || !supabaseAnonKey) {
      return new Response("Supabase env missing", {
        status: 500,
        headers: corsHeaders,
      });
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    const {
      data: { user },
      error: userErr,
    } = await supabase.auth.getUser(token);
    if (userErr || !user) {
      return new Response("Unauthorized", { status: 401, headers: corsHeaders });
    }

    const { data: roles } = await supabase
      .from("user_roles")
      .select("role")
      .eq("user_id", user.id)
      .eq("role", "super_admin");
    if (!roles || roles.length == 0) {
      return new Response("Forbidden", { status: 403, headers: corsHeaders });
    }

    const { data: groupsData } = await supabase
      .from("training_groups")
      .select("id,name,group_type")
      .eq("is_active", true)
      .order("difficulty_level", { ascending: true });

    const { data: trainingTypesData } = await supabase
      .from("training_types")
      .select("id,name,display_name")
      .eq("is_active", true)
      .order("sort_order", { ascending: true });

    const groups = (groupsData ?? []) as Array<{
      id: string;
      name: string;
      group_type?: string | null;
    }>;

    const performanceGroups = groups.filter((g) => (g.group_type ?? "normal") === "performance");
    const trainingTypeNames = (trainingTypesData ?? []).map((t) =>
      String((t as { display_name?: string; name?: string }).display_name ?? (t as { name?: string }).name ?? ""),
    ).filter((x) => x.length > 0);

    const ttLabels = buildTrainingTypeLabels(
      (trainingTypesData ?? []) as Array<{ name?: string; display_name?: string }>,
    );

    const performanceMembersByGroup = new Map<string, string[]>();
    for (const group of performanceGroups) {
      const { data: membersData } = await supabase
        .from("group_members")
        .select("user_id, users!inner(first_name,last_name,email)")
        .eq("group_id", group.id);

      const memberLabels = ((membersData ?? []) as Array<{
        user_id: string;
        users?: { first_name?: string; last_name?: string; email?: string } | null;
      }>)
        .map((m) => {
          const u = m.users ?? {};
          const fullName = `${u.first_name ?? ""} ${u.last_name ?? ""}`.trim();
          const email = (u.email ?? "").trim();
          if (!fullName && !email) return "";
          return email ? `${fullName} <${email}>` : fullName;
        })
        .filter((x) => x.length > 0)
        .sort((a, b) => a.localeCompare(b, "tr"));

      performanceMembersByGroup.set(group.name, memberLabels);
    }

    const allPerfMembers = Array.from(
      new Set(Array.from(performanceMembersByGroup.values()).flat()),
    ).sort((a, b) => a.localeCompare(b, "tr"));

    const groupNamesOrdered = groups.map((g) => g.name);
    const sheetTitleByGroup = uniqueSheetTitles(groupNamesOrdered);

    const workbook = new ExcelJS.Workbook();

    const { start: nextMonthStart, end: nextMonthEnd } = getNextMonthBounds();
    const targetWeekdays = [2, 4, 6, 0];
    const monthDates = targetWeekdays.flatMap((wd) =>
      datesOfWeekdayInRange(nextMonthStart, nextMonthEnd, wd),
    ).sort((a, b) => a.getTime() - b.getTime());

    const listSheet = workbook.addWorksheet("Listeler");
    listSheet.columns = [
      { header: "Grup Adı", key: "group_name", width: 30 },
      { header: "Grup Türü", key: "group_type", width: 16 },
      { header: "Liste Key", key: "range_key", width: 22 },
      { header: "Antrenman Türleri", key: "training_type", width: 24 },
    ];
    listSheet.getRow(1).font = { bold: true };

    const makeRangeKey = (name: string): string => {
      const normalized = name
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[^A-Za-z0-9]/g, "_")
        .replace(/_+/g, "_")
        .replace(/^_+|_+$/g, "");
      return `perf_${normalized || "group"}`;
    };

    for (const g of groups) {
      const isPerf = (g.group_type ?? "normal") === "performance";
      const rangeKey = isPerf ? makeRangeKey(g.name) : "";
      listSheet.addRow({
        group_name: g.name,
        group_type: isPerf ? "performance" : "normal",
        range_key: rangeKey,
      });
    }
    trainingTypeNames.forEach((t, i) => {
      listSheet.getCell(`D${i + 2}`).value = t;
    });

    listSheet.getCell("E1").value = "Performans Sporcu Havuzu";
    listSheet.getCell("E1").font = { bold: true };
    if (allPerfMembers.length == 0) {
      listSheet.getCell("E2").value = " ";
    } else {
      allPerfMembers.forEach((member, idx) => {
        listSheet.getCell(`E${idx + 2}`).value = member;
      });
    }

    listSheet.getCell("F1").value = "Şablon sekmesi";
    listSheet.getCell("G1").value = "Antrenman grubu";
    listSheet.getCell("F1").font = { bold: true };
    listSheet.getCell("G1").font = { bold: true };
    groups.forEach((g, i) => {
      const title = sheetTitleByGroup.get(g.name) ?? sanitizeSheetTitle(g.name);
      listSheet.getCell(`F${i + 2}`).value = title;
      listSheet.getCell(`G${i + 2}`).value = g.name;
    });

    const perfMaxRow = Math.max(allPerfMembers.length + 1, 2);
    const typeMaxRow = Math.max(trainingTypeNames.length + 1, 2);

    for (let gi = 0; gi < groups.length; gi++) {
      const g = groups[gi];
      const sheetName = sheetTitleByGroup.get(g.name) ?? sanitizeSheetTitle(g.name);
      const sheet = workbook.addWorksheet(sheetName);
      sheet.columns = programColumnDefinitions();
      sheet.getRow(1).font = { bold: true };

      const isPerf = (g.group_type ?? "normal") === "performance";
      const membersThisGroup = performanceMembersByGroup.get(g.name) ?? [];
      const perfDefaultUser = membersThisGroup[0] ?? "";

      /** Aynı gün + aynı grup (veya performansta aynı sporcu) DB'de tekil olmalı; örnek satır monthDates[0] ile çakışmasın */
      const sampleRows: ProgramRow[] = [];
      const datesWithoutExample = monthDates.length > 0 ? monthDates.slice(1) : [];
      for (const date of datesWithoutExample) {
        if (isPerf) {
          sampleRows.push({
            ...buildGroupRow(date, g.name, ttLabels),
            target_type: "Performans",
            performance_user: perfDefaultUser,
          });
        } else {
          sampleRows.push(buildGroupRow(date, g.name, ttLabels));
        }
      }
      if (monthDates.length > 0) {
        let ex = exampleDoubleMainStepRow(monthDates[0], g.name, ttLabels);
        if (isPerf && perfDefaultUser) {
          ex = {
            ...ex,
            target_type: "Performans",
            performance_user: perfDefaultUser,
          };
        }
        sampleRows.unshift(ex);
      }

      sampleRows.forEach((row) => sheet.addRow(row));
      const lastDataRow = Math.max(sheet.rowCount, 1);
      applyProgramSheetFormatting(sheet, lastDataRow);
      const listRow = gi + 2;
      applyProgramSheetValidations(sheet, {
        groupCellRef: `'Listeler'!$A$${listRow}:$A$${listRow}`,
        perfMaxRow,
        typeMaxRow,
        lastDataRow,
      });
    }

    const guide = workbook.addWorksheet("Açıklama");
    guide.columns = [{ header: "Kural", key: "kural", width: 140 }];
    guide.getRow(1).font = { bold: true };
    guide.addRows([
      { kural: "Sadece .xlsx yükleyin. CSV desteklenmez." },
      { kural: "Her aktif antrenman grubu ayrı sekmededir; sekmede veri satırı yoksa o ay o grup için plan yok demektir. Grup adı o sekmenin 'Antrenman Grubu' alanında sabitlenmiştir (Listeler!A ile aynı satır)." },
      { kural: "Antrenman yapısı Adım 1–8 ile kurulur: her adımda Tür (Isınma, Ana, Toparlanma, Soğuma), süre ve pace bilgisi. İlk boş Adım Tür’den sonrakiler okunmaz. En az bir Ana adımı olmalı." },
      { kural: "Tekrar: 1 = tek geçiş. Tekrar > 1 ise (interval) yalnızca ilk Ana ve hemen sonraki Toparlanma birlikte N kez tekrarlanır; öncesindeki/sonrasındaki adımlar (ör. ısınma, soğuma) tekrar dışında kalır." },
      { kural: "Pace Tipi: Vdot veya Aralık (Aralık ise Pace Min/Max zorunlu)." },
      { kural: "Antrenman Tarihi: gg.aa.yyyy. Pace hücreleri metin (HH:MM)." },
      { kural: "Antrenman Türü listedeki adla birebir eşleşmelidir." },
      { kural: "Eski şablonda hâlâ 'Ana Süre (dk)' gibi klasik sütunlar varsa içe aktarma o satırda klasik modu kullanır." },
      { kural: "Excel açılır listeleri (doğrulama) performans için ilk ~120 veri satırına uygulanır; daha fazla satır ekliyorsanız üstteki dolu bir satırı kopyalayıp yapıştırarak doğrulamayı çoğaltabilirsiniz." },
    ]);

    const buffer = await workbook.xlsx.writeBuffer();
    const base64 = uint8ToBase64(new Uint8Array(buffer));

    return new Response(JSON.stringify({
      file_name: "monthly_program_template.xlsx",
      mime_type:
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      file_base64: base64,
    }), {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({
        message: "Template olusturulamadi",
        error: String(error),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
