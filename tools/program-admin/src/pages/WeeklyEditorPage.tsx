import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { WeekDayForm } from "../components/WeekDayForm";
import { WeekPreviewModal } from "../components/WeekPreviewModal";
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

function dayHasDraftContent(day: DayDraft): boolean {
  return (
    day.workout.trim().length > 0 ||
    day.coachNotes.trim().length > 0 ||
    (day.workoutDefinition?.steps?.length ?? 0) > 0 ||
    (day.persistedCoachText?.trim().length ?? 0) > 0
  );
}

const emptyDays = (): DayDraft[] =>
  Array.from({ length: 7 }, () => ({
    workout: "",
    coachNotes: "",
    trainingTypeOverride: null,
    trackLane: null,
    workoutDefinition: null,
    persistedCoachText: null,
  }));

type GroupDraftSnapshot = {
  days: DayDraft[];
  dirty: boolean;
};

function memberKey(ids: Iterable<string>): string {
  return [...ids].sort().join(",");
}

function draftCacheKey(groupId: string, memberIds: string[]): string {
  if (memberIds.length === 0) return groupId;
  return `${groupId}|${memberKey(memberIds)}`;
}

function parseDraftCacheKey(key: string): {
  groupId: string;
  memberIds: string[];
} {
  if (!key.includes("|")) {
    return { groupId: key, memberIds: [] };
  }
  const [groupId, members] = key.split("|");
  return {
    groupId,
    memberIds: members ? members.split(",").filter(Boolean) : [],
  };
}

function snapshotFromDays(days: DayDraft[], dirty: boolean): GroupDraftSnapshot {
  return {
    days: days.map((d) => ({ ...d })),
    dirty,
  };
}

function draftLabel(
  key: string,
  groups: TrainingGroup[],
  members: GroupMember[],
): string {
  const { groupId, memberIds } = parseDraftCacheKey(key);
  const groupName = groups.find((g) => g.id === groupId)?.name ?? "Grup";
  if (memberIds.length === 0) return groupName;
  if (memberIds.length === 1) {
    const name =
      members.find((m) => m.user_id === memberIds[0])?.userName ?? "sporcu";
    return `${groupName} (${name})`;
  }
  return `${groupName} (${memberIds.length} sporcu)`;
}

