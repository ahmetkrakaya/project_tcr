import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:project_tcr/core/constants/app_constants.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/ui/responsive.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../providers/auth_notifier.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';

/// Verify Email Page
class VerifyEmailPage extends ConsumerStatefulWidget {
  final String email;

  const VerifyEmailPage({
    super.key,
    required this.email,
  });

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // NOT: ref.watch KULLANMIYORUZ - router'ı tetikler
    // Loading durumu local _isLoading ile yönetiliyor

    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Doğrula'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.login),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: AppSpacing.xl,
            right: AppSpacing.xl,
            top: AppSpacing.xl,
            bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.l,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: context.heightPct(0.03)),
                // Icon
                Icon(
                  Icons.email_outlined,
                  size: 80,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppSpacing.l),
                // Title
                Text(
                  'Email Adresini Doğrula',
                  style: AppTypography.headlineMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.m),
                // Description
                Text(
                  '${widget.email} adresine gönderilen doğrulama kodunu girin.',
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.neutral500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                // Code Input
                AppTextField(
                  controller: _codeController,
                  label: 'Doğrulama Kodu',
                  hint: '8 haneli kod',
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  prefixIcon: Icons.lock_outlined,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Doğrulama kodu gerekli';
                    }
                    if (value.length != 8) {
                      return 'Kod 8 haneli olmalı';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                // Verify Button
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleVerify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Doğrula',
                            style: AppTypography.buttonText.copyWith(
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                // Resend Code
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Kod gelmedi mi? ',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                    TextButton(
                      onPressed: _isResending ? null : _handleResend,
                      child: _isResending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'Tekrar Gönder',
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // Info
                Container(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  decoration: BoxDecoration(
                    color: AppColors.neutral100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Önemli Bilgiler',
                              style: AppTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Doğrulama kodu 8 haneli bir sayıdır\n'
                        '• Kod 10 dakika geçerlidir\n'
                        '• Eğer kodu girmeden uygulamayı kapatırsanız, tekrar kayıt olmanız gerekecektir\n'
                        '• Email doğrulandıktan sonra hesabınız yetkili bir kişi tarafından onaylanana kadar bekleyecektir',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleVerify() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _isLoading = true);
      
      final result = await ref.read(authNotifierProvider.notifier).verifyEmail(
        widget.email,
        _codeController.text.trim(),
      );
      
      if (!mounted) return;
      
      setState(() => _isLoading = false);
      
      // Hata durumunda snackbar göster
      if (result.isFailure) {
        // Pending approval durumunu kontrol et (özel bir hata mesajı)
        final authState = ref.read(authNotifierProvider);
        if (authState is AuthPendingApproval) {
          // Email doğrulandı ama kullanıcı henüz onaylanmamış
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Üyelik isteğiniz alınmıştır. Hesabınız yetkili bir kişi tarafından aktif edildiğinde giriş yapabilirsiniz.',
              ),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 5),
            ),
          );
          // Login sayfasına yönlendir
          context.goNamed(RouteNames.login);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Doğrulama başarısız'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } else if (result.isSuccess) {
        // Başarılı doğrulama - profil ve grup kontrolü yap
        final user = result.user!;
        
        // Profil tamamlanmamışsa veya gruba üye değilse onboarding'e git
        if (user.firstName == null || user.firstName!.isEmpty) {
          context.goNamed(RouteNames.onboarding);
        } else {
          // Grup üyeliği kontrolü
          try {
            ref.invalidate(userGroupsProvider);
            final userGroups = await ref.read(userGroupsProvider.future);
            if (!mounted) return;
            
            if (userGroups.isEmpty) {
              // Gruba üye değil - onboarding'e yönlendir
              context.goNamed(RouteNames.onboarding);
            } else {
              // Her şey tamam - ana sayfaya git
              context.go('/home');
            }
          } catch (e) {
            // Grup kontrolü başarısız olursa yine de ana sayfaya git
            context.go('/home');
          }
        }
      }
    }
  }

  Future<void> _handleResend() async {
    setState(() => _isResending = true);
    
    final success = await ref
        .read(authNotifierProvider.notifier)
        .resendVerificationEmail(widget.email);
    
    setState(() => _isResending = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Doğrulama kodu tekrar gönderildi'
                : 'Doğrulama kodu gönderilemedi',
          ),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }
}
