import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import ExcelJS from "https://esm.sh/exceljs@4.4.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type ImportError = { row: number; message: string; sheet?: string };

function asText(value: unknown): string {
  if (value == null) return "";
  if (typeof value === "string") return value.trim();
  if (typeof value === "number") return String(value);
  if (value instanceof Date) {
    const y = value.getFullYear();
    const m = String(value.getMonth() + 1).padStart(2, "0");
    const d = String(value.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }
  if (typeof value === "object" && value !== null && "text" in value) {
    return String((value as { text: unknown }).text ?? "").trim();
  }
  if (typeof value === "object" && value !== null && "richText" in value) {
    const rt = (value as { richText?: Array<{ text?: string }> }).richText;
    if (Array.isArray(rt)) {
      return rt.map((x) => x.text ?? "").join("").trim();
    }
  }
  return String(value).trim();
}

function parseDateOnly(value: unknown): string | null {
  if (value instanceof Date) {
    const y = value.getFullYear();
    const m = String(value.getMonth() + 1).padStart(2, "0");
    const d = String(value.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    const n = value;
    if (n > 20000 && n < 80000) {
      const excelEpoch = new Date(1899, 11, 30);
      const ms = excelEpoch.getTime() + Math.round(n) * 86400000;
      const dt = new Date(ms);
      const y = dt.getFullYear();
      const m = String(dt.getMonth() + 1).padStart(2, "0");
      const d = String(dt.getDate()).padStart(2, "0");
      return `${y}-${m}-${d}`;
    }
  }
  const raw = asText(value);
  if (!raw) return null;
  let m = raw.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  m = raw.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})/);
  if (m) {
    const d = m[1].padStart(2, "0");
    const mo = m[2].padStart(2, "0");
    const y = m[3];
    return `${y}-${mo}-${d}`;
  }
  return null;
}

function parsePaceSeconds(value: unknown): number | null {
  if (value == null || value === "") return null;
  if (typeof value === "number" && Number.isFinite(value)) {
    const n = value;
    if (n > 0 && n < 1) {
      const secsMidnight = Math.round(n * 86400);
      const totalMm = Math.floor(secsMidnight / 60);
      const ss = secsMidnight % 60;
      return totalMm * 60 + ss;
    }
    if (Number.isInteger(n) && n > 30 && n < 1200) return n;
    return null;
  }
  const raw = asText(value).replace(",", ".");
  if (!raw) return null;
  let match = raw.match(/^(\d{1,2}):(\d{2})$/);
  if (match) {
    const mm = Number(match[1]);
    const ss = Number(match[2]);
    if (mm < 0 || ss < 0 || ss > 59) return null;
    return mm * 60 + ss;
  }
  match = raw.match(/^(\d{1,2})\.(\d{2})$/);
  if (match) {
    const mm = Number(match[1]);
    const ss = Number(match[2]);
    if (mm < 0 || ss < 0 || ss > 59) return null;
    return mm * 60 + ss;
  }
  return null;
}

function parseMinutesToSeconds(value: unknown): number | null {
  if (value == null || value === "") return null;
  if (typeof value === "number" && Number.isFinite(value)) {
    const v = value;
    if (v > 0 && v < 1) {
      const secs = Math.round(v * 86400);
      const minutes = secs / 60;
      if (minutes > 0 && minutes <= 600) return Math.round(minutes * 60);
    }
    if (v > 0 && v <= 3000) return Math.round(v * 60);
    return null;
  }
  let raw = asText(value).trim().replace(/\s+/g, " ");
  raw = raw.replace(",", ".");
  const numMatch = raw.match(/^([\d.]+)/);
  if (numMatch) {
    const n = Number(numMatch[1]);
    if (!Number.isNaN(n) && n > 0) return Math.round(n * 60);
  }
  return null;
}

function extractEmail(label: string): string | null {
  const m = label.match(/<([^>]+)>/);
  if (m?.[1]) return m[1].trim().toLowerCase();
  const candidate = label.trim().toLowerCase();
  return candidate.includes("@") ? candidate : null;
}

const ADIM_COUNT = 8;

