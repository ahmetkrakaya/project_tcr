import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/vdot_calculator.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../domain/entities/workout_entity.dart';

/// Tek bir segment veya repeat adımını düzenlemek için kullanılan state (UI için)
class WorkoutStepEditState {
  final String stepType; // 'segment' | 'repeat'
  WorkoutSegmentEntity? segment;
  int repeatCount;
  List<WorkoutStepEditState>? repeatSteps;
  bool isExpanded; // Segment açık mı kapalı mı (UI state)

  WorkoutStepEditState({
    required this.stepType,
    this.segment,
    this.repeatCount = 2,
    this.repeatSteps,
    this.isExpanded = false, // Varsayılan olarak kapalı
  });

  WorkoutStepEntity toEntity() {
    if (stepType == 'repeat') {
      return WorkoutStepEntity(
        type: 'repeat',
        repeatCount: repeatCount,
        steps: repeatSteps?.map((s) => s.toEntity()).toList(),
      );
    }
    return WorkoutStepEntity(
      type: 'segment',
      segment: segment ?? WorkoutSegmentEntity(
        segmentType: WorkoutSegmentType.warmup,
        targetType: WorkoutTargetType.duration,
        target: WorkoutTarget.pace,
        durationSeconds: 300,
        useVdotForPace: null,
      ),
    );
  }

  static WorkoutStepEditState fromEntity(WorkoutStepEntity e) {
    if (e.isRepeat) {
      return WorkoutStepEditState(
        stepType: 'repeat',
        repeatCount: e.repeatCount ?? 2,
        repeatSteps: e.steps?.map((s) => WorkoutStepEditState.fromEntity(s)).toList(),
      );
    }
    return WorkoutStepEditState(
      stepType: 'segment',
      segment: e.segment,
    );
  }
}

/// Segment tabanlı antrenman editörü
class WorkoutSegmentEditor extends ConsumerStatefulWidget {
  final WorkoutDefinitionEntity? initialDefinition;
  final String? trainingTypeName;
  final int? thresholdOffsetMinSeconds;
  final int? thresholdOffsetMaxSeconds;
  final ValueChanged<WorkoutDefinitionEntity?> onChanged;
  final ValueChanged<String>? onSummaryChanged;

  const WorkoutSegmentEditor({
    super.key,
    this.initialDefinition,
    this.trainingTypeName,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
    required this.onChanged,
    this.onSummaryChanged,
  });

  @override
  ConsumerState<WorkoutSegmentEditor> createState() => _WorkoutSegmentEditorState();
}

class _WorkoutSegmentEditorState extends ConsumerState<WorkoutSegmentEditor> {
  late List<WorkoutStepEditState> _steps;

  @override
  void initState() {
    super.initState();
    _steps = widget.initialDefinition != null && widget.initialDefinition!.steps.isNotEmpty
        ? widget.initialDefinition!.steps.map((e) => WorkoutStepEditState.fromEntity(e)).toList()
        : [];
  }

