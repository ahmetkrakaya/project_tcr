import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/ui/responsive.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../providers/auth_notifier.dart';

/// Şifre sıfırlama linkine tıklandıktan sonra yeni şifre belirleme sayfası
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    _errorMessage = null;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final password = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();
    if (password != confirm) {
      setState(() => _errorMessage = 'Şifreler eşleşmiyor');
      return;
    }

    if (password.length < 6) {
      setState(() => _errorMessage = 'Şifre en az 6 karakter olmalıdır');
      return;
    }

    setState(() => _isLoading = true);
    final error = await ref.read(authNotifierProvider.notifier).updatePassword(password);
    if (!mounted) return;

    setState(() => _isLoading = false);
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }

    ref.read(authNotifierProvider.notifier).completePasswordReset();
    if (mounted) {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.l,
          ),
          child: Column(
            children: [
              _buildLogoBanner(context),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: context.heightPct(0.02)),
                      Text(
                        'Yeni Şifre Belirle',
                        style: AppTypography.headlineMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Hesabınız için yeni bir şifre girin.',
                        style: AppTypography.bodyLarge.copyWith(
                          color: AppColors.neutral500,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.l),
                      AppTextField(
                        controller: _passwordController,
                        label: 'Yeni şifre',
                        hint: 'En az 6 karakter',
                        obscureText: _obscurePassword,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Şifre girin';
                          if (v.length < 6) return 'En az 6 karakter olmalı';
                          return null;
                        },
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.neutral500,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.m),
                      AppTextField(
                        controller: _confirmPasswordController,
                        label: 'Şifre tekrar',
                        hint: 'Şifrenizi tekrar girin',
                        obscureText: _obscureConfirm,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.done,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Şifre tekrarını girin';
                          if (v != _passwordController.text.trim()) return 'Şifreler eşleşmiyor';
                          return null;
                        },
                        onSubmitted: (_) => _submit(),
                        suffix: IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.neutral500,
                          ),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.error.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.l),
                      FilledButton(
                        onPressed: _isLoading ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Şifreyi Güncelle'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoBanner(BuildContext context) {
    final logoSize = context.imageSize(
      min: 96,
      max: 140,
      fractionOfWidth: 0.3,
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: context.responsiveValue(
          small: AppSpacing.l,
          medium: AppSpacing.xl,
          large: AppSpacing.xxl,
        ),
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF5C7A8A),
            Color(0xFF7A9AAD),
            Color(0xFF8FAFC0),
          ],
        ),
      ),
      child: Center(
        child: Image.asset(
          'assets/images/tcr_logo-removed.png',
          width: logoSize,
          height: logoSize,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
