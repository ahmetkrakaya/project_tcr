import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';

/// User Avatar Widget
class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? name;
  final double size;
  final VoidCallback? onTap;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;
  final bool isOnline;

  const UserAvatar({
    super.key,
    this.imageUrl,
    this.name,
    this.size = 48,
    this.onTap,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: showBorder
            ? Border.all(
                color: borderColor ?? AppColors.primary,
                width: borderWidth,
              )
            : null,
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _buildPlaceholder(),
                errorWidget: (_, __, ___) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );

    if (isOnline) {
      avatar = Stack(
        children: [
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.25,
              height: size * 0.25,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatar,
      );
    }

    return avatar;
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.primaryContainer,
      child: Center(
        child: name != null && name!.isNotEmpty
            ? Text(
                _getInitials(name!),
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.bold,
                ),
              )
            : Icon(
                Icons.person,
                color: AppColors.primary,
                size: size * 0.5,
              ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }
}

/// Avatar Group Widget
class AvatarGroup extends StatelessWidget {
  final List<String?> imageUrls;
  final List<String?>? names;
  final double size;
  final int maxCount;
  final double overlap;
  final int? totalCount;

  const AvatarGroup({
    super.key,
    required this.imageUrls,
    this.names,
    this.size = 32,
    this.maxCount = 4,
    this.overlap = 0.3,
    this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final displayCount = imageUrls.length > maxCount ? maxCount : imageUrls.length;
    final remaining = (totalCount ?? imageUrls.length) - displayCount;

    return SizedBox(
      width: size + (displayCount - 1) * size * (1 - overlap) + (remaining > 0 ? size * (1 - overlap) : 0),
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < displayCount; i++)
            Positioned(
              left: i * size * (1 - overlap),
              child: UserAvatar(
                imageUrl: imageUrls[i],
                name: names?[i],
                size: size,
                showBorder: true,
                borderColor: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
          if (remaining > 0)
            Positioned(
              left: displayCount * size * (1 - overlap),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: AppColors.neutral200,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    '+$remaining',
                    style: TextStyle(
                      color: AppColors.neutral700,
                      fontSize: size * 0.35,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Role Badge Avatar
class RoleAvatarBadge extends StatelessWidget {
  final String? imageUrl;
  final String? name;
  final String role; // 'super_admin', 'coach', 'member'
  final double size;

  const RoleAvatarBadge({
    super.key,
    this.imageUrl,
    this.name,
    required this.role,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        UserAvatar(
          imageUrl: imageUrl,
          name: name,
          size: size,
        ),
        if (role != 'member')
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: _getBadgeColor(),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              child: Icon(
                _getBadgeIcon(),
                color: Colors.white,
                size: size * 0.25,
              ),
            ),
          ),
      ],
    );
  }

  Color _getBadgeColor() {
    switch (role) {
      case 'super_admin':
        return AppColors.superAdmin;
      case 'coach':
        return AppColors.coach;
      default:
        return AppColors.member;
    }
  }

  IconData _getBadgeIcon() {
    switch (role) {
      case 'super_admin':
        return Icons.shield;
      case 'coach':
        return Icons.sports;
      default:
        return Icons.person;
    }
  }
}
