import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../events/domain/entities/event_entity.dart' show TrainingTypeEntity;
import '../../../events/presentation/providers/event_provider.dart';
import '../../../workout/domain/entities/workout_entity.dart' show WorkoutDefinitionEntity;
import '../../../workout/data/models/workout_model.dart' show WorkoutDefinitionModel;
import '../../../workout/presentation/widgets/workout_segment_editor.dart';
import '../../data/models/group_model.dart';
import '../../domain/entities/group_entity.dart';
import '../providers/group_provider.dart';

/// Etkinlik için grup programları düzenleyici
class EventGroupProgramItem {
  final String? id;
  final TrainingGroupEntity group;
  String programContent;
  /// Yapılandırılmış antrenman (segment, yineleme). Doluysa export ve detaylı gösterim için kullanılır.
  WorkoutDefinitionEntity? workoutDefinition;
  String? routeId;
  String? routeName;
  String? trainingTypeId;
  String? trainingTypeName;
  String? trainingTypeColor;
  int? thresholdOffsetMinSeconds;
  int? thresholdOffsetMaxSeconds;

  EventGroupProgramItem({
    this.id,
    required this.group,
    this.programContent = '',
    this.workoutDefinition,
    this.routeId,
    this.routeName,
    this.trainingTypeId,
    this.trainingTypeName,
    this.trainingTypeColor,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
  });

  EventGroupProgramModel toModel(String eventId, int orderIndex) {
    return EventGroupProgramModel(
      id: id ?? '',
      eventId: eventId,
      trainingGroupId: group.id,
      programContent: programContent,
      workoutDefinition: workoutDefinition != null
          ? WorkoutDefinitionModel.fromEntity(workoutDefinition!)
          : null,
      routeId: null,
      trainingTypeId: trainingTypeId,
      orderIndex: orderIndex,
      createdAt: DateTime.now(),
    );
  }
}

/// Etkinlik Grup Programları Editörü Widget
class EventGroupProgramsEditor extends ConsumerStatefulWidget {
  final List<EventGroupProgramItem> programs;
  final ValueChanged<List<EventGroupProgramItem>> onChanged;

  const EventGroupProgramsEditor({
    super.key,
    required this.programs,
    required this.onChanged,
  });

  @override
  ConsumerState<EventGroupProgramsEditor> createState() =>
      _EventGroupProgramsEditorState();
}

