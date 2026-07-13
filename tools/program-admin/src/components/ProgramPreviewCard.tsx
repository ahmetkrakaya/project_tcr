import { parseCoachText } from "../lib/coach_text_parser";
import type { TrainingType, WorkoutDefinition } from "../lib/api";
import { adjustSegmentJsonForLane } from "../lib/track_lane";

type WorkoutStep = {
  type?: string;
  repeat_count?: number;
  steps?: WorkoutStep[];
  segment?: {
    segment_type?: string;
    target_type?: string;
    duration_seconds?: number;
    distance_meters?: number;
    pace_seconds_per_km_min?: number;
    pace_seconds_per_km_max?: number;
    use_vdot_for_pace?: boolean;
    duration_seconds_min?: number;
    duration_seconds_max?: number;
  };
};

const SEGMENT_LABELS: Record<string, string> = {
  warmup: "Isınma",
  main: "Ana",
  recovery: "Toparlanma",
  cooldown: "Soğuma",
};

function formatDuration(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  if (m <= 0) return `${s}s`;
  if (s === 0) return `${m} dk`;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function formatPace(secPerKm: number): string {
  const m = Math.floor(secPerKm / 60);
  const s = secPerKm % 60;
  return `${m}:${String(s).padStart(2, "0")}/km`;
}

function formatDistance(meters: number): string {
  if (meters >= 1000) {
    const km = meters / 1000;
    return meters % 1000 === 0 ? `${km} km` : `${km.toFixed(1)} km`;
  }
  return `${Math.round(meters)} m`;
}

function segmentDetails(
  seg: NonNullable<WorkoutStep["segment"]>,
  referenceLane: number | null,
  viewLane: number | null,
): string[] {
  const adjusted =
    referenceLane != null &&
    viewLane != null &&
    referenceLane !== viewLane
      ? adjustSegmentJsonForLane(seg, referenceLane, viewLane)
      : seg;
  const out: string[] = [];
  if (adjusted.target_type === "duration" && adjusted.duration_seconds) {
    out.push(formatDuration(adjusted.duration_seconds));
  }
  if (adjusted.distance_meters && adjusted.distance_meters > 0) {
    out.push(formatDistance(adjusted.distance_meters));
  }
  if (
    adjusted.target_type !== "duration" &&
    adjusted.duration_seconds &&
    adjusted.duration_seconds > 0
  ) {
    out.push(formatDuration(adjusted.duration_seconds));
  }
  if (adjusted.duration_seconds_min && adjusted.duration_seconds_max) {
    out.push(
      `${formatDuration(adjusted.duration_seconds_min)}-${formatDuration(adjusted.duration_seconds_max)}`,
    );
  } else if (adjusted.duration_seconds_min) {
    out.push(formatDuration(adjusted.duration_seconds_min));
  }
  if (seg.use_vdot_for_pace) {
    out.push("VDOT pace");
  } else if (seg.pace_seconds_per_km_min && seg.pace_seconds_per_km_max) {
    const min = seg.pace_seconds_per_km_min;
    const max = seg.pace_seconds_per_km_max;
    out.push(
      min === max
        ? `Tempo ${formatPace(min)}`
        : `Tempo ${formatPace(min)}-${formatPace(max)}`,
    );
  }
  return out;
}

function StepList({
  steps,
  depth = 0,
  referenceLane,
  viewLane,
}: {
  steps: WorkoutStep[];
  depth?: number;
  referenceLane: number | null;
  viewLane: number | null;
}) {
  return (
    <>
      {steps.map((step, i) => (
        <StepNode
          key={`${depth}-${i}`}
          step={step}
          depth={depth}
          referenceLane={referenceLane}
          viewLane={viewLane}
        />
      ))}
    </>
  );
}

function StepNode({
  step,
  depth,
  referenceLane,
  viewLane,
}: {
  step: WorkoutStep;
  depth: number;
  referenceLane: number | null;
  viewLane: number | null;
}) {
  if (step.type === "repeat" && step.steps) {
    return (
      <div className="preview-step" style={{ marginLeft: depth * 12 }}>
        <div className="preview-repeat">
          <span className="preview-repeat-icon">↻</span>
          {step.repeat_count ?? 1}x tekrar
        </div>
        <StepList
          steps={step.steps}
          depth={depth + 1}
          referenceLane={referenceLane}
          viewLane={viewLane}
        />
      </div>
    );
  }

  if (step.type === "segment" && step.segment) {
    const seg = step.segment;
    const label = SEGMENT_LABELS[seg.segment_type ?? "main"] ?? "Ana";
    const details = segmentDetails(seg, referenceLane, viewLane);
    return (
      <div className="preview-step" style={{ marginLeft: depth * 12 }}>
        <div className="preview-segment">
          <div className="preview-segment-icon">🏃</div>
          <div>
            <div className="preview-segment-title">{label}</div>
            {details.length > 0 && (
              <div className="preview-segment-details">{details.join(" · ")}</div>
            )}
          </div>
        </div>
      </div>
    );
  }

  return null;
}

function stepsFromDefinition(
  def: WorkoutDefinition | null | undefined,
): WorkoutStep[] {
  if (!def?.steps || !Array.isArray(def.steps)) return [];
  return def.steps as WorkoutStep[];
}

type Props = {
  workoutText: string;
  coachNotes: string;
  trainingTypeOverride: string | null;
  trainingTypes: TrainingType[];
  workoutDefinition?: WorkoutDefinition | null;
  trackLane?: number | null;
  planDateLabel?: string;
};

export function ProgramPreviewCard({
  workoutText,
  coachNotes,
  trainingTypeOverride,
  trainingTypes,
  workoutDefinition,
  trackLane = null,
  planDateLabel,
}: Props) {
  const typeLabel =
    trainingTypes.find((t) => t.name === trainingTypeOverride)?.display_name ??
    "Otomatik";

  const typedText = workoutText.trim();
  const storedSteps = stepsFromDefinition(workoutDefinition);
  const hasStoredWorkout = storedSteps.length > 0;

  if (!typedText && !hasStoredWorkout) {
    if (!coachNotes.trim()) {
      return (
        <div className="preview-card preview-card--rest">
          <span>😴</span> Dinlenme günü
        </div>
      );
    }
    return (
      <div className="preview-card">
        {planDateLabel && <div className="preview-meta">{planDateLabel}</div>}
        <span className="preview-chip">{typeLabel}</span>
        <p className="preview-notes">{coachNotes}</p>
      </div>
    );
  }

  if (typedText) {
    const parsed = parseCoachText(typedText);
    if (!parsed.ok) {
      return (
        <div className="preview-card preview-card--error">{parsed.error}</div>
      );
    }
    if (parsed.isRest) {
      return (
        <div className="preview-card">
          {planDateLabel && <div className="preview-meta">{planDateLabel}</div>}
          <span className="preview-chip">{typeLabel}</span>
          {coachNotes.trim() && <p className="preview-notes">{coachNotes}</p>}
          <div className="preview-card preview-card--rest" style={{ marginTop: 8 }}>
            <span>😴</span> Dinlenme günü
          </div>
        </div>
      );
    }
    const steps = (parsed.workoutDefinition.steps ?? []) as WorkoutStep[];
    return (
      <div className="preview-card">
        {planDateLabel && <div className="preview-meta">{planDateLabel}</div>}
        <div className="preview-chip-row">
          <span className="preview-chip">{typeLabel}</span>
          {trackLane != null && (
            <span className="preview-chip preview-chip--lane">
              Kulvar {trackLane}
            </span>
          )}
        </div>
        {coachNotes.trim() && <p className="preview-notes">{coachNotes}</p>}
        {steps.length > 0 && (
          <div className="preview-structure">
            <div className="preview-structure-label">Antrenman yapısı</div>
            <StepList
              steps={steps}
              referenceLane={trackLane}
              viewLane={trackLane}
            />
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="preview-card">
      {planDateLabel && <div className="preview-meta">{planDateLabel}</div>}
      <div className="preview-chip-row">
        <span className="preview-chip">{typeLabel}</span>
        {trackLane != null && (
          <span className="preview-chip preview-chip--lane">
            Kulvar {trackLane}
          </span>
        )}
      </div>
      {coachNotes.trim() && <p className="preview-notes">{coachNotes}</p>}
      <div className="preview-structure">
        <div className="preview-structure-label">Antrenman yapısı</div>
        <StepList
          steps={storedSteps}
          referenceLane={trackLane}
          viewLane={trackLane}
        />
      </div>
    </div>
  );
}

export function dayHasPreviewContent(day: {
  workout: string;
  coachNotes: string;
  workoutDefinition?: WorkoutDefinition | null;
}): boolean {
  return (
    day.workout.trim().length > 0 ||
    day.coachNotes.trim().length > 0 ||
    stepsFromDefinition(day.workoutDefinition).length > 0
  );
}
