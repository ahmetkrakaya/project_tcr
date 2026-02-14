import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../profile/presentation/pages/webview_page.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/ui/responsive.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../providers/auth_notifier.dart';

/// Register Page
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _lastNameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();
  
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;
  bool _isLoading = false;
  bool _isCheckingEmail = false;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(_onEmailFocusChange);
  }

  @override
  void dispose() {
    _emailFocusNode.removeListener(_onEmailFocusChange);
    _lastNameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onEmailFocusChange() {
    if (!_emailFocusNode.hasFocus) {
      _checkEmailAvailability();
    }
  }

  Future<void> _checkEmailAvailability() async {
    final email = _emailController.text.trim();
    
    if (email.isEmpty || !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      setState(() {
        _emailError = null;
      });
      return;
    }

    setState(() {
      _isCheckingEmail = true;
      _emailError = null;
    });

    final exists = await ref.read(authNotifierProvider.notifier).checkEmailExists(email);

    if (!mounted) return;

    setState(() {
      _isCheckingEmail = false;
      if (exists) {
        _emailError = 'Bu email adresi zaten kayıtlı';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.neutral800),
          onPressed: () => context.goNamed(RouteNames.login),
        ),
        title: const Text('Kayıt Ol'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.l,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo Banner - tam genişlik, yan boşluk yok
              // İçerik - padding ile
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: context.heightPct(0.025)),
                      // Başlıklar
                      Text(
                        'TCR Ailesine Katıl!',
                        style: AppTypography.headlineMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bilgilerini girerek hemen başla',
                        style: AppTypography.bodyLarge.copyWith(
                          color: AppColors.neutral500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.l),
                
                // Ad Soyad
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _firstNameController,
                        label: 'Ad',
                        hint: 'Adınız',
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) {
                          // Ad alanında "next" basıldığında soyad alanına geç
                          _lastNameFocusNode.requestFocus();
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ad gerekli';
                          }
                          if (value.length < 2) {
                            return 'En az 2 karakter';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: AppTextField(
                        controller: _lastNameController,
                        focusNode: _lastNameFocusNode,
                        label: 'Soyad',
                        hint: 'Soyadınız',
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) {
                          // Soyad alanında "next" basıldığında email alanına geç
                          _emailFocusNode.requestFocus();
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Soyad gerekli';
                          }
                          if (value.length < 2) {
                            return 'En az 2 karakter';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.m),
                
                // Email
                AppTextField(
                  controller: _emailController,
                  focusNode: _emailFocusNode,
                  label: 'Email',
                  hint: 'ornek@email.com',
                  keyboardType: TextInputType.emailAddress,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[a-zA-Z0-9@._\-+]+'),
                    ),
                  ],
                  textInputAction: TextInputAction.next,
                  prefixIcon: Icons.email_outlined,
                  onSubmitted: (_) {
                    // Email alanında "next" basıldığında şifre alanına geç
                    _passwordFocusNode.requestFocus();
                  },
                  suffix: _isCheckingEmail
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _emailError != null
                          ? Icon(Icons.error, color: AppColors.error)
                          : _emailController.text.isNotEmpty && 
                            RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(_emailController.text)
                              ? Icon(Icons.check_circle, color: AppColors.success)
                              : null,
                  errorText: _emailError,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Email gerekli';
                    }
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                      return 'Geçerli bir email girin';
                    }
                    if (_emailError != null) {
                      return _emailError;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.m),
                
                // Şifre
                AppTextField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  label: 'Şifre',
                  hint: '••••••••',
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  prefixIcon: Icons.lock_outlined,
                  onSubmitted: (_) {
                    // Şifre alanında "next" basıldığında şifre tekrar alanına geç
                    _confirmPasswordFocusNode.requestFocus();
                  },
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Şifre gerekli';
                    }
                    if (value.length < 6) {
                      return 'En az 6 karakter';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Şifre Tekrar
                AppTextField(
                  controller: _confirmPasswordController,
                  focusNode: _confirmPasswordFocusNode,
                  label: 'Şifre Tekrar',
                  hint: '••••••••',
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  prefixIcon: Icons.lock_outlined,
                  onSubmitted: (_) {
                    // Şifre tekrar alanında "done" basıldığında kayıt işlemini başlat
                    if (!_isLoading && _acceptedTerms && _emailError == null && !_isCheckingEmail) {
                      _handleRegister();
                    }
                  },
                  suffix: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Şifre tekrarı gerekli';
                    }
                    if (value != _passwordController.text) {
                      return 'Şifreler eşleşmiyor';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                
                // Kullanım Koşulları
                Row(
                  children: [
                    Checkbox(
                      value: _acceptedTerms,
                      onChanged: (value) {
                        setState(() {
                          _acceptedTerms = value ?? false;
                        });
                      },
                      activeColor: AppColors.primary,
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'Kayıt olarak ',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.neutral600,
                          ),
                          children: [
                            TextSpan(
                              text: 'Kullanım Koşulları',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (context) => const WebViewPage(
                                        url: 'https://www.rivlus.com/terms',
                                        title: 'Kullanım Koşulları',
                                      ),
                                    ),
                                  );
                                },
                            ),
                            const TextSpan(text: ' ve '),
                            TextSpan(
                              text: 'Gizlilik Politikası',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (context) => const WebViewPage(
                                        url: 'https://www.rivlus.com/privacy',
                                        title: 'Gizlilik Politikası',
                                      ),
                                    ),
                                  );
                                },
                            ),
                            const TextSpan(text: '\'nı kabul ediyorum.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Kayıt Ol Butonu
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading || !_acceptedTerms || _emailError != null || _isCheckingEmail 
                        ? null 
                        : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.neutral300,
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
                            'Kayıt Ol',
                            style: AppTypography.buttonText.copyWith(
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                
                      // Giriş Yap Linki
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Zaten hesabın var mı? ',
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.neutral500,
                            ),
                          ),
                          TextButton(
                            onPressed: _isLoading ? null : () => context.goNamed(RouteNames.login),
                            child: Text(
                              'Giriş Yap',
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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

 
  Future<void> _handleRegister() async {
    if (_formKey.currentState?.validate() ?? false) {
      if (!_acceptedTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen kullanım koşullarını kabul edin'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      
      setState(() {
        _isLoading = true;
      });
      
      final result = await ref.read(authNotifierProvider.notifier).signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
      );
      
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });
      
      if (result.isFailure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Kayıt başarısız'),
            backgroundColor: AppColors.error,
          ),
        );
      } else if (result.emailVerificationRequired) {
        context.goNamed(
          RouteNames.verifyEmail,
          queryParameters: {'email': result.email ?? _emailController.text.trim()},
        );
      } else if (result.isSuccess) {
        context.go('/home');
      }
    }
  }
}
