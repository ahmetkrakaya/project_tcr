export const TRACK_LANE_MIN = 1;
export const TRACK_LANE_MAX = 8;
export const DEFAULT_LANE1_KM = 0.4;
const LANE_WIDTH_M = 1.22;

export function lapLengthKm(
  lane: number,
  lane1Km = DEFAULT_LANE1_KM,
): number {
  if (lane <= 1) return lane1Km;
  const extraMetersPerLane = 2 * Math.PI * LANE_WIDTH_M;
  return lane1Km + (lane - 1) * (extraMetersPerLane / 1000);
}

export function laneRatio(
  referenceLane: number,
  viewLane: number,
  lane1Km = DEFAULT_LANE1_KM,
): number {
  const ref = lapLengthKm(referenceLane, lane1Km);
  const view = lapLengthKm(viewLane, lane1Km);
  return view / ref;
}

type SegmentJson = {
  target_type?: string;
  distance_meters?: number;
  duration_seconds?: number;
  duration_seconds_min?: number;
  duration_seconds_max?: number;
  pace_seconds_per_km_min?: number;
  pace_seconds_per_km_max?: number;
};

function shouldAdjustSegment(seg: SegmentJson): boolean {
  if (seg.distance_meters && seg.distance_meters > 0) return true;
  if (
    seg.target_type === "duration" &&
    seg.duration_seconds &&
    seg.duration_seconds < 1200
  ) {
    return true;
  }
  return (
    seg.duration_seconds != null ||
    seg.duration_seconds_min != null ||
    seg.duration_seconds_max != null
  );
}

export function adjustSegmentJsonForLane(
  seg: SegmentJson,
  referenceLane: number,
  viewLane: number,
): SegmentJson {
  if (referenceLane === viewLane || !shouldAdjustSegment(seg)) return seg;
  const ratio = laneRatio(referenceLane, viewLane);
  if (Math.abs(ratio - 1) < 0.0001) return seg;

  const out: SegmentJson = { ...seg };
  const scale = (v?: number) =>
    v != null && v > 0 ? Math.max(1, Math.round(v * ratio)) : undefined;

  out.duration_seconds = scale(seg.duration_seconds);
  out.duration_seconds_min = scale(seg.duration_seconds_min);
  out.duration_seconds_max = scale(seg.duration_seconds_max);

  const hasPace = seg.pace_seconds_per_km_min != null;
  const hasTime =
    seg.duration_seconds != null ||
    seg.duration_seconds_min != null ||
    seg.duration_seconds_max != null;

  if (
    seg.distance_meters &&
    seg.distance_meters > 0 &&
    hasPace &&
    !hasTime &&
    seg.pace_seconds_per_km_min
  ) {
    const lapCount = seg.distance_meters / (lapLengthKm(referenceLane) * 1000);
    const viewKm = lapCount * lapLengthKm(viewLane);
    out.duration_seconds = Math.round(seg.pace_seconds_per_km_min * viewKm);
    if (
      seg.pace_seconds_per_km_max &&
      seg.pace_seconds_per_km_max !== seg.pace_seconds_per_km_min
    ) {
      out.duration_seconds_min = Math.round(
        seg.pace_seconds_per_km_min * viewKm,
      );
      out.duration_seconds_max = Math.round(
        seg.pace_seconds_per_km_max * viewKm,
      );
    }
  }

  return out;
}

export const TRACK_LANE_OPTIONS = Array.from(
  { length: TRACK_LANE_MAX },
  (_, i) => i + 1,
);