class _EventGroupProgramsEditorState
    extends ConsumerState<EventGroupProgramsEditor> {
  late List<EventGroupProgramItem> _programs;

  @override
  void initState() {
    super.initState();
    _programs = List.from(widget.programs);
  }

  @override
  void didUpdateWidget(EventGroupProgramsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.programs != widget.programs) {
      _programs = List.from(widget.programs);
    }
  }

  void _addProgram(TrainingGroupEntity group) {
    setState(() {
      _programs.add(EventGroupProgramItem(group: group));
    });
    widget.onChanged(_programs);
  }

  void _removeProgram(int index) {
    setState(() {
      _programs.removeAt(index);
    });
    widget.onChanged(_programs);
  }

  void _updateProgramContent(int index, String content) {
    _programs[index].programContent = content;
    widget.onChanged(_programs);
  }

  void _updateProgramWorkout(int index, WorkoutDefinitionEntity? definition) {
    _programs[index].workoutDefinition = definition;
    widget.onChanged(_programs);
  }

  void _updateProgramTrainingType(
    int index,
    String? typeId,
    String? typeName,
    String? typeColor, {
    int? offsetMin,
    int? offsetMax,
  }) {
    _programs[index].trainingTypeId = typeId;
    _programs[index].trainingTypeName = typeName;
    _programs[index].trainingTypeColor = typeColor;
    _programs[index].thresholdOffsetMinSeconds = offsetMin;
    _programs[index].thresholdOffsetMaxSeconds = offsetMax;
    widget.onChanged(_programs);
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(allGroupsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Grup Programları',
              style: AppTypography.titleMedium,
            ),
            TextButton.icon(
              onPressed: () => _showAddGroupSheet(context, groupsAsync),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Grup Ekle'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Her grup için özel antrenman programı eklemelisiniz. Her grup için antrenman türü seçilmelidir.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.neutral500,
          ),
        ),
        const SizedBox(height: 16),

        // Program listesi
        if (_programs.isEmpty)
          _buildEmptyState()
        else
          ..._programs.asMap().entries.map((entry) {
            final index = entry.key;
            final program = entry.value;
            return _buildProgramCard(index, program);
          }),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.neutral100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.neutral200,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.groups_outlined,
            size: 48,
            color: AppColors.neutral400,
          ),
          const SizedBox(height: 12),
          Text(
            'Henüz grup programı eklenmedi',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.neutral500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Gruplar için özel antrenman programları eklemek için "Grup Ekle" butonuna tıklayın.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.neutral400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProgramCard(int index, EventGroupProgramItem program) {
    final groupColor = _parseColor(program.group.color);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: groupColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: groupColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: groupColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: groupColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getIconData(program.group.icon),
                    color: groupColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        program.group.name,
                        style: AppTypography.titleSmall.copyWith(
                          color: groupColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (program.group.targetDistance != null)
                        Text(
                          'Hedef: ${program.group.targetDistance}',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => _removeProgram(index),
                  color: AppColors.neutral400,
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Antrenman türü seçimi
                _buildTrainingTypeSelector(index, program),
                const SizedBox(height: 12),

                // Segment tabanlı antrenman editörü (FIT/TCX export için)
                WorkoutSegmentEditor(
                  initialDefinition: program.workoutDefinition,
                  trainingTypeName: program.trainingTypeName,
                  thresholdOffsetMinSeconds: program.thresholdOffsetMinSeconds,
                  thresholdOffsetMaxSeconds: program.thresholdOffsetMaxSeconds,
                  onChanged: (def) => _updateProgramWorkout(index, def),
                  onSummaryChanged: (summary) {
                    if (summary.isNotEmpty) _updateProgramContent(index, summary);
                  },
                ),
                const SizedBox(height: 12),

                // Kısa açıklama (özet otomatik dolar veya serbest metin)
                TextFormField(
                  initialValue: program.programContent,
                  decoration: InputDecoration(
                    labelText: 'Kısa açıklama',
                    hintText: 'Özet yukarıdaki adımlardan otomatik gelir veya serbest metin yazın',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  maxLines: 1,
                  onChanged: (value) => _updateProgramContent(index, value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainingTypeSelector(int index, EventGroupProgramItem program) {
    final typesAsync = ref.watch(trainingTypesProvider);
    final typeColor = program.trainingTypeColor != null
        ? _parseColor(program.trainingTypeColor!)
        : AppColors.neutral400;

    return InkWell(
      onTap: () => _showTrainingTypeSelectionSheet(index, typesAsync),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: program.trainingTypeId != null
              ? typeColor.withValues(alpha: 0.08)
              : AppColors.neutral100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: program.trainingTypeId != null
                ? typeColor.withValues(alpha: 0.3)
                : AppColors.neutral200,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.fitness_center,
              size: 20,
              color: program.trainingTypeId != null
                  ? typeColor
                  : AppColors.neutral400,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                program.trainingTypeName ?? 'Antrenman Türü Seç *',
                style: AppTypography.bodyMedium.copyWith(
                  color: program.trainingTypeId != null
                      ? AppColors.neutral700
                      : AppColors.error,
                  fontWeight: program.trainingTypeId == null
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (program.trainingTypeId != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    _updateProgramTrainingType(index, null, null, null),
                color: AppColors.neutral400,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else
              const Icon(
                Icons.chevron_right,
                color: AppColors.neutral400,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  void _showAddGroupSheet(
    BuildContext context,
    AsyncValue<List<TrainingGroupEntity>> groupsAsync,
  ) {
    final addedGroupIds = _programs.map((p) => p.group.id).toSet();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutral300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Grup Seç', style: AppTypography.titleLarge),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: groupsAsync.when(
                  data: (groups) {
                    final availableGroups = groups
                        .where((g) => !addedGroupIds.contains(g.id))
                        .toList();

                    if (availableGroups.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 48,
                              color: AppColors.success,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Tüm gruplar eklendi',
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.neutral500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      itemCount: availableGroups.length,
                      itemBuilder: (context, index) {
                        final group = availableGroups[index];
                        final groupColor = _parseColor(group.color);

                        return ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: groupColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _getIconData(group.icon),
                              color: groupColor,
                            ),
                          ),
                          title: Text(group.name),
                          subtitle: Text(
                            group.targetDistance != null
                                ? 'Hedef: ${group.targetDistance}'
                                : group.description ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: () {
                            Navigator.pop(context);
                            _addProgram(group);
                          },
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (_, __) => const Center(
                    child: Text('Gruplar yüklenemedi'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTrainingTypeSelectionSheet(
    int programIndex,
    AsyncValue<List<TrainingTypeEntity>> typesAsync,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutral300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Antrenman Türü Seç', style: AppTypography.titleLarge),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: typesAsync.when(
                  data: (types) {
                    if (types.isEmpty) {
                      return Center(
                        child: Text(
                          'Antrenman türü bulunamadı',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.neutral500,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      itemCount: types.length,
                      itemBuilder: (context, index) {
                        final type = types[index];
                        final typeColor = _parseColor(type.color);
                        final isSelected =
                            type.id == _programs[programIndex].trainingTypeId;

                        return InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            _updateProgramTrainingType(
                              programIndex,
                              type.id,
                              type.displayName,
                              type.color,
                              offsetMin: type.thresholdOffsetMinSeconds,
                              offsetMax: type.thresholdOffsetMaxSeconds,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? typeColor.withValues(alpha: 0.1)
                                  : null,
                              border: Border(
                                bottom: BorderSide(
                                  color: AppColors.neutral200,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: typeColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.fitness_center,
                                    color: typeColor,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        type.displayName,
                                        style: AppTypography.titleSmall.copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: isSelected ? typeColor : null,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        type.description,
                                        style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.neutral600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: typeColor,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (_, __) => const Center(
                    child: Text('Antrenman türleri yüklenemedi'),
                  ),
                ),
              ),
            ],
          ),
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

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'directions_run':
        return Icons.directions_run;
      case 'directions_walk':
        return Icons.directions_walk;
      case 'accessibility_new':
        return Icons.accessibility_new;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'sports':
        return Icons.sports;
      default:
        return Icons.directions_run;
    }
  }
}
