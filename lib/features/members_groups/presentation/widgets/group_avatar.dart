import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/group_entity.dart';

/// Grup ikonu veya fotoğrafı
class GroupAvatar extends StatelessWidget {
  final String? imageUrl;
  final String icon;
  final String color;
  final double size;
  final double borderRadius;
  final bool isPerformanceGroup;
  final VoidCallback? onTap;

  const GroupAvatar({
    super.key,
    this.imageUrl,
    required this.icon,
    required this.color,
    this.size = 44,
    this.borderRadius = 10,
    this.isPerformanceGroup = false,
    this.onTap,
  });

  factory GroupAvatar.fromGroup(
    TrainingGroupEntity group, {
    double size = 44,
    double? borderRadius,
    VoidCallback? onTap,
  }) {
    return GroupAvatar(
      imageUrl: group.imageUrl,
      icon: group.icon,
      color: group.color,
      size: size,
      borderRadius: borderRadius ?? 10,
      isPerformanceGroup: group.isPerformanceGroup,
      onTap: onTap,
    );
  }

  bool get _hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    Widget avatar;
    if (_hasImage) {
      avatar = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => _iconFallback(),
          errorWidget: (_, __, ___) => _iconFallback(),
        ),
      );
    } else {
      avatar = _iconFallback();
    }

    if (onTap != null && _hasImage) {
      return GestureDetector(onTap: onTap, child: avatar);
    }
    return avatar;
  }

  Widget _iconFallback() {
    final groupColor = _parseColor(color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: groupColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        isPerformanceGroup ? Icons.star : _getIconData(icon),
        color: groupColor,
        size: size * 0.5,
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
      case 'running':
        return Icons.directions_run;
      default:
        return Icons.directions_run;
    }
  }
}
