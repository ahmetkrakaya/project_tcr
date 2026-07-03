import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../providers/group_provider.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// Yaklaşan Doğum Günleri Sayfası
class UpcomingBirthdaysPage extends ConsumerWidget {
  const UpcomingBirthdaysPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final birthdaysAsync = ref.watch(upcomingBirthdaysProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yaklaşan Doğum Günleri'),
      ),
      body: birthdaysAsync.when(
        data: (users) {
          if (users.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.cake_outlined,
              title: 'Yaklaşan doğum günü yok',
              description:
                  'Önümüzdeki 2 gün içinde doğum günü olan üyeler burada görünecek',
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(activeUsersProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return _BirthdayCard(user: user);
              },
            ),
          );
        },
        loading: () => const Center(child: LoadingWidget()),
        error: (error, _) => Center(
          child: ErrorStateWidget(
            title: 'Doğum günleri yüklenemedi',
            message: error.toString(),
            onRetry: () => ref.invalidate(activeUsersProvider),
          ),
        ),
      ),
    );
  }
}

class _BirthdayCard extends StatelessWidget {
  final UserEntity user;

  const _BirthdayCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final daysRemaining = birthdayDaysRemaining(user);
    final age = birthdayAge(user);
    final isToday = daysRemaining == 0;
    final isYesterday = daysRemaining == -1;

    // Doğum tarihi formatı (gün Ay)
    final birthDateFormatted = user.birthDate != null
        ? DateFormat('d MMMM', 'tr_TR').format(user.birthDate!)
        : '';

    // Kullanıcının ana rolünü belirle
    final primaryRole = user.isAdmin
        ? 'super_admin'
        : user.isCoach
            ? 'coach'
            : 'member';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isToday ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isToday
            ? const BorderSide(color: AppColors.warning, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.pushNamed(
          RouteNames.userProfile,
          pathParameters: {'userId': user.id},
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              Stack(
                clipBehavior: Clip.none,
                children: [
                  RoleAvatarBadge(
                    size: 52,
                    name: user.fullName,
                    imageUrl: user.avatarUrl,
                    role: primaryRole,
                  ),
                  if (isToday)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          '🎂',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              // Bilgiler
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.cake_outlined,
                          size: 14,
                          color: ThemeBrightnessHolder.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          birthDateFormatted,
                          style: AppTypography.bodySmall.copyWith(
                            color: ThemeBrightnessHolder.onSurfaceVariant,
                          ),
                        ),
                        if (age > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '$age yaşına ${isYesterday || (daysRemaining < 0) ? 'girdi' : 'giriyor'}',
                            style: AppTypography.bodySmall.copyWith(
                              color: ThemeBrightnessHolder.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Gün bilgisi badge
              _buildDayBadge(daysRemaining),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayBadge(int daysRemaining) {
    String text;
    Color bgColor;
    Color textColor;

    if (daysRemaining == 0) {
      text = 'Bugün!';
      bgColor = AppColors.warning;
      textColor = Colors.white;
    } else if (daysRemaining == -1) {
      text = 'Dün';
      bgColor = AppColors.neutral300;
      textColor = AppColors.neutral700;
    } else if (daysRemaining == 1) {
      text = 'Yarın';
      bgColor = AppColors.warningContainer;
      textColor = AppColors.warning;
    } else {
      text = '$daysRemaining gün';
      bgColor = AppColors.primaryContainer;
      textColor = AppColors.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: AppTypography.labelSmall.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
