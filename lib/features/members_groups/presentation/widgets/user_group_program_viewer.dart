import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/vdot_calculator.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../events/domain/entities/event_entity.dart' show EventEntity;
import '../../../events/presentation/providers/event_provider.dart';
import '../../../routes/presentation/providers/route_provider.dart';
import '../../../workout/domain/entities/workout_entity.dart' show WorkoutDefinitionEntity, WorkoutStepEntity, WorkoutSegmentType, WorkoutTarget;
import '../../domain/entities/group_entity.dart';
import '../providers/group_provider.dart';

/// Kullanıcının grup programlarını gösteren widget
/// Etkinlik detay sayfasında kullanılır
class UserGroupProgramViewer extends ConsumerWidget {
  final String eventId;

  const UserGroupProgramViewer({
    super.key,
    required this.eventId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const placeholderPersonalProgramContent = 'Kişiye özel program';
    final programsAsync = ref.watch(userEventGroupProgramsProvider(eventId));
    final memberProgramsAsync = ref.watch(userEventMemberProgramsProvider(eventId));
    final eventAsync = ref.watch(eventByIdProvider(eventId));
    final userVdot = ref.watch(userVdotProvider);
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
    final allProgramsAsync = isAdminOrCoach
        ? ref.watch(eventGroupProgramsProvider(eventId))
        : null;

    return eventAsync.when(
      data: (event) {
        if (event.isPast) return const SizedBox.shrink();

        return programsAsync.when(
          data: (programs) {
            return memberProgramsAsync.when(
              data: (memberPrograms) {
                if (programs.isEmpty && memberPrograms.isEmpty) {
                  if (isAdminOrCoach && allProgramsAsync != null) {
                    final allPrograms = allProgramsAsync.valueOrNull ?? [];
                    if (allPrograms.isNotEmpty) {
                      return _buildAdminOnlyButton(context, ref, allPrograms, event);
                    }
                  }
                  return const SizedBox.shrink();
                }

                // Kişisel programları EventGroupProgramEntity formatına dönüştür
                final allPrograms = <EventGroupProgramEntity>[
                  ...programs,
                  ...memberPrograms.map((mp) => EventGroupProgramEntity(
                    id: mp.id,
                    eventId: mp.eventId,
                    trainingGroupId: mp.trainingGroupId,
                    groupName: mp.groupName,
                    groupColor: mp.groupColor,
                    programContent: mp.programContent,
                    workoutDefinition: mp.workoutDefinition,
                    routeId: mp.routeId,
                    routeName: mp.routeName,
                    trainingTypeId: mp.trainingTypeId,
                    trainingTypeName: mp.trainingTypeName,
                    trainingTypeDescription: mp.trainingTypeDescription,
                    trainingTypeColor: mp.trainingTypeColor,
                    thresholdOffsetMinSeconds: mp.thresholdOffsetMinSeconds,
                    thresholdOffsetMaxSeconds: mp.thresholdOffsetMaxSeconds,
                    orderIndex: mp.orderIndex,
                    createdAt: mp.createdAt,
                  )),
                ];

                // Backend placeholder kaydını (sadece "kişiye özel program" metni) UI'da göstermeyelim.
                final visiblePrograms = allPrograms.where((p) {
                  final content = (p.programContent).trim();
                  final isPlaceholder = content.toLowerCase() == placeholderPersonalProgramContent.toLowerCase();
                  final hasWorkout = p.workoutDefinition != null && !p.workoutDefinition!.isEmpty;
                  return !(isPlaceholder && !hasWorkout);
                }).toList();

                final allGroupPrograms = isAdminOrCoach
                    ? (allProgramsAsync?.valueOrNull ?? [])
                    : <EventGroupProgramEntity>[];

                final trackLengthKmNoRoute = event.laneConfig?.trackLengthKm;
                if (event.routeId == null) {
                  return _buildProgramsColumn(context, ref, visiblePrograms, userVdot, event, trackLengthKmNoRoute, memberPrograms.isNotEmpty, allGroupPrograms: allGroupPrograms);
                }
                final routeAsync = ref.watch(routeByIdProvider(event.routeId!));
                return routeAsync.when(
                  data: (route) {
                    final trackLengthKm = event.laneConfig?.trackLengthKm ?? route.totalDistance;
                    return _buildProgramsColumn(context, ref, visiblePrograms, userVdot, event, trackLengthKm, memberPrograms.isNotEmpty, allGroupPrograms: allGroupPrograms);
                  },
                  loading: () => _buildProgramsColumn(context, ref, visiblePrograms, userVdot, event, trackLengthKmNoRoute, memberPrograms.isNotEmpty, allGroupPrograms: allGroupPrograms),
                  error: (_, __) => _buildProgramsColumn(context, ref, visiblePrograms, userVdot, event, trackLengthKmNoRoute, memberPrograms.isNotEmpty, allGroupPrograms: allGroupPrograms),
                );
              },
              loading: () => _buildGroupProgramsFallback(context, ref, programs, userVdot, event),
              error: (_, __) => _buildGroupProgramsFallback(context, ref, programs, userVdot, event),
            );
          },
          loading: () => Container(
            padding: const EdgeInsets.all(16),
            child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(16),
        child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildProgramsColumn(
    BuildContext context,
    WidgetRef ref,
    List<EventGroupProgramEntity> programs,
    double? userVdot,
    EventEntity event,
    double? trackLengthKm,
    bool hasPersonalProgram, {
    List<EventGroupProgramEntity> allGroupPrograms = const [],
  }) {
    if (programs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              hasPersonalProgram ? Icons.star : Icons.fitness_center,
              size: 20,
              color: hasPersonalProgram ? AppColors.secondary : AppColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasPersonalProgram ? 'Kişisel Programın' : 'Senin Programın',
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (allGroupPrograms.isNotEmpty)
              _buildAllProgramsButton(context, ref, allGroupPrograms, event),
          ],
        ),
        const SizedBox(height: 12),
        ...programs.map((program) => _buildProgramCard(
              context,
              ref,
              program,
              userVdot,
              event: event,
              trackLengthKm: trackLengthKm,
            )),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildGroupProgramsFallback(
    BuildContext context,
    WidgetRef ref,
    List<EventGroupProgramEntity> programs,
    double? userVdot,
    EventEntity event,
  ) {
    if (programs.isEmpty) return const SizedBox.shrink();
    final trackLengthKm = event.laneConfig?.trackLengthKm;
    return _buildProgramsColumn(context, ref, programs, userVdot, event, trackLengthKm, false);
  }

  Widget _buildProgramCard(
    BuildContext context,
    WidgetRef ref,
    EventGroupProgramEntity program,
    double? userVdot, {
    required EventEntity event,
    double? trackLengthKm,
  }) {
    int? userPaceSecPerKm;
    if (userVdot != null && userVdot > 0) {
      final paceRange = VdotCalculator.getPaceRangeFromOffsets(
        userVdot,
        program.thresholdOffsetMinSeconds,
        program.thresholdOffsetMaxSeconds,
      );
      if (paceRange != null) {
        userPaceSecPerKm = paceRange.$1;
      }
    }
    final userLaneNumber = event.laneConfig != null && userPaceSecPerKm != null
        ? event.laneConfig!.laneNumberForPace(userPaceSecPerKm)
        : null;

    final trainingColor = _parseColor(program.trainingTypeColor ?? '#6366F1');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: trainingColor.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst şerit: grup + (opsiyonel) kulvar
          if ((program.groupName != null && program.groupName!.trim().isNotEmpty) || userLaneNumber != null)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
              decoration: const BoxDecoration(color: AppColors.neutral200),
              child: Row(
                children: [
                  if (program.groupName != null && program.groupName!.trim().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: trainingColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        program.groupName!.trim(),
                        style: AppTypography.labelMedium.copyWith(
                          color: trainingColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (program.groupName != null && program.groupName!.trim().isNotEmpty && userLaneNumber != null)
                    const SizedBox(width: 10),
                  if (userLaneNumber != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.tertiary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.track_changes, size: 18, color: AppColors.tertiary),
                          const SizedBox(width: 6),
                          Text(
                            'Kulvar $userLaneNumber',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.tertiary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // Program segmentleri
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (program.workoutDefinition != null &&
                    !program.workoutDefinition!.isEmpty &&
                    (userVdot == null || userVdot <= 0) &&
                    program.workoutDefinition!.hasVdotPaceSegments) ...[
                  _buildVdotRequiredCard(context),
                ] else if (program.workoutDefinition != null && !program.workoutDefinition!.isEmpty) ...[
                  Text(
                    'Program',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.neutral500,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ..._buildStructuredWorkoutSummary(
                    program.workoutDefinition!,
                    userVdot,
                    offsetMin: program.thresholdOffsetMinSeconds,
                    offsetMax: program.thresholdOffsetMaxSeconds,
                    trackLengthKm: trackLengthKm != null && userLaneNumber != null
                        ? _trackLengthKmForLane(trackLengthKm, userLaneNumber)
                        : trackLengthKm,
                  ),
                ] else
                  Text(
                    program.programContent,
                    style: AppTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),

                // Antrenman türü + açıklama + kişisel pace
                if (program.trainingTypeName != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: trainingColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: trainingColor.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.fitness_center,
                              size: 18,
                              color: trainingColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                program.trainingTypeName!,
                                style: AppTypography.titleSmall.copyWith(
                                  color: trainingColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (program.trainingTypeDescription != null &&
                            program.trainingTypeDescription!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            program.trainingTypeDescription!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.neutral600,
                              height: 1.45,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // Rota (varsa)
                if (program.routeId != null && program.routeName != null) ...[
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () => context.pushNamed(
                      RouteNames.routeDetail,
                      pathParameters: {'routeId': program.routeId!},
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.tertiary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.map_outlined, size: 20, color: AppColors.tertiary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              program.routeName!,
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.tertiary,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.chevron_right, size: 20, color: AppColors.tertiary),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVdotRequiredCard(BuildContext context) {
    return GestureDetector(
      onTap: () => context.pushNamed(RouteNames.paceCalculator),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(Icons.speed, size: 36, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              'Antrenman programını görmek için\nVDOT değerini gir',
              textAlign: TextAlign.center,
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Bu antrenman kişisel pace değerlerine göre hazırlandı. Programı görüntülemek için VDOT hesaplayıcıdan değerini kaydet.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.neutral600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'VDOT Hesapla',
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String colorHex) {
    try {
      final hex = colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  /// Süreyi "5:18" formatında gösterir (dakika:saniye)
  static String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  /// Segment için pace (sn/km) hesapla (VDOT veya manuel)
  int? _segmentPaceSec(
    dynamic s,
    double? userVdot, {
    int? offsetMin,
    int? offsetMax,
  }) {
    int? paceSec = s.customPaceSecondsPerKm ?? s.paceSecondsPerKm ?? s.paceSecondsPerKmMin;
    if (paceSec == null && s.useVdotForPace == true && userVdot != null && userVdot > 0) {
      final paceRange = VdotCalculator.getPaceRangeForSegmentType(
        userVdot,
        s.segmentType.name,
        offsetMin,
        offsetMax,
      );
      if (paceRange != null) {
        paceSec = paceRange.$1; // Hızlı pace (hesaplama için)
      }
    }
    return paceSec;
  }

  /// Kulvar 1 uzunluğundan (km) verilen kulvar numarasının uzunluğunu hesaplar (IAAF: kulvar genişliği 1.22 m)
  static double _trackLengthKmForLane(double lane1TrackKm, int laneNumber) {
    if (laneNumber <= 1) return lane1TrackKm;
    const laneWidthM = 1.22;
    const extraMetersPerLane = 2 * 3.14159265359 * laneWidthM; // ~7.67 m per lane
    return lane1TrackKm + (laneNumber - 1) * (extraMetersPerLane / 1000);
  }

  /// Ana antrenman/toparlanma segmenti için pist tur sayısı ve tur süresi metni (ısınma/soğuma hariç)
  /// Kulvar uzunluğuna göre hem tur sayısı hem tur süresi hesaplanır (her kulvar farklı uzunlukta).
  String? _segmentTurAndLapTime(
    dynamic s,
    double trackLengthKm,
    double? userVdot, {
    int? offsetMin,
    int? offsetMax,
  }) {
    double? segmentMeters;
    if (s.distanceMeters != null) {
      segmentMeters = s.distanceMeters;
    } else if (s.durationSeconds != null) {
      final paceSec = _segmentPaceSec(s, userVdot, offsetMin: offsetMin, offsetMax: offsetMax);
      if (paceSec != null && paceSec > 0) {
        segmentMeters = s.durationSeconds! * (1000.0 / paceSec);
      }
    }
    if (segmentMeters == null || segmentMeters <= 0) return null;
    final trackM = trackLengthKm * 1000;
    final exactLaps = segmentMeters / trackM;
    if (exactLaps <= 0) return null;
    final km = segmentMeters / 1000;
    // Tur sayısını kulvara göre göster: tam sayıysa "4 tur", değilse "3.9 tur" (kulvar değişince sayı değişsin)
    final lapsText = exactLaps == exactLaps.roundToDouble()
        ? '${exactLaps.round()} tur'
        : '${exactLaps.toStringAsFixed(1)} tur';
    final lapParts = <String>['$lapsText (~${km.toStringAsFixed(1)} km)'];
    final paceSec = _segmentPaceSec(s, userVdot, offsetMin: offsetMin, offsetMax: offsetMax);
    if (paceSec != null && paceSec > 0) {
      final lapTimeSec = (trackLengthKm * paceSec).round();
      lapParts.add('tur ~${_formatDuration(lapTimeSec)}');
    }
    return lapParts.join(' · ');
  }

  List<Widget> _buildStructuredWorkoutSummary(
    WorkoutDefinitionEntity def,
    double? userVdot, {
    int? offsetMin,
    int? offsetMax,
    double? trackLengthKm,
    bool isAdminView = false,
  }) {
    // Segmentleri kategorilere ayır: Isınma en üstte, Soğuma en altta
    final warmupSteps = <WorkoutStepEntity>[];
    final middleSteps = <WorkoutStepEntity>[];
    final cooldownSteps = <WorkoutStepEntity>[];
    
    for (final step in def.steps) {
      if (step.isSegment && step.segment != null) {
        if (step.segment!.segmentType == WorkoutSegmentType.warmup) {
          warmupSteps.add(step);
        } else if (step.segment!.segmentType == WorkoutSegmentType.cooldown) {
          cooldownSteps.add(step);
        } else {
          middleSteps.add(step);
        }
      } else {
        // Yineleme blokları ortada
        middleSteps.add(step);
      }
    }
    
    // Sıralı liste: Isınma -> Ortadaki -> Soğuma
    final sortedSteps = <WorkoutStepEntity>[
      ...warmupSteps,
      ...middleSteps,
      ...cooldownSteps,
    ];
    
    final widgets = <Widget>[];
    for (final step in sortedSteps) {
      if (step.isSegment && step.segment != null) {
        final s = step.segment!;
        final dur = s.durationSeconds != null ? _formatDuration(s.durationSeconds!) : null;
        final dist = s.distanceMeters != null ? '${(s.distanceMeters! / 1000).toStringAsFixed(1)} km' : null;
        final pace = _segmentPaceDisplay(s, userVdot, offsetMin: offsetMin, offsetMax: offsetMax, isAdminView: isAdminView);

        final parts = <String>[s.segmentType.displayName];
        if (dur != null) parts.add(dur);
        if (dist != null) parts.add(dist);
        if (pace != null) parts.add('$pace pace');
        // Pist kulvarda tur/mesafe ve tur süresi: sadece ana antrenman ve toparlanma (ısınma/soğuma hariç)
        if (trackLengthKm != null && trackLengthKm > 0 &&
            s.segmentType != WorkoutSegmentType.warmup &&
            s.segmentType != WorkoutSegmentType.cooldown) {
          final turLap = _segmentTurAndLapTime(
            s,
            trackLengthKm,
            userVdot,
            offsetMin: offsetMin,
            offsetMax: offsetMax,
          );
          if (turLap != null && turLap.isNotEmpty) parts.add(turLap);
        }
        final segmentIconData = _getSegmentIconAndColor(s.segmentType);
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: segmentIconData.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(segmentIconData.icon, size: 18, color: segmentIconData.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.segmentType.displayName,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.neutral900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatSegmentDetails(parts, s.segmentType.displayName),
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
          ),
        );
      } else if (step.isRepeat && step.repeatCount != null && step.steps != null && step.steps!.isNotEmpty) {
        // Tekrar bloğu: başlık + her segment (Ana Antrenman, Toparlanma) ayrı satırda, pace ile
        final innerSegmentRows = <Widget>[];
        for (final e in step.steps!) {
          if (e.isSegment && e.segment != null) {
            final seg = e.segment!;
            final dur = seg.durationSeconds != null ? _formatDuration(seg.durationSeconds!) : null;
            final paceStr = _segmentPaceDisplay(seg, userVdot, offsetMin: offsetMin, offsetMax: offsetMax, isAdminView: isAdminView);
            final parts = <String>[];
            if (dur != null) parts.add(dur);
            if (paceStr != null) parts.add('$paceStr pace');
            if (trackLengthKm != null && trackLengthKm > 0 &&
                seg.segmentType != WorkoutSegmentType.warmup &&
                seg.segmentType != WorkoutSegmentType.cooldown) {
              final turLap = _segmentTurAndLapTime(seg, trackLengthKm, userVdot, offsetMin: offsetMin, offsetMax: offsetMax);
              if (turLap != null && turLap.isNotEmpty) parts.add(turLap);
            }
            final detailLine = parts.join(' · ');
            final innerSegmentIconData = _getSegmentIconAndColor(seg.segmentType);
            innerSegmentRows.add(
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(innerSegmentIconData.icon, size: 16, color: innerSegmentIconData.color),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            seg.segmentType.displayName,
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.neutral900,
                            ),
                          ),
                          if (detailLine.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              detailLine,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.neutral600,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${step.repeatCount}×',
                    style: AppTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tekrar',
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.neutral900,
                        ),
                      ),
                      ...innerSegmentRows,
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return widgets;
  }

  /// Bir segment için gösterilecek pace metni (VDOT veya manuel). Isınma/tekrar içi aynı mantık.
  /// [isAdminView] true ise VDOT bazlı pace yerine "VDOT Pace Değeri" metni döner.
  String? _segmentPaceDisplay(
    dynamic s,
    double? userVdot, {
    int? offsetMin,
    int? offsetMax,
    bool isAdminView = false,
  }) {
    if (s.target == WorkoutTarget.pace) {
      if (s.useVdotForPace == true) {
        if (isAdminView) return 'VDOT Pace Değeri';
        if (userVdot != null && userVdot > 0) {
          final paceStr = VdotCalculator.getPaceForSegmentType(
            userVdot,
            s.segmentType.name,
            offsetMin,
            offsetMax,
          );
          if (paceStr != null) return paceStr;
        }
      } else {
        final paceMin = s.customPaceSecondsPerKm ?? s.paceSecondsPerKmMin ?? s.paceSecondsPerKm;
        final paceMax = s.paceSecondsPerKmMax;
        if (paceMin != null) {
          if (paceMax != null && paceMax != paceMin) {
            return '${VdotCalculator.formatPace(paceMin)} / ${VdotCalculator.formatPace(paceMax)}';
          }
          return VdotCalculator.formatPace(paceMin);
        }
      }
    }
    if (isAdminView && (offsetMin != null || offsetMax != null)) {
      return 'VDOT Pace Değeri';
    }
    if (userVdot != null && userVdot > 0 && (offsetMin != null || offsetMax != null)) {
      final paceStr = VdotCalculator.getPaceForSegmentType(
        userVdot,
        s.segmentType.name,
        offsetMin,
        offsetMax,
      );
      if (paceStr != null) return paceStr;
    }
    return null;
  }

  /// Segment başlığını çıkarıp sadece detayları döndürür (süre, pace, tur vb.)
  String _formatSegmentDetails(List<String> parts, String segmentName) {
    if (parts.length <= 1) return parts.join(' · ');
    final rest = parts.skip(1).toList();
    return rest.join(' · ');
  }

  /// Segment türüne göre uygun ikon ve renk döndürür
  ({IconData icon, Color color}) _getSegmentIconAndColor(WorkoutSegmentType segmentType) {
    switch (segmentType) {
      case WorkoutSegmentType.warmup:
        return (icon: Icons.local_fire_department, color: AppColors.error);
      case WorkoutSegmentType.cooldown:
        return (icon: Icons.ac_unit, color: AppColors.primary);
      case WorkoutSegmentType.recovery:
        return (icon: Icons.favorite, color: AppColors.success);
      case WorkoutSegmentType.main:
        return (icon: Icons.directions_run, color: AppColors.primary);
    }
  }

  // ==================== Admin/Koç: Tüm Grup Programları ====================

  Widget _buildAllProgramsButton(
    BuildContext context,
    WidgetRef ref,
    List<EventGroupProgramEntity> allPrograms,
    EventEntity event,
  ) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showAllGroupProgramsSheet(context, ref, allPrograms, event),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'Tüm Programlar',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminOnlyButton(
    BuildContext context,
    WidgetRef ref,
    List<EventGroupProgramEntity> allPrograms,
    EventEntity event,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.fitness_center, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Antrenman Programları',
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            _buildAllProgramsButton(context, ref, allPrograms, event),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _showAllGroupProgramsSheet(
    BuildContext context,
    WidgetRef ref,
    List<EventGroupProgramEntity> allPrograms,
    EventEntity event,
  ) {
    const placeholderPersonalProgramContent = 'Kişiye özel program';
    final normalPrograms = allPrograms.where((p) {
      final content = (p.programContent).trim();
      final isPlaceholder = content.toLowerCase() == placeholderPersonalProgramContent.toLowerCase();
      return !isPlaceholder;
    }).toList();

    final grouped = <String, List<EventGroupProgramEntity>>{};
    for (final p in normalPrograms) {
      final key = p.groupName ?? 'Grup';
      grouped.putIfAbsent(key, () => []).add(p);
    }

    final performanceGroupIds = allPrograms
        .where((p) {
          final content = (p.programContent).trim();
          final isPlaceholder = content.toLowerCase() == placeholderPersonalProgramContent.toLowerCase();
          return isPlaceholder;
        })
        .map((p) => p.trainingGroupId)
        .toSet()
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutral300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.groups, color: AppColors.primary, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'Tüm Grup Programları',
                      style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    for (final entry in grouped.entries) ...[
                      _buildAdminGroupSection(entry.key, entry.value, event),
                      const SizedBox(height: 20),
                    ],
                    if (performanceGroupIds.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Kişiye Özel Programlar',
                        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ...performanceGroupIds.map((groupId) {
                        final async = ref.watch(eventMemberProgramsProvider((eventId: event.id, groupId: groupId)));
                        return async.when(
                          data: (memberPrograms) {
                            if (memberPrograms.isEmpty) return const SizedBox.shrink();
                            final groupName = memberPrograms.first.groupName ?? 'Performans';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    groupName,
                                    style: AppTypography.labelMedium.copyWith(
                                      color: AppColors.secondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...memberPrograms.map((mp) => _buildMemberProgramCardInAllSheet(mp, event)).toList(),
                                const SizedBox(height: 20),
                              ],
                            );
                          },
                          loading: () => Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            alignment: Alignment.centerLeft,
                            child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                          error: (_, __) => const SizedBox.shrink(),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberProgramCardInAllSheet(EventMemberProgramEntity mp, EventEntity event) {
    final trainingColor = _parseColor(mp.trainingTypeColor ?? '#6366F1');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  (mp.userName ?? '').isNotEmpty ? (mp.userName!)[0].toUpperCase() : '?',
                  style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mp.userName ?? 'Üye',
                  style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (mp.workoutDefinition != null && !mp.workoutDefinition!.isEmpty) ...[
            Text(
              'Program',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.neutral500,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            ..._buildStructuredWorkoutSummary(
              mp.workoutDefinition!,
              null,
              offsetMin: mp.thresholdOffsetMinSeconds,
              offsetMax: mp.thresholdOffsetMaxSeconds,
              isAdminView: true,
              trackLengthKm: event.laneConfig?.trackLengthKm,
            ),
          ] else
            Text(
              mp.programContent,
              style: AppTypography.bodyMedium.copyWith(height: 1.35),
            ),
          if (mp.trainingTypeName != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: trainingColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: trainingColor.withValues(alpha: 0.2)),
              ),
              child: Text(
                mp.trainingTypeName!,
                style: AppTypography.labelMedium.copyWith(
                  color: trainingColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdminGroupSection(
    String groupName,
    List<EventGroupProgramEntity> programs,
    EventEntity event,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final program in programs)
          _buildAdminProgramCard(program, event),
      ],
    );
  }

  Widget _buildAdminProgramCard(EventGroupProgramEntity program, EventEntity event) {
    final trainingColor = _parseColor(program.trainingTypeColor ?? '#6366F1');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: trainingColor.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Admin görünümünde de grup adı kart üstünde görünsün.
          if (program.groupName != null && program.groupName!.trim().isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: const BoxDecoration(color: AppColors.neutral200),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: trainingColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      program.groupName!.trim(),
                      style: AppTypography.labelMedium.copyWith(
                        color: trainingColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (program.workoutDefinition != null && !program.workoutDefinition!.isEmpty) ...[
                  Text(
                    'Program',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.neutral500,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ..._buildStructuredWorkoutSummary(
                    program.workoutDefinition!,
                    null,
                    offsetMin: program.thresholdOffsetMinSeconds,
                    offsetMax: program.thresholdOffsetMaxSeconds,
                    isAdminView: true,
                  ),
                ] else
                  Text(
                    program.programContent,
                    style: AppTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                if (program.trainingTypeName != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: trainingColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: trainingColor.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.fitness_center, size: 18, color: trainingColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                program.trainingTypeName!,
                                style: AppTypography.titleSmall.copyWith(
                                  color: trainingColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (program.trainingTypeDescription != null &&
                            program.trainingTypeDescription!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            program.trainingTypeDescription!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.neutral600,
                              height: 1.45,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
