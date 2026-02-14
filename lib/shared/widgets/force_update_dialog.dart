import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'app_button.dart';

/// Force update dialog widget
/// Shows a dialog that cannot be dismissed, forcing user to update the app
class ForceUpdateDialog extends StatelessWidget {
  final String message;
  final String? storeUrl;

  const ForceUpdateDialog({
    super.key,
    required this.message,
    this.storeUrl,
  });

  /// Show the force update dialog
  static Future<void> show(BuildContext context, {
    required String message,
    String? storeUrl,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (context) => ForceUpdateDialog(
        message: message,
        storeUrl: storeUrl,
      ),
    );
  }

  Future<void> _openStore(BuildContext context) async {
    if (storeUrl == null || storeUrl!.isEmpty) {
      // Fallback: Show error message if no store URL
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mağaza bağlantısı bulunamadı'),
          ),
        );
      }
      return;
    }

    final uri = Uri.parse(storeUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mağaza açılamadı'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent back button from dismissing
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.system_update,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'Güncelleme Gerekli',
                style: AppTypography.headlineSmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurfaceLight,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Message
              Text(
                message.isNotEmpty
                    ? message
                    : 'Uygulamayı kullanmaya devam etmek için lütfen en son sürüme güncelleyin.',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.onSurfaceVariantLight,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Update Button
              AppButton(
                text: 'Güncelle',
                onPressed: () => _openStore(context),
                variant: AppButtonVariant.primary,
                size: AppButtonSize.large,
                isFullWidth: true,
                icon: Icons.download,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
