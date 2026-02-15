import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/deep_link/deep_link_handler.dart';
import '../../../../core/notifications/notification_handler.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/update_check_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/ui/responsive.dart';
import '../../../../shared/widgets/force_update_dialog.dart';
import '../providers/auth_notifier.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';

/// Splash Page
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.5, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.5, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();
    _checkUpdateAndAuth();
  }

  Future<void> _checkUpdateAndAuth() async {
    // Minimum splash süresi
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;

    // Deep link path main()'de erkenden set edildi (intent kaybı olmasın diye)

    // Önce güncelleme kontrolü yap
    final updateResult = await UpdateCheckService.checkForUpdate();
    
    if (!mounted) return;

    // Zorunlu güncelleme varsa dialog göster ve auth kontrolüne geçme
    if (updateResult.isForceUpdate) {
      final message = updateResult.versionInfo?.message ??
          'Uygulamayı kullanmaya devam etmek için lütfen en son sürüme güncelleyin.';
      final storeUrl = updateResult.storeUrl;
      
      ForceUpdateDialog.show(
        context,
        message: message,
        storeUrl: storeUrl,
      );
      return; // Auth kontrolüne geçme, güncelleme yapılana kadar bekle
    }

    // Güncelleme yoksa normal auth akışına devam et
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    if (!mounted) return;

    // Auth durumunu kontrol et; loading/initial ise bekle
    var authState = ref.read(authNotifierProvider);

    int retryCount = 0;
    while ((authState is AuthLoading || authState is AuthInitial) && retryCount < 10) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      authState = ref.read(authNotifierProvider);
      retryCount++;
    }

    if (!mounted) return;

    // Hâlâ loading/initial ise ve pending deep link varsa → splash'te kal, listener ile bekle
    if ((authState is AuthLoading || authState is AuthInitial) && pendingDeepLinkPath != null) {
      if (kDebugMode) debugPrint('TCR_DEEPLINK splash: auth not ready, waiting with listener...');
      _waitForAuthWithListener();
      return;
    }

    _navigateBasedOnAuth(authState);
  }

  /// Auth henüz hazır değilken splash'te kalır, auth state değişince yönlendirir.
  void _waitForAuthWithListener() {
    ref.listenManual<AuthState>(authNotifierProvider, (prev, next) {
      if (!mounted) return;
      if (next is AuthLoading || next is AuthInitial) return; // hâlâ bekliyor
      _navigateBasedOnAuth(next);
    });
  }

  /// Auth durumuna göre doğru sayfaya yönlendirir.
  Future<void> _navigateBasedOnAuth(AuthState authState) async {
    if (!mounted) return;
    
    if (authState is AuthNeedsPasswordReset) {
      context.go('/reset-password');
      return;
    }

    if (authState is AuthAuthenticated) {
      final router = ref.read(appRouterProvider);

      // Deep link ile açıldıysa doğrudan ilgili sayfaya git (etkinlik / market)
      final deepLinkPath = takePendingDeepLinkPath();
      if (deepLinkPath != null) {
        if (kDebugMode) debugPrint('TCR_DEEPLINK splash: navigating to $deepLinkPath');
        context.go(deepLinkPath);
        _navigateFromPendingNotificationAfterFrame(router);
        return;
      }

      final user = authState.user;

      // Profil tamamlanmamışsa onboarding'e git
      if (user.firstName == null || user.firstName!.isEmpty) {
        context.goNamed(RouteNames.onboarding);
        _navigateFromPendingNotificationAfterFrame(router);
        return;
      }

      // Grup üyeliği kontrolü
      try {
        final userGroups = await ref.read(userGroupsProvider.future);
        if (!mounted) return;
        
        if (userGroups.isEmpty) {
          // Gruba üye değil - onboarding'e yönlendir
          context.goNamed(RouteNames.onboarding);
        } else {
          // Her şey tamam - ana sayfaya git
          context.go('/home');
        }
        _navigateFromPendingNotificationAfterFrame(router);
      } catch (e) {
        // Grup kontrolü başarısız olursa yine de ana sayfaya git
        context.go('/home');
        _navigateFromPendingNotificationAfterFrame(router);
      }
    } else {
      // Giriş yok → pending deep link varsa login'de sonra kullanılacak; yoksa normal login
      context.go('/login');
    }
  }

  /// Cold start bildirimle açıldıysa, auth tamamlandıktan ve /home veya onboarding'e
  /// gittikten sonra bir frame bekleyip bekleyen bildirim varsa ilgili sayfaya yönlendirir.
  void _navigateFromPendingNotificationAfterFrame(GoRouter router) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final message = getPendingInitialMessage();
      if (message != null) {
        navigateFromNotification(router, message);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // NOT: ref.listen KULLANMIYORUZ
    // Auth değişiklikleri _checkAuth metodu tarafından 2 saniye sonra kontrol ediliyor
    // Bu sayede splash ekranı düzgün görünüyor

    final logoSize = context.imageSize(
      min: 120,
      max: 220,
      fractionOfWidth: 0.4,
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary,
              AppColors.primaryDark,
            ],
          ),
        ),
        child: Stack(
          children: [
            // Ortadaki ana içerik
            Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.responsiveValue(
                            small: AppSpacing.l,
                            medium: AppSpacing.xl,
                            large: AppSpacing.xxl,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Logo
                            Image.asset(
                              'assets/images/tcr_logo-removed.png',
                              width: logoSize,
                              height: logoSize,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: AppSpacing.l),
                            // App Name
                            Text(
                              AppConstants.appName,
                              style: AppTypography.displayMedium.copyWith(
                                color: const Color(0xFFC0C0C0), // Gümüş renk
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.s),
                            Text(
                              AppConstants.appFullName,
                              style: AppTypography.titleMedium.copyWith(
                                color: const Color(0xFFC0C0C0),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.xxl),
                            // Loading indicator
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFC0C0C0),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Alttaki Atatürk sözü
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + AppSpacing.l,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.responsiveValue(
                      small: AppSpacing.xl,
                      medium: AppSpacing.xxl,
                      large: AppSpacing.xxl * 2,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '"Ben sporcunun zeki, çevik ve aynı zamanda ahlaklısını severim."',
                          style: AppTypography.bodyMedium.copyWith(
                            color: const Color(0xFFC0C0C0).withValues(alpha: 0.8),
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Mustafa Kemal ATATÜRK',
                        style: AppTypography.labelMedium.copyWith(
                          color: const Color(0xFFC0C0C0).withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
