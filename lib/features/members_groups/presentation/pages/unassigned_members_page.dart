import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../providers/group_provider.dart';

/// Adminlerin, herhangi bir gruba dahil olmayan aktif üyeleri atayabildiği sayfa.
class UnassignedMembersPage extends ConsumerStatefulWidget {
  const UnassignedMembersPage({super.key});

  @override
  ConsumerState<UnassignedMembersPage> createState() =>
      _UnassignedMembersPageState();
}

class _UnassignedMembersPageState extends ConsumerState<UnassignedMembersPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Sayfa açıldığında listeyi güncel çekmek için cache'i invalidation ediyoruz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(unassignedUsersProvider);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final unassignedUsersAsync = ref.watch(unassignedUsersProvider);
    final searchQuery = _searchController.text.toLowerCase().trim();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBackground =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final pageSurface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        backgroundColor: pageSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Gruba Dahil Olmayan Üyeler'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AppSearchField(
                controller: _searchController,
                hint: 'Üye ara...',
                onChanged: (_) => setState(() {}),
                onClear: () => setState(() {}),
              ),
            ),
            Expanded(
              child: unassignedUsersAsync.when(
                data: (users) {
                  if (!isAdmin) {
                    return const EmptyStateWidget(
                      icon: Icons.lock_outline,
                      title: 'Yetki yok',
                      description: 'Bu sayfayı sadece adminler görüntüleyebilir.',
                    );
                  }

                  final filteredUsers = searchQuery.isEmpty
                      ? users
                      : users.where((u) {
                          final fullName = u.fullName.toLowerCase();
                          final email = u.email.toLowerCase();
                          return fullName.contains(searchQuery) ||
                              email.contains(searchQuery);
                        }).toList();

                  if (filteredUsers.isEmpty) {
                    return EmptyStateWidget(
                      icon: searchQuery.isEmpty
                          ? Icons.group_off
                          : Icons.search_off,
                      title: searchQuery.isEmpty
                          ? 'Henüz gruba dahil olmayan üye yok'
                          : 'Sonuç bulunamadı',
                      description: searchQuery.isEmpty
                          ? 'Aktif üyeler bir gruba atanıncaya kadar burada görünür.'
                          : '"$searchQuery" için sonuç bulunamadı',
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(unassignedUsersProvider);
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: filteredUsers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final user = filteredUsers[index];
                        final primaryRole = user.isAdmin
                            ? 'super_admin'
                            : user.isCoach
                                ? 'coach'
                                : 'member';

                        return _UnassignedUserCard(
                          user: user,
                          role: primaryRole,
                          onAssignPressed: () =>
                              _showAssignToGroupDialog(context, user),
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(child: LoadingWidget()),
                error: (error, _) => Center(
                  child: ErrorStateWidget(
                    title: 'Üyeler yüklenemedi',
                    message: error.toString(),
                    onRetry: () => ref.invalidate(unassignedUsersProvider),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAssignToGroupDialog(
    BuildContext context,
    UserEntity user,
  ) async {
    final groupsAsync = await ref.read(allGroupsProvider.future);
    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetSurface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final messenger = ScaffoldMessenger.of(context);
    if (groupsAsync.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Henüz grup oluşturulmamış')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.45,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: BoxDecoration(
            color: sheetSurface,
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
                      child: Text(
                        '${user.fullName} - Gruba Ata',
                        style: AppTypography.titleLarge.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: groupsAsync.length,
                  itemBuilder: (ctx, index) {
                    final group = groupsAsync[index];
                    final groupColor = _parseGroupColor(group.color);

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      elevation: 0,
                      color: groupColor.withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: groupColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.groups,
                            color: groupColor,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          group.name,
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: group.targetDistance != null
                            ? Text('Hedef: ${group.targetDistance}')
                            : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          Navigator.pop(ctx);
                          try {
                            await ref
                                .read(memberTransferProvider.notifier)
                                .transferMember(user.id, group.id);
                            ref.invalidate(unassignedUsersProvider);
                            ref.invalidate(activeUsersProvider);
                            ref.invalidate(allGroupsProvider);

                            if (context.mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${user.fullName} "${group.name}" grubuna atandı',
                                  ),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            }
                          } catch (_) {
                            if (context.mounted) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Gruba atama başarısız. Lütfen tekrar deneyin.',
                                  ),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseGroupColor(String colorHex) {
    try {
      final hex = colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }
}

class _UnassignedUserCard extends StatelessWidget {
  final UserEntity user;
  final String role;
  final VoidCallback onAssignPressed;

  const _UnassignedUserCard({
    required this.user,
    required this.role,
    required this.onAssignPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardSurface = isDark ? AppColors.surfaceVariantDark : AppColors.surfaceLight;
    final cardBorder = isDark ? AppColors.neutral400 : AppColors.neutral200;

    return Container(
      decoration: BoxDecoration(
        color: cardSurface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            RoleAvatarBadge(
              size: 48,
              name: user.fullName,
              imageUrl: user.avatarUrl,
              role: role,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.fullName,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.neutral500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              text: 'Gruba Ata',
              icon: Icons.group_add,
              variant: AppButtonVariant.primary,
              size: AppButtonSize.small,
              onPressed: onAssignPressed,
            ),
          ],
        ),
      ),
    );
  }
}

