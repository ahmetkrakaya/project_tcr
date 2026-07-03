import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../providers/user_points_leaderboard_provider.dart';

class UserPointsLeaderboardPage extends ConsumerWidget {
  const UserPointsLeaderboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final isAdmin = ref.watch(isAdminProvider);
    final dataAsync = ref.watch(userPointsLeaderboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kullanıcı Puanları'),
      ),
      body: !isAdmin
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Bu sayfaya erişim yetkiniz yok.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : dataAsync.when(
              data: (items) {
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(userPointsLeaderboardProvider);
                    await ref.read(userPointsLeaderboardProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: cs.outlineVariant,
                    ),
                    itemBuilder: (context, index) {
                      final e = items[index];
                      final rank = index + 1;

                      return ListTile(
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            UserAvatar(
                              imageUrl: e.avatarUrl,
                              name: e.fullName,
                              size: 44,
                              showBorder: false,
                            ),
                            Positioned(
                              left: -6,
                              top: -6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: cs.surface,
                                    width: 2,
                                  ),
                                ),
                                child: Text(
                                  '$rank',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: isDark
                                        ? Colors.white
                                        : cs.onPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          e.fullName,
                          style: AppTypography.titleSmall.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.warningLight
                                    .withValues(alpha: 0.18)
                                : const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(12),
                            border: isDark
                                ? Border.all(
                                    color: AppColors.warningLight
                                        .withValues(alpha: 0.35),
                                  )
                                : null,
                          ),
                          child: Text(
                            '${e.points}',
                            style: AppTypography.titleSmall.copyWith(
                              color: isDark
                                  ? AppColors.warningLight
                                  : const Color(0xFFFF8F00),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Puanlar yüklenemedi: $err',
                    style: AppTypography.bodyMedium.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
    );
  }
}

