import type { DayDraft, TrainingType } from "../lib/api";
import { DAY_LABELS, dayDate, ymd } from "../lib/dates";
import { TRACK_LANE_OPTIONS } from "../lib/track_lane";
import { dayHasPreviewContent, ProgramPreviewCard } from "./ProgramPreviewCard";

type Props = {
  weekStartMonday: Date;
  days: DayDraft[];
  trainingTypes: TrainingType[];
  disabled?: boolean;
  locked?: boolean;
  showInlinePreview?: boolean;
  onChange: (index: number, patch: Partial<DayDraft>) => void;
};

export function WeekDayForm({
  weekStartMonday,
  days,
  trainingTypes,
  disabled,
  locked,
  showInlinePreview = true,
  onChange,
}: Props) {
  const fieldsDisabled = disabled || locked;
  return (
    <div className="day-grid">
      {days.map((day, index) => {
        const date = dayDate(weekStartMonday, index);
        const dateLabel = new Intl.DateTimeFormat("tr-TR", {
          day: "numeric",
          month: "long",
        }).format(date);

        return (
          <div className="card day-card" key={index}>
            <h3>
              {DAY_LABELS[index]}{" "}
              <span className="date-sub">
                {dateLabel} ({ymd(date)})
              </span>
            </h3>
            <div className="stack">
              <label>
                Antrenman metni
                <textarea
                  value={day.workout}
                  disabled={fieldsDisabled}
                  placeholder={
                    locked
                      ? "Önce grup (ve performansta sporcu) seçin"
                      : "Örn: 45dk kolay veya REST"
                  }
                  onChange={(e) =>
                    onChange(index, {
                      workout: e.target.value,
                      workoutDefinition: null,
                      persistedCoachText: null,
                    })
                  }
                />
              </label>
              <label>
                Koç notu
                <textarea
                  value={day.coachNotes}
                  disabled={fieldsDisabled}
                  placeholder={
                    locked
                      ? "Önce grup (ve performansta sporcu) seçin"
                      : "Sporcuya gösterilecek not (opsiyonel)"
                  }
                  onChange={(e) =>
                    onChange(index, { coachNotes: e.target.value })
                  }
                />
              </label>
              <div className="day-field-row">
                <label>
                  Antrenman türü
                  <select
                    value={day.trainingTypeOverride ?? ""}
                    disabled={fieldsDisabled}
                    onChange={(e) =>
                      onChange(index, {
                        trainingTypeOverride: e.target.value || null,
                      })
                    }
                  >
                    <option value="">Otomatik (metinden)</option>
                    {trainingTypes.map((t) => (
                      <option key={t.id} value={t.name}>
                        {t.display_name}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  Pist
                  <select
                    value={day.trackLane ?? ""}
                    disabled={fieldsDisabled}
                    onChange={(e) =>
                      onChange(index, {
                        trackLane: e.target.value
                          ? Number(e.target.value)
                          : null,
                      })
                    }
                  >
                    <option value="">Pistte değil</option>
                    {TRACK_LANE_OPTIONS.map((lane) => (
                      <option key={lane} value={lane}>
                        Kulvar {lane}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
              {showInlinePreview && dayHasPreviewContent(day) && (
                  <div className="day-inline-preview">
                    <div className="day-inline-preview-label">Önizleme</div>
                    <ProgramPreviewCard
                      workoutText={day.workout}
                      coachNotes={day.coachNotes}
                      trainingTypeOverride={day.trainingTypeOverride}
                      trainingTypes={trainingTypes}
                      workoutDefinition={day.workoutDefinition}
                      trackLane={day.trackLane}
                    />
                  </div>
                )}
            </div>
          </div>
        );
      })}
    </div>
  );
}
