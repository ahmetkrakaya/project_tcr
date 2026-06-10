import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../domain/entities/group_entity.dart';
import '../providers/group_provider.dart';

/// Grup katılım ve değişim talepleri (admin)
class GroupRequestsPage extends ConsumerWidget {
  const GroupRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(allPendingJoinRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grup Talepleri'),
      ),
      body: requestsAsync.when(
        data: (requests) {
          if (requests.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.inbox_outlined,
              title: 'Bekleyen talep yok',
              description: 'Katılım ve grup değişim talepleri burada görünür',
            );
          }

          final joinRequests =
              requests.where((r) => r.isJoin).toList();
          final transferRequests =
              requests.where((r) => r.isTransfer).toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(allPendingJoinRequestsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (joinRequests.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.group_add,
                    title: 'Katılım Talepleri',
                    count: joinRequests.length,
                    iconColor: AppColors.primary,
                  ),
                  const SizedBox(height: 12),
                  ...joinRequests.map(
                    (r) => _RequestCard(
                      request: r,
                      onApprove: () =>
                          _handleApprove(context, ref, r.id, r.groupId),
                      onReject: () =>
                          _handleReject(context, ref, r.id, r.groupId),
                    ),
                  ),
                ],
                if (joinRequests.isNotEmpty && transferRequests.isNotEmpty)
                  const SizedBox(height: 24),
                if (transferRequests.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.swap_horiz,
                    title: 'Grup Değişim Talepleri',
                    count: transferRequests.length,
                    iconColor: AppColors.warning,
                  ),
                  const SizedBox(height: 12),
                  ...transferRequests.map(
                    (r) => _RequestCard(
                      request: r,
                      onApprove: () =>
                          _handleApprove(context, ref, r.id, r.groupId),
                      onReject: () =>
                          _handleReject(context, ref, r.id, r.groupId),
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
            title: 'Talepler yüklenemedi',
            message: error.toString(),
            onRetry: () => ref.invalidate(allPendingJoinRequestsProvider),
          ),
        ),
      ),
    );
  }

  Future<void> _handleApprove(
    BuildContext context,
    WidgetRef ref,
    String requestId,
    String groupId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(joinRequestActionProvider.notifier).approveRequest(
            requestId,
            groupId,
          );
      ref.invalidate(allPendingJoinRequestsProvider);
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Talep onaylandı'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Onay sırasında hata: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleReject(
    BuildContext context,
    WidgetRef ref,
    String requestId,
    String groupId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(joinRequestActionProvider.notifier).rejectRequest(
            requestId,
            groupId,
          );
      ref.invalidate(allPendingJoinRequestsProvider);
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Talep reddedildi'),
            backgroundColor: AppColors.neutral600,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Red sırasında hata: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
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

class _RequestCard extends ConsumerWidget {
  final GroupJoinRequestEntity request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _RequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  String _subtitle() {
    if (request.isTransfer) {
      final from = request.fromGroupName ?? 'Mevcut grup';
      final to = request.groupName ?? 'Hedef grup';
      return '$from → $to • ${_formatDate(request.requestedAt)}';
    }
    return '${request.groupName ?? "Grup"} • ${_formatDate(request.requestedAt)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(joinRequestActionProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: request.isTransfer
          ? AppColors.warningContainer
          : AppColors.primary.withValues(alpha: 0.06),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: UserAvatar(
          size: 44,
          name: request.userName,
          imageUrl: request.userAvatarUrl,
        ),
        title: Text(
          request.userName,
          style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _subtitle(),
          style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: actionState.isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.cancel, color: AppColors.error),
                    tooltip: 'Reddet',
                    visualDensity: VisualDensity.compact,
                    onPressed: onReject,
                  ),
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: AppColors.success),
                    tooltip: 'Onayla',
                    visualDensity: VisualDensity.compact,
                    onPressed: onApprove,
                  ),
                ],
              ),
      ),
    );
  }
}
