import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/track_lane_calculator.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../workout/data/models/workout_model.dart';
import '../../../workout/domain/entities/workout_entity.dart';
import '../../../workout/utils/segment_target_resolver.dart';

/// Aylık plan satırı: özet + yapılandırılmış antrenman adımları.
/// [enableLanePicker] true ise sporcu pist kulvarını değiştirip pace/süre dönüşümü görebilir.
class AdminMonthlyProgramEntryCard extends StatefulWidget {
  final Map<String, dynamic> row;
  final bool enableLanePicker;

  const AdminMonthlyProgramEntryCard({
    super.key,
    required this.row,
    this.enableLanePicker = false,
  });

  @override
  State<AdminMonthlyProgramEntryCard> createState() =>
      _AdminMonthlyProgramEntryCardState();
}

class _AdminMonthlyProgramEntryCardState extends State<AdminMonthlyProgramEntryCard> {
  int? _viewLane;

  @override
  void initState() {
    super.initState();
    _viewLane = _referenceLane;
  }

  @override
  void didUpdateWidget(covariant AdminMonthlyProgramEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row['track_lane'] != widget.row['track_lane']) {
      _viewLane = _referenceLane;
    }
  }

  int? get _referenceLane {
    final raw = widget.row['track_lane'];
    if (raw is int && raw >= TrackLaneCalculator.minLane && raw <= TrackLaneCalculator.maxLane) {
      return raw;
    }
    if (raw is num) {
      final v = raw.round();
      if (v >= TrackLaneCalculator.minLane && v <= TrackLaneCalculator.maxLane) return v;
    }
    return null;
  }

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

  String? _paceLine(WorkoutSegmentEntity s) {
    if (s.useVdotForPace == true) return 'VDOT pace';
    final pace = effectivePaceDisplay(s, isAdminView: true);
    if (pace != null) return 'Tempo $pace';
    return null;
  }

  String? _splitLine(WorkoutSegmentEntity s) {
    if (s.targetType != WorkoutTargetType.distance) return null;
    final split = effectiveSplitDisplay(s);
    if (split != null) return 'Süre $split';
    return null;
  }

  WorkoutDefinitionEntity? _displayDefinition(WorkoutDefinitionEntity? def) {
    if (def == null) return null;
    final ref = _referenceLane;
    final view = _viewLane;
    if (ref == null || view == null || ref == view) return def;
    return TrackLaneCalculator.adjustDefinitionForLane(
      def,
      referenceLane: ref,
      viewLane: view,
    );
  }

  Future<void> _pickLane() async {
    final ref = _referenceLane;
    if (ref == null || !widget.enableLanePicker) return;

    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'Pist kulvarı',
                  style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Koç $ref. kulvar için hazırladı. Farklı kulvarda koşacaksanız seçin; tempo aynı kalır, süreler güncellenir.',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.neutral600),
                ),
              ),
              for (var lane = TrackLaneCalculator.minLane;
                  lane <= TrackLaneCalculator.maxLane;
                  lane++)
                ListTile(
                  leading: Icon(
                    Icons.track_changes,
                    color: lane == _viewLane ? AppColors.tertiary : AppColors.neutral500,
                  ),
                  title: Text('Kulvar $lane'),
                  trailing: lane == ref
                      ? Text(
                          'Koç',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                        )
                      : null,
                  selected: lane == _viewLane,
                  onTap: () => Navigator.pop(ctx, lane),
                ),
            ],
          ),
        );
      },
    );

    if (picked != null && mounted) {
      setState(() => _viewLane = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
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
    final rawDef = _parseWorkout(row['workout_definition']);
    final def = _displayDefinition(rawDef);
    final programContent = (row['program_content'] as String?) ?? '';
    final coachNotes = (row['coach_notes'] as String?)?.trim() ?? '';
    final hasStructuredWorkout = def != null && !def.isEmpty;
    final showProgramContent =
        programContent.isNotEmpty && !hasStructuredWorkout;
    final referenceLane = _referenceLane;
    final showLane = referenceLane != null;

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
                        if (trainingTypeName.isNotEmpty)
                          _chip(trainingTypeName, AppColors.secondary),
                      ],
                    ),
                  ],
                ),
              ),
              if (showLane) ...[
                const SizedBox(width: 8),
                _laneBadge(referenceLane),
              ],
            ],
          ),
          if (coachNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              coachNotes,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.neutral800,
                height: 1.4,
              ),
            ),
          ],
          if (showProgramContent) ...[
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

  Widget _laneBadge(int lane) {
    final interactive = widget.enableLanePicker;
    final changed = _viewLane != null && _viewLane != _referenceLane;

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.tertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: changed
            ? Border.all(color: AppColors.tertiary.withValues(alpha: 0.45))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.track_changes, size: 16, color: AppColors.tertiary),
          const SizedBox(width: 4),
          Text(
            'Kulvar ${_viewLane ?? lane}',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.tertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (interactive) ...[
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 16, color: AppColors.tertiary),
          ],
        ],
      ),
    );

    if (!interactive) return badge;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _pickLane,
        borderRadius: BorderRadius.circular(10),
        child: badge,
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
      final dur = s.targetType == WorkoutTargetType.duration && s.durationSeconds != null
          ? _formatDurationSec(s.durationSeconds!)
          : null;
      final distM = s.distanceMeters;
      final dist = distM != null && distM > 0
          ? (distM >= 1000
              ? '${(distM / 1000).toStringAsFixed(distM % 1000 == 0 ? 0 : 1)} km'
              : '${distM.round()} m')
          : null;
      final split = _splitLine(s);
      final pace = _paceLine(s);
      final details = <String>[];
      if (dur != null) details.add(dur);
      if (dist != null) details.add(dist);
      if (split != null) details.add(split);
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
