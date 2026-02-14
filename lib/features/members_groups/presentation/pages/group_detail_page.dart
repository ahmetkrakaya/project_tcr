import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../domain/entities/group_entity.dart';
import '../providers/group_provider.dart';

/// Grup Detay Sayfası
class GroupDetailPage extends ConsumerWidget {
  final String groupId;

  const GroupDetailPage({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupByIdProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
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
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: _buildHeader(group),
              ),
              actions: [
                if (isAdminOrCoach)
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
                    _buildInfoSection(group),
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
                    _buildMembersList(membersAsync, isAdminOrCoach, ref),
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

  Widget _buildHeader(TrainingGroupEntity group) {
    final groupColor = _parseColor(group.color);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            groupColor,
            groupColor.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            // Grup başlığında koşan kadın + erkek emojileri,
            // birbirine yakın ve zıt yöne bakacak şekilde
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Solda sola doğru koşan erkek (arka planda)
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
                  child: const Text(
                    '🏃‍♂️',
                    style: TextStyle(fontSize: 40),
                  ),
                ),
                const SizedBox(width: 4),
                // Sağda sola doğru koşan kadın (öne geçmiş gibi)
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
                  child: const Text(
                    '🏃‍♀️',
                    style: TextStyle(fontSize: 40),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              group.name,
              style: AppTypography.headlineSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
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
    );
  }

  Widget _buildInfoSection(TrainingGroupEntity group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.description != null && group.description!.isNotEmpty) ...[
          Text(
            'Açıklama',
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.neutral500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            group.description!,
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            _buildStatCard(
              icon: Icons.people_outline,
              value: '${group.memberCount}',
              label: 'Üye',
            ),
            const SizedBox(width: 12),
            _buildStatCard(
              icon: Icons.speed,
              value: group.difficultyText,
              label: 'Zorluk',
            ),
            if (group.targetDistance != null) ...[
              const SizedBox(width: 12),
              _buildStatCard(
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

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.neutral100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.neutral600),
            const SizedBox(height: 8),
            Text(
              value,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.neutral500,
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
      return Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: groupColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: groupColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle,
                    color: groupColor,
                    size: 20,
                  ),
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
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            text: 'Ayrıl',
            variant: AppButtonVariant.outlined,
            isLoading: isLoading,
            onPressed: () async {
              final confirmed = await _showLeaveConfirmation(context);
              if (confirmed) {
                await ref.read(groupMembershipProvider.notifier).leaveGroup(groupId);
                if (context.mounted) {
                  context.pop();
                }
              }
            },
          ),
        ],
      );
    }

    return AppButton(
      text: 'Gruba Katıl',
      icon: Icons.add,
      isFullWidth: true,
      isLoading: isLoading,
      onPressed: () async {
        try {
          await ref.read(groupMembershipProvider.notifier).joinGroup(groupId);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Gruba katıldınız'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        } on UserAlreadyInGroupException catch (e) {
          if (context.mounted) {
            _showAlreadyInGroupDialog(context, ref, e, groupId);
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Gruba katılırken hata: $e'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      },
    );
  }

  void _showAlreadyInGroupDialog(
    BuildContext context,
    WidgetRef ref,
    UserAlreadyInGroupException e,
    String targetGroupId,
  ) {
    final groupName = e.currentGroupName ?? 'mevcut grup';
    final currentGroupId = e.currentGroupId;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zaten bir gruba üyesiniz'),
        content: Text(
          'Şu an "$groupName" grubuna üyesiniz. Başka bir gruba geçmek için önce bu gruptan ayrılmalısınız.',
        ),
        actions: [
          if (currentGroupId != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final notifier = ref.read(groupMembershipProvider.notifier);
                try {
                  await notifier.leaveGroup(currentGroupId);
                  await notifier.joinGroup(targetGroupId);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Grup değiştirildi, yeni gruba katıldınız'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (err) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('İşlem sırasında hata: $err'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Çıkıp bu gruba katıl'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersList(
    AsyncValue<List<GroupMemberEntity>> membersAsync,
    bool isAdminOrCoach,
    WidgetRef ref,
  ) {
    return membersAsync.when(
      data: (members) {
        if (members.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.neutral100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'Henüz üye yok',
                style: TextStyle(color: AppColors.neutral500),
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
                  color: AppColors.neutral500,
                ),
              ),
              trailing: isAdminOrCoach
                  ? IconButton(
                      icon: const Icon(
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

  Future<bool> _showLeaveConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Gruptan Ayrıl'),
            content: const Text(
              'Bu gruptan ayrılmak istediğinizden emin misiniz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Ayrıl',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
        ) ??
        false;
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
      return AppColors.primary;
    }
  }

}
