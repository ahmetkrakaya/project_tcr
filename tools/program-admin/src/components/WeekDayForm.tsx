import type { DayDraft, TrainingType } from "../lib/api";
import { DAY_LABELS, dayDate, ymd } from "../lib/dates";

type Props = {
  weekStartMonday: Date;
  days: DayDraft[];
  trainingTypes: TrainingType[];
  disabled?: boolean;
  onChange: (index: number, patch: Partial<DayDraft>) => void;
};

export function WeekDayForm({
  weekStartMonday,
  days,
  trainingTypes,
  disabled,
  onChange,
}: Props) {
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
                  disabled={disabled}
                  placeholder="Örn: 45dk kolay veya REST"
                  onChange={(e) =>
                    onChange(index, { workout: e.target.value })
                  }
                />
              </label>
              <label>
                Koç notu
                <textarea
                  value={day.coachNotes}
                  disabled={disabled}
                  placeholder="Sporcuya gösterilecek not (opsiyonel)"
                  onChange={(e) =>
                    onChange(index, { coachNotes: e.target.value })
                  }
                />
              </label>
              <label>
                Antrenman türü
                <select
                  value={day.trainingTypeOverride ?? ""}
                  disabled={disabled}
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
            </div>
          </div>
        );
      })}
    </div>
  );
}
