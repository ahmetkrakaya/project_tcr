import { DAY_LABELS, dayDate, weekTitle } from "../lib/dates";
import type { DayDraft, TrainingType } from "../lib/api";
import { ProgramPreviewCard } from "./ProgramPreviewCard";

type Props = {
  open: boolean;
  onClose: () => void;
  weekStartMonday: Date;
  days: DayDraft[];
  trainingTypes: TrainingType[];
};

export function WeekPreviewModal({
  open,
  onClose,
  weekStartMonday,
  days,
  trainingTypes,
}: Props) {
  if (!open) return null;

  const dateFmt = new Intl.DateTimeFormat("tr-TR", {
    day: "numeric",
    month: "short",
  });

  return (
    <div className="modal-backdrop" onClick={onClose} role="presentation">
      <div
        className="modal-panel"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="preview-title"
      >
        <div className="modal-header">
          <div>
            <h2 id="preview-title">Haftalık önizleme</h2>
            <p className="muted">{weekTitle(weekStartMonday)}</p>
          </div>
          <button type="button" className="btn btn-ghost" onClick={onClose}>
            Kapat
          </button>
        </div>
        <div className="modal-body stack">
          {days.map((day, index) => {
            const date = dayDate(weekStartMonday, index);
            return (
              <section key={index} className="preview-day-section">
                <h3>
                  {DAY_LABELS[index]} {dateFmt.format(date)}
                </h3>
                <ProgramPreviewCard
                  workoutText={day.workout}
                  coachNotes={day.coachNotes}
                  trainingTypeOverride={day.trainingTypeOverride}
                  trainingTypes={trainingTypes}
                />
              </section>
            );
          })}
        </div>
      </div>
    </div>
  );
}
