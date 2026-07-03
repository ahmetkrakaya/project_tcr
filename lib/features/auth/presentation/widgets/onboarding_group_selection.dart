import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../members_groups/domain/entities/group_entity.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';
import '../../../members_groups/presentation/widgets/group_avatar.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

class OnboardingGroupSelection extends ConsumerStatefulWidget {
  const OnboardingGroupSelection({
    super.key,
    this.onCompletenessChanged,
  });

  final ValueChanged<bool>? onCompletenessChanged;

  @override
  OnboardingGroupSelectionState createState() => OnboardingGroupSelectionState();
}

class OnboardingGroupSelectionState
    extends ConsumerState<OnboardingGroupSelection> {
  String? _selectedGroupId;

  bool get isComplete => _selectedGroupId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncInitialSelection());
  }

  void _notifyCompleteness() {
    widget.onCompletenessChanged?.call(isComplete);
  }

  Future<void> _syncInitialSelection() async {
    final groups = ref.read(allGroupsProvider).valueOrNull;
    if (groups == null) return;

    for (final group in groups) {
      if (group.isUserMember) {
        if (_selectedGroupId != group.id) {
          setState(() => _selectedGroupId = group.id);
          _notifyCompleteness();
        }
        return;
      }
    }

    try {
      final pending = await ref.read(userPendingJoinRequestsProvider.future);
      if (pending.isNotEmpty && mounted) {
        final groupId = pending.first.groupId;
        if (_selectedGroupId != groupId) {
          setState(() => _selectedGroupId = groupId);
          _notifyCompleteness();
        }
      }
    } catch (_) {}
  }

  Future<({bool ok, bool newlySubmitted})> submitJoinRequest() async {
    if (_selectedGroupId == null) return (ok: false, newlySubmitted: false);

    final groups = ref.read(allGroupsProvider).valueOrNull ?? [];
    TrainingGroupEntity? selected;
    for (final group in groups) {
      if (group.id == _selectedGroupId) {
        selected = group;
        break;
      }
    }

    if (selected?.isUserMember == true) {
      return (ok: true, newlySubmitted: false);
    }

    final dataSource = ref.read(groupDataSourceProvider);
    final hasPending =
        await dataSource.hasUserPendingRequest(_selectedGroupId!);
    if (hasPending) return (ok: true, newlySubmitted: false);

    await ref.read(groupMembershipProvider.notifier).joinGroup(_selectedGroupId!);
    ref.invalidate(userPendingJoinRequestsProvider);
    ref.invalidate(hasUserPendingRequestProvider(_selectedGroupId!));
    return (ok: true, newlySubmitted: true);
  }

  void _selectGroup(String groupId) {
    if (_selectedGroupId == groupId) return;
    setState(() => _selectedGroupId = groupId);
    _notifyCompleteness();
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(allGroupsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen(allGroupsProvider, (previous, next) {
      next.whenData((_) => _syncInitialSelection());
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Grubunu seç',
                style: AppTypography.headlineSmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Antrenman programların ve etkinliklerin seçtiğin gruba göre düzenlenir.',
                style: AppTypography.bodyMedium.copyWith(
                  color: ThemeBrightnessHolder.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Expanded(
          child: groupsAsync.when(
            loading: () => const Center(child: LoadingWidget()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: EmptyStateWidget(
                  icon: Icons.error_outline_rounded,
                  title: 'Gruplar yüklenemedi',
                  description: error.toString(),
                  buttonText: 'Tekrar dene',
                  onButtonPressed: () => ref.invalidate(allGroupsProvider),
                ),
              ),
            ),
            data: (groups) {
              if (groups.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28),
                    child: EmptyStateWidget(
                      icon: Icons.groups_outlined,
                      title: 'Grup bulunamadı',
                      description: 'Şu an katılabileceğin aktif grup yok.',
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
                itemCount: groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final group = groups[index];
                  return _OnboardingGroupTile(
                    group: group,
                    isSelected: _selectedGroupId == group.id,
                    isDark: isDark,
                    onTap: () => _selectGroup(group.id),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
          child: Text(
            'Seçimin admin onayından sonra aktif olur.',
            style: AppTypography.bodySmall.copyWith(
              color: ThemeBrightnessHolder.onSurfaceVariant,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _OnboardingGroupTile extends StatelessWidget {
  const _OnboardingGroupTile({
    required this.group,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final TrainingGroupEntity group;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[];
    if (group.targetDistance != null && group.targetDistance!.isNotEmpty) {
      final distance = group.targetDistance!;
      subtitleParts.add(
        distance.toLowerCase().contains('km') ? distance : '$distance km',
      );
    }
    subtitleParts.add(group.difficultyText);
    if (group.isPerformanceGroup) subtitleParts.add('Performans');
    final subtitle = subtitleParts.join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDark
                ? AppColors.surfaceDark.withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.95),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : (isDark
                      ? AppColors.neutral700.withValues(alpha: 0.45)
                      : AppColors.neutral200),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              GroupAvatar.fromGroup(group, size: 48, borderRadius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: AppTypography.bodySmall.copyWith(
                          color: ThemeBrightnessHolder.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isSelected
                    ? Icon(
                        Icons.check_circle_rounded,
                        key: const ValueKey('selected'),
                        color: AppColors.primary,
                        size: 24,
                      )
                    : Icon(
                        Icons.circle_outlined,
                        key: const ValueKey('unselected'),
                        color: ThemeBrightnessHolder.outline,
                        size: 24,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