/** Şablondaki (monthly-program-template) ile aynı sekme adı kuralları */
function sanitizeSheetTitle(name: string): string {
  let s = name.replace(/[\\/*?:[\]]/g, " ").replace(/\s+/g, " ").trim();
  if (s.length > 31) s = s.slice(0, 31).trim();
  return s.length > 0 ? s : "Grup";
}

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

function isReservedMonthlySheet(name: string): boolean {
  const n = name.trim().toLowerCase();
  return n === "listeler" || n === "açıklama" || n === "aciklama";
}

function segmentJson(
  segmentType: "warmup" | "main" | "recovery" | "cooldown",
  durationSeconds: number,
  paceTypeNorm: string,
  paceMin: number | null,
  paceMax: number | null,
): Record<string, unknown> {
  const isAralık = paceTypeNorm === "aralık";
  const useVdot = paceTypeNorm === "vdot";
  return {
    type: "segment",
    segment: {
      segment_type: segmentType,
      target_type: "duration",
      target: "pace",
      duration_seconds: durationSeconds,
      ...(useVdot ? { use_vdot_for_pace: true } : {}),
      ...(isAralık && paceMin != null ? { pace_seconds_per_km_min: paceMin } : {}),
      ...(isAralık && paceMax != null ? { pace_seconds_per_km_max: paceMax } : {}),
    },
  };
}

function normalizePaceType(s: string): string {
  const t = s.toLowerCase().trim();
  if (t === "aralık" || t === "aralik") return "aralık";
  return "vdot";
}

type ClassicRow = {
  wuSec: number | null;
  wuPaceMin: number | null;
  wuPaceMax: number | null;
  wuPaceType: string;
  mainSec: number;
  mainPaceType: string;
  mainPaceMin: number | null;
  mainPaceMax: number | null;
  recSec: number | null;
  recPaceMin: number | null;
  recPaceMax: number | null;
  recPaceType: string;
  cdSec: number | null;
  cdPaceMin: number | null;
  cdPaceMax: number | null;
  cdPaceType: string;
  repeatCount: number;
};

function buildClassicWorkoutDefinition(row: ClassicRow): Record<string, unknown> {
  const steps: Array<Record<string, unknown>> = [];

  if (row.wuSec != null && row.wuSec > 0) {
    const pt = normalizePaceType(row.wuPaceType);
    steps.push(
      segmentJson("warmup", row.wuSec, pt, row.wuPaceMin, row.wuPaceMax),
    );
  }

  const mainPt = normalizePaceType(row.mainPaceType);
  const mainSegment = segmentJson(
    "main",
    row.mainSec,
    mainPt,
    mainPt === "aralık" ? row.mainPaceMin : null,
    mainPt === "aralık" ? row.mainPaceMax : null,
  );

  const repeatInner: Array<Record<string, unknown>> = [mainSegment];
  if (row.recSec != null && row.recSec > 0) {
    const rpt = normalizePaceType(row.recPaceType);
    repeatInner.push(
      segmentJson("recovery", row.recSec, rpt, row.recPaceMin, row.recPaceMax),
    );
  }

  steps.push({
    type: "repeat",
    repeat_count: row.repeatCount,
    steps: repeatInner,
  });

  if (row.cdSec != null && row.cdSec > 0) {
    const cpt = normalizePaceType(row.cdPaceType);
    steps.push(
      segmentJson("cooldown", row.cdSec, cpt, row.cdPaceMin, row.cdPaceMax),
    );
  }

  return { steps };
}

type AdimParsed = {
  kind: "warmup" | "main" | "recovery" | "cooldown";
  sec: number;
  paceType: string;
  pMin: number | null;
  pMax: number | null;
};

/** Excel / şablon metni; varsayılan toLowerCase() Türkçe I/ı/İ için yanlış (Isınma → isınma ≠ ısınma) */
function normalizeAdimTurLabel(s: string): string {
  return s.trim().replace(/\s+/g, " ").toLocaleLowerCase("tr-TR").normalize("NFC");
}

function mapAdimTur(t: string): AdimParsed["kind"] | null {
  const x = normalizeAdimTurLabel(t);
  /** "Isınma"→ısınma, "İsınma"→isınma (ilk harf farklı); Excel/klavye kaynaklı her ikisi de olur */
  if (x === "ısınma" || x === "isınma" || x === "isinma" || x === "warmup") return "warmup";
  if (x === "ana" || x === "main") return "main";
  if (x === "toparlanma" || x === "recovery") return "recovery";
  if (x === "soğuma" || x === "soguma" || x === "cooldown") return "cooldown";
  return null;
}

function buildModBWorkoutDefinition(
  adimlar: AdimParsed[],
  repeatCount: number,
): Record<string, unknown> {
  const segNodes = adimlar.map((a) =>
    segmentJson(a.kind, a.sec, normalizePaceType(a.paceType), a.pMin, a.pMax)
  );
  if (repeatCount <= 1) {
    return { steps: segNodes };
  }
  const mainIdx = adimlar.findIndex((a) => a.kind === "main");
  const recIdx = adimlar.findIndex((a, i) => i > mainIdx && a.kind === "recovery");
  if (mainIdx === -1 || recIdx === -1) {
    return { steps: segNodes };
  }
  const before = segNodes.slice(0, mainIdx);
  const inner = [segNodes[mainIdx], segNodes[recIdx]];
  const after = segNodes.slice(recIdx + 1);
  return {
    steps: [
      ...before,
      { type: "repeat", repeat_count: repeatCount, steps: inner },
      ...after,
    ],
  };
}

function workoutSummaryClassic(repeatCount: number): string {
  return `Sabit blok (Isınma + ${repeatCount}x[Ana+Toparlanma] + Soğuma)`;
}

function workoutSummaryModB(n: number, repeatCount: number): string {
  if (repeatCount > 1) {
    return `Çoklu adım (${n} segment, ${repeatCount}x Ana+Toparlanma çekirdeği)`;
  }
  return `Çoklu adım (${n} segment)`;
}

function normalizeTrainingTypeLookupKey(s: string): string {
  return s.toLowerCase().trim().replace(/^\d+\s+/, "").replace(/\s+/g, " ");
}

function resolveTrainingTypeId(
  rawLabel: string,
  trainingTypeMap: Map<string, string>,
): string | null {
  const n = normalizeTrainingTypeLookupKey(rawLabel);
  if (!n) return null;
  const direct = trainingTypeMap.get(n);
  if (direct) return direct;
  if (n === "easy") {
    const x = trainingTypeMap.get("easy run");
    if (x) return x;
  }
  if (n === "threshold") {
    const x = trainingTypeMap.get("threshold (tempo)");
    if (x) return x;
  }
  if (n.includes("hard tempo")) {
    return trainingTypeMap.get("interval") ?? trainingTypeMap.get("repetition") ?? null;
  }
  return null;
}

function classicDataPresent(
  wuPresent: boolean,
  mainPresent: boolean,
  recPresent: boolean,
  cdPresent: boolean,
  repeatCount: number,
): boolean {
  return wuPresent || mainPresent || recPresent || cdPresent ||
    (Number.isFinite(repeatCount) && repeatCount > 1);
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

    const body = (await req.json().catch(() => null)) as
      | {
          month_key?: string;
          title?: string;
          file_name?: string;
          file_bytes?: number[];
        }
      | null;

    const monthKey = body?.month_key?.trim();
    const fileBytes = body?.file_bytes;
    const fileName = body?.file_name?.trim() || "monthly_program.xlsx";

    if (!monthKey || !/^\d{4}-(0[1-9]|1[0-2])$/.test(monthKey)) {
      return new Response("month_key invalid", { status: 400, headers: corsHeaders });
    }
    if (!fileBytes || !Array.isArray(fileBytes) || fileBytes.length === 0) {
      return new Response("file_bytes required", { status: 400, headers: corsHeaders });
    }
    if (!fileName.toLowerCase().endsWith(".xlsx")) {
      return new Response("Only .xlsx is supported", { status: 400, headers: corsHeaders });
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
    const userId = userData.user.id;

    const { data: roles } = await supabase
      .from("user_roles")
      .select("role")
      .eq("user_id", userId)
      .eq("role", "super_admin");
    if (!roles || roles.length === 0) {
      return new Response("Forbidden", { status: 403, headers: corsHeaders });
    }

    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(new Uint8Array(fileBytes).buffer);

    const { data: groupsDataOrdered } = await supabase
      .from("training_groups")
      .select("id,name,group_type")
      .eq("is_active", true)
      .order("difficulty_level", { ascending: true });

    const groupsOrdered = (groupsDataOrdered ?? []) as Array<{
      id: string;
      name: string;
      group_type?: string | null;
    }>;

    const sheetTitleByGroup = uniqueSheetTitles(groupsOrdered.map((g) => g.name));
    const groupNameBySheetTitle = new Map<string, string>();
    for (const g of groupsOrdered) {
      const t = sheetTitleByGroup.get(g.name);
      if (t) groupNameBySheetTitle.set(t, g.name);
    }

    const programLegacy = workbook.getWorksheet("Program");
    type SheetJob = {
      sheet: ExcelJS.Worksheet;
      implicitGroup: string | null;
      sheetTag?: string;
    };
    const sheetJobs: SheetJob[] = [];

    if (programLegacy) {
      sheetJobs.push({ sheet: programLegacy, implicitGroup: null });
    } else {
      const candidates = workbook.worksheets.filter((ws) =>
        !isReservedMonthlySheet(ws.name)
      );
      const allTitlesMatch = candidates.length > 0 &&
        candidates.every((ws) => groupNameBySheetTitle.has(ws.name));

      if (allTitlesMatch) {
        for (const ws of candidates) {
          const gName = groupNameBySheetTitle.get(ws.name)!;
          sheetJobs.push({ sheet: ws, implicitGroup: gName, sheetTag: ws.name });
        }
      } else if (candidates.length === 1) {
        sheetJobs.push({ sheet: candidates[0], implicitGroup: null });
      } else if (candidates.length === 0) {
        return new Response(
          JSON.stringify({
            success: false,
            message:
              "Veri sekmesi yok. Eski şablonda 'Program' sekmesi veya yeni şablondaki grup sekmeleri beklenir.",
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      } else {
        const unknown = candidates.filter((ws) => !groupNameBySheetTitle.has(ws.name));
        const detail = unknown.length > 0
          ? ` Tanınmayan sekmeler: ${unknown.map((w) => `"${w.name}"`).join(", ")}.`
          : "";
        return new Response(
          JSON.stringify({
            success: false,
            message:
              `Grup sekmeleri şablonla uyuşmuyor.${detail} Güncel şablonu indirin veya eski tek sayfa ('Program') kullanın.`,
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    const errors: ImportError[] = [];
    const rawEntries: Array<Record<string, unknown>> = [];

    const get = (row: ExcelJS.Row, c: number | null): unknown =>
      c ? row.getCell(c).value : null;

    for (const job of sheetJobs) {
      const { sheet, implicitGroup, sheetTag } = job;
      const pushErr = (rowNum: number, msg: string) => {
        const message = sheetTag ? `[${sheetTag}] Satır ${rowNum}: ${msg}` : msg;
        errors.push({ row: rowNum, sheet: sheetTag, message });
      };

      const headers = sheet.getRow(1).values as Array<string | null>;
      const normTr = (s: string) => s.trim().toLocaleLowerCase("tr-TR");
      const col = (name: string): number | null => {
        const want = normTr(name);
        const idx = headers.findIndex(
          (v) => typeof v === "string" && normTr(v) === want,
        );
        return idx === -1 ? null : idx;
      };

      const cDate = col("antrenman tarihi");
      const cTargetType = col("hedef türü");
      const cGroup = col("antrenman grubu");
      const cPerfUser = col("performans sporcuları");
      const hasClassicCols = col("ana süre (dk)") != null;
      const cWuMin = col("ısınma süre (dk)") ?? col("isınma süre (dk)");
      const cWuPaceMin = col("ısınma pace min") ?? col("isınma pace min");
      const cWuPaceMax = col("ısınma pace max") ?? col("isınma pace max");
      const cWuPaceType = col("ısınma pace tipi") ?? col("isınma pace tipi");
      const cMainMin = col("ana süre (dk)");
      const cMainPaceType = col("ana pace tipi");
      const cMainPaceMin = col("ana pace min");
      const cMainPaceMax = col("ana pace max");
      const cRecMin = col("toparlanma süre (dk)");
      const cRecPaceMin = col("toparlanma pace min");
      const cRecPaceMax = col("toparlanma pace max");
      const cRecPaceType = col("toparlanma pace tipi");
      const cCdMin = col("soğuma süre (dk)") ?? col("soguma süre (dk)");
      const cCdPaceMin = col("soğuma pace min") ?? col("soguma pace min");
      const cCdPaceMax = col("soğuma pace max") ?? col("soguma pace max");
      const cCdPaceType = col("soğuma pace tipi") ?? col("soguma pace tipi");
      const cRepeat = col("tekrar");
      const cTrainingType = col("antrenman türü");

      const adimCols: Array<{
        tur: number | null;
        sure: number | null;
        paceTip: number | null;
        pMin: number | null;
        pMax: number | null;
      }> = [];
      for (let k = 1; k <= ADIM_COUNT; k++) {
        adimCols.push({
          tur: col(`adım ${k} tür`) ?? col(`adim ${k} tur`),
          sure: col(`adım ${k} süre (dk)`) ?? col(`adim ${k} sure (dk)`),
          paceTip: col(`adım ${k} pace tipi`) ?? col(`adim ${k} pace tipi`),
          pMin: col(`adım ${k} pace min`) ?? col(`adim ${k} pace min`),
          pMax: col(`adım ${k} pace max`) ?? col(`adim ${k} pace max`),
        });
      }

      if (!cDate || !cTargetType || !cGroup || !cTrainingType) {
        return new Response(
          "Şablon kolonları eksik. Lütfen güncel şablonu tekrar indirin.",
          { status: 400, headers: corsHeaders },
        );
      }
      if (hasClassicCols && (!cMainPaceType || !cRepeat)) {
        return new Response(
          "Klasik şablonda Ana Pace Tipi ve Tekrar sütunları gerekir.",
          { status: 400, headers: corsHeaders },
        );
      }

      sheet.eachRow((row, rowNum) => {
        if (rowNum === 1) return;
        const planDate = parseDateOnly(get(row, cDate));
        const targetType = asText(get(row, cTargetType)).toLowerCase();
        const groupCellVal = asText(get(row, cGroup));
        let groupName = groupCellVal;
        const perfUserLabel = asText(get(row, cPerfUser));
      const wuSec = parseMinutesToSeconds(get(row, cWuMin));
      const wuPaceMin = parsePaceSeconds(get(row, cWuPaceMin));
      const wuPaceMax = parsePaceSeconds(get(row, cWuPaceMax));
      const wuPaceTypeRaw = asText(get(row, cWuPaceType)) || "Vdot";
      const mainSec = parseMinutesToSeconds(get(row, cMainMin));
      const mainPaceType = asText(get(row, cMainPaceType)).toLowerCase();
      const mainPaceMin = parsePaceSeconds(get(row, cMainPaceMin));
      const mainPaceMax = parsePaceSeconds(get(row, cMainPaceMax));
      const recSec = parseMinutesToSeconds(get(row, cRecMin));
      const recPaceMin = parsePaceSeconds(get(row, cRecPaceMin));
      const recPaceMax = parsePaceSeconds(get(row, cRecPaceMax));
      const recPaceTypeRaw = asText(get(row, cRecPaceType)) || "Vdot";
      const cdSec = parseMinutesToSeconds(get(row, cCdMin));
      const cdPaceMin = parsePaceSeconds(get(row, cCdPaceMin));
      const cdPaceMax = parsePaceSeconds(get(row, cCdPaceMax));
      const cdPaceTypeRaw = asText(get(row, cCdPaceType)) || "Vdot";
      const repeatRaw = cRepeat ? asText(get(row, cRepeat)) : "";
      const repeatCount = repeatRaw === "" ? 1 : Number(repeatRaw);
      const trainingTypeName = asText(get(row, cTrainingType));

      const adimlarParsed: AdimParsed[] = [];
      let usesModB = false;
      for (let k = 0; k < ADIM_COUNT; k++) {
        const ac = adimCols[k];
        const turS = asText(get(row, ac.tur));
        if (!turS) break;
        usesModB = true;
        const kind = mapAdimTur(turS);
        if (!kind) {
          pushErr(rowNum, `Adım ${k + 1} Tür geçersiz`);
          adimlarParsed.length = 0;
          break;
        }
        const sec = parseMinutesToSeconds(get(row, ac.sure));
        const ptRaw = asText(get(row, ac.paceTip)) || "Vdot";
        const pMin = parsePaceSeconds(get(row, ac.pMin));
        const pMax = parsePaceSeconds(get(row, ac.pMax));
        if (!sec || sec <= 0) {
          pushErr(rowNum, `Adım ${k + 1} süresi zorunlu`);
          adimlarParsed.length = 0;
          break;
        }
        const pt = normalizePaceType(ptRaw);
        if (pt === "aralık" && (pMin == null || pMax == null)) {
          pushErr(rowNum, `Adım ${k + 1}: Aralık için Pace Min/Max zorunlu`);
          adimlarParsed.length = 0;
          break;
        }
        adimlarParsed.push({ kind, sec, paceType: ptRaw, pMin, pMax });
      }

      const isEmptyRow = !planDate && !targetType && !groupCellVal && !usesModB;
      if (isEmptyRow) return;

      if (implicitGroup != null) {
        groupName = implicitGroup;
        if (groupCellVal && groupCellVal !== implicitGroup) {
          pushErr(
            rowNum,
            `Antrenman Grubu bu sekmede '${implicitGroup}' olmalı (hücrede: '${groupCellVal}')`,
          );
        }
      }

      if (!planDate) pushErr(rowNum, "Antrenman Tarihi geçersiz");
      if (!["grup", "performans"].includes(targetType)) {
        pushErr(rowNum, "Hedef Türü: Grup veya Performans olmalı");
      }
      if (!groupName) {
        pushErr(rowNum, "Antrenman Grubu zorunlu");
      }
      if (targetType === "performans" && !perfUserLabel) {
        pushErr(rowNum, "Performans satırında sporcu seçimi zorunlu");
      }
      if (!trainingTypeName) {
        pushErr(rowNum, "Antrenman Türü zorunlu");
      }

      const wuPresent = wuSec != null && wuSec > 0;
      const recPresent = recSec != null && recSec > 0;
      const cdPresent = cdSec != null && cdSec > 0;
      const mainPresent = mainSec != null && mainSec > 0;

      if (usesModB) {
        if (!Number.isFinite(repeatCount) || repeatCount < 1) {
          pushErr(rowNum, "Tekrar en az 1 olmalı");
        }
        if (hasClassicCols && classicDataPresent(wuPresent, mainPresent, recPresent, cdPresent, repeatCount)) {
          pushErr(
            rowNum,
            "Adım satırı kullanılıyorsa klasik sütunlarda süre ve Tekrar>1 doldurulmamalı",
          );
        }
        if (adimlarParsed.length === 0) {
          pushErr(rowNum, "Adım tanımı eksik");
        }
        const hasMain = adimlarParsed.some((a) => a.kind === "main");
        if (!hasMain) {
          pushErr(rowNum, "En az bir Ana adımı olmalı");
        }
        if (repeatCount > 1) {
          const mainIdx = adimlarParsed.findIndex((a) => a.kind === "main");
          const recIdx = adimlarParsed.findIndex((a, i) => i > mainIdx && a.kind === "recovery");
          if (mainIdx === -1 || recIdx === -1) {
            pushErr(
              rowNum,
              "Tekrar > 1 iken sırayla en az bir Ana ve onu izleyen Toparlanma adımı gerekli",
            );
          }
        }
      } else if (hasClassicCols) {
        if (!mainPresent || !mainSec) {
          pushErr(rowNum, "Ana Süre (dk) zorunlu (veya Adım sütunlarını doldurun)");
        }
        if (!Number.isFinite(repeatCount) || repeatCount < 1) {
          pushErr(rowNum, "Tekrar en az 1 olmalı");
        }
        if (repeatCount > 1 && !recPresent) {
          pushErr(rowNum, "Tekrar > 1 iken Toparlanma süresi zorunlu");
        }
        if (normalizePaceType(mainPaceType) === "aralık" && (mainPaceMin == null || mainPaceMax == null)) {
          pushErr(rowNum, "Ana Pace Tipi Aralık ise Ana Pace Min/Max zorunlu");
        }
        if (wuPresent && normalizePaceType(wuPaceTypeRaw) === "aralık" &&
          (wuPaceMin == null || wuPaceMax == null)) {
          pushErr(rowNum, "Isınma Aralık: Pace Min/Max zorunlu");
        }
        if (recPresent && normalizePaceType(recPaceTypeRaw) === "aralık" &&
          (recPaceMin == null || recPaceMax == null)) {
          pushErr(rowNum, "Toparlanma Aralık: Pace Min/Max zorunlu");
        }
        if (cdPresent && normalizePaceType(cdPaceTypeRaw) === "aralık" &&
          (cdPaceMin == null || cdPaceMax == null)) {
          pushErr(rowNum, "Soğuma Aralık: Pace Min/Max zorunlu");
        }
      } else {
        pushErr(rowNum, "En az bir Adım Türü girin");
      }

      rawEntries.push({
        rowNum,
        sourceSheet: sheetTag ?? null,
        planDate,
        targetType,
        groupName,
        perfUserLabel,
        usesModB,
        adimlarParsed,
        wuSec,
        wuPaceMin,
        wuPaceMax,
        wuPaceType: wuPaceTypeRaw,
        mainSec: mainSec ?? 0,
        mainPaceType,
        mainPaceMin,
        mainPaceMax,
        recSec,
        recPaceMin,
        recPaceMax,
        recPaceType: recPaceTypeRaw,
        cdSec,
        cdPaceMin,
        cdPaceMax,
        cdPaceType: cdPaceTypeRaw,
        repeatCount: Math.floor(Number.isFinite(repeatCount) ? repeatCount : 1),
        trainingTypeName,
      });
    });
    }

    if (errors.length > 0) {
      return new Response(
        JSON.stringify({ success: false, accepted_rows: 0, rejected_rows: errors.length, errors }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: users } = await supabase
      .from("users")
      .select("id,email");
    const { data: memberships } = await supabase
      .from("group_members")
      .select("group_id,user_id");
    const { data: trainingTypes } = await supabase
      .from("training_types")
      .select("id,name,display_name")
      .eq("is_active", true);

    const groupMap = new Map(
      groupsOrdered.map((g) => [
        String(g.name).toLowerCase(),
        { id: g.id as string, groupType: (g.group_type as string | null) ?? "normal" },
      ]),
    );
    const userMap = new Map((users ?? []).map((u) => [String(u.email).toLowerCase(), u.id]));
    const memberSet = new Set((memberships ?? []).map((m) => `${m.group_id}::${m.user_id}`));
    const trainingTypeMap = new Map(
      (trainingTypes ?? []).flatMap((t) => {
        const rec = t as { id: string; name?: string | null; display_name?: string | null };
        const keys = [
          String(rec.name ?? "").toLowerCase().trim(),
          String(rec.display_name ?? "").toLowerCase().trim(),
        ].filter((x) => x.length > 0);
        return keys.map((k) => [k, rec.id] as const);
      }),
    );

    const insertRows: Array<Record<string, unknown>> = [];
    for (const entry of rawEntries) {
      const rowNum = Number(entry.rowNum);
      const targetType = String(entry.targetType);
      const sourceSheet = entry.sourceSheet ? String(entry.sourceSheet) : undefined;
      const rejectRow = (msg: string) => {
        const message = sourceSheet ? `[${sourceSheet}] Satır ${rowNum}: ${msg}` : msg;
        errors.push({ row: rowNum, sheet: sourceSheet, message });
      };
      let trainingGroupId: string | null = null;
      let userIdRef: string | null = null;

      const groupObj = groupMap.get(String(entry.groupName).toLowerCase()) ?? null;
      trainingGroupId = groupObj?.id ?? null;
      if (!trainingGroupId) {
        rejectRow("Antrenman grubu bulunamadı");
        continue;
      }

      if (targetType === "performans") {
        const mail = extractEmail(String(entry.perfUserLabel));
        userIdRef = mail ? (userMap.get(mail) ?? null) : null;
        if (!userIdRef) {
          rejectRow("Performans sporcusu çözümlenemedi");
          continue;
        }
        if (groupObj?.groupType !== "performance") {
          rejectRow("Performans satırında performans grubu seçilmeli");
          continue;
        }
        if (!memberSet.has(`${trainingGroupId}::${userIdRef}`)) {
          rejectRow("Sporcu seçilen performans grubunun üyesi değil");
          continue;
        }
      }

      let workoutDefinition: Record<string, unknown>;
      let programContentStr: string;
      if (entry.usesModB) {
        const steps = entry.adimlarParsed as AdimParsed[];
        const rc = Number(entry.repeatCount);
        workoutDefinition = buildModBWorkoutDefinition(
          steps,
          Number.isFinite(rc) && rc >= 1 ? Math.floor(rc) : 1,
        );
        programContentStr = workoutSummaryModB(
          steps.length,
          Number.isFinite(rc) && rc >= 1 ? Math.floor(rc) : 1,
        );
      } else {
        workoutDefinition = buildClassicWorkoutDefinition({
          wuSec: entry.wuSec as number | null,
          wuPaceMin: entry.wuPaceMin as number | null,
          wuPaceMax: entry.wuPaceMax as number | null,
          wuPaceType: String(entry.wuPaceType),
          mainSec: Number(entry.mainSec),
          mainPaceType: String(entry.mainPaceType),
          mainPaceMin: entry.mainPaceMin as number | null,
          mainPaceMax: entry.mainPaceMax as number | null,
          recSec: entry.recSec as number | null,
          recPaceMin: entry.recPaceMin as number | null,
          recPaceMax: entry.recPaceMax as number | null,
          recPaceType: String(entry.recPaceType),
          cdSec: entry.cdSec as number | null,
          cdPaceMin: entry.cdPaceMin as number | null,
          cdPaceMax: entry.cdPaceMax as number | null,
          cdPaceType: String(entry.cdPaceType),
          repeatCount: Number(entry.repeatCount),
        });
        programContentStr = workoutSummaryClassic(Number(entry.repeatCount));
      }
      const trainingTypeId = resolveTrainingTypeId(String(entry.trainingTypeName), trainingTypeMap);
      if (!trainingTypeId) {
        rejectRow("Antrenman Türü bulunamadı");
        continue;
      }

      insertRows.push({
        plan_date: entry.planDate,
        scope_type: targetType === "performans" ? "member" : "group",
        training_group_id: trainingGroupId,
        user_id: userIdRef,
        training_type_id: trainingTypeId,
        program_content: programContentStr,
        workout_definition: workoutDefinition,
        sort_order: 0,
      });
    }

    if (errors.length > 0) {
      return new Response(
        JSON.stringify({ success: false, accepted_rows: 0, rejected_rows: errors.length, errors }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Replace month data atomically-ish
    const { data: monthBatches } = await supabase
      .from("monthly_program_batches")
      .select("id")
      .eq("month_key", monthKey);
    const batchIds = (monthBatches ?? []).map((b) => b.id as string);
    if (batchIds.length > 0) {
      await supabase.from("monthly_program_entries").delete().in("batch_id", batchIds);
      await supabase.from("monthly_program_batches").delete().in("id", batchIds);
    }

    const { data: batch, error: batchErr } = await supabase
      .from("monthly_program_batches")
      .insert({
        month_key: monthKey,
        title: body?.title ?? `${monthKey} Programi`,
        status: "active",
        source_file_name: fileName,
        row_count: insertRows.length,
        error_count: 0,
        uploaded_by: userId,
      })
      .select("id")
      .single();

    if (batchErr || !batch) {
      return new Response("Batch create failed", { status: 500, headers: corsHeaders });
    }

    const rowsWithBatch = insertRows.map((r) => ({ ...r, batch_id: batch.id }));
    const { error: insertErr } = await supabase
      .from("monthly_program_entries")
      .insert(rowsWithBatch);
    if (insertErr) {
      await supabase.from("monthly_program_batches").delete().eq("id", batch.id);
      return new Response(
        JSON.stringify({ success: false, message: insertErr.message }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        accepted_rows: rowsWithBatch.length,
        rejected_rows: 0,
        errors: [],
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        success: false,
        message: "Import failed",
        error: String(error),
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
