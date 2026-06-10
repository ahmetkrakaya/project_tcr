import { useCallback, useEffect, useState } from "react";
import { WeekDayForm } from "../components/WeekDayForm";
import {
  type DayDraft,
  type GroupMember,
  type TrainingGroup,
  type TrainingType,
  dayDraftsToPayload,
  fetchGroupMembers,
  fetchTrainingGroups,
  fetchTrainingTypes,
  getWeeklyProgramEntries,
  rowsToDayDrafts,
  upsertWeeklyProgram,
} from "../lib/api";
import { mondayOf, weekTitle } from "../lib/dates";

const emptyDays = (): DayDraft[] =>
  Array.from({ length: 7 }, () => ({
    workout: "",
    coachNotes: "",
    trainingTypeOverride: null,
  }));

export function WeeklyEditorPage() {
  const [weekStart, setWeekStart] = useState(() => mondayOf(new Date()));
  const [groups, setGroups] = useState<TrainingGroup[]>([]);
  const [trainingTypes, setTrainingTypes] = useState<TrainingType[]>([]);
  const [selectedGroupId, setSelectedGroupId] = useState<string>("");
  const [members, setMembers] = useState<GroupMember[]>([]);
  const [selectedMemberIds, setSelectedMemberIds] = useState<Set<string>>(
    new Set(),
  );
  const [days, setDays] = useState<DayDraft[]>(emptyDays);
  const [dirty, setDirty] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingWeek, setLoadingWeek] = useState(false);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<{
    type: "success" | "error" | "warning";
    text: string;
  } | null>(null);

  const selectedGroup = groups.find((g) => g.id === selectedGroupId);
  const isPerformance = selectedGroup?.group_type === "performance";

  const loadWeekData = useCallback(
    async (clearFirst = false) => {
      if (!selectedGroupId) return;

      if (isPerformance && selectedMemberIds.size > 1) {
        if (clearFirst) setDays(emptyDays());
        setDirty(false);
        return;
      }

      if (clearFirst) setDays(emptyDays());
      setLoadingWeek(true);
      setMessage(null);
      try {
        const memberId =
          isPerformance && selectedMemberIds.size === 1
            ? [...selectedMemberIds][0]
            : null;

        const rows = await getWeeklyProgramEntries({
          weekStartMonday: weekStart,
          trainingGroupId: selectedGroupId,
          memberUserId: memberId,
        });
        setDays(rowsToDayDrafts(rows, weekStart));
        setDirty(false);
      } catch (err) {
        setMessage({
          type: "error",
          text:
            err instanceof Error ? err.message : "Haftalık plan yüklenemedi",
        });
      } finally {
        setLoadingWeek(false);
      }
    },
    [selectedGroupId, weekStart, isPerformance, selectedMemberIds],
  );

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const [g, types] = await Promise.all([
          fetchTrainingGroups(),
          fetchTrainingTypes(),
        ]);
        if (cancelled) return;
        setGroups(g);
        setTrainingTypes(types);
        if (g.length > 0) {
          setSelectedGroupId(g[0].id);
        }
      } catch (err) {
        if (!cancelled) {
          setMessage({
            type: "error",
            text: err instanceof Error ? err.message : "Veriler yüklenemedi",
          });
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!selectedGroupId) return;
    let cancelled = false;
    (async () => {
      try {
        const m = await fetchGroupMembers(selectedGroupId);
        if (cancelled) return;
        setMembers(m);
        setSelectedMemberIds(new Set());
      } catch (err) {
        if (!cancelled) {
          setMessage({
            type: "error",
            text:
              err instanceof Error ? err.message : "Grup üyeleri yüklenemedi",
          });
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [selectedGroupId]);

  useEffect(() => {
    if (!selectedGroupId || loading) return;
    loadWeekData(true);
  }, [selectedGroupId, weekStart, selectedMemberIds, loading, loadWeekData]);

  function shiftWeek(delta: number) {
    if (dirty && !confirm("Kaydedilmemiş değişiklikler var. Devam edilsin mi?")) {
      return;
    }
    const next = new Date(weekStart);
    next.setDate(next.getDate() + delta * 7);
    setWeekStart(mondayOf(next));
  }

  function handleGroupChange(groupId: string) {
    if (
      dirty &&
      !confirm("Kaydedilmemiş değişiklikler var. Grup değiştirilsin mi?")
    ) {
      return;
    }
    setSelectedGroupId(groupId);
    setSelectedMemberIds(new Set());
    setDirty(false);
  }

  function toggleMember(userId: string) {
    if (
      dirty &&
      !confirm("Kaydedilmemiş değişiklikler var. Sporcu seçimi değiştirilsin mi?")
    ) {
      return;
    }
    setSelectedMemberIds((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
  }

  function updateDay(index: number, patch: Partial<DayDraft>) {
    setDays((prev) =>
      prev.map((d, i) => (i === index ? { ...d, ...patch } : d)),
    );
    setDirty(true);
  }

  async function copyPreviousWeek() {
    if (!selectedGroupId) return;
    setLoadingWeek(true);
    setMessage(null);
    try {
      const prevMonday = new Date(weekStart);
      prevMonday.setDate(prevMonday.getDate() - 7);
      const memberId =
        isPerformance && selectedMemberIds.size === 1
          ? [...selectedMemberIds][0]
          : null;
      const rows = await getWeeklyProgramEntries({
        weekStartMonday: prevMonday,
        trainingGroupId: selectedGroupId,
        memberUserId: memberId,
      });
      setDays(rowsToDayDrafts(rows, prevMonday));
      setDirty(true);
      setMessage({
        type: "success",
        text: "Geçen haftanın programı kopyalandı (kaydetmeyi unutmayın)",
      });
    } catch (err) {
      setMessage({
        type: "error",
        text: err instanceof Error ? err.message : "Kopyalama başarısız",
      });
    } finally {
      setLoadingWeek(false);
    }
  }

  async function handleSave() {
    if (!selectedGroup) return;

    if (isPerformance && selectedMemberIds.size === 0) {
      setMessage({
        type: "warning",
        text: "Performans grubu için en az bir sporcu seçin",
      });
      return;
    }

    setSaving(true);
    setMessage(null);
    const payload = dayDraftsToPayload(days, weekStart);
    const targets =
      isPerformance ? [...selectedMemberIds] : [null as string | null];

    const allErrors: Array<{ plan_date: string; message: string }> = [];

    try {
      for (const memberId of targets) {
        const { errors } = await upsertWeeklyProgram({
          weekStartMonday: weekStart,
          scopeType: isPerformance ? "member" : "group",
          trainingGroupId: selectedGroup.id,
          memberUserId: memberId,
          days: payload,
        });
        allErrors.push(...errors);
      }

      if (allErrors.length > 0) {
        const summary = allErrors
          .slice(0, 5)
          .map((e) => `${e.plan_date}: ${e.message}`)
          .join("\n");
        setMessage({
          type: "error",
          text: `Kayıt hataları:\n${summary}${
            allErrors.length > 5 ? `\n…ve ${allErrors.length - 5} hata daha` : ""
          }`,
        });
      } else {
        setDirty(false);
        setMessage({
          type: "success",
          text:
            targets.length > 1
              ? `${targets.length} sporcu için program kaydedildi`
              : "Program kaydedildi",
        });
        await loadWeekData(false);
      }
    } catch (err) {
      setMessage({
        type: "error",
        text: err instanceof Error ? err.message : "Kayıt başarısız",
      });
    } finally {
      setSaving(false);
    }
  }

  if (loading) {
    return <p className="muted">Yükleniyor…</p>;
  }

  return (
    <div className="stack">
      <div className="card toolbar">
        <div className="row">
          <button type="button" className="btn btn-ghost" onClick={() => shiftWeek(-1)}>
            ← Önceki hafta
          </button>
          <strong>{weekTitle(weekStart)}</strong>
          <button type="button" className="btn btn-ghost" onClick={() => shiftWeek(1)}>
            Sonraki hafta →
          </button>
        </div>
        <div className="row">
          <button
            type="button"
            className="btn"
            onClick={copyPreviousWeek}
            disabled={loadingWeek || saving}
          >
            Geçen haftadan kopyala
          </button>
          <button
            type="button"
            className="btn btn-primary"
            onClick={handleSave}
            disabled={!dirty || saving || loadingWeek}
          >
            {saving ? "Kaydediliyor…" : dirty ? "Kaydet" : "Kaydedildi"}
          </button>
        </div>
      </div>

      {message && (
        <div className={`alert alert-${message.type}`} style={{ whiteSpace: "pre-wrap" }}>
          {message.text}
        </div>
      )}

      <div className="card stack">
        <div className="row">
          <label style={{ flex: 1, minWidth: 200 }}>
            Antrenman grubu
            <select
              value={selectedGroupId}
              onChange={(e) => handleGroupChange(e.target.value)}
            >
              {groups.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                  {g.group_type === "performance" ? " (Performans)" : ""}
                </option>
              ))}
            </select>
          </label>
        </div>

        {isPerformance && (
          <div className="stack">
            <span className="muted">
              Sporcular (birden fazla seçilirse aynı program hepsine atanır)
            </span>
            <div className="member-chips">
              {members.map((m) => (
                <button
                  key={m.user_id}
                  type="button"
                  className={`chip ${selectedMemberIds.has(m.user_id) ? "selected" : ""}`}
                  onClick={() => toggleMember(m.user_id)}
                >
                  {m.userName}
                </button>
              ))}
              {members.length === 0 && (
                <span className="muted">Bu grupta üye yok</span>
              )}
            </div>
            {selectedMemberIds.size > 1 && (
              <div className="alert alert-warning">
                Çoklu sporcu modu: mevcut hafta yüklenmez; girdiğiniz program
                seçili tüm sporculara kaydedilir.
              </div>
            )}
          </div>
        )}
      </div>

      {loadingWeek ? (
        <p className="muted">Hafta yükleniyor…</p>
      ) : (
        <WeekDayForm
          weekStartMonday={weekStart}
          days={days}
          trainingTypes={trainingTypes}
          disabled={saving}
          onChange={updateDay}
        />
      )}
    </div>
  );
}
