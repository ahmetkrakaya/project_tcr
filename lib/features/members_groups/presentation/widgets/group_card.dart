import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/group_entity.dart';

/// Grup kartı widget'ı
class GroupCard extends StatelessWidget {
  final TrainingGroupEntity group;
  final VoidCallback? onTap;
  final VoidCallback? onJoinLeave;
  final bool isLoading;

  const GroupCard({
    super.key,
    required this.group,
    this.onTap,
    this.onJoinLeave,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final groupColor = _parseColor(group.color);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    
    // Ekran boyutuna göre dinamik boyutlandırma
    final iconSize = isSmallScreen ? 48.0 : 56.0;
    final iconInnerSize = isSmallScreen ? 24.0 : 28.0;
    final padding = isSmallScreen ? 12.0 : 16.0;
    final spacing = isSmallScreen ? 12.0 : 16.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: group.isUserMember
              ? groupColor.withValues(alpha: 0.5)
              : AppColors.neutral200,
          width: group.isUserMember ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Row(
            children: [
              // Grup ikonu
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: groupColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _getIconData(group.icon),
                  color: groupColor,
                  size: iconInnerSize,
                ),
              ),
              SizedBox(width: spacing),
              // Grup bilgileri
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.name,
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: isSmallScreen ? 14 : null,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (group.description != null &&
                        group.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        group.description!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (group.targetDistance != null)
                          _buildInfoChip(
                            icon: Icons.straighten,
                            label: '${group.targetDistance} km',
                            color: groupColor,
                          ),
                        _buildDifficultyChip(group.difficultyLevel),
                      ],
                    ),
                  ],
                ),
              ),
              // Katıl/Ayrıl butonu
              if (onJoinLeave != null)
                isLoading
                    ? SizedBox(
                        width: isSmallScreen ? 20 : 24,
                        height: isSmallScreen ? 20 : 24,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(
                          minWidth: isSmallScreen ? 36 : 48,
                          minHeight: isSmallScreen ? 36 : 48,
                        ),
                        onPressed: onJoinLeave,
                        icon: Icon(
                          group.isUserMember
                              ? Icons.check_circle
                              : Icons.add_circle_outline,
                          color: group.isUserMember
                              ? groupColor
                              : AppColors.neutral400,
                          size: isSmallScreen ? 20 : 24,
                        ),
                      ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildDifficultyChip(int level) {
    final color = _getDifficultyColor(level);
    final text = _getDifficultyText(level);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
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

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'directions_run':
        return Icons.directions_run;
      case 'directions_walk':
        return Icons.directions_walk;
      case 'accessibility_new':
        return Icons.accessibility_new;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'sports':
        return Icons.sports;
      default:
        return Icons.directions_run;
    }
  }

  Color _getDifficultyColor(int level) {
    switch (level) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.lightGreen;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.deepOrange;
      case 5:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getDifficultyText(int level) {
    switch (level) {
      case 1:
        return 'Başlangıç';
      case 2:
        return 'Kolay';
      case 3:
        return 'Orta';
      case 4:
        return 'Zor';
      case 5:
        return 'Çok Zor';
      default:
        return 'Bilinmiyor';
    }
  }
}
