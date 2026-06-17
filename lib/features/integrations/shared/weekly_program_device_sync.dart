import '../../../core/utils/track_lane_calculator.dart';
import '../../events/utils/monthly_program_mapper.dart';
import '../../workout/data/models/workout_model.dart';
import '../../workout/domain/entities/workout_entity.dart';

/// Haftalık/aylık plan satırından cihaz senkronu için tek antrenman.
class WeeklyProgramDeviceSyncItem {
  final String entryId;
  final DateTime scheduledAt;
  final WorkoutDefinitionEntity definition;
  final String title;
  final String? trainingTypeName;
  final int? thresholdOffsetMinSeconds;
  final int? thresholdOffsetMaxSeconds;
  final int? referenceLane;
  final int? viewLane;

  const WeeklyProgramDeviceSyncItem({
    required this.entryId,
    required this.scheduledAt,
    required this.definition,
    required this.title,
    this.trainingTypeName,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
    this.referenceLane,
    this.viewLane,
  });
}

/// Etkinlik saati yokken plan günü sabah 08:00 varsayılan.
const int kDefaultWorkoutScheduleHour = 8;
const int kDefaultWorkoutScheduleMinute = 0;

String weeklyProgramSyncKey(String entryId, {int? viewLane}) {
  if (viewLane != null) return 'monthly:$entryId:L$viewLane';
  return 'monthly:$entryId';
}

int? parseTrackLaneFromRow(Map<String, dynamic> row) {
  final raw = row['track_lane'];
  if (raw is int &&
      raw >= TrackLaneCalculator.minLane &&
      raw <= TrackLaneCalculator.maxLane) {
    return raw;
  }
  if (raw is num) {
    final v = raw.round();
    if (v >= TrackLaneCalculator.minLane && v <= TrackLaneCalculator.maxLane) {
      return v;
    }
  }
  return null;
}

WorkoutDefinitionEntity? prepareWorkoutForTrackView(
  WorkoutDefinitionEntity? definition, {
  required int? referenceLane,
  required int? viewLane,
}) {
  if (definition == null || definition.isEmpty) return definition;
  if (referenceLane == null || viewLane == null) return definition;
  return TrackLaneCalculator.prepareForTrackView(
    definition,
    referenceLane: referenceLane,
    viewLane: viewLane,
  );
}

Map<String, dynamic>? workoutDefinitionJson(WorkoutDefinitionEntity? definition) {
  if (definition == null || definition.isEmpty) return null;
  return WorkoutDefinitionModel.fromEntity(definition).toJson();
}

/// Tek plan satırından kulvar ayarlı cihaz senkronu öğesi.
WeeklyProgramDeviceSyncItem? buildMonthlySyncItem(
  Map<String, dynamic> row, {
  int? viewLane,
}) {
  if (!monthlyRowHasProgramContent(row)) return null;
  if (!monthlyRowHasStructuredWorkout(row)) return null;

  final rawDef = _parseWorkoutDefinition(row['workout_definition']);
  if (rawDef == null || rawDef.isEmpty) return null;

  final referenceLane = parseTrackLaneFromRow(row);
  final effectiveLane = viewLane ?? referenceLane;
  final def = prepareWorkoutForTrackView(
    rawDef,
    referenceLane: referenceLane,
    viewLane: effectiveLane,
  );
  if (def == null || def.isEmpty) return null;

  final planDateStr = row['plan_date'] as String? ?? '';
  final trainingTypeData = row['training_types'] as Map<String, dynamic>?;

  return WeeklyProgramDeviceSyncItem(
    entryId: row['id'] as String,
    scheduledAt: scheduledAtForPlanDate(planDateStr),
    definition: def,
    title: titleForMonthlyRow(row),
    trainingTypeName: trainingTypeData?['display_name'] as String?,
    thresholdOffsetMinSeconds:
        trainingTypeData?['threshold_offset_min_seconds'] as int?,
    thresholdOffsetMaxSeconds:
        trainingTypeData?['threshold_offset_max_seconds'] as int?,
    referenceLane: referenceLane,
    viewLane: effectiveLane,
  );
}

String _turkishShortDayName(DateTime date) {
  const names = ['Pz', 'Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct'];
  return names[date.weekday % 7];
}

WorkoutDefinitionEntity? _parseWorkoutDefinition(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map<String, dynamic>) {
    return WorkoutDefinitionModel.fromJson(raw).toEntity();
  }
  if (raw is Map) {
    return WorkoutDefinitionModel.fromJson(Map<String, dynamic>.from(raw)).toEntity();
  }
  if (raw is List) {
    return WorkoutDefinitionModel.fromJsonList(raw).toEntity();
  }
  return null;
}

bool monthlyRowHasStructuredWorkout(Map<String, dynamic> row) {
  final def = _parseWorkoutDefinition(row['workout_definition']);
  return def != null && !def.isEmpty;
}

DateTime scheduledAtForPlanDate(String planDateStr) {
  final parts = planDateStr.split('-');
  if (parts.length != 3) return DateTime.now();
  final y = int.tryParse(parts[0]) ?? DateTime.now().year;
  final m = int.tryParse(parts[1]) ?? DateTime.now().month;
  final d = int.tryParse(parts[2]) ?? DateTime.now().day;
  return DateTime(y, m, d, kDefaultWorkoutScheduleHour, kDefaultWorkoutScheduleMinute);
}

String titleForMonthlyRow(Map<String, dynamic> row) {
  final planDateStr = row['plan_date'] as String? ?? '';
  final scheduled = scheduledAtForPlanDate(planDateStr);
  final day = _turkishShortDayName(scheduled);
  final trainingType =
      (row['training_types'] as Map<String, dynamic>?)?['display_name'] as String?;
  final groupName =
      (row['training_groups'] as Map<String, dynamic>?)?['name'] as String?;
  final base = (trainingType != null && trainingType.isNotEmpty)
      ? trainingType
      : (groupName ?? 'Antrenman');
  return '$day • $base';
}

List<WeeklyProgramDeviceSyncItem> mapMonthlyRowsToDeviceSyncItems(
  List<Map<String, dynamic>> rows,
) {
  final out = <WeeklyProgramDeviceSyncItem>[];
  for (final row in rows) {
    if (!monthlyRowHasProgramContent(row)) continue;
    if (!monthlyRowHasStructuredWorkout(row)) continue;

    final def = _parseWorkoutDefinition(row['workout_definition']);
    if (def == null || def.isEmpty) continue;

    final planDateStr = row['plan_date'] as String? ?? '';
    final trainingTypeData = row['training_types'] as Map<String, dynamic>?;

    final referenceLane = parseTrackLaneFromRow(row);
    out.add(
      WeeklyProgramDeviceSyncItem(
        entryId: row['id'] as String,
        scheduledAt: scheduledAtForPlanDate(planDateStr),
        definition: def,
        title: titleForMonthlyRow(row),
        trainingTypeName: trainingTypeData?['display_name'] as String?,
        thresholdOffsetMinSeconds:
            trainingTypeData?['threshold_offset_min_seconds'] as int?,
        thresholdOffsetMaxSeconds:
            trainingTypeData?['threshold_offset_max_seconds'] as int?,
        referenceLane: referenceLane,
        viewLane: referenceLane,
      ),
    );
  }
  return out;
}
