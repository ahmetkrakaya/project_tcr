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

  const WeeklyProgramDeviceSyncItem({
    required this.entryId,
    required this.scheduledAt,
    required this.definition,
    required this.title,
    this.trainingTypeName,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
  });
}

/// Etkinlik saati yokken plan günü sabah 08:00 varsayılan.
const int kDefaultWorkoutScheduleHour = 8;
const int kDefaultWorkoutScheduleMinute = 0;

String weeklyProgramSyncKey(String entryId) => 'monthly:$entryId';

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
      ),
    );
  }
  return out;
}
