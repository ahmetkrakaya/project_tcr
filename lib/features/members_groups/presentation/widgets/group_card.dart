import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/group_entity.dart';
import 'group_avatar.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// Grup listesi satırı
class GroupCard extends StatelessWidget {
  final TrainingGroupEntity group;
  final VoidCallback? onTap;
  final VoidCallback? onRequestJoin;
  final bool hasPendingRequest;
  final bool isLoading;

  const GroupCard({
    super.key,
    required this.group,
    this.onTap,
    this.onRequestJoin,
    this.hasPendingRequest = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor =
        isDark ? AppColors.neutral400.withValues(alpha: 0.35) : AppColors.neutral200;

    final subtitleParts = <String>[];
    if (group.targetDistance != null && group.targetDistance!.isNotEmpty) {
      final distance = group.targetDistance!;
      subtitleParts.add(distance.toLowerCase().contains('km') ? distance : '$distance km');
    }
    subtitleParts.add(group.difficultyText);
    if (group.isPerformanceGroup) subtitleParts.add('Performans');
    final subtitle = subtitleParts.join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: dividerColor, width: 1)),
          ),
          child: Row(
            children: [
              GroupAvatar.fromGroup(group),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group.name,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.bodySmall.copyWith(
                          color: ThemeBrightnessHolder.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (group.isUserMember)
                _buildMemberBadge()
              else if (onRequestJoin != null)
                _buildJoinAction(onRequestJoin: onRequestJoin!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberBadge() {
    final groupColor = _parseColor(group.color);
    return Tooltip(
      message: 'Üyesiniz',
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: groupColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.check_circle,
          size: 18,
          color: groupColor,
        ),
      ),
    );
  }

  Widget _buildJoinAction({required VoidCallback onRequestJoin}) {
    if (isLoading) {
      return const SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final icon = hasPendingRequest ? Icons.hourglass_top : Icons.group_add;
    final color = hasPendingRequest ? AppColors.warning : AppColors.secondary;
    final tooltip = hasPendingRequest ? 'Talep bekleniyor' : 'Katılım talebi gönder';

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hasPendingRequest ? null : onRequestJoin,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
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
