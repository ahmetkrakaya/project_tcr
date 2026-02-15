import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/deep_link/deep_link_handler.dart';
import '../../../profile/presentation/pages/webview_page.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/ui/responsive.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../providers/auth_notifier.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';
import '../../../events/presentation/providers/event_provider.dart';

/// Login Page
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _isLoading = false; // Local loading state - router'ı tetiklemez
  String? _errorMessage;

  void _showPasswordResetLinkErrorDialog(String message) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Şifre sıfırlama linki geçersiz'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
      passwordResetLinkErrorNotifier.value = null;
    });
  }

  void _onResetLinkError() {
    final message = passwordResetLinkErrorNotifier.value;
    if (message != null && message.isNotEmpty) {
      _showPasswordResetLinkErrorDialog(message);
    }
  }

  @override
  void initState() {
    super.initState();
    passwordResetLinkErrorNotifier.addListener(_onResetLinkError);
    // Uygulama şifre sıfırlama linkiyle açıldıysa ve link geçersizse mesaj zaten set edilmiş olabilir
    final existing = passwordResetLinkErrorNotifier.value;
    if (existing != null && existing.isNotEmpty) {
      _showPasswordResetLinkErrorDialog(existing);
    }
    // Cold start deep link: bazen oturum splash'ten sonra yüklenir, login'e atılmış oluruz.
    // Zaten giriş yapılmışsa ve pending path varsa doğrudan oraya git.
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirectIfAlreadyAuthenticatedWithPendingLink());
  }

  void _redirectIfAlreadyAuthenticatedWithPendingLink() {
    if (!mounted) return;
    final authState = ref.read(authNotifierProvider);
    if (authState is! AuthAuthenticated) return;
    final path = takePendingDeepLinkPath();
    if (path != null) context.go(path);
  }

  @override
  void dispose() {
    passwordResetLinkErrorNotifier.removeListener(_onResetLinkError);
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // NOT: ref.watch KULLANMIYORUZ - bu router'ı tetikler ve splash'a gider
    // Loading durumu local _isLoading ile yönetiliyor

    // Cold start deep link: oturum login açıldıktan sonra yüklenirse (geç restore) burada yakala
    ref.listen<AuthState>(authNotifierProvider, (prev, next) {
      if (next is AuthAuthenticated) {
        final path = takePendingDeepLinkPath();
        if (path != null && mounted) context.go(path);
      }
    });

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: bottomInset > 0 ? bottomInset + AppSpacing.l : AppSpacing.l,
          ),
          child: Column(
            children: [
              // Logo Banner - tam genişlik, yan boşluk yok
              _buildLogoBanner(context),
              // İçerik - padding ile
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  children: [
                    SizedBox(height: context.heightPct(0.03)),
                    // Başlıklar
                    _buildHeader(),
                    SizedBox(height: context.heightPct(0.03)),
                    // Form
                    _buildSocialLoginButtons(context, ref, _isLoading),
                    const SizedBox(height: AppSpacing.l),
                    _buildTermsText(context),
                  ],
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
      max: 160,
      fractionOfWidth: 0.35,
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
      decoration: BoxDecoration(
        // Mavi-gri tonlarında gradient banner
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF5C7A8A), // Koyu mavi-gri
            Color(0xFF7A9AAD), // Orta mavi-gri
            Color(0xFF8FAFC0), // Açık mavi-gri
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5C7A8A).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
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

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleText = Text(
          AppConstants.appFullName,
          style: AppTypography.displaySmall.copyWith(
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          softWrap: false,
        );

        return Column(
          children: [
            // Başlık, farklı ekran genişliklerinde tek satırda kalacak şekilde ölçeklenir
            SizedBox(
              width: constraints.maxWidth,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: titleText,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Kulübe katılmak için giriş yap',
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.neutral500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmailLoginForm(
    BuildContext context,
    WidgetRef ref,
    bool isLoading,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          AppTextField(
            controller: _emailController,
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
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Email gerekli';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return 'Geçerli bir email girin';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            label: 'Şifre',
            hint: '••••••••',
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            prefixIcon: Icons.lock_outlined,
            onSubmitted: (_) {
              // Şifre alanında "done" basıldığında giriş yap
              if (!_isLoading) {
                _handleEmailLogin(ref);
              }
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
                return 'Şifre en az 6 karakter olmalı';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isLoading ? null : () => _showForgotPasswordDialog(context, ref),
              child: Text(
                'Şifremi Unuttum',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Hata mesajı göster
          if (_errorMessage != null) ...[
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
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: AppColors.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: isLoading ? null : () => _handleEmailLogin(ref),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Giriş Yap',
                      style: AppTypography.buttonText.copyWith(
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Hesabın yok mu? ',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.neutral500,
                ),
              ),
              TextButton(
                onPressed: isLoading ? null : () => context.goNamed(RouteNames.register),
                child: Text(
                  'Kayıt Ol',
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
    );
  }

  Widget _buildSocialLoginButtons(
    BuildContext context,
    WidgetRef ref,
    bool isLoading,
  ) {
    return _buildEmailLoginForm(context, ref, isLoading);
  }


  Widget _buildTermsText(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: 'Devam ederek ',
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.neutral500,
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
          const TextSpan(text: '\'nı kabul etmiş olursun.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Future<void> _handleEmailLogin(WidgetRef ref) async {
    // Hata mesajını temizle ve loading başlat
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });
    
    if (_formKey.currentState?.validate() ?? false) {
      final result = await ref.read(authNotifierProvider.notifier).signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );
      
      if (!mounted) return;
      
      // Loading'i kapat
      setState(() {
        _isLoading = false;
      });
      
      // Hata durumunda mesajı göster
      if (result.isFailure) {
        setState(() {
          _errorMessage = result.error;
        });
      } else if (result.isSuccess) {
        // Başarılı giriş - deep link ile gelindiyse önce oraya git
        final deepLinkPath = takePendingDeepLinkPath();
        if (deepLinkPath != null) {
          context.go(deepLinkPath);
          return;
        }

        // Profil ve grup kontrolü yap
        final user = result.user!;
        
        // Profil tamamlanmamışsa veya gruba üye değilse onboarding'e git
        if (user.firstName == null || user.firstName!.isEmpty) {
          context.goNamed(RouteNames.onboarding);
        } else {
          // Grup üyeliği kontrolü
          try {
            ref.invalidate(userGroupsProvider);
            // Event provider'larını da invalidate et (giriş yapıldığında filtreleme doğru uygulanması için)
            ref.invalidate(thisWeekEventsProvider);
            ref.invalidate(allEventsProvider);
            ref.invalidate(upcomingEventsProvider);
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
    } else {
      // Form validation başarısız - loading'i kapat
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showForgotPasswordDialog(BuildContext context, WidgetRef ref) {
    final emailController = TextEditingController();
    var isSending = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Şifremi Unuttum'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Email adresinizi girin, size şifre sıfırlama bağlantısı göndereceğiz.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  enabled: !isSending,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'ornek@email.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[a-zA-Z0-9@._\-+]+'),
                    ),
                  ],
                ),
                if (isSending) ...[
                  const SizedBox(height: 20),
                  const Center(
                    child: SizedBox(
                      height: 32,
                      width: 32,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSending ? null : () => Navigator.pop(dialogContext),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: isSending
                    ? null
                    : () async {
                        if (emailController.text.isEmpty) return;
                        isSending = true;
                        setDialogState(() {});
                        final success = await ref
                            .read(authNotifierProvider.notifier)
                            .resetPassword(emailController.text.trim());
                        if (dialogContext.mounted) {
                          isSending = false;
                          setDialogState(() {});
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                success
                                    ? 'Şifre sıfırlama bağlantısı gönderildi'
                                    : 'Bir hata oluştu',
                              ),
                              backgroundColor:
                                  success ? AppColors.success : AppColors.error,
                            ),
                          );
                        }
                      },
                child: const Text('Gönder'),
              ),
            ],
          );
        },
      ),
    );
  }
}

