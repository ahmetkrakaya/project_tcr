import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'app_button.dart';

/// Empty State Widget
class EmptyStateWidget extends StatelessWidget {
  final IconData? icon;
  final String? imagePath;
  final String title;
  final String? description;
  final String? buttonText;
  final VoidCallback? onButtonPressed;
  final double iconSize;

  const EmptyStateWidget({
    super.key,
    this.icon,
    this.imagePath,
    required this.title,
    this.description,
    this.buttonText,
    this.onButtonPressed,
    this.iconSize = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (imagePath != null)
              Image.asset(
                imagePath!,
                width: 200,
                height: 200,
              )
            else if (icon != null)
              Container(
                width: iconSize + 40,
                height: iconSize + 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: iconSize,
                  color: AppColors.primary.withValues(alpha: 0.7),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              title,
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.neutral700,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.neutral500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (buttonText != null && onButtonPressed != null) ...[
              const SizedBox(height: 24),
              AppButton(
                text: buttonText!,
                onPressed: onButtonPressed,
                variant: AppButtonVariant.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error State Widget
class ErrorStateWidget extends StatelessWidget {
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final IconData icon;

  const ErrorStateWidget({
    super.key,
    this.title,
    this.message,
    this.onRetry,
    this.icon = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.errorContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 60,
                color: AppColors.error.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title ?? 'Bir Hata Oluştu',
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.neutral700,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.neutral500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              AppButton(
                text: 'Tekrar Dene',
                onPressed: onRetry,
                icon: Icons.refresh,
                variant: AppButtonVariant.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// No Connection Widget
class NoConnectionWidget extends StatelessWidget {
  final VoidCallback? onRetry;

  const NoConnectionWidget({
    super.key,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorStateWidget(
      icon: Icons.wifi_off,
      title: 'İnternet Bağlantısı Yok',
      message: 'Lütfen internet bağlantınızı kontrol edin ve tekrar deneyin.',
      onRetry: onRetry,
    );
  }
}

/// İçerik bulunamadı / silinmiş (bildirimden gelindiğinde vb.) için kullanıcı dostu ekran.
/// Tüm detay sayfalarında aynı deneyimi sunar.
class ContentNotFoundWidget extends StatelessWidget {
  final VoidCallback? onGoToNotifications;
  final VoidCallback? onBack;

  const ContentNotFoundWidget({
    super.key,
    this.onGoToNotifications,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.neutral200,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off,
                size: 56,
                color: AppColors.neutral500,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'İçerik Bulunamadı',
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.neutral700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Bu içerik artık mevcut değil veya silinmiş olabilir.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.neutral500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (onGoToNotifications != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppButton(
                  text: 'Bildirimlere Dön',
                  onPressed: onGoToNotifications,
                  icon: Icons.notifications_outlined,
                  variant: AppButtonVariant.primary,
                ),
              ),
            if (onBack != null)
              AppButton(
                text: 'Geri Dön',
                onPressed: onBack,
                variant: AppButtonVariant.outlined,
              ),
          ],
        ),
      ),
    );
  }
}
