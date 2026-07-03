import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/vdot_calculator.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/report_info_button.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../events/domain/entities/event_entity.dart' show TrainingTypeEntity;
import '../../../events/presentation/providers/event_provider.dart';
import '../providers/group_provider.dart';

const _info = ReportInfo(
  title: 'VDOT & Eşik Pace',
  summary:
      'Üyelerin koşu seviyesini (VDOT) ve buna karşılık gelen eşik temposunu '
      'listeler; antrenman temposu planlamasında temel alınır.',
  terms: [
    ReportInfoTerm('VDOT', 'Koşu performans seviyesini gösteren tahmini değer; yüksek = daha hızlı.'),
    ReportInfoTerm('Eşik Pace', 'Sürdürülebilir tempo sınırı (dk/km); antrenman bölgelerinin referansı.'),
  ],
  takeaways: [
    'Eşik tempoya göre antrenman bölgelerini doğru ayarlayın.',
    'VDOT güncel tutuldukça tempolar daha isabetli olur.',
    'Benzer VDOT’lu sporcular birlikte antrenman yapabilir.',
  ],
);

class VdotThresholdListPage extends ConsumerStatefulWidget {
  const VdotThresholdListPage({super.key});

  @override
  ConsumerState<VdotThresholdListPage> createState() => _VdotThresholdListPageState();
}

class _VdotThresholdListPageState extends ConsumerState<VdotThresholdListPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeUsersAsync = ref.watch(activeUsersProvider);
    final searchQuery = _searchController.text.toLowerCase().trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('VDOT & Eşik Pace'),
        actions: const [ReportInfoButton(info: _info)],
      ),
      body: activeUsersAsync.when(
        data: (users) {
          final usersWithVdot = users
              .where((u) => u.vdot != null && u.vdot! > 0)
              .toList();

          if (usersWithVdot.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.speed,
              title: 'VDOT verisi yok',
              description: 'Henüz VDOT değeri girmiş üye bulunmuyor',
            );
          }

          usersWithVdot.sort((a, b) {
            final paceA = VdotCalculator.getThresholdPace(a.vdot!);
            final paceB = VdotCalculator.getThresholdPace(b.vdot!);
            return paceA.compareTo(paceB);
          });

          final filteredUsers = searchQuery.isEmpty
              ? usersWithVdot
              : usersWithVdot.where((u) =>
                  u.fullName.toLowerCase().contains(searchQuery)).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: AppSearchField(
                  controller: _searchController,
                  hint: 'Ad soyad ara...',
                  onChanged: (_) => setState(() {}),
                  onClear: () => setState(() {}),
                ),
              ),
              Expanded(
                child: filteredUsers.isEmpty
                    ? EmptyStateWidget(
                        icon: Icons.search_off,
                        title: 'Sonuç bulunamadı',
                        description: '"$searchQuery" için sonuç bulunamadı',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = filteredUsers[index];
                          final originalRank = usersWithVdot.indexOf(user) + 1;
                          return _VdotUserTile(
                            user: user,
                            rank: originalRank,
                            onTap: () => _showPaceDetailsSheet(context, ref, user),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: LoadingWidget()),
        error: (error, _) => Center(
          child: ErrorStateWidget(
            title: 'Veriler yüklenemedi',
            message: error.toString(),
            onRetry: () => ref.invalidate(activeUsersProvider),
          ),
        ),
      ),
    );
  }

  void _showPaceDetailsSheet(BuildContext context, WidgetRef ref, UserEntity user) {
    final vdot = user.vdot!;
    final thresholdPaceSec = VdotCalculator.getThresholdPace(vdot);
    final thresholdPace = VdotCalculator.formatPace(thresholdPaceSec);
    final trainingTypesAsync = ref.read(trainingTypesProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (ctx, scrollController) => Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      UserAvatar(
                        size: 44,
                        name: user.fullName,
                        imageUrl: user.avatarUrl,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.fullName,
                              style: AppTypography.titleMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'VDOT ${vdot.toStringAsFixed(1)}',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Eşik: $thresholdPace /km',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: cs.secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                Expanded(
                  child: trainingTypesAsync.when(
                    data: (types) {
                      final activeTypes = types
                          .where((t) =>
                              t.isActive && t.thresholdOffsetMinSeconds != null)
                          .toList()
                        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

                      if (activeTypes.isEmpty) {
                        return Center(
                          child: Text(
                            'Antrenman türü bulunamadı',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        );
                      }

                      return ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: activeTypes.length,
                        itemBuilder: (ctx, index) {
                          final type = activeTypes[index];
                          return _buildTrainingTypePaceRow(ctx, type, vdot);
                        },
                      );
                    },
                    loading: () => const Center(child: LoadingWidget()),
                    error: (_, __) => Center(
                      child: Text(
                        'Antrenman türleri yüklenemedi',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrainingTypePaceRow(
    BuildContext context,
    TrainingTypeEntity type,
    double vdot,
  ) {
    final cs = Theme.of(context).colorScheme;
    final paceRange = VdotCalculator.formatPaceRange(
      vdot,
      type.thresholdOffsetMinSeconds,
      type.thresholdOffsetMaxSeconds,
    );
    if (paceRange == null) return const SizedBox.shrink();

    Color typeColor;
    try {
      final hex = type.color.replaceFirst('#', '');
      typeColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      typeColor = cs.primary;
    }
    if (cs.brightness == Brightness.dark && typeColor.computeLuminance() < 0.45) {
      typeColor = Color.lerp(typeColor, Colors.white, 0.45)!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.fitness_center, size: 18, color: typeColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.displayName,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                if (type.description.isNotEmpty)
                  Text(
                    type.description,
                    style: AppTypography.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$paceRange /km',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
              color: typeColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _VdotUserTile extends StatelessWidget {
  final UserEntity user;
  final int rank;
  final VoidCallback onTap;

  const _VdotUserTile({
    required this.user,
    required this.rank,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vdot = user.vdot!;
    final thresholdPaceSec = VdotCalculator.getThresholdPace(vdot);
    final thresholdPace = VdotCalculator.formatPace(thresholdPaceSec);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: cs.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Center(
                child: Text(
                  '$rank',
                  style: AppTypography.bodyMedium.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            UserAvatar(
              size: 40,
              name: user.fullName,
              imageUrl: user.avatarUrl,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                user.fullName,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'VDOT ${vdot.toStringAsFixed(1)}',
                    style: AppTypography.labelSmall.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$thresholdPace /km',
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.secondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