  @override
  void didUpdateWidget(WorkoutSegmentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDefinition != widget.initialDefinition && _steps.isEmpty) {
      _steps = widget.initialDefinition != null && widget.initialDefinition!.steps.isNotEmpty
          ? widget.initialDefinition!.steps.map((e) => WorkoutStepEditState.fromEntity(e)).toList()
          : [];
    }
  }

  void _emit() {
    if (_steps.isEmpty) {
      widget.onChanged(null);
      widget.onSummaryChanged?.call('');
      return;
    }
    final def = WorkoutDefinitionEntity(
      steps: _steps.map((s) => s.toEntity()).toList(),
    );
    widget.onChanged(def);
    widget.onSummaryChanged?.call(_buildSummary(def));
  }

  String _buildSummary(WorkoutDefinitionEntity def) {
    final parts = <String>[];
    for (final step in def.steps) {
      if (step.isSegment && step.segment != null) {
        final s = step.segment!;
        final dur = s.durationSeconds != null ? _StepRowState._formatDurationShort(s.durationSeconds!) : null;
        final dist = s.distanceMeters != null ? '${(s.distanceMeters! / 1000).toStringAsFixed(1)}km' : null;
        final pace = s.effectivePaceSecondsPerKm != null
            ? VdotCalculator.formatPace(s.effectivePaceSecondsPerKm!)
            : null;
        parts.add('${s.segmentType.displayName}${dur != null ? " $dur" : ""}${dist != null ? " $dist" : ""}${pace != null ? " $pace pace" : ""}');
      } else if (step.isRepeat && step.repeatCount != null && step.steps != null) {
        final inner = step.steps!.map((e) {
          if (e.isSegment && e.segment != null) {
            final s = e.segment!;
            final d = s.durationSeconds != null ? _StepRowState._formatDurationShort(s.durationSeconds!) : '';
            return '${s.segmentType.displayName} $d';
          }
          return '';
        }).where((e) => e.isNotEmpty).join(' + ');
        parts.add('${step.repeatCount}x ($inner)');
      }
    }
    return parts.join(' · ');
  }

  /// Tüm step'lerde (Tekrar içleri dahil) ısınma ve soğuma sayısı
  (int warmupCount, int cooldownCount) _countWarmupAndCooldown() {
    int warmup = 0, cooldown = 0;
    void countSteps(List<WorkoutStepEditState> steps) {
      for (final s in steps) {
        if (s.stepType == 'segment' && s.segment != null) {
          if (s.segment!.segmentType == WorkoutSegmentType.warmup) warmup++;
          if (s.segment!.segmentType == WorkoutSegmentType.cooldown) cooldown++;
        }
        if (s.stepType == 'repeat' && s.repeatSteps != null) {
          countSteps(s.repeatSteps!);
        }
      }
    }
    countSteps(_steps);
    return (warmup, cooldown);
  }

  void _addSegment() {
    final (warmupCount, _) = _countWarmupAndCooldown();
    setState(() {
      _steps.add(WorkoutStepEditState(
        stepType: 'segment',
        segment: WorkoutSegmentEntity(
          segmentType: warmupCount == 0 ? WorkoutSegmentType.warmup : WorkoutSegmentType.main,
          targetType: WorkoutTargetType.duration,
          target: WorkoutTarget.pace,
          durationSeconds: 300,
          useVdotForPace: null,
        ),
        isExpanded: true, // Yeni eklenen segment açık olarak gelsin
      ));
    });
    _emit();
  }

  Future<void> _addRepeat() async {
    // Mevcut segmentleri al (Tekrar blokları, ısınma ve soğuma hariç)
    final availableSegments = _steps
        .where((s) => s.stepType == 'segment' && 
            s.segment != null &&
            s.segment!.segmentType != WorkoutSegmentType.warmup &&
            s.segment!.segmentType != WorkoutSegmentType.cooldown)
        .toList();
    
    if (availableSegments.isEmpty) {
      // Segment yoksa uyarı göster
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Önce en az bir segment eklemelisiniz')),
        );
      }
      return;
    }
    
    // Popup'ta segment seçimi yap
    final selectedSegments = await _showSegmentSelectionDialog(availableSegments);
    if (selectedSegments == null || selectedSegments.isEmpty) {
      return; // Kullanıcı iptal etti veya hiçbir şey seçmedi
    }
    
    setState(() {
      // Seçilen segmentlerin kopyalarını oluştur (Tekrar içine eklenecek)
      final repeatSteps = selectedSegments.map((s) {
        if (s.stepType == 'segment' && s.segment != null) {
          return WorkoutStepEditState(
            stepType: 'segment',
            segment: s.segment,
          );
        }
        return s;
      }).toList();
      
      // Tekrar bloğunu ekle
      _steps.add(WorkoutStepEditState(
        stepType: 'repeat',
        repeatCount: 2,
        repeatSteps: repeatSteps,
      ));
      
      // Seçilen segmentleri orijinal listeden sil (geriye doğru sil ki index'ler bozulmasın)
      final indicesToRemove = <int>[];
      for (var i = _steps.length - 2; i >= 0; i--) {
        final step = _steps[i];
        if (step.stepType == 'segment' && step.segment != null) {
          // Seçilen segmentlerden biri mi?
          final isSelected = selectedSegments.any((selected) =>
              selected.stepType == 'segment' &&
              selected.segment != null &&
              selected.segment!.segmentType == step.segment!.segmentType &&
              selected.segment!.durationSeconds == step.segment!.durationSeconds &&
              selected.segment!.distanceMeters == step.segment!.distanceMeters &&
              selected.segment!.paceSecondsPerKmMin == step.segment!.paceSecondsPerKmMin &&
              selected.segment!.paceSecondsPerKmMax == step.segment!.paceSecondsPerKmMax);
          
          if (isSelected) {
            indicesToRemove.add(i);
          }
        }
      }
      
      // İndeksleri sil
      for (final index in indicesToRemove) {
        _steps.removeAt(index);
      }
    });
    _emit();
  }

  Future<List<WorkoutStepEditState>?> _showSegmentSelectionDialog(
    List<WorkoutStepEditState> availableSegments, {
    List<WorkoutStepEditState>? initiallySelected,
  }) async {
    // Başlangıçta seçili olan segmentleri işaretle
    final initialSelectedIndices = <int>{};
    if (initiallySelected != null) {
      for (final selected in initiallySelected) {
        final index = availableSegments.indexWhere(
          (s) => s.segment?.segmentType == selected.segment?.segmentType &&
              s.segment?.durationSeconds == selected.segment?.durationSeconds &&
              s.segment?.distanceMeters == selected.segment?.distanceMeters,
        );
        if (index != -1) {
          initialSelectedIndices.add(index);
        }
      }
    }
    
    return showModalBottomSheet<List<WorkoutStepEditState>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        // StatefulBuilder içinde state olarak tut
        final selectedIndices = <int>{...initialSelectedIndices};
        
        return StatefulBuilder(
          builder: (context, setState) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Tekrar için Segment Seç',
                          style: AppTypography.titleMedium,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context, null),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Segment listesi
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: availableSegments.length,
                      itemBuilder: (context, index) {
                        final segment = availableSegments[index].segment!;
                        final isSelected = selectedIndices.contains(index);
                        
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                selectedIndices.add(index);
                              } else {
                                selectedIndices.remove(index);
                              }
                            });
                          },
                          title: Row(
                            children: [
                              Icon(
                                _segmentIcon(segment.segmentType),
                                size: 20,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  segment.segmentType.displayName,
                                  style: AppTypography.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            _StepRowState._buildSegmentSummary(segment),
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.neutral600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  // Butonlar
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: const Text('İptal'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedIndices.isEmpty
                                ? null
                                : () {
                                    final selected = selectedIndices
                                        .map((i) => availableSegments[i])
                                        .toList();
                                    Navigator.pop(context, selected);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Tamam'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _segmentIcon(WorkoutSegmentType t) {
    switch (t) {
      case WorkoutSegmentType.warmup:
        return Icons.whatshot;
      case WorkoutSegmentType.main:
        return Icons.directions_run;
      case WorkoutSegmentType.recovery:
        return Icons.favorite_border;
      case WorkoutSegmentType.cooldown:
        return Icons.ac_unit;
    }
  }

  void _removeStep(int index) {
    setState(() {
      _steps.removeAt(index);
    });
    _emit();
  }

  void _updateStep(int index, WorkoutStepEditState step) {
    setState(() {
      _steps[index] = step;
    });
    _emit();
  }

  /// Segmentleri sıralı şekilde render et: Isınma en üstte, Soğuma en altta
  List<Widget> _buildSortedSteps() {
    // Tekrar içinde geçen segmentlerin _steps'teki indekslerini topla (dışarıda gösterilmesin)
    final indicesOnlyInRepeats = <int>{};
    for (var i = 0; i < _steps.length; i++) {
      final step = _steps[i];
      if (step.stepType == 'repeat' && step.repeatSteps != null) {
        for (final repeatStep in step.repeatSteps!) {
          final idx = _steps.indexOf(repeatStep);
          if (idx >= 0) indicesOnlyInRepeats.add(idx);
        }
      }
    }
    
    // Segmentleri kategorilere ayır (Tekrar içindekiler hariç)
    final warmupSteps = <WorkoutStepEditState>[];
    final middleSteps = <WorkoutStepEditState>[];
    final cooldownSteps = <WorkoutStepEditState>[];
    
    for (var i = 0; i < _steps.length; i++) {
      // Tekrar içinde olan segmentleri ana listede gösterme
      if (indicesOnlyInRepeats.contains(i)) continue;
      
      final step = _steps[i];
      if (step.stepType == 'segment' && step.segment != null) {
        if (step.segment!.segmentType == WorkoutSegmentType.warmup) {
          warmupSteps.add(step);
        } else if (step.segment!.segmentType == WorkoutSegmentType.cooldown) {
          cooldownSteps.add(step);
        } else {
          middleSteps.add(step);
        }
      } else {
        // Tekrar blokları ortada
        middleSteps.add(step);
      }
    }
    
    // Sıralı liste oluştur: Isınma -> Ortadaki (Ana, Toparlanma, Tekrar) -> Soğuma
    final sortedSteps = <WorkoutStepEditState>[
      ...warmupSteps,
      ...middleSteps,
      ...cooldownSteps,
    ];
    
    final (warmupCount, cooldownCount) = _countWarmupAndCooldown();
    // Widget listesi oluştur
    return sortedSteps.asMap().entries.map((entry) {
      final originalIndex = _steps.indexOf(entry.value);
      final step = entry.value;
      // Step içeriğine göre unique key oluştur
      final stepKey = step.stepType == 'segment' && step.segment != null
          ? 'step_${originalIndex}_${step.segment!.segmentType.name}_${step.segment!.customPaceSecondsPerKm}_${step.segment!.paceSecondsPerKmMin}_${step.segment!.paceSecondsPerKmMax}'
          : 'step_${originalIndex}_${step.stepType}';
      return _StepRow(
        key: ValueKey(stepKey),
        index: originalIndex,
        step: step,
        trainingTypeName: widget.trainingTypeName,
        thresholdOffsetMinSeconds: widget.thresholdOffsetMinSeconds,
        thresholdOffsetMaxSeconds: widget.thresholdOffsetMaxSeconds,
        onChanged: (s) => _updateStep(originalIndex, s),
        onRemove: () => _removeStep(originalIndex),
        allSteps: _steps,
        onEditRepeatSegments: (selectedSegments) {
          setState(() {
            // Önceki seçili segmentleri al
            final previousSelected = step.repeatSteps ?? [];
            
            // Yeni seçilen segmentlerin kopyalarını oluştur
            final repeatSteps = selectedSegments.map((s) {
              if (s.stepType == 'segment' && s.segment != null) {
                return WorkoutStepEditState(
                  stepType: 'segment',
                  segment: s.segment,
                );
              }
              return s;
            }).toList();
            
            // Tekrar bloğunu güncelle
            _steps[originalIndex] = WorkoutStepEditState(
              stepType: 'repeat',
              repeatCount: step.repeatCount,
              repeatSteps: repeatSteps,
            );
            
            // Önceki seçili segmentleri geri ekle (eğer yeni seçimde yoksa)
            for (final prevSelected in previousSelected) {
              if (prevSelected.stepType == 'segment' && prevSelected.segment != null) {
                // Yeni seçimde bu segment var mı?
                final isInNewSelection = selectedSegments.any((newSelected) =>
                    newSelected.stepType == 'segment' &&
                    newSelected.segment != null &&
                    newSelected.segment!.segmentType == prevSelected.segment!.segmentType &&
                    newSelected.segment!.durationSeconds == prevSelected.segment!.durationSeconds &&
                    newSelected.segment!.distanceMeters == prevSelected.segment!.distanceMeters &&
                    newSelected.segment!.paceSecondsPerKmMin == prevSelected.segment!.paceSecondsPerKmMin &&
                    newSelected.segment!.paceSecondsPerKmMax == prevSelected.segment!.paceSecondsPerKmMax);
                
                // Yeni seçimde yoksa ve orijinal listede de yoksa geri ekle
                if (!isInNewSelection) {
                  final existsInList = _steps.any((existingStep) =>
                      existingStep.stepType == 'segment' &&
                      existingStep.segment != null &&
                      existingStep.segment!.segmentType == prevSelected.segment!.segmentType &&
                      existingStep.segment!.durationSeconds == prevSelected.segment!.durationSeconds &&
                      existingStep.segment!.distanceMeters == prevSelected.segment!.distanceMeters &&
                      existingStep.segment!.paceSecondsPerKmMin == prevSelected.segment!.paceSecondsPerKmMin &&
                      existingStep.segment!.paceSecondsPerKmMax == prevSelected.segment!.paceSecondsPerKmMax);
                  
                  if (!existsInList) {
                    // Segmenti geri ekle (Tekrar bloğundan önce)
                    _steps.insert(originalIndex, WorkoutStepEditState(
                      stepType: 'segment',
                      segment: prevSelected.segment,
                    ));
                  }
                }
              }
            }
            
            // Yeni seçilen segmentleri listeden sil (eğer önceki seçimde yoksa)
            final indicesToRemove = <int>[];
            for (var i = _steps.length - 1; i >= 0; i--) {
              // Tekrar bloğunun kendisini atla
              if (i == originalIndex) continue;
              
              final existingStep = _steps[i];
              if (existingStep.stepType == 'segment' && existingStep.segment != null) {
                // Önceki seçimde bu segment var mıydı?
                final wasInPreviousSelection = previousSelected.any((prevSelected) =>
                    prevSelected.stepType == 'segment' &&
                    prevSelected.segment != null &&
                    prevSelected.segment!.segmentType == existingStep.segment!.segmentType &&
                    prevSelected.segment!.durationSeconds == existingStep.segment!.durationSeconds &&
                    prevSelected.segment!.distanceMeters == existingStep.segment!.distanceMeters &&
                    prevSelected.segment!.paceSecondsPerKmMin == existingStep.segment!.paceSecondsPerKmMin &&
                    prevSelected.segment!.paceSecondsPerKmMax == existingStep.segment!.paceSecondsPerKmMax);
                
                // Yeni seçimde bu segment var mı?
                final isInNewSelection = selectedSegments.any((newSelected) =>
                    newSelected.stepType == 'segment' &&
                    newSelected.segment != null &&
                    newSelected.segment!.segmentType == existingStep.segment!.segmentType &&
                    newSelected.segment!.durationSeconds == existingStep.segment!.durationSeconds &&
                    newSelected.segment!.distanceMeters == existingStep.segment!.distanceMeters &&
                    newSelected.segment!.paceSecondsPerKmMin == existingStep.segment!.paceSecondsPerKmMin &&
                    newSelected.segment!.paceSecondsPerKmMax == existingStep.segment!.paceSecondsPerKmMax);
                
                // Önceki seçimde yoktu ama yeni seçimde varsa, listeden sil
                if (!wasInPreviousSelection && isInNewSelection) {
                  indicesToRemove.add(i);
                }
              }
            }
            
            // İndeksleri sil (geriye doğru sil ki index'ler bozulmasın)
            for (final index in indicesToRemove) {
              _steps.removeAt(index);
            }
          });
          _emit();
        },
        warmupCount: warmupCount,
        cooldownCount: cooldownCount,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                'Antrenman adımları',
                style: AppTypography.labelMedium.copyWith(color: AppColors.neutral600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: TextButton.icon(
                onPressed: _addSegment,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Segment'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: TextButton.icon(
                onPressed: _addRepeat,
                icon: const Icon(Icons.repeat, size: 18),
                label: const Text('Tekrar'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
        if (_steps.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.neutral100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.neutral200),
            ),
            child: Row(
              children: [
                Icon(Icons.fitness_center, color: AppColors.neutral400, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Segment veya Tekrar ekleyerek antrenmanı oluşturun. FIT/TCX export için yapılandırılmış antrenman kullanılır.',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.neutral600),
                  ),
                ),
              ],
            ),
          )
        else
          ..._buildSortedSteps(),
      ],
    );
  }
}

class _StepRow extends ConsumerStatefulWidget {
  final int index;
  final WorkoutStepEditState step;
  final String? trainingTypeName;
  final int? thresholdOffsetMinSeconds;
  final int? thresholdOffsetMaxSeconds;
  final ValueChanged<WorkoutStepEditState> onChanged;
  final VoidCallback onRemove;
  final List<WorkoutStepEditState> allSteps; // Tüm step'ler (Tekrar için segment seçimi için)
  final Function(List<WorkoutStepEditState>)? onEditRepeatSegments; // Tekrar segmentlerini düzenleme callback'i
  final int warmupCount; // Isınma sadece 1 kez
  final int cooldownCount; // Soğuma sadece 1 kez

  const _StepRow({
    super.key,
    required this.index,
    required this.step,
    this.trainingTypeName,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
    required this.onChanged,
    required this.onRemove,
    required this.allSteps,
    this.onEditRepeatSegments,
    required this.warmupCount,
    required this.cooldownCount,
  });

  @override
  ConsumerState<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends ConsumerState<_StepRow> {
  double? get _userVdot => ref.watch(userVdotProvider);
  late bool _isExpanded; // Segment açık/kapalı durumu
  
  @override
  void initState() {
    super.initState();
    // Widget'tan gelen step'in isExpanded değerini kullan
    _isExpanded = widget.step.isExpanded;
  }
  
  // Pace modu: true = Aralık, false = Değer
  bool _isPaceRangeMode() {
    final s = widget.step.segment;
    if (s == null) return false;
    // Eğer min veya max varsa ve customPaceSecondsPerKm yoksa -> aralık modu
    // Aksi halde -> değer modu
    final hasRange = s.paceSecondsPerKmMin != null || s.paceSecondsPerKmMax != null;
    final hasSingle = s.customPaceSecondsPerKm != null;
    return hasRange && !hasSingle;
  }

  String? _getSuggestedPaceForSegment(WorkoutSegmentEntity segment) {
    final vdot = _userVdot;
    if (vdot == null || vdot <= 0) return null;
    return VdotCalculator.getPaceForSegmentType(
      vdot,
      segment.segmentType.name,
      widget.thresholdOffsetMinSeconds,
      widget.thresholdOffsetMaxSeconds,
    );
  }

  @override
  void didUpdateWidget(_StepRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Widget güncellendiğinde state'i yeniden hesapla
    if (oldWidget.step != widget.step) {
      // Step değiştiğinde isExpanded değerini güncelle
      _isExpanded = widget.step.isExpanded;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.step.stepType == 'repeat') {
      return _buildRepeatRow();
    }
    return _buildSegmentRow();
  }

  Widget _buildSegmentRow() {
    final s = widget.step.segment!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_StepRowState._segmentIcon(s.segmentType), size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.segmentType.displayName,
                  style: AppTypography.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Butonları sağa hizalamak için kompakt butonlar
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Tamamlandı/Küçült butonu
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _isExpanded = !_isExpanded;
                          // Step'in isExpanded değerini güncelle
                          widget.step.isExpanded = _isExpanded;
                        });
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        child: Icon(
                          _isExpanded ? Icons.check_circle : Icons.check_circle_outline,
                          size: 20,
                          color: _isExpanded ? AppColors.primary : AppColors.neutral400,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Silme butonu
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onRemove,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.close,
                          size: 20,
                          color: AppColors.neutral600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Eğer collapsed ise sadece özet göster
          if (!_isExpanded) ...[
            const SizedBox(height: 8),
            Text(
              _StepRowState._buildSegmentSummary(s),
              style: AppTypography.bodySmall.copyWith(color: AppColors.neutral600),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<WorkoutSegmentType>(
                  value: s.segmentType,
                  decoration: const InputDecoration(labelText: 'Segment', isDense: true),
                  isExpanded: true,
                  items: WorkoutSegmentType.values.map((e) {
                    final isWarmupDisabled = e == WorkoutSegmentType.warmup && widget.warmupCount >= 1 && s.segmentType != WorkoutSegmentType.warmup;
                    final isCooldownDisabled = e == WorkoutSegmentType.cooldown && widget.cooldownCount >= 1 && s.segmentType != WorkoutSegmentType.cooldown;
                    return DropdownMenuItem<WorkoutSegmentType>(
                      value: e,
                      enabled: !isWarmupDisabled && !isCooldownDisabled,
                      child: Text(
                        e.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    // Focus'u kaldır ve scroll pozisyonunu koru
                    FocusScope.of(context).unfocus();
                    // Segment türü değiştiğinde otomatik pace doldurma kaldırıldı
                    // Kullanıcı manuel pace girebilir veya VDOT modunu seçebilir
                    widget.onChanged(WorkoutStepEditState(
                      stepType: 'segment',
                      segment: WorkoutSegmentEntity(
                        segmentType: v,
                        targetType: s.targetType,
                        target: s.target,
                        durationSeconds: s.durationSeconds,
                        distanceMeters: s.distanceMeters,
                        paceSecondsPerKm: s.paceSecondsPerKm,
                        paceSecondsPerKmMin: s.paceSecondsPerKmMin,
                        paceSecondsPerKmMax: s.paceSecondsPerKmMax,
                        customPaceSecondsPerKm: s.customPaceSecondsPerKm,
                        useVdotForPace: s.useVdotForPace,
                        heartRateBpmMin: s.heartRateBpmMin,
                        heartRateBpmMax: s.heartRateBpmMax,
                        cadenceMin: s.cadenceMin,
                        cadenceMax: s.cadenceMax,
                        powerWattsMin: s.powerWattsMin,
                        powerWattsMax: s.powerWattsMax,
                      ),
                      isExpanded: widget.step.isExpanded,
                    ));
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<WorkoutTargetType>(
                  value: s.targetType,
                  decoration: const InputDecoration(labelText: 'Hedef türü', isDense: true),
                  isExpanded: true,
                  items: WorkoutTargetType.values.map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      e.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    widget.onChanged(WorkoutStepEditState(
                      stepType: 'segment',
                      segment: WorkoutSegmentEntity(
                        segmentType: s.segmentType,
                        targetType: v,
                        target: s.target,
                        durationSeconds: s.durationSeconds,
                        distanceMeters: s.distanceMeters,
                        paceSecondsPerKm: s.paceSecondsPerKm,
                        paceSecondsPerKmMin: s.paceSecondsPerKmMin,
                        paceSecondsPerKmMax: s.paceSecondsPerKmMax,
                        customPaceSecondsPerKm: s.customPaceSecondsPerKm,
                        useVdotForPace: s.useVdotForPace,
                        heartRateBpmMin: s.heartRateBpmMin,
                        heartRateBpmMax: s.heartRateBpmMax,
                        cadenceMin: s.cadenceMin,
                        cadenceMax: s.cadenceMax,
                        powerWattsMin: s.powerWattsMin,
                        powerWattsMax: s.powerWattsMax,
                      ),
                      isExpanded: widget.step.isExpanded,
                    ));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (s.targetType == WorkoutTargetType.duration) ...[
                Flexible(
                  child: GestureDetector(
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      _showDurationPicker(s.durationSeconds, (totalSeconds) {
                        FocusScope.of(context).unfocus();
                        widget.onChanged(WorkoutStepEditState(
                          stepType: 'segment',
                          segment: WorkoutSegmentEntity(
                            segmentType: s.segmentType,
                            targetType: s.targetType,
                            target: s.target,
                            durationSeconds: totalSeconds,
                            distanceMeters: s.distanceMeters,
                            paceSecondsPerKm: s.paceSecondsPerKm,
                            paceSecondsPerKmMin: s.paceSecondsPerKmMin,
                            paceSecondsPerKmMax: s.paceSecondsPerKmMax,
                            customPaceSecondsPerKm: s.customPaceSecondsPerKm,
                            useVdotForPace: s.useVdotForPace,
                            heartRateBpmMin: s.heartRateBpmMin,
                            heartRateBpmMax: s.heartRateBpmMax,
                            cadenceMin: s.cadenceMin,
                            cadenceMax: s.cadenceMax,
                            powerWattsMin: s.powerWattsMin,
                            powerWattsMax: s.powerWattsMax,
                          ),
                          isExpanded: widget.step.isExpanded,
                        ));
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.neutral100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.neutral200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(s.durationSeconds ?? 300),
                            style: AppTypography.bodyMedium,
                          ),
                          Icon(Icons.arrow_drop_down, color: AppColors.neutral600),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (s.targetType == WorkoutTargetType.distance) ...[
                Flexible(
                  child: GestureDetector(
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      _showDistancePicker(s.distanceMeters, (meters) {
                        FocusScope.of(context).unfocus();
                        widget.onChanged(WorkoutStepEditState(
                          stepType: 'segment',
                          segment: WorkoutSegmentEntity(
                            segmentType: s.segmentType,
                            targetType: s.targetType,
                            target: s.target,
                            durationSeconds: s.durationSeconds,
                            distanceMeters: meters,
                            paceSecondsPerKm: s.paceSecondsPerKm,
                            paceSecondsPerKmMin: s.paceSecondsPerKmMin,
                            paceSecondsPerKmMax: s.paceSecondsPerKmMax,
                            customPaceSecondsPerKm: s.customPaceSecondsPerKm,
                            useVdotForPace: s.useVdotForPace,
                            heartRateBpmMin: s.heartRateBpmMin,
                            heartRateBpmMax: s.heartRateBpmMax,
                            cadenceMin: s.cadenceMin,
                            cadenceMax: s.cadenceMax,
                            powerWattsMin: s.powerWattsMin,
                            powerWattsMax: s.powerWattsMax,
                          ),
                          isExpanded: widget.step.isExpanded,
                        ));
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.neutral100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.neutral200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDistance(s.distanceMeters ?? 1000),
                            style: AppTypography.bodyMedium,
                          ),
                          Icon(Icons.arrow_drop_down, color: AppColors.neutral600),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Segment türüne göre önerilen pace
          
          // Pace modu seçici (Manuel Değer / Manuel Aralık / VDOT ile Hesapla)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.neutral100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildPaceModeButton(
                      label: 'Pace',
                      isSelected: s.useVdotForPace != true && !_isPaceRangeMode(),
                      onTap: () {
                        // Focus'u kaldır ve scroll pozisyonunu koru
                        FocusScope.of(context).unfocus();
                        // VDOT veya Aralık modundan Manuel Değer moduna geç
                        final min = s.paceSecondsPerKmMin ?? s.customPaceSecondsPerKm;
                        widget.onChanged(WorkoutStepEditState(
                          stepType: 'segment',
                          segment: WorkoutSegmentEntity(
                            segmentType: s.segmentType,
                            targetType: s.targetType,
                            target: s.target,
                            durationSeconds: s.durationSeconds,
                            distanceMeters: s.distanceMeters,
                            paceSecondsPerKm: s.paceSecondsPerKm,
                            paceSecondsPerKmMin: null,
                            paceSecondsPerKmMax: null,
                            customPaceSecondsPerKm: min,
                            useVdotForPace: false,
                            heartRateBpmMin: s.heartRateBpmMin,
                            heartRateBpmMax: s.heartRateBpmMax,
                            cadenceMin: s.cadenceMin,
                            cadenceMax: s.cadenceMax,
                            powerWattsMin: s.powerWattsMin,
                            powerWattsMax: s.powerWattsMax,
                          ),
                          isExpanded: widget.step.isExpanded,
                        ));
                      },
                    ),
                  ),
                  Expanded(
                    child: _buildPaceModeButton(
                      label: 'Pace Aralığı',
                      isSelected: s.useVdotForPace != true && _isPaceRangeMode(),
                      onTap: () {
                        // Focus'u kaldır ve scroll pozisyonunu koru
                        FocusScope.of(context).unfocus();
                        // VDOT veya Değer modundan Manuel Aralık moduna geç
                        // Önce mevcut değeri kontrol et, yoksa önerilen pace'in ortasını kullan
                        int? centerPace = s.customPaceSecondsPerKm ?? s.paceSecondsPerKm;
                        centerPace ??= _getSuggestedPaceCenter(s);
                        
                        // Önerilen pace'in etrafında ±10 saniye aralık oluştur
                        const rangeOffset = 10; // ±10 saniye
                        final minPace = centerPace != null ? (centerPace - rangeOffset) : null;
                        final maxPace = centerPace != null ? (centerPace + rangeOffset) : null;
                        
                        widget.onChanged(WorkoutStepEditState(
                          stepType: 'segment',
                          segment: WorkoutSegmentEntity(
                            segmentType: s.segmentType,
                            targetType: s.targetType,
                            target: s.target,
                            durationSeconds: s.durationSeconds,
                            distanceMeters: s.distanceMeters,
                            paceSecondsPerKm: s.paceSecondsPerKm,
                            paceSecondsPerKmMin: minPace,
                            paceSecondsPerKmMax: maxPace,
                            customPaceSecondsPerKm: null,
                            useVdotForPace: false,
                            heartRateBpmMin: s.heartRateBpmMin,
                            heartRateBpmMax: s.heartRateBpmMax,
                            cadenceMin: s.cadenceMin,
                            cadenceMax: s.cadenceMax,
                            powerWattsMin: s.powerWattsMin,
                            powerWattsMax: s.powerWattsMax,
                          ),
                          isExpanded: widget.step.isExpanded,
                        ));
                      },
                    ),
                  ),
                  Expanded(
                    child: _buildPaceModeButton(
                      label: 'VDOT Pace',
                      isSelected: s.useVdotForPace == true,
                      onTap: () {
                        // Focus'u kaldır ve scroll pozisyonunu koru
                        FocusScope.of(context).unfocus();
                        // Manuel moddan VDOT moduna geç
                        widget.onChanged(WorkoutStepEditState(
                          stepType: 'segment',
                          segment: WorkoutSegmentEntity(
                            segmentType: s.segmentType,
                            targetType: s.targetType,
                            target: s.target,
                            durationSeconds: s.durationSeconds,
                            distanceMeters: s.distanceMeters,
                            paceSecondsPerKm: s.paceSecondsPerKm,
                            paceSecondsPerKmMin: null,
                            paceSecondsPerKmMax: null,
                            customPaceSecondsPerKm: null,
                            useVdotForPace: true,
                            heartRateBpmMin: s.heartRateBpmMin,
                            heartRateBpmMax: s.heartRateBpmMax,
                            cadenceMin: s.cadenceMin,
                            cadenceMax: s.cadenceMax,
                            powerWattsMin: s.powerWattsMin,
                            powerWattsMax: s.powerWattsMax,
                          ),
                          isExpanded: widget.step.isExpanded,
                        ));
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Pace input alanları
            if (s.useVdotForPace == true)
              // VDOT modu: bilgilendirici mesaj
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Her kullanıcı kendi VDOT değerine göre pace görecek',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              )
            else if (!_isPaceRangeMode())
              // Tek değer modu
              GestureDetector(
                onTap: () {
                  FocusScope.of(context).unfocus();
                  _showPacePicker(
                    s.customPaceSecondsPerKm ?? _StepRowState._parsePaceStringToSeconds(_getDefaultPaceFromSuggestion(s)),
                    (sec) {
                      FocusScope.of(context).unfocus();
                      widget.onChanged(WorkoutStepEditState(
                        stepType: 'segment',
                        segment: WorkoutSegmentEntity(
                          segmentType: s.segmentType,
                          targetType: s.targetType,
                          target: s.target,
                          durationSeconds: s.durationSeconds,
                          distanceMeters: s.distanceMeters,
                          paceSecondsPerKm: s.paceSecondsPerKm,
                          paceSecondsPerKmMin: null,
                          paceSecondsPerKmMax: null,
                          customPaceSecondsPerKm: sec,
                          useVdotForPace: false,
                          heartRateBpmMin: s.heartRateBpmMin,
                          heartRateBpmMax: s.heartRateBpmMax,
                          cadenceMin: s.cadenceMin,
                          cadenceMax: s.cadenceMax,
                          powerWattsMin: s.powerWattsMin,
                          powerWattsMax: s.powerWattsMax,
                        ),
                        isExpanded: widget.step.isExpanded,
                      ));
                    },
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.neutral100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.neutral200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        s.customPaceSecondsPerKm != null
                            ? _formatPaceInput(s.customPaceSecondsPerKm!)
                            : _getDefaultPaceFromSuggestion(s),
                        style: AppTypography.bodyMedium,
                      ),
                      Icon(Icons.arrow_drop_down, color: AppColors.neutral600),
                    ],
                  ),
                ),
              )
            else
              // Aralık modu
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        _showPacePicker(
                          s.paceSecondsPerKmMin ?? _StepRowState._parsePaceStringToSeconds(_getDefaultPaceFromSuggestion(s)),
                          (sec) {
                            FocusScope.of(context).unfocus();
                            widget.onChanged(WorkoutStepEditState(
                              stepType: 'segment',
                              segment: WorkoutSegmentEntity(
                                segmentType: s.segmentType,
                                targetType: s.targetType,
                                target: s.target,
                                durationSeconds: s.durationSeconds,
                                distanceMeters: s.distanceMeters,
                                paceSecondsPerKm: s.paceSecondsPerKm,
                                paceSecondsPerKmMin: sec,
                                paceSecondsPerKmMax: s.paceSecondsPerKmMax,
                                customPaceSecondsPerKm: null,
                                useVdotForPace: false,
                                heartRateBpmMin: s.heartRateBpmMin,
                                heartRateBpmMax: s.heartRateBpmMax,
                                cadenceMin: s.cadenceMin,
                                cadenceMax: s.cadenceMax,
                                powerWattsMin: s.powerWattsMin,
                                powerWattsMax: s.powerWattsMax,
                              ),
                              isExpanded: widget.step.isExpanded,
                            ));
                          },
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.neutral100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.neutral200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              s.paceSecondsPerKmMin != null
                                  ? _formatPaceInput(s.paceSecondsPerKmMin!)
                                  : _getDefaultPaceFromSuggestion(s),
                              style: AppTypography.bodyMedium,
                            ),
                            Icon(Icons.arrow_drop_down, color: AppColors.neutral600),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        _showPacePicker(
                          s.paceSecondsPerKmMax ?? (s.paceSecondsPerKmMin != null ? s.paceSecondsPerKmMin! + 30 : (_StepRowState._parsePaceStringToSeconds(_getDefaultPaceFromSuggestion(s)) ?? 330)),
                          (sec) {
                            FocusScope.of(context).unfocus();
                            widget.onChanged(WorkoutStepEditState(
                              stepType: 'segment',
                              segment: WorkoutSegmentEntity(
                                segmentType: s.segmentType,
                                targetType: s.targetType,
                                target: s.target,
                                durationSeconds: s.durationSeconds,
                                distanceMeters: s.distanceMeters,
                                paceSecondsPerKm: s.paceSecondsPerKm,
                                paceSecondsPerKmMin: s.paceSecondsPerKmMin,
                                paceSecondsPerKmMax: sec,
                                customPaceSecondsPerKm: null,
                                heartRateBpmMin: s.heartRateBpmMin,
                                heartRateBpmMax: s.heartRateBpmMax,
                                cadenceMin: s.cadenceMin,
                                cadenceMax: s.cadenceMax,
                                powerWattsMin: s.powerWattsMin,
                                powerWattsMax: s.powerWattsMax,
                              ),
                              isExpanded: widget.step.isExpanded,
                            ));
                          },
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.neutral100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.neutral200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              s.paceSecondsPerKmMax != null
                                  ? _formatPaceInput(s.paceSecondsPerKmMax!)
                                  : (s.paceSecondsPerKmMin != null
                                      ? _formatPaceInput(s.paceSecondsPerKmMin! + 30)
                                      : _getDefaultPaceFromSuggestion(s)),
                              style: AppTypography.bodyMedium,
                            ),
                            Icon(Icons.arrow_drop_down, color: AppColors.neutral600),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }


  String _getDefaultPaceFromSuggestion(WorkoutSegmentEntity segment) {
    final suggested = _getSuggestedPaceForSegment(segment);
    if (suggested != null) {
      // "4:36-5:00 /km" veya "4:36 /km" formatından pace değerini çıkar
      final pacePart = suggested.split('/').first.trim();
      // Eğer aralık varsa (örn: "4:36-5:00"), ilk değeri al
      final firstPace = pacePart.split('-').first.trim();
      return firstPace;
    }
    return '5:00';
  }

  /// Önerilen pace'in ortasını bulur (aralık ise ortasını, tek değer ise kendisini)
  int? _getSuggestedPaceCenter(WorkoutSegmentEntity segment) {
    final suggested = _getSuggestedPaceForSegment(segment);
    if (suggested == null) return null;
    
    final pacePart = suggested.split('/').first.trim();
    final paceParts = pacePart.split('-');
    
    if (paceParts.length == 2) {
      // Aralık var, ortasını bul
      final minPace = _StepRowState._parsePaceStringToSeconds(paceParts[0].trim());
      final maxPace = _StepRowState._parsePaceStringToSeconds(paceParts[1].trim());
      if (minPace != null && maxPace != null) {
        return ((minPace + maxPace) / 2).round();
      }
      // Eğer parse edilemezse ilk değeri kullan
      return minPace;
    } else {
      // Tek değer
      return _StepRowState._parsePaceStringToSeconds(paceParts[0].trim());
    }
  }

  String _formatPaceInput(int seconds) {
    final m = seconds ~/ 60;
    final sec = seconds % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    
    if (hours > 0) {
      return '${hours}sa ${minutes}dk ${secs}sn';
    } else if (minutes > 0) {
      return '${minutes}dk ${secs}sn';
    } else {
      return '${secs}sn';
    }
  }

  static String _formatDurationShort(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    
    if (hours > 0) {
      return '${hours}sa ${minutes}dk ${secs}sn';
    } else if (minutes > 0) {
      if (secs > 0) {
        return '${minutes}dk ${secs}sn';
      } else {
        return '${minutes}dk';
      }
    } else {
      return '${secs}sn';
    }
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '1.0 km';
    final m = meters.toInt();
    if (m >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    } else {
      return '$m m';
    }
  }


  static int? _parsePaceStringToSeconds(String input) {
    final parts = input.trim().split(RegExp(r'[:\s]'));
    if (parts.length >= 2) {
      final m = int.tryParse(parts[0]);
      final s = int.tryParse(parts[1]);
      if (m != null && s != null && m >= 0 && s >= 0 && s < 60) return m * 60 + s;
    }
    final single = int.tryParse(input.trim());
    if (single != null && single > 0) return single * 60;
    return null;
  }

  // Süre picker için bottom sheet
  Future<void> _showDurationPicker(int? currentSeconds, Function(int) onSelected) async {
    final totalSeconds = currentSeconds ?? 300; // Varsayılan 5 dakika
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    int selectedHours = hours;
    int selectedMinutes = minutes;
    int selectedSeconds = seconds;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 250,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal'),
                  ),
                  Text(
                    'Süre Seç',
                    style: AppTypography.titleMedium,
                  ),
                  TextButton(
                    onPressed: () {
                      final total = selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds;
                      onSelected(total);
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Tamam',
                      style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: selectedHours),
                      onSelectedItemChanged: (value) => selectedHours = value,
                      children: List.generate(24, (i) => Center(child: Text('$i sa'))),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: selectedMinutes),
                      onSelectedItemChanged: (value) => selectedMinutes = value,
                      children: List.generate(60, (i) => Center(child: Text('$i dk'))),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: selectedSeconds),
                      onSelectedItemChanged: (value) => selectedSeconds = value,
                      children: List.generate(60, (i) => Center(child: Text('$i sn'))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mesafe picker için bottom sheet
  Future<void> _showDistancePicker(double? currentMeters, Function(double) onSelected) async {
    final meters = (currentMeters ?? 1000).toInt(); // Varsayılan 1km
    final initialIndex = (meters ~/ 5).clamp(0, 2000); // 0-10000m, 5m artışlarla

    int selectedIndex = initialIndex;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 250,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal'),
                  ),
                  Text(
                    'Mesafe Seç',
                    style: AppTypography.titleMedium,
                  ),
                  TextButton(
                    onPressed: () {
                      final selectedMeters = (selectedIndex * 5).toDouble();
                      onSelected(selectedMeters);
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Tamam',
                      style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                itemExtent: 40,
                scrollController: FixedExtentScrollController(initialItem: initialIndex),
                onSelectedItemChanged: (value) => selectedIndex = value,
                children: List.generate(2001, (i) {
                  final m = i * 5;
                  return Center(
                    child: Text('$m m'),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Pace picker için bottom sheet
  Future<void> _showPacePicker(int? currentSeconds, Function(int) onSelected) async {
    final totalSeconds = currentSeconds ?? 300; // Varsayılan 5:00
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    int selectedMinutes = minutes;
    int selectedSeconds = seconds;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 250,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal'),
                  ),
                  Text(
                    'Pace Seç',
                    style: AppTypography.titleMedium,
                  ),
                  TextButton(
                    onPressed: () {
                      final total = selectedMinutes * 60 + selectedSeconds;
                      onSelected(total);
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Tamam',
                      style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: selectedMinutes),
                      onSelectedItemChanged: (value) => selectedMinutes = value,
                      children: List.generate(60, (i) => Center(child: Text('$i\''))),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: selectedSeconds),
                      onSelectedItemChanged: (value) => selectedSeconds = value,
                      children: List.generate(60, (i) => Center(child: Text('$i\'\''))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaceModeButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.labelMedium.copyWith(
              color: isSelected ? Colors.white : AppColors.neutral600,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  static IconData _segmentIcon(WorkoutSegmentType t) {
    switch (t) {
      case WorkoutSegmentType.warmup:
        return Icons.whatshot;
      case WorkoutSegmentType.main:
        return Icons.directions_run;
      case WorkoutSegmentType.recovery:
        return Icons.favorite_border;
      case WorkoutSegmentType.cooldown:
        return Icons.ac_unit;
    }
  }

  static String _buildSegmentSummary(WorkoutSegmentEntity segment) {
    final parts = <String>[];
    
    if (segment.targetType == WorkoutTargetType.duration && segment.durationSeconds != null) {
      parts.add(_formatDurationShort(segment.durationSeconds!));
    } else if (segment.targetType == WorkoutTargetType.distance && segment.distanceMeters != null) {
      parts.add('${(segment.distanceMeters! / 1000).toStringAsFixed(1)}km');
    }
    
    if (segment.target == WorkoutTarget.pace) {
      if (segment.paceSecondsPerKmMin != null && segment.paceSecondsPerKmMax != null) {
        final minM = segment.paceSecondsPerKmMin! ~/ 60;
        final minS = segment.paceSecondsPerKmMin! % 60;
        final maxM = segment.paceSecondsPerKmMax! ~/ 60;
        final maxS = segment.paceSecondsPerKmMax! % 60;
        parts.add('$minM:${minS.toString().padLeft(2, '0')}-$maxM:${maxS.toString().padLeft(2, '0')} pace');
      } else if (segment.customPaceSecondsPerKm != null) {
        final m = segment.customPaceSecondsPerKm! ~/ 60;
        final s = segment.customPaceSecondsPerKm! % 60;
        parts.add('$m:${s.toString().padLeft(2, '0')} pace');
      }
    }
    
    return parts.isEmpty ? 'Segment' : parts.join(' · ');
  }

  Widget _buildRepeatRow() {
    return GestureDetector(
      onTap: () => _editRepeatSegments(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.repeat, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Tekrar',
                    style: AppTypography.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 0,
                  child: SizedBox(
                    width: 50,
                    child: TextFormField(
                      initialValue: '${widget.step.repeatCount}',
                      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onChanged: (v) {
                        final c = int.tryParse(v);
                        if (c != null && c >= 1) {
                          widget.onChanged(WorkoutStepEditState(
                            stepType: 'repeat',
                            repeatCount: c,
                            repeatSteps: widget.step.repeatSteps,
                            isExpanded: widget.step.isExpanded,
                          ));
                        }
                      },
                      onTap: () {},
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  flex: 0,
                  child: Text(
                    'kez',
                    style: AppTypography.bodySmall,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          // Tekrar içindeki segmentleri göster (tam düzenleme arayüzü ile)
          if (widget.step.repeatSteps != null && widget.step.repeatSteps!.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...widget.step.repeatSteps!.asMap().entries.map((entry) {
              final repeatIndex = entry.key;
              final repeatStep = entry.value;
              if (repeatStep.segment == null) return const SizedBox.shrink();
              
              return Container(
                margin: EdgeInsets.only(
                  bottom: repeatIndex == widget.step.repeatSteps!.length - 1 ? 0 : 12,
                  left: 16, // Girinti
                ),
                child: _RepeatSegmentEditor(
                  key: ValueKey('repeat_segment_${widget.index}_$repeatIndex'),
                  segment: repeatStep.segment!,
                  trainingTypeName: widget.trainingTypeName,
                  thresholdOffsetMinSeconds: widget.thresholdOffsetMinSeconds,
                  thresholdOffsetMaxSeconds: widget.thresholdOffsetMaxSeconds,
                  warmupCount: widget.warmupCount,
                  cooldownCount: widget.cooldownCount,
                  onChanged: (updatedSegment) {
                    // Tekrar içindeki segmenti güncelle
                    final updatedSteps = List<WorkoutStepEditState>.from(widget.step.repeatSteps ?? []);
                    updatedSteps[repeatIndex] = WorkoutStepEditState(
                      stepType: 'segment',
                      segment: updatedSegment,
                    );
                    widget.onChanged(WorkoutStepEditState(
                      stepType: 'repeat',
                      repeatCount: widget.step.repeatCount,
                      repeatSteps: updatedSteps,
                      isExpanded: widget.step.isExpanded,
                    ));
                  },
                  onRemove: () {
                    // Tekrar içindeki segmenti sil
                    final updatedSteps = List<WorkoutStepEditState>.from(widget.step.repeatSteps ?? []);
                    updatedSteps.removeAt(repeatIndex);
                    widget.onChanged(WorkoutStepEditState(
                      stepType: 'repeat',
                      repeatCount: widget.step.repeatCount,
                      repeatSteps: updatedSteps,
                      isExpanded: widget.step.isExpanded,
                    ));
                  },
                ),
              );
            }),
          ],
          ],
        ),
      ),
    );
  }

  Future<void> _editRepeatSegments() async {
    if (widget.onEditRepeatSegments == null) return;
    
    // Mevcut segmentleri al (Tekrar blokları, ısınma ve soğuma hariç)
    // Hem top-level segmentleri hem de tüm Tekrar bloklarının içindeki segmentleri dahil et
    final availableSegments = <WorkoutStepEditState>[];
    
    // Top-level segmentleri ekle
    for (final s in widget.allSteps) {
      if (s.stepType == 'segment' && 
          s.segment != null &&
          s.segment!.segmentType != WorkoutSegmentType.warmup &&
          s.segment!.segmentType != WorkoutSegmentType.cooldown) {
        availableSegments.add(s);
      }
      // Tekrar bloklarının içindeki segmentleri de ekle
      if (s.stepType == 'repeat' && s.repeatSteps != null) {
        for (final repeatStep in s.repeatSteps!) {
          if (repeatStep.stepType == 'segment' && 
              repeatStep.segment != null &&
              repeatStep.segment!.segmentType != WorkoutSegmentType.warmup &&
              repeatStep.segment!.segmentType != WorkoutSegmentType.cooldown) {
            // Aynı segment zaten listede yoksa ekle
            if (!availableSegments.any((existing) => 
                existing.segment?.segmentType == repeatStep.segment?.segmentType &&
                existing.segment?.durationSeconds == repeatStep.segment?.durationSeconds &&
                existing.segment?.distanceMeters == repeatStep.segment?.distanceMeters)) {
              availableSegments.add(repeatStep);
            }
          }
        }
      }
    }
    
    if (availableSegments.isEmpty) {
      // Segment yoksa uyarı göster
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tekrar için segment bulunamadı')),
        );
      }
      return;
    }
    
    // Popup'ta segment seçimi yap (mevcut seçili segmentlerle)
    final selectedSegments = await _showSegmentSelectionDialogForRepeat(
      availableSegments,
      initiallySelected: widget.step.repeatSteps ?? [],
    );
    
    if (selectedSegments != null) {
      widget.onEditRepeatSegments!(selectedSegments);
    }
  }

  Future<List<WorkoutStepEditState>?> _showSegmentSelectionDialogForRepeat(
    List<WorkoutStepEditState> availableSegments, {
    required List<WorkoutStepEditState> initiallySelected,
  }) async {
    final selectedIndices = <int>{};
    
    // Başlangıçta seçili olan segmentleri işaretle
    for (final selected in initiallySelected) {
      final index = availableSegments.indexWhere(
        (s) => s.segment?.segmentType == selected.segment?.segmentType &&
            s.segment?.durationSeconds == selected.segment?.durationSeconds &&
            s.segment?.distanceMeters == selected.segment?.distanceMeters,
      );
      if (index != -1) {
        selectedIndices.add(index);
      }
    }
    
    return showModalBottomSheet<List<WorkoutStepEditState>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        // StatefulBuilder içinde state olarak tut
        final selectedIndices = <int>{};
        for (final selected in initiallySelected) {
          final index = availableSegments.indexWhere(
            (s) => s.segment?.segmentType == selected.segment?.segmentType &&
                s.segment?.durationSeconds == selected.segment?.durationSeconds &&
                s.segment?.distanceMeters == selected.segment?.distanceMeters,
          );
          if (index != -1) {
            selectedIndices.add(index);
          }
        }
        
        return StatefulBuilder(
          builder: (context, setState) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Tekrar için Segment Seç',
                          style: AppTypography.titleMedium,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context, null),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Segment listesi
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: availableSegments.length,
                      itemBuilder: (context, index) {
                        final segment = availableSegments[index].segment!;
                        final isSelected = selectedIndices.contains(index);
                        
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                selectedIndices.add(index);
                              } else {
                                selectedIndices.remove(index);
                              }
                            });
                          },
                          title: Row(
                            children: [
                              Icon(
                                _getSegmentIcon(segment.segmentType),
                                size: 20,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  segment.segmentType.displayName,
                                  style: AppTypography.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            _buildSegmentSummaryForRepeat(segment),
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.neutral600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  // Butonlar
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: const Text('İptal'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedIndices.isEmpty
                                ? null
                                : () {
                                    final selected = selectedIndices
                                        .map((i) => availableSegments[i])
                                        .toList();
                                    Navigator.pop(context, selected);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Tamam'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getSegmentIcon(WorkoutSegmentType t) {
    switch (t) {
      case WorkoutSegmentType.warmup:
        return Icons.whatshot;
      case WorkoutSegmentType.main:
        return Icons.directions_run;
      case WorkoutSegmentType.recovery:
        return Icons.favorite_border;
      case WorkoutSegmentType.cooldown:
        return Icons.ac_unit;
    }
  }

  String _buildSegmentSummaryForRepeat(WorkoutSegmentEntity segment) {
    final parts = <String>[];
    
    if (segment.targetType == WorkoutTargetType.duration && segment.durationSeconds != null) {
      parts.add(_formatDurationShort(segment.durationSeconds!));
    } else if (segment.targetType == WorkoutTargetType.distance && segment.distanceMeters != null) {
      parts.add('${(segment.distanceMeters! / 1000).toStringAsFixed(1)}km');
    }
    
    if (segment.target == WorkoutTarget.pace) {
      if (segment.paceSecondsPerKmMin != null && segment.paceSecondsPerKmMax != null) {
        final minM = segment.paceSecondsPerKmMin! ~/ 60;
        final minS = segment.paceSecondsPerKmMin! % 60;
        final maxM = segment.paceSecondsPerKmMax! ~/ 60;
        final maxS = segment.paceSecondsPerKmMax! % 60;
        parts.add('$minM:${minS.toString().padLeft(2, '0')}-$maxM:${maxS.toString().padLeft(2, '0')} pace');
      } else if (segment.customPaceSecondsPerKm != null) {
        final m = segment.customPaceSecondsPerKm! ~/ 60;
        final s = segment.customPaceSecondsPerKm! % 60;
        parts.add('$m:${s.toString().padLeft(2, '0')} pace');
      }
    }
    
    return parts.isEmpty ? 'Segment' : parts.join(' · ');
  }
}

/// Tekrar içindeki segmentler için düzenleme widget'ı
class _RepeatSegmentEditor extends ConsumerStatefulWidget {
  final WorkoutSegmentEntity segment;
  final String? trainingTypeName;
  final int? thresholdOffsetMinSeconds;
  final int? thresholdOffsetMaxSeconds;
  final int warmupCount;
  final int cooldownCount;
  final ValueChanged<WorkoutSegmentEntity> onChanged;
  final VoidCallback onRemove;

  const _RepeatSegmentEditor({
    super.key,
    required this.segment,
    this.trainingTypeName,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
    required this.warmupCount,
    required this.cooldownCount,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  ConsumerState<_RepeatSegmentEditor> createState() => _RepeatSegmentEditorState();
}

class _RepeatSegmentEditorState extends ConsumerState<_RepeatSegmentEditor> {
  double? get _userVdot => ref.watch(userVdotProvider);
  bool _isExpanded = false; // Tekrar içi segment başlangıçta kapalı

  @override
  Widget build(BuildContext context) {
    final s = widget.segment;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_StepRowState._segmentIcon(s.segmentType), size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.segmentType.displayName,
                  style: AppTypography.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _isExpanded = !_isExpanded;
                        });
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        child: Icon(
                          _isExpanded ? Icons.check_circle : Icons.check_circle_outline,
                          size: 20,
                          color: _isExpanded ? AppColors.primary : AppColors.neutral400,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onRemove,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.close,
                          size: 20,
                          color: AppColors.neutral600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (!_isExpanded) ...[
            const SizedBox(height: 8),
            Text(
              _StepRowState._buildSegmentSummary(s),
              style: AppTypography.bodySmall.copyWith(color: AppColors.neutral600),
            ),
          ] else ...[
            const SizedBox(height: 12),
            // Segment düzenleme formu
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<WorkoutSegmentType>(
                    value: s.segmentType,
                    decoration: const InputDecoration(labelText: 'Segment', isDense: true),
                    isExpanded: true,
                    items: WorkoutSegmentType.values.map((e) {
                      final isWarmupDisabled = e == WorkoutSegmentType.warmup && widget.warmupCount >= 1 && s.segmentType != WorkoutSegmentType.warmup;
                      final isCooldownDisabled = e == WorkoutSegmentType.cooldown && widget.cooldownCount >= 1 && s.segmentType != WorkoutSegmentType.cooldown;
                      return DropdownMenuItem<WorkoutSegmentType>(
                        value: e,
                        enabled: !isWarmupDisabled && !isCooldownDisabled,
                        child: Text(
                          e.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      int? newCustomPace = s.customPaceSecondsPerKm;
                      if (s.target == WorkoutTarget.pace && s.customPaceSecondsPerKm == null) {
                        final vdot = _userVdot;
                        if (vdot != null && vdot > 0) {
                          final paceRange = VdotCalculator.getPaceRangeForSegmentType(
                            vdot,
                            v.name,
                            widget.thresholdOffsetMinSeconds,
                            widget.thresholdOffsetMaxSeconds,
                          );
                          if (paceRange != null) {
                            newCustomPace = paceRange.$1; // Hızlı pace
                          }
                        }
                      }
                      widget.onChanged(WorkoutSegmentEntity(
                        segmentType: v,
                        targetType: s.targetType,
                        target: s.target,
                        durationSeconds: s.durationSeconds,
                        distanceMeters: s.distanceMeters,
                        paceSecondsPerKm: s.paceSecondsPerKm,
                        paceSecondsPerKmMin: s.paceSecondsPerKmMin,
                        paceSecondsPerKmMax: s.paceSecondsPerKmMax,
                        customPaceSecondsPerKm: newCustomPace,
                        useVdotForPace: s.useVdotForPace,
                        heartRateBpmMin: s.heartRateBpmMin,
                        heartRateBpmMax: s.heartRateBpmMax,
                        cadenceMin: s.cadenceMin,
                        cadenceMax: s.cadenceMax,
                        powerWattsMin: s.powerWattsMin,
                        powerWattsMax: s.powerWattsMax,
                      ));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<WorkoutTargetType>(
                    value: s.targetType,
                    decoration: const InputDecoration(labelText: 'Hedef türü', isDense: true),
                    isExpanded: true,
                    items: WorkoutTargetType.values.map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(
                        e.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      widget.onChanged(WorkoutSegmentEntity(
                        segmentType: s.segmentType,
                        targetType: v,
                        target: s.target,
                        durationSeconds: s.durationSeconds,
                        distanceMeters: s.distanceMeters,
                        paceSecondsPerKm: s.paceSecondsPerKm,
                        paceSecondsPerKmMin: s.paceSecondsPerKmMin,
                        paceSecondsPerKmMax: s.paceSecondsPerKmMax,
                        customPaceSecondsPerKm: s.customPaceSecondsPerKm,
                        useVdotForPace: s.useVdotForPace,
                        heartRateBpmMin: s.heartRateBpmMin,
                        heartRateBpmMax: s.heartRateBpmMax,
                        cadenceMin: s.cadenceMin,
                        cadenceMax: s.cadenceMax,
                        powerWattsMin: s.powerWattsMin,
                        powerWattsMax: s.powerWattsMax,
                      ));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (s.targetType == WorkoutTargetType.duration) ...[
                  Flexible(
                    child: GestureDetector(
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        _showDurationPicker(s.durationSeconds, (totalSeconds) {
                          FocusScope.of(context).unfocus();
                          widget.onChanged(WorkoutSegmentEntity(
                            segmentType: s.segmentType,
                            targetType: s.targetType,
                            target: s.target,
                            durationSeconds: totalSeconds,
                            distanceMeters: s.distanceMeters,
                            paceSecondsPerKm: s.paceSecondsPerKm,
                            paceSecondsPerKmMin: s.paceSecondsPerKmMin,
                            paceSecondsPerKmMax: s.paceSecondsPerKmMax,
                            customPaceSecondsPerKm: s.customPaceSecondsPerKm,
                            useVdotForPace: s.useVdotForPace,
                            heartRateBpmMin: s.heartRateBpmMin,
                            heartRateBpmMax: s.heartRateBpmMax,
                            cadenceMin: s.cadenceMin,
                            cadenceMax: s.cadenceMax,
                            powerWattsMin: s.powerWattsMin,
                            powerWattsMax: s.powerWattsMax,
                          ));
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.neutral100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.neutral200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(s.durationSeconds ?? 300),
                              style: AppTypography.bodyMedium,
                            ),
                            Icon(Icons.arrow_drop_down, color: AppColors.neutral600),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (s.targetType == WorkoutTargetType.distance) ...[
                  Flexible(
                    child: GestureDetector(
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        _showDistancePicker(s.distanceMeters, (meters) {
                          FocusScope.of(context).unfocus();
                          widget.onChanged(WorkoutSegmentEntity(
                            segmentType: s.segmentType,
                            targetType: s.targetType,
                            target: s.target,
                            durationSeconds: s.durationSeconds,
                            distanceMeters: meters,
                            paceSecondsPerKm: s.paceSecondsPerKm,
                            paceSecondsPerKmMin: s.paceSecondsPerKmMin,
                            paceSecondsPerKmMax: s.paceSecondsPerKmMax,
                            customPaceSecondsPerKm: s.customPaceSecondsPerKm,
                            useVdotForPace: s.useVdotForPace,
                            heartRateBpmMin: s.heartRateBpmMin,
                            heartRateBpmMax: s.heartRateBpmMax,
                            cadenceMin: s.cadenceMin,
                            cadenceMax: s.cadenceMax,
                            powerWattsMin: s.powerWattsMin,
                            powerWattsMax: s.powerWattsMax,
                          ));
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.neutral100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.neutral200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDistance(s.distanceMeters ?? 1000),
                              style: AppTypography.bodyMedium,
                            ),
                            Icon(Icons.arrow_drop_down, color: AppColors.neutral600),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.neutral100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildPaceModeButton(
                        label: 'Pace',
                        isSelected: s.useVdotForPace != true && !_isPaceRangeMode(),
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          final min = s.paceSecondsPerKmMin ?? s.customPaceSecondsPerKm;
                          widget.onChanged(WorkoutSegmentEntity(
                            segmentType: s.segmentType,
                            targetType: s.targetType,
                            target: s.target,
                            durationSeconds: s.durationSeconds,
                            distanceMeters: s.distanceMeters,
                            paceSecondsPerKm: s.paceSecondsPerKm,
                            paceSecondsPerKmMin: null,
                            paceSecondsPerKmMax: null,
                            customPaceSecondsPerKm: min,
                            useVdotForPace: false,
                            heartRateBpmMin: s.heartRateBpmMin,
                            heartRateBpmMax: s.heartRateBpmMax,
                            cadenceMin: s.cadenceMin,
                            cadenceMax: s.cadenceMax,
                            powerWattsMin: s.powerWattsMin,
                            powerWattsMax: s.powerWattsMax,
                          ));
                        },
                      ),
                    ),
                    Expanded(
                      child: _buildPaceModeButton(
                        label: 'Pace Aralığı',
                        isSelected: s.useVdotForPace != true && _isPaceRangeMode(),
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          int? centerPace = s.customPaceSecondsPerKm ?? s.paceSecondsPerKm;
                          centerPace ??= _getSuggestedPaceCenter(s);
                          const rangeOffset = 10;
                          final minPace = centerPace != null ? (centerPace - rangeOffset) : null;
                          final maxPace = centerPace != null ? (centerPace + rangeOffset) : null;
                          widget.onChanged(WorkoutSegmentEntity(
                            segmentType: s.segmentType,
                            targetType: s.targetType,
                            target: s.target,
                            durationSeconds: s.durationSeconds,
                            distanceMeters: s.distanceMeters,
                            paceSecondsPerKm: s.paceSecondsPerKm,
                            paceSecondsPerKmMin: minPace,
                            paceSecondsPerKmMax: maxPace,
                            customPaceSecondsPerKm: null,
                            useVdotForPace: false,
                            heartRateBpmMin: s.heartRateBpmMin,
                            heartRateBpmMax: s.heartRateBpmMax,
                            cadenceMin: s.cadenceMin,
                            cadenceMax: s.cadenceMax,
                            powerWattsMin: s.powerWattsMin,
                            powerWattsMax: s.powerWattsMax,
                          ));
                        },
                      ),
                    ),
                    Expanded(
                      child: _buildPaceModeButton(
                        label: 'VDOT Pace',
                        isSelected: s.useVdotForPace == true,
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          widget.onChanged(WorkoutSegmentEntity(
                            segmentType: s.segmentType,
                            targetType: s.targetType,
                            target: s.target,
                            durationSeconds: s.durationSeconds,
                            distanceMeters: s.distanceMeters,
                            paceSecondsPerKm: s.paceSecondsPerKm,
                            paceSecondsPerKmMin: null,
                            paceSecondsPerKmMax: null,
                            customPaceSecondsPerKm: null,
                            useVdotForPace: true,
                            heartRateBpmMin: s.heartRateBpmMin,
                            heartRateBpmMax: s.heartRateBpmMax,
                            cadenceMin: s.cadenceMin,
                            cadenceMax: s.cadenceMax,
                            powerWattsMin: s.powerWattsMin,
                            powerWattsMax: s.powerWattsMax,
                          ));
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (s.useVdotForPace == true)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Her kullanıcı kendi VDOT değerine göre pace görecek',
                          style: AppTypography.bodySmall.copyWith(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                )
              else if (!_isPaceRangeMode())
                GestureDetector(
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    _showPacePicker(
                      s.customPaceSecondsPerKm ?? _StepRowState._parsePaceStringToSeconds(_getDefaultPaceFromSuggestion(s)),
                      (sec) {
                        FocusScope.of(context).unfocus();
                        widget.onChanged(WorkoutSegmentEntity(
                          segmentType: s.segmentType,
                          targetType: s.targetType,
                          target: s.target,
                          durationSeconds: s.durationSeconds,
                          distanceMeters: s.distanceMeters,
                          paceSecondsPerKm: s.paceSecondsPerKm,
                          paceSecondsPerKmMin: null,
                          paceSecondsPerKmMax: null,
                          customPaceSecondsPerKm: sec,
                          useVdotForPace: false,
                          heartRateBpmMin: s.heartRateBpmMin,
                          heartRateBpmMax: s.heartRateBpmMax,
                          cadenceMin: s.cadenceMin,
                          cadenceMax: s.cadenceMax,
                          powerWattsMin: s.powerWattsMin,
                          powerWattsMax: s.powerWattsMax,
                        ));
                      },
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.neutral100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.neutral200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          s.customPaceSecondsPerKm != null
                              ? _formatPaceInput(s.customPaceSecondsPerKm!)
                              : _getDefaultPaceFromSuggestion(s),
                          style: AppTypography.bodyMedium,
                        ),
                        Icon(Icons.arrow_drop_down, color: AppColors.neutral600),
                      ],
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          _showPacePicker(
                            s.paceSecondsPerKmMin ?? _StepRowState._parsePaceStringToSeconds(_getDefaultPaceFromSuggestion(s)),
                            (sec) {
                              FocusScope.of(context).unfocus();
                              widget.onChanged(WorkoutSegmentEntity(
                                segmentType: s.segmentType,
                                targetType: s.targetType,
                                target: s.target,
                                durationSeconds: s.durationSeconds,
                                distanceMeters: s.distanceMeters,
                                paceSecondsPerKm: s.paceSecondsPerKm,
                                paceSecondsPerKmMin: sec,
                                paceSecondsPerKmMax: s.paceSecondsPerKmMax,
                                customPaceSecondsPerKm: null,
                                useVdotForPace: false,
                                heartRateBpmMin: s.heartRateBpmMin,
                                heartRateBpmMax: s.heartRateBpmMax,
                                cadenceMin: s.cadenceMin,
                                cadenceMax: s.cadenceMax,
                                powerWattsMin: s.powerWattsMin,
                                powerWattsMax: s.powerWattsMax,
                              ));
                            },
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          decoration: BoxDecoration(
                            color: AppColors.neutral100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.neutral200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                s.paceSecondsPerKmMin != null
                                    ? _formatPaceInput(s.paceSecondsPerKmMin!)
                                    : _getDefaultPaceFromSuggestion(s),
                                style: AppTypography.bodyMedium,
                              ),
                              Icon(Icons.arrow_drop_down, color: AppColors.neutral600),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          _showPacePicker(
                            s.paceSecondsPerKmMax ?? (s.paceSecondsPerKmMin != null ? s.paceSecondsPerKmMin! + 30 : (_StepRowState._parsePaceStringToSeconds(_getDefaultPaceFromSuggestion(s)) ?? 330)),
                            (sec) {
                              FocusScope.of(context).unfocus();
                              widget.onChanged(WorkoutSegmentEntity(
                                segmentType: s.segmentType,
                                targetType: s.targetType,
                                target: s.target,
                                durationSeconds: s.durationSeconds,
                                distanceMeters: s.distanceMeters,
                                paceSecondsPerKm: s.paceSecondsPerKm,
                                paceSecondsPerKmMin: s.paceSecondsPerKmMin,
                                paceSecondsPerKmMax: sec,
                                customPaceSecondsPerKm: null,
                                useVdotForPace: false,
                                heartRateBpmMin: s.heartRateBpmMin,
                                heartRateBpmMax: s.heartRateBpmMax,
                                cadenceMin: s.cadenceMin,
                                cadenceMax: s.cadenceMax,
                                powerWattsMin: s.powerWattsMin,
                                powerWattsMax: s.powerWattsMax,
                              ));
                            },
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          decoration: BoxDecoration(
                            color: AppColors.neutral100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.neutral200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                s.paceSecondsPerKmMax != null
                                    ? _formatPaceInput(s.paceSecondsPerKmMax!)
                                    : (s.paceSecondsPerKmMin != null
                                        ? _formatPaceInput(s.paceSecondsPerKmMin! + 30)
                                        : _getDefaultPaceFromSuggestion(s)),
                                style: AppTypography.bodyMedium,
                              ),
                              Icon(Icons.arrow_drop_down, color: AppColors.neutral600),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      );
  }

  bool _isPaceRangeMode() {
    final s = widget.segment;
    final hasRange = s.paceSecondsPerKmMin != null || s.paceSecondsPerKmMax != null;
    final hasSingle = s.customPaceSecondsPerKm != null;
    return hasRange && !hasSingle;
  }

  String? _getSuggestedPaceForSegment(WorkoutSegmentEntity segment) {
    final vdot = _userVdot;
    if (vdot == null || vdot <= 0) return null;
    return VdotCalculator.getPaceForSegmentType(
      vdot,
      segment.segmentType.name,
      widget.thresholdOffsetMinSeconds,
      widget.thresholdOffsetMaxSeconds,
    );
  }

  String _getDefaultPaceFromSuggestion(WorkoutSegmentEntity segment) {
    final suggested = _getSuggestedPaceForSegment(segment);
    if (suggested != null) {
      final pacePart = suggested.split('/').first.trim();
      final firstPace = pacePart.split('-').first.trim();
      return firstPace;
    }
    return '5:00';
  }

  int? _getSuggestedPaceCenter(WorkoutSegmentEntity segment) {
    final suggested = _getSuggestedPaceForSegment(segment);
    if (suggested == null) return null;
    final pacePart = suggested.split('/').first.trim();
    final paceParts = pacePart.split('-');
    if (paceParts.length == 2) {
      final minPace = _StepRowState._parsePaceStringToSeconds(paceParts[0].trim());
      final maxPace = _StepRowState._parsePaceStringToSeconds(paceParts[1].trim());
      if (minPace != null && maxPace != null) {
        return ((minPace + maxPace) / 2).round();
      }
      return minPace;
    } else {
      return _StepRowState._parsePaceStringToSeconds(paceParts[0].trim());
    }
  }

  String _formatPaceInput(int seconds) {
    final m = seconds ~/ 60;
    final sec = seconds % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '${hours}sa ${minutes}dk ${secs}sn';
    } else if (minutes > 0) {
      return '${minutes}dk ${secs}sn';
    } else {
      return '${secs}sn';
    }
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '1.0 km';
    final m = meters.toInt();
    if (m >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    } else {
      return '$m m';
    }
  }

  Future<void> _showDurationPicker(int? currentSeconds, Function(int) onSelected) async {
    final totalSeconds = currentSeconds ?? 300;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;

    int selectedHours = hours;
    int selectedMinutes = minutes;
    int selectedSeconds = secs;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 250,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal'),
                  ),
                  Text(
                    'Süre Seç',
                    style: AppTypography.titleMedium,
                  ),
                  TextButton(
                    onPressed: () {
                      final total = selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds;
                      onSelected(total);
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Tamam',
                      style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: selectedHours),
                      onSelectedItemChanged: (value) => selectedHours = value,
                      children: List.generate(24, (i) => Center(child: Text('$i sa'))),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: selectedMinutes),
                      onSelectedItemChanged: (value) => selectedMinutes = value,
                      children: List.generate(60, (i) => Center(child: Text('$i dk'))),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: selectedSeconds),
                      onSelectedItemChanged: (value) => selectedSeconds = value,
                      children: List.generate(60, (i) => Center(child: Text('$i sn'))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDistancePicker(double? currentMeters, Function(double) onSelected) async {
    final meters = (currentMeters ?? 1000).toInt();
    final initialIndex = (meters ~/ 5).clamp(0, 2000);
    int selectedIndex = initialIndex;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 250,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal'),
                  ),
                  Text(
                    'Mesafe Seç',
                    style: AppTypography.titleMedium,
                  ),
                  TextButton(
                    onPressed: () {
                      final selectedMeters = (selectedIndex * 5).toDouble();
                      onSelected(selectedMeters);
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Tamam',
                      style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                itemExtent: 40,
                scrollController: FixedExtentScrollController(initialItem: initialIndex),
                onSelectedItemChanged: (value) => selectedIndex = value,
                children: List.generate(2001, (i) {
                  final m = i * 5;
                  return Center(
                    child: Text('$m m'),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPacePicker(int? currentSeconds, Function(int) onSelected) async {
    final totalSeconds = currentSeconds ?? 300;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    int selectedMinutes = minutes;
    int selectedSeconds = seconds;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 250,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal'),
                  ),
                  Text(
                    'Pace Seç',
                    style: AppTypography.titleMedium,
                  ),
                  TextButton(
                    onPressed: () {
                      final total = selectedMinutes * 60 + selectedSeconds;
                      onSelected(total);
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Tamam',
                      style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: selectedMinutes),
                      onSelectedItemChanged: (value) => selectedMinutes = value,
                      children: List.generate(20, (i) => Center(child: Text('$i dk'))),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: selectedSeconds),
                      onSelectedItemChanged: (value) => selectedSeconds = value,
                      children: List.generate(60, (i) => Center(child: Text('$i sn'))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaceModeButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.labelMedium.copyWith(
              color: isSelected ? Colors.white : AppColors.neutral600,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
