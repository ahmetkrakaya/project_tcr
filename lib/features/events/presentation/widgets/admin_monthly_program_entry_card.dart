import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/vdot_calculator.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../workout/data/models/workout_model.dart';
import '../../../workout/domain/entities/workout_entity.dart';

/// Admin — aylık plan satırı: özet + yapılandırılmış antrenman adımları
class AdminMonthlyProgramEntryCard extends StatelessWidget {
  final Map<String, dynamic> row;

  const AdminMonthlyProgramEntryCard({super.key, required this.row});

  static WorkoutDefinitionEntity? _parseWorkout(dynamic raw) {
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

  static String _formatDurationSec(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    if (m <= 0) return '${s}s';
    if (s == 0) return '${m} dk';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static String? _paceLine(WorkoutSegmentEntity s) {
    if (s.useVdotForPace == true) return 'VDOT pace';
    final min = s.paceSecondsPerKmMin;
    final max = s.paceSecondsPerKmMax;
    if (min != null && max != null) {
      return '${VdotCalculator.formatPace(min)} – ${VdotCalculator.formatPace(max)}';
    }
    final e = s.paceSecondsPerKm ?? s.effectivePaceSecondsPerKm;
    if (e != null) return VdotCalculator.formatPace(e);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final planDateStr = row['plan_date'] as String? ?? '';
    DateTime? planDate;
    try {
      planDate = DateTime.tryParse(planDateStr);
    } catch (_) {
      planDate = null;
    }
    final groupName =
        (row['training_groups'] as Map<String, dynamic>?)?['name'] as String? ?? '';
    final trainingTypeName =
        (row['training_types'] as Map<String, dynamic>?)?['display_name'] as String? ?? '';
    final scopeType = (row['scope_type'] as String?) ?? 'group';
    final userMap = row['users'] as Map<String, dynamic>?;
    final userLabel = userMap == null
        ? null
        : '${userMap['first_name'] ?? ''} ${userMap['last_name'] ?? ''}'.trim();
    final programContent = (row['program_content'] as String?) ?? '';
    final def = _parseWorkout(row['workout_definition']);

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (planDate != null)
                Container(
                  width: 52,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${planDate.day}',
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary,
                        ),
                      ),
                      Text(
                        '${planDate.month}.${planDate.year}',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.neutral600,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              if (planDate != null) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (groupName.isNotEmpty)
                      Text(
                        groupName,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _chip(
                          scopeType == 'member' ? 'Performans' : 'Grup',
                          scopeType == 'member'
                              ? AppColors.primary
                              : AppColors.tertiary,
                        ),
                        if (trainingTypeName.isNotEmpty)
                          _chip(trainingTypeName, AppColors.secondary),
                        if (scopeType == 'member' &&
                            userLabel != null &&
                            userLabel.isNotEmpty)
                          _chip(userLabel, AppColors.neutral700),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (programContent.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              programContent,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.neutral800,
                height: 1.35,
              ),
            ),
          ],
          if (def != null && !def.isEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Antrenman yapısı',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.neutral500,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 10),
            ..._buildSteps(def.steps, 0),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }

  List<Widget> _buildSteps(List<WorkoutStepEntity> steps, int depth) {
    final out = <Widget>[];
    for (final step in steps) {
      out.add(_stepTile(step, depth));
    }
    return out;
  }

  Widget _stepTile(WorkoutStepEntity step, int depth) {
    final pad = EdgeInsets.only(left: depth * 12.0, bottom: 12);
    if (step.isSegment && step.segment != null) {
      final s = step.segment!;
      final dur = s.durationSeconds != null ? _formatDurationSec(s.durationSeconds!) : null;
      final pace = _paceLine(s);
      final details = <String>[];
      if (dur != null) details.add(dur);
      if (pace != null) details.add(pace);

      return Padding(
        padding: pad,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.directions_run,
                size: 18,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.segmentType.displayName,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details.join(' · '),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.neutral600,
                        height: 1.35,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (step.isRepeat && step.repeatCount != null && step.steps != null) {
      return Padding(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.repeat, size: 18, color: AppColors.tertiary),
                const SizedBox(width: 6),
                Text(
                  '${step.repeatCount}x tekrar',
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.tertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._buildSteps(step.steps!, depth + 1),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