export function WeeklyEditorPage() {
  const [weekStart, setWeekStart] = useState(() => mondayOf(new Date()));
  const [groups, setGroups] = useState<TrainingGroup[]>([]);
  const [trainingTypes, setTrainingTypes] = useState<TrainingType[]>([]);
  const [selectedGroupId, setSelectedGroupId] = useState<string>("");
  const [members, setMembers] = useState<GroupMember[]>([]);
  const [membersGroupId, setMembersGroupId] = useState<string | null>(null);
  const [membersLoading, setMembersLoading] = useState(false);
  const [selectedMemberIds, setSelectedMemberIds] = useState<string[]>([]);
  const [days, setDays] = useState<DayDraft[]>(emptyDays);
  const [dirty, setDirty] = useState(false);
  const [draftCache, setDraftCache] = useState<Record<string, GroupDraftSnapshot>>(
    {},
  );
  const [loading, setLoading] = useState(true);
  const [loadingWeek, setLoadingWeek] = useState(false);
  const [saving, setSaving] = useState(false);
  const [previewOpen, setPreviewOpen] = useState(false);
  const [message, setMessage] = useState<{
    type: "success" | "error" | "warning";
    text: string;
  } | null>(null);

  const loadRequestRef = useRef(0);
  const daysRef = useRef(days);
  const dirtyRef = useRef(dirty);
  const draftCacheRef = useRef(draftCache);

  daysRef.current = days;
  dirtyRef.current = dirty;
  draftCacheRef.current = draftCache;

  const selectedGroup = groups.find((g) => g.id === selectedGroupId);
  const isPerformance = selectedGroup?.group_type === "performance";
  const selectedMemberKey = useMemo(
    () => memberKey(selectedMemberIds),
    [selectedMemberIds],
  );

  const canEditProgram = Boolean(
    selectedGroupId && (!isPerformance || selectedMemberIds.length > 0),
  );

  const stashCurrentDraft = useCallback(() => {
    if (!selectedGroupId) return;
    const key = draftCacheKey(selectedGroupId, selectedMemberIds);
    setDraftCache((prev) => ({
      ...prev,
      [key]: snapshotFromDays(daysRef.current, dirtyRef.current),
    }));
  }, [selectedGroupId, selectedMemberIds]);

  const cacheWithCurrent = useMemo(() => {
    const merged = { ...draftCache };
    if (selectedGroupId && canEditProgram) {
      merged[draftCacheKey(selectedGroupId, selectedMemberIds)] =
        snapshotFromDays(days, dirty);
    }
    return merged;
  }, [
    draftCache,
    days,
    dirty,
    selectedGroupId,
    selectedMemberIds,
    canEditProgram,
  ]);

  const pendingSaveCount = useMemo(
    () => Object.values(cacheWithCurrent).filter((s) => s.dirty).length,
    [cacheWithCurrent],
  );

  const copySourceGroups = useMemo(
    () =>
      groups.filter(
        (g) => g.group_type !== "performance" && g.id !== selectedGroupId,
      ),
    [groups, selectedGroupId],
  );

  const membersReady =
    !isPerformance || (membersGroupId === selectedGroupId && !membersLoading);

  const loadWeekFromApi = useCallback(async () => {
    if (!selectedGroupId) return;

    const requestId = ++loadRequestRef.current;
    setLoadingWeek(true);

    try {
      const memberId =
        isPerformance && selectedMemberIds.length === 1
          ? selectedMemberIds[0]
          : null;

      const rows = await getWeeklyProgramEntries({
        weekStartMonday: weekStart,
        trainingGroupId: selectedGroupId,
        memberUserId: memberId,
      });

      if (requestId !== loadRequestRef.current) return;

      setDays(rowsToDayDrafts(rows, weekStart));
      setDirty(false);
    } catch (err) {
      if (requestId !== loadRequestRef.current) return;
      setMessage({
        type: "error",
        text:
          err instanceof Error ? err.message : "Haftalık plan yüklenemedi",
      });
    } finally {
      if (requestId === loadRequestRef.current) {
        setLoadingWeek(false);
      }
    }
  }, [selectedGroupId, weekStart, isPerformance, selectedMemberIds]);

  const restoreDraftOrLoad = useCallback(async () => {
    if (!selectedGroupId) return;

    if (isPerformance && selectedMemberIds.length === 0) {
      setDays(emptyDays());
      setDirty(false);
      return;
    }

    if (isPerformance && selectedMemberIds.length > 1) {
      const cached =
        draftCacheRef.current[
          draftCacheKey(selectedGroupId, selectedMemberIds)
        ];
      if (cached) {
        setDays(cached.days.map((d) => ({ ...d })));
        setDirty(cached.dirty);
        return;
      }
      setDays(emptyDays());
      setDirty(false);
      return;
    }

    const cached =
      draftCacheRef.current[draftCacheKey(selectedGroupId, selectedMemberIds)];
    if (cached) {
      setDays(cached.days.map((d) => ({ ...d })));
      setDirty(cached.dirty);
      return;
    }

    await loadWeekFromApi();
  }, [selectedGroupId, isPerformance, selectedMemberIds, loadWeekFromApi]);

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
    if (!selectedGroupId) {
      setMembers([]);
      setMembersGroupId(null);
      setMembersLoading(false);
      return;
    }

    const groupId = selectedGroupId;
    setMembers([]);
    setMembersGroupId(null);
    setMembersLoading(true);

    let cancelled = false;
    (async () => {
      try {
        const m = await fetchGroupMembers(groupId);
        if (cancelled || groupId !== selectedGroupId) return;
        setMembers(m);
        setMembersGroupId(groupId);
      } catch (err) {
        if (!cancelled && groupId === selectedGroupId) {
          setMessage({
            type: "error",
            text:
              err instanceof Error ? err.message : "Grup üyeleri yüklenemedi",
          });
        }
      } finally {
        if (!cancelled && groupId === selectedGroupId) {
          setMembersLoading(false);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [selectedGroupId]);

  useEffect(() => {
    if (!selectedGroupId || loading) return;
    void restoreDraftOrLoad();
  }, [
    selectedGroupId,
    weekStart,
    selectedMemberKey,
    loading,
    restoreDraftOrLoad,
  ]);

  function shiftWeek(delta: number) {
    if (
      pendingSaveCount > 0 &&
      !confirm(
        `${pendingSaveCount} kaydedilmemiş taslak var. Hafta değiştirilsin mi?`,
      )
    ) {
      return;
    }
    setDraftCache({});
    const next = new Date(weekStart);
    next.setDate(next.getDate() + delta * 7);
    setWeekStart(mondayOf(next));
    setMessage(null);
  }

  function handleGroupChange(groupId: string) {
    if (groupId === selectedGroupId) return;

    const target = groups.find((g) => g.id === groupId);
    stashCurrentDraft();
    setSelectedGroupId(groupId);
    setSelectedMemberIds([]);
    setMembers([]);
    setMembersGroupId(null);
    setMembersLoading(target?.group_type === "performance");
    setMessage(null);

    if (target?.group_type === "performance") {
      setDays(emptyDays());
      setDirty(false);
    }
  }

  function toggleMember(userId: string) {
    const prevCount = selectedMemberIds.length;
    stashCurrentDraft();

    const nextIds = selectedMemberIds.includes(userId)
      ? selectedMemberIds.filter((id) => id !== userId)
      : [...selectedMemberIds, userId];

    setSelectedMemberIds(nextIds);
    setMessage(null);

    if (nextIds.length === 0) {
      setDays(emptyDays());
      setDirty(false);
      return;
    }

    if (nextIds.length > 1 && prevCount <= 1) {
      const cached =
        draftCacheRef.current[draftCacheKey(selectedGroupId, nextIds)];
      if (cached) {
        setDays(cached.days.map((d) => ({ ...d })));
        setDirty(cached.dirty);
        return;
      }
      if (prevCount === 0) {
        setDays(emptyDays());
      }
      setDirty(nextIds.length > 0);
    }
  }

  function updateDay(index: number, patch: Partial<DayDraft>) {
    setDays((prev) =>
      prev.map((d, i) => (i === index ? { ...d, ...patch } : d)),
    );
    setDirty(true);
  }

  async function copyFromOtherGroup(sourceGroupId: string) {
    if (!selectedGroupId || !canEditProgram) return;

    setMessage(null);
    const cached = draftCacheRef.current[sourceGroupId];
    if (cached?.days.some((d) => dayHasDraftContent(d))) {
      setDays(cached.days.map((d) => ({ ...d })));
      setDirty(true);
      const name = groups.find((g) => g.id === sourceGroupId)?.name ?? "Grup";
      setMessage({
        type: "success",
        text: `${name} taslağından kopyalandı (kaydetmeyi unutmayın)`,
      });
      return;
    }

    setLoadingWeek(true);
    try {
      const rows = await getWeeklyProgramEntries({
        weekStartMonday: weekStart,
        trainingGroupId: sourceGroupId,
      });
      if (rows.length === 0) {
        setMessage({
          type: "warning",
          text: "Seçilen grupta bu hafta için kayıtlı program yok",
        });
        return;
      }
      setDays(rowsToDayDrafts(rows, weekStart));
      setDirty(true);
      const name = groups.find((g) => g.id === sourceGroupId)?.name ?? "Grup";
      setMessage({
        type: "success",
        text: `${name} programından kopyalandı (kaydetmeyi unutmayın)`,
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

  async function copyPreviousWeek() {
    if (!selectedGroupId || !canEditProgram) return;
    setLoadingWeek(true);
    setMessage(null);
    try {
      const prevMonday = new Date(weekStart);
      prevMonday.setDate(prevMonday.getDate() - 7);
      const memberId =
        isPerformance && selectedMemberIds.length === 1
          ? selectedMemberIds[0]
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
    const mergedCache = { ...draftCacheRef.current };
    if (selectedGroupId && canEditProgram) {
      mergedCache[draftCacheKey(selectedGroupId, selectedMemberIds)] =
        snapshotFromDays(daysRef.current, dirtyRef.current);
    }

    const dirtyEntries = Object.entries(mergedCache).filter(
      ([, snapshot]) => snapshot.dirty,
    );

    if (dirtyEntries.length === 0) {
      setMessage({
        type: "warning",
        text: "Kaydedilecek değişiklik yok",
      });
      return;
    }

    setSaving(true);
    setMessage(null);

    const allErrors: Array<{ label: string; plan_date?: string; message: string }> =
      [];
    const savedKeys: string[] = [];

    try {
      for (const [key, snapshot] of dirtyEntries) {
        const { groupId, memberIds } = parseDraftCacheKey(key);
        const group = groups.find((g) => g.id === groupId);
        if (!group) continue;

        const label = draftLabel(key, groups, members);
        const isPerf = group.group_type === "performance";

        if (isPerf && memberIds.length === 0) {
          allErrors.push({
            label,
            message: "sporcu seçilmedi",
          });
          continue;
        }

        const targets = isPerf ? memberIds : [null as string | null];
        const keyErrors: Array<{ plan_date: string; message: string }> = [];

        for (const memberId of targets) {
          const { errors } = await upsertWeeklyProgram({
            weekStartMonday: weekStart,
            scopeType: isPerf ? "member" : "group",
            trainingGroupId: groupId,
            memberUserId: memberId,
            days: dayDraftsToPayload(snapshot.days, weekStart),
          });
          keyErrors.push(...errors);
        }

        if (keyErrors.length === 0) {
          savedKeys.push(key);
        } else {
          for (const error of keyErrors) {
            allErrors.push({
              label,
              plan_date: error.plan_date,
              message: error.message,
            });
          }
        }
      }

      setDraftCache((prev) => {
        const next = { ...prev, ...mergedCache };
        for (const key of savedKeys) {
          if (next[key]) {
            next[key] = { ...next[key], dirty: false };
          }
        }
        return next;
      });

      if (selectedGroupId && canEditProgram) {
        const currentKey = draftCacheKey(selectedGroupId, selectedMemberIds);
        if (savedKeys.includes(currentKey)) {
          setDirty(false);
        }
      }

      if (allErrors.length > 0) {
        const summary = allErrors
          .slice(0, 5)
          .map((e) =>
            e.plan_date
              ? `${e.label} — ${e.plan_date}: ${e.message}`
              : `${e.label}: ${e.message}`,
          )
          .join("\n");
        setMessage({
          type: "error",
          text: `Kayıt hataları:\n${summary}${
            allErrors.length > 5 ? `\n…ve ${allErrors.length - 5} hata daha` : ""
          }`,
        });
      } else {
        setMessage({
          type: "success",
          text:
            savedKeys.length === 1
              ? `${draftLabel(savedKeys[0], groups, members)} kaydedildi`
              : `${savedKeys.length} program kaydedildi`,
        });
        await restoreDraftOrLoad();
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

  const saveButtonLabel = saving
    ? "Kaydediliyor…"
    : pendingSaveCount > 1
      ? `Tümünü kaydet (${pendingSaveCount})`
      : pendingSaveCount === 1
        ? "Kaydet"
        : "Kaydedildi";

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
          {loadingWeek && (
            <span className="muted" aria-live="polite">
              Program yükleniyor…
            </span>
          )}
          {pendingSaveCount > 0 && (
            <span className="muted">
              {pendingSaveCount} kaydedilmemiş taslak
            </span>
          )}
          <button
            type="button"
            className="btn btn-secondary"
            onClick={() => setPreviewOpen(true)}
            disabled={loadingWeek || saving}
          >
            Önizleme
          </button>
          <button
            type="button"
            className="btn"
            onClick={copyPreviousWeek}
            disabled={loadingWeek || saving || !canEditProgram}
          >
            Geçen haftadan kopyala
          </button>
          {copySourceGroups.length > 0 && (
            <label className="copy-group-select">
              <span className="sr-only">Gruptan kopyala</span>
              <select
                defaultValue=""
                disabled={loadingWeek || saving || !canEditProgram}
                onChange={(e) => {
                  const value = e.target.value;
                  if (value) {
                    void copyFromOtherGroup(value);
                    e.target.value = "";
                  }
                }}
              >
                <option value="">Gruptan kopyala…</option>
                {copySourceGroups.map((g) => (
                  <option key={g.id} value={g.id}>
                    {g.name}
                  </option>
                ))}
              </select>
            </label>
          )}
          <button
            type="button"
            className="btn btn-primary"
            onClick={handleSave}
            disabled={pendingSaveCount === 0 || saving || loadingWeek}
          >
            {saveButtonLabel}
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
              {groups.map((g) => {
                const hasDraft = Object.entries(cacheWithCurrent).some(
                  ([key, snapshot]) =>
                    snapshot.dirty &&
                    parseDraftCacheKey(key).groupId === g.id,
                );
                return (
                  <option key={g.id} value={g.id}>
                    {g.name}
                    {g.group_type === "performance" ? " (Performans)" : ""}
                    {hasDraft ? " •" : ""}
                  </option>
                );
              })}
            </select>
          </label>
        </div>

        {isPerformance && (
          <div className="stack">
            <span className="muted">
              Sporcular (birden fazla seçilirse aynı program hepsine atanır)
            </span>
            {membersLoading && (
              <span className="muted">Sporcular yükleniyor…</span>
            )}
            <div className="member-chips">
              {membersReady &&
                members.map((m) => (
                <button
                  key={m.user_id}
                  type="button"
                  className={`chip ${selectedMemberIds.includes(m.user_id) ? "selected" : ""}`}
                  onClick={() => toggleMember(m.user_id)}
                >
                  {m.userName}
                </button>
              ))}
              {membersReady && members.length === 0 && (
                <span className="muted">Bu grupta üye yok</span>
              )}
            </div>
            {selectedMemberIds.length > 1 && (
              <div className="alert alert-warning">
                Çoklu sporcu modu: mevcut hafta yüklenmez; girdiğiniz program
                seçili tüm sporculara kaydedilir.
              </div>
            )}
          </div>
        )}
      </div>

      {!canEditProgram && (
        <div className="alert alert-warning">
          {!selectedGroupId
            ? "Program girmek için bir antrenman grubu seçin."
            : "Performans grubunda program girmek için en az bir sporcu seçin."}
        </div>
      )}

      <div
        className={`day-grid-wrapper${loadingWeek ? " day-grid-wrapper--loading" : ""}`}
        aria-busy={loadingWeek}
      >
        <WeekDayForm
          weekStartMonday={weekStart}
          days={days}
          trainingTypes={trainingTypes}
          disabled={saving || loadingWeek}
          locked={!canEditProgram}
          onChange={updateDay}
        />
      </div>

      <WeekPreviewModal
        open={previewOpen}
        onClose={() => setPreviewOpen(false)}
        weekStartMonday={weekStart}
        days={days}
        trainingTypes={trainingTypes}
      />
    </div>
  );
}
