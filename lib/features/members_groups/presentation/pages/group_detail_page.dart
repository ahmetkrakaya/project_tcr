import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/full_screen_image_viewer.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../chat/presentation/providers/chat_provider.dart';
import '../../domain/entities/group_entity.dart';
import '../providers/group_provider.dart';
import '../widgets/group_avatar.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// Grup Detay Sayfası
class GroupDetailPage extends ConsumerWidget {
  final String groupId;

  const GroupDetailPage({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupByIdProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final isAdmin = ref.watch(isAdminProvider);
    final membershipState = ref.watch(groupMembershipProvider);

    return groupAsync.when(
      data: (group) => Scaffold(
        body: CustomScrollView(
          slivers: [
            // Header
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
              leading: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: _buildHeader(context, group),
              ),
              actions: [
                if (isAdmin)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            context.pushNamed(
                              RouteNames.editGroup,
                              pathParameters: {'groupId': groupId},
                            );
                            break;
                          case 'delete':
                            _showDeleteConfirmation(context, ref);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined),
                              SizedBox(width: 8),
                              Text('Düzenle'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, color: AppColors.error),
                              SizedBox(width: 8),
                              Text('Sil', style: TextStyle(color: AppColors.error)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            // Content
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Grup bilgileri
                    _buildInfoSection(context, group),
                    const SizedBox(height: 24),

                    // Katıl/Ayrıl butonu
                    _buildJoinLeaveButton(context, ref, group, membershipState),
                    const SizedBox(height: 16),

                    // Üyeler
                    Text(
                      'Üyeler (${group.memberCount})',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildMembersList(context, membersAsync, isAdmin, ref),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      loading: () => const Scaffold(
        body: Center(child: LoadingWidget()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: ErrorStateWidget(
            title: 'Grup yüklenemedi',
            message: error.toString(),
            onRetry: () => ref.invalidate(groupByIdProvider(groupId)),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, TrainingGroupEntity group) {
    final groupColor = _parseColor(group.color);
    final hasImage = group.hasImage;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImage)
          GestureDetector(
            onTap: () => showFullScreenImage(context, group.imageUrl!),
            child: CachedNetworkImage(
              imageUrl: group.imageUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [groupColor, groupColor.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [groupColor, groupColor.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: hasImage ? 0.25 : 0.0),
                Colors.black.withValues(alpha: hasImage ? 0.55 : 0.0),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              GroupAvatar.fromGroup(
                group,
                size: hasImage ? 80 : 72,
                borderRadius: hasImage ? 20 : 18,
                onTap: hasImage
                    ? () => showFullScreenImage(context, group.imageUrl!)
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                group.name,
                style: AppTypography.headlineSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              if (group.targetDistance != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Hedef: ${group.targetDistance} km',
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection(BuildContext context, TrainingGroupEntity group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.description != null && group.description!.isNotEmpty) ...[
          Text(
            'Açıklama',
            style: AppTypography.titleSmall.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            group.description!,
            style: AppTypography.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            _buildStatCard(
              context,
              icon: Icons.people_outline,
              value: '${group.memberCount}',
              label: 'Üye',
            ),
            const SizedBox(width: 12),
            _buildStatCard(
              context,
              icon: Icons.speed,
              value: group.difficultyText,
              label: 'Zorluk',
            ),
            if (group.targetDistance != null) ...[
              const SizedBox(width: 12),
              _buildStatCard(
                context,
                icon: Icons.straighten,
                value: '${group.targetDistance} km',
                label: 'Mesafe',
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          children: [
            Icon(icon, color: cs.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinLeaveButton(
    BuildContext context,
    WidgetRef ref,
    TrainingGroupEntity group,
    AsyncValue<void> membershipState,
  ) {
    final isLoading = membershipState is AsyncLoading;
    final groupColor = _parseColor(group.color);

    if (group.isUserMember) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: groupColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: groupColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: groupColor, size: 20),
            const SizedBox(width: 8),
            Text(
              'Bu Grubun Üyesisiniz',
              style: AppTypography.labelLarge.copyWith(
                color: groupColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final hasPendingAsync = ref.watch(hasUserPendingRequestProvider(groupId));
    final hasPending = hasPendingAsync.value ?? false;
    final allGroups = ref.watch(allGroupsProvider).valueOrNull ?? [];
    final isTransfer = allGroups.any((g) => g.isUserMember);

    if (hasPending) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_top, color: AppColors.warning, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isTransfer ? 'Grup değişim talebi bekleniyor' : 'Katılım talebi bekleniyor',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                final dataSource = ref.read(groupDataSourceProvider);
                await dataSource.cancelJoinRequest(groupId);
                ref.invalidate(hasUserPendingRequestProvider(groupId));
                ref.invalidate(userPendingJoinRequestsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Talep iptal edildi')),
                  );
                }
              },
              child: const Text('İptal Et'),
            ),
          ],
        ),
      );
    }

    return AppButton(
      text: isTransfer ? 'Grup Değişim Talebi Gönder' : 'Katılım Talebi Gönder',
      icon: Icons.send,
      isFullWidth: true,
      isLoading: isLoading,
      onPressed: () async {
        try {
          await ref.read(groupMembershipProvider.notifier).joinGroup(groupId);
          ref.invalidate(hasUserPendingRequestProvider(groupId));
          ref.invalidate(userPendingJoinRequestsProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isTransfer
                      ? 'Grup değişim talebi gönderildi. Admin onayı bekleniyor.'
                      : 'Katılım talebi gönderildi. Admin onayı bekleniyor.',
                ),
                backgroundColor: AppColors.success,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Talep gönderilirken hata: $e'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      },
    );
  }

  Widget _buildMembersList(
    BuildContext context,
    AsyncValue<List<GroupMemberEntity>> membersAsync,
    bool isAdmin,
    WidgetRef ref,
  ) {
    final cs = Theme.of(context).colorScheme;
    final blockedIds = ref.watch(blockedUserIdsProvider).valueOrNull ?? [];

    return membersAsync.when(
      data: (allMembers) {
        final members = blockedIds.isEmpty
            ? allMembers
            : allMembers.where((m) => !blockedIds.contains(m.userId)).toList();
        if (members.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Center(
              child: Text(
                'Henüz üye yok',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: members.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final member = members[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              // Biraz daha rahat bir yükseklik için hafif negatif yoğunluk
              visualDensity: const VisualDensity(vertical: -1),
              onTap: () => context.pushNamed(
                RouteNames.userProfile,
                pathParameters: {'userId': member.userId},
              ),
              leading: UserAvatar(
                size: 44,
                name: member.userName,
                imageUrl: member.userAvatarUrl,
              ),
              title: Text(
                member.userName,
                style: AppTypography.bodyMedium,
              ),
              subtitle: Text(
                'Katılım: ${_formatDate(member.joinedAt)}',
                style: AppTypography.bodySmall.copyWith(
                  color: ThemeBrightnessHolder.onSurfaceVariant,
                ),
              ),
              trailing: isAdmin
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.swap_horiz, color: cs.primary),
                          tooltip: 'Gruba Taşı',
                          onPressed: () => _showTransferMemberDialog(context, ref, member),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.remove_circle_outline,
                            color: AppColors.error,
                          ),
                          onPressed: () async {
                            final confirmed = await _showRemoveMemberConfirmation(
                              context,
                              member.userName,
                            );
                            if (confirmed) {
                              final dataSource = ref.read(groupDataSourceProvider);
                              await dataSource.removeMemberFromGroup(
                                groupId,
                                member.userId,
                              );
                              ref.invalidate(groupMembersProvider(groupId));
                              ref.invalidate(groupByIdProvider(groupId));
                            }
                          },
                        ),
                      ],
                    )
                  : null,
            );
          },
        );
      },
      loading: () => const Center(child: LoadingWidget(size: 24)),
      error: (_, __) => const Text('Üyeler yüklenemedi'),
    );
  }

  void _showTransferMemberDialog(BuildContext context, WidgetRef ref, GroupMemberEntity member) async {
    final groupsAsync = await ref.read(allGroupsProvider.future);
    final otherGroups = groupsAsync.where((g) => g.id != groupId).toList();

    if (otherGroups.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Taşınabilecek başka grup yok')),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (ctx, scrollController) {
          final sheetCs = Theme.of(ctx).colorScheme;
          return Container(
          decoration: BoxDecoration(
            color: sheetCs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: sheetCs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${member.userName} - Gruba Taşı',
                  style: AppTypography.titleLarge,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: otherGroups.length,
                  itemBuilder: (ctx, index) {
                    final targetGroup = otherGroups[index];
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _parseColor(targetGroup.color).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.groups,
                          color: _parseColor(targetGroup.color),
                          size: 20,
                        ),
                      ),
                      title: Text(targetGroup.name),
                      subtitle: targetGroup.targetDistance != null
                          ? Text('Hedef: ${targetGroup.targetDistance}')
                          : null,
                      onTap: () async {
                        Navigator.pop(ctx);
                        try {
                          await ref.read(memberTransferProvider.notifier).transferMember(
                            member.userId,
                            targetGroup.id,
                            fromGroupId: groupId,
                          );
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('${member.userName} "${targetGroup.name}" grubuna taşındı'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Taşıma sırasında hata: $e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
        },
      ),
    );
  }

  Future<bool> _showRemoveMemberConfirmation(
    BuildContext context,
    String memberName,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Üyeyi Çıkar'),
            content: Text(
              '$memberName adlı üyeyi gruptan çıkarmak istediğinizden emin misiniz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Çıkar',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref) {
    final pageContext = context; // Sayfa context'i (dialog kapanınca bunu kullanacağız)
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Grubu Sil'),
        content: const Text(
          'Bu grubu silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await ref.read(groupDeleteProvider.notifier).deleteGroup(groupId);
                // Silme başarılı - direkt liste sayfasına dön
                if (pageContext.mounted) {
                  pageContext.goNamed(RouteNames.groups);
                }
              } catch (e) {
                if (pageContext.mounted) {
                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    SnackBar(
                      content: Text('Grup silinirken hata oluştu: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Sil',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Color _parseColor(String colorHex) {
    try {
      final hex = colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return ThemeBrightnessHolder.primary;
    }
  }

}
