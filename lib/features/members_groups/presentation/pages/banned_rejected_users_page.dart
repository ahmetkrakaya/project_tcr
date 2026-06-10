import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../providers/group_provider.dart';

/// Engellenen ve reddedilen kullanıcılar sayfası (sadece admin erişimli)
class BannedRejectedUsersPage extends ConsumerWidget {
  const BannedRejectedUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(rejectedBannedUsersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Engellenen ve Reddedilenler'),
      ),
      body: usersAsync.when(
        data: (users) {
          if (users.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.shield_outlined,
              title: 'Kayıt yok',
              description:
                  'Engellenen veya reddedilen kullanıcılar burada görünür',
            );
          }

          final banned = users.where((u) => u.isBanned).toList();
          final rejected = users.where((u) => u.isRejected).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(rejectedBannedUsersProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (banned.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.block,
                    title: 'Engellenenler',
                    count: banned.length,
                    iconColor: AppColors.error,
                  ),
                  const SizedBox(height: 12),
                  ...banned.map(
                    (u) => _UserCard(
                      user: u,
                      statusLabel: 'Engellendi',
                      statusColor: AppColors.error,
                      actionIcon: Icons.restore,
                      actionTooltip: 'Aktif Et',
                      onAction: () => _handleReactivate(context, ref, u),
                    ),
                  ),
                ],
                if (banned.isNotEmpty && rejected.isNotEmpty)
                  const SizedBox(height: 24),
                if (rejected.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.person_off_outlined,
                    title: 'Reddedilenler',
                    count: rejected.length,
                    iconColor: AppColors.warning,
                  ),
                  const SizedBox(height: 12),
                  ...rejected.map(
                    (u) => _UserCard(
                      user: u,
                      statusLabel: 'Reddedildi',
                      statusColor: AppColors.warning,
                      actionIcon: Icons.check_circle,
                      actionTooltip: 'Kabul Et',
                      onAction: () => _handleApprove(context, ref, u),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: LoadingWidget()),
        error: (error, _) => Center(
          child: ErrorStateWidget(
            title: 'Yüklenemedi',
            message: error.toString(),
            onRetry: () => ref.invalidate(rejectedBannedUsersProvider),
          ),
        ),
      ),
    );
  }

  Future<void> _handleReactivate(
    BuildContext context,
    WidgetRef ref,
    UserEntity user,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Üyeyi Aktif Et'),
        content: Text(
          '${user.fullName} adlı kullanıcının engeli kaldırılacak ve uygulamaya erişimi yeniden açılacak. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Aktif Et',
              style: TextStyle(color: AppColors.success),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(userApprovalProvider.notifier).reactivateUser(user.id);

    final approvalState = ref.read(userApprovalProvider);
    if (approvalState is AsyncError) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Hata: ${approvalState.error}'),
          backgroundColor: AppColors.error,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${user.fullName} yeniden aktif edildi'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _handleApprove(
    BuildContext context,
    WidgetRef ref,
    UserEntity user,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Üyeliği Kabul Et'),
        content: Text(
          '${user.fullName} adlı kullanıcının üyelik başvurusu kabul edilecek ve aktif üyeler listesine eklenecek. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Kabul Et',
              style: TextStyle(color: AppColors.success),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(userApprovalProvider.notifier).approveUser(user.id);

    final approvalState = ref.read(userApprovalProvider);
    if (approvalState is AsyncError) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Hata: ${approvalState.error}'),
          backgroundColor: AppColors.error,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${user.fullName} kabul edildi'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final Color iconColor;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 8),
        Text(
          '$title ($count)',
          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _UserCard extends ConsumerWidget {
  final UserEntity user;
  final String statusLabel;
  final Color statusColor;
  final IconData actionIcon;
  final String actionTooltip;
  final VoidCallback onAction;

  const _UserCard({
    required this.user,
    required this.statusLabel,
    required this.statusColor,
    required this.actionIcon,
    required this.actionTooltip,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approvalState = ref.watch(userApprovalProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: UserAvatar(
          size: 44,
          name: user.fullName,
          imageUrl: user.avatarUrl,
        ),
        title: Text(
          user.fullName,
          style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLabel,
                style: AppTypography.labelSmall.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        trailing: approvalState.isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: Icon(actionIcon, color: AppColors.success),
                tooltip: actionTooltip,
                visualDensity: VisualDensity.compact,
                onPressed: onAction,
              ),
      ),
    );
  }
}
