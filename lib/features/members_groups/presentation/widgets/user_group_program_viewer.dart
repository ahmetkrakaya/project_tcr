import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/theme_brightness_holder.dart';
import '../../../../core/utils/vdot_calculator.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../events/domain/entities/event_entity.dart';
import '../../../events/presentation/providers/event_provider.dart';
import '../../../events/presentation/widgets/admin_monthly_program_entry_card.dart';
import '../../../events/utils/monthly_program_mapper.dart';
import '../../../../core/utils/track_lane_calculator.dart';
import '../../../routes/presentation/providers/route_provider.dart';
import '../../data/datasources/group_remote_datasource.dart';
import '../../domain/entities/group_entity.dart';
import '../providers/group_provider.dart';

final _currentUserGroupIdProvider = FutureProvider<String?>((ref) async {
  final ds = GroupRemoteDataSource(Supabase.instance.client);
  return ds.getCurrentUserGroupId();
});

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
    final currentUserGroupIdAsync = ref.watch(_currentUserGroupIdProvider);
    final eventAsync = ref.watch(eventByIdProvider(eventId));
    final userVdot = ref.watch(userVdotProvider);
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
    final allProgramsAsync =
        isAdminOrCoach ? ref.watch(eventGroupProgramsProvider(eventId)) : null;

    return eventAsync.when(
      data: (event) {
        final shouldHidePrograms = event.isPast;
        if (shouldHidePrograms) return const SizedBox.shrink();

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

                final currentGroupId = currentUserGroupIdAsync.valueOrNull;

                // Performans grubu kişisel programı: sadece gerçekten içerik varsa göster.
                // Boş/kısmi kayıtlar (örn. sadece şablon/placeholder) kullanıcıda görünmesin.
                final visibleMemberPrograms = memberPrograms.where((mp) {
                  // Kullanıcı artık o grupta değilse, eski kişisel programı gösterme.
                  if (currentGroupId != null &&
                      currentGroupId.isNotEmpty &&
                      mp.trainingGroupId != currentGroupId) {
                    return false;
                  }
                  final content = (mp.programContent).trim();
                  final hasWorkout = mp.workoutDefinition != null && !mp.workoutDefinition!.isEmpty;
                  final isPlaceholder = content.toLowerCase() == placeholderPersonalProgramContent.toLowerCase();
                  final hasText = content.isNotEmpty && !isPlaceholder;
                  return hasWorkout || hasText;
                }).toList();

                // Kişisel programları EventGroupProgramEntity formatına dönüştür
                final allPrograms = <EventGroupProgramEntity>[
                  ...programs,
                  ...visibleMemberPrograms.map((mp) => EventGroupProgramEntity(
                    id: mp.id,
                    eventId: mp.eventId,
                    trainingGroupId: mp.trainingGroupId,
                    groupName: mp.groupName,
                    groupColor: mp.groupColor,
                    programContent: mp.programContent,
                    coachNotes: mp.coachNotes,
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
                  return _buildProgramsColumn(
                    context,
                    ref,
                    visiblePrograms,
                    userVdot,
                    event,
                    trackLengthKmNoRoute,
                    visibleMemberPrograms.isNotEmpty,
                    allGroupPrograms: allGroupPrograms,
                  );
                }
                final routeAsync = ref.watch(routeByIdProvider(event.routeId!));
                return routeAsync.when(
                  data: (route) {
                    final trackLengthKm = event.laneConfig?.trackLengthKm ?? route.totalDistance;
                    return _buildProgramsColumn(
                      context,
                      ref,
                      visiblePrograms,
                      userVdot,
                      event,
                      trackLengthKm,
                      visibleMemberPrograms.isNotEmpty,
                      allGroupPrograms: allGroupPrograms,
                    );
                  },
                  loading: () => _buildProgramsColumn(
                    context,
                    ref,
                    visiblePrograms,
                    userVdot,
                    event,
                    trackLengthKmNoRoute,
                    visibleMemberPrograms.isNotEmpty,
                    allGroupPrograms: allGroupPrograms,
                  ),
                  error: (_, __) => _buildProgramsColumn(
                    context,
                    ref,
                    visiblePrograms,
                    userVdot,
                    event,
                    trackLengthKmNoRoute,
                    visibleMemberPrograms.isNotEmpty,
                    allGroupPrograms: allGroupPrograms,
                  ),
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
              color: hasPersonalProgram
                  ? _accentColor(light: AppColors.secondary, dark: AppColors.secondaryLight)
                  : ThemeBrightnessHolder.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasPersonalProgram ? 'Kişisel Programın' : 'Senin Programın',
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (allGroupPrograms.isNotEmpty)
              _buildAllProgramsButton(
                context,
                ref,
                allGroupPrograms,
                event,
                trackLengthKm: trackLengthKm,
              ),
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

  Color _accentColor({required Color light, required Color dark}) =>
      ThemeBrightnessHolder.isDark ? dark : light;

  bool _shouldOfferLanePicker(EventEntity event, EventGroupProgramEntity program) {
    final def = program.workoutDefinition;
    if (def == null || def.isEmpty) return false;
    if (event.laneConfig != null) return true;
    return event.eventType == EventType.training;
  }

  int? _referenceTrackLane(
    EventGroupProgramEntity program,
    EventEntity event,
    double? userVdot,
  ) {
    if (!_shouldOfferLanePicker(event, program)) return null;

    final laneConfig = event.laneConfig;
    if (laneConfig != null && userVdot != null && userVdot > 0) {
      final paceRange = VdotCalculator.getPaceRangeFromOffsets(
        userVdot,
        program.thresholdOffsetMinSeconds,
        program.thresholdOffsetMaxSeconds,
      );
      if (paceRange != null) {
        final matched = laneConfig.laneNumberForPace(paceRange.$1);
        if (matched != null) return matched;
      }
      if (laneConfig.lanes.isNotEmpty) {
        return laneConfig.lanes.first.laneNumber;
      }
    }

    return TrackLaneCalculator.minLane;
  }

  double? _lane1Km(EventEntity event, double? trackLengthKm) =>
      event.laneConfig?.trackLengthKm ?? trackLengthKm;

  Widget _buildEntryCard({
    required Map<String, dynamic> row,
    required EventEntity event,
    double? trackLengthKm,
    bool enableLanePicker = false,
  }) {
    return AdminMonthlyProgramEntryCard(
      row: row,
      enableLanePicker: enableLanePicker,
      enableDeviceSync: false,
      showPlanDate: false,
      lane1Km: _lane1Km(event, trackLengthKm),
    );
  }

  Widget _buildProgramCard(
    BuildContext context,
    WidgetRef ref,
    EventGroupProgramEntity program,
    double? userVdot, {
    required EventEntity event,
    double? trackLengthKm,
  }) {
    final offerLanePicker = _shouldOfferLanePicker(event, program);
    final trackLane = offerLanePicker
        ? _referenceTrackLane(program, event, userVdot)
        : null;
    final row = eventGroupProgramToMonthlyRow(
      program,
      trackLane: trackLane,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _buildEntryCard(
        row: row,
        event: event,
        trackLengthKm: trackLengthKm,
        enableLanePicker: offerLanePicker && trackLane != null,
      ),
    );
  }

  // ==================== Admin/Koç: Tüm Grup Programları ====================

  Widget _buildAllProgramsButton(
    BuildContext context,
    WidgetRef ref,
    List<EventGroupProgramEntity> allPrograms,
    EventEntity event, {
    double? trackLengthKm,
  }) {
    return Material(
      color: ThemeBrightnessHolder.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showAllGroupProgramsSheet(
          context,
          ref,
          allPrograms,
          event,
          trackLengthKm: _lane1Km(event, trackLengthKm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups, size: 18, color: ThemeBrightnessHolder.primary),
              const SizedBox(width: 6),
              Text(
                'Tüm Programlar',
                style: AppTypography.labelSmall.copyWith(
                  color: ThemeBrightnessHolder.primary,
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
            Icon(Icons.fitness_center, size: 20, color: ThemeBrightnessHolder.primary),
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
    EventEntity event, {
    double? trackLengthKm,
  }) {
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
          decoration: BoxDecoration(
            color: ThemeBrightnessHolder.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ThemeBrightnessHolder.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.groups, color: ThemeBrightnessHolder.primary, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'Tüm Grup Programları',
                      style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close),
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
                      _buildAdminGroupSection(
                        entry.key,
                        entry.value,
                        event,
                        trackLengthKm: trackLengthKm,
                      ),
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
                                    color: _accentColor(
                                      light: AppColors.secondary,
                                      dark: AppColors.secondaryLight,
                                    ).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    groupName,
                                    style: AppTypography.labelMedium.copyWith(
                                      color: _accentColor(
                                        light: AppColors.secondary,
                                        dark: AppColors.secondaryLight,
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...memberPrograms.map(
                                  (mp) => _buildMemberProgramCardInAllSheet(
                                    mp,
                                    event,
                                    trackLengthKm: trackLengthKm,
                                  ),
                                ),
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

  Widget _buildMemberProgramCardInAllSheet(
    EventMemberProgramEntity mp,
    EventEntity event, {
    double? trackLengthKm,
  }) {
    final groupLabel = mp.groupName?.trim();
    final userLabel = mp.userName ?? 'Üye';
    final displayGroup = groupLabel != null && groupLabel.isNotEmpty
        ? '$userLabel · $groupLabel'
        : userLabel;
    final row = eventMemberProgramToMonthlyRow(
      mp,
      displayGroupName: displayGroup,
    );
    return _buildEntryCard(
      row: row,
      event: event,
      trackLengthKm: trackLengthKm,
    );
  }

  Widget _buildAdminGroupSection(
    String groupName,
    List<EventGroupProgramEntity> programs,
    EventEntity event, {
    double? trackLengthKm,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final program in programs)
          _buildAdminProgramCard(
            program,
            event,
            trackLengthKm: trackLengthKm,
          ),
      ],
    );
  }

  Widget _buildAdminProgramCard(
    EventGroupProgramEntity program,
    EventEntity event, {
    double? trackLengthKm,
  }) {
    final row = eventGroupProgramToMonthlyRow(program);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _buildEntryCard(
        row: row,
        event: event,
        trackLengthKm: trackLengthKm,
      ),
    );
  }

}