import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../auth/presentation/widgets/onboarding_group_selection.dart';
import '../../../auth/presentation/widgets/onboarding_profile_form.dart';
import '../providers/strava_provider.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

enum AppOnboardingFlowMode { full, stravaOnly }

/// Birleşik onboarding (profil + Strava) veya yalnızca Strava akışı.
class AppOnboardingFlow extends ConsumerStatefulWidget {
  const AppOnboardingFlow({
    super.key,
    required this.mode,
    required this.onClose,
    this.topBanner,
  });

  final AppOnboardingFlowMode mode;
  final VoidCallback onClose;
  final Widget? topBanner;

  @override
  ConsumerState<AppOnboardingFlow> createState() => _AppOnboardingFlowState();
}

/// Strava gate için yalnızca Strava adımlarını gösteren sarmalayıcı.
class StravaOnboardingOverlay extends ConsumerWidget {
  const StravaOnboardingOverlay({
    super.key,
    required this.onClose,
  });

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppOnboardingFlow(
      mode: AppOnboardingFlowMode.stravaOnly,
      onClose: onClose,
    );
  }
}

class _AppOnboardingFlowState extends ConsumerState<AppOnboardingFlow> {
  static const _fullPageCount = 6;
  static const _stravaPageCount = 3;
  static const _profilePageIndex = 2;
  static const _groupPageIndex = 3;

  final _pageController = PageController();
  final _profileFormKey = GlobalKey<OnboardingProfileFormState>();
  final _groupSelectionKey = GlobalKey<OnboardingGroupSelectionState>();
  int _currentPage = 0;
  bool _isConnecting = false;
  bool _isProfileSaving = false;
  bool _isGroupSaving = false;
  bool _isProfileComplete = false;
  bool _isGroupSelectionComplete = false;

  int get _pageCount => widget.mode == AppOnboardingFlowMode.full
      ? _fullPageCount
      : _stravaPageCount;

  bool get _isOnIncompleteProfilePage =>
      widget.mode == AppOnboardingFlowMode.full &&
      _currentPage == _profilePageIndex &&
      !_isProfileComplete;

  bool get _isOnIncompleteGroupPage =>
      widget.mode == AppOnboardingFlowMode.full &&
      _currentPage == _groupPageIndex &&
      !_isGroupSelectionComplete;

  bool get _isForwardSwipeBlocked =>
      _isOnIncompleteProfilePage || _isOnIncompleteGroupPage;

  ScrollPhysics get _pagePhysics =>
      _isForwardSwipeBlocked
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage >= _pageCount - 1) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _handleNext() async {
    if (_isOnIncompleteProfilePage || _isOnIncompleteGroupPage) return;

    if (widget.mode == AppOnboardingFlowMode.full &&
        _currentPage == _profilePageIndex) {
      setState(() => _isProfileSaving = true);
      try {
        final saved = await _profileFormKey.currentState?.saveProfile() ?? false;
        if (!saved) return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Hata: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _isProfileSaving = false);
      }
    }

    if (widget.mode == AppOnboardingFlowMode.full &&
        _currentPage == _groupPageIndex) {
      setState(() => _isGroupSaving = true);
      try {
        final result =
            await _groupSelectionKey.currentState?.submitJoinRequest() ??
                (ok: false, newlySubmitted: false);
        if (!result.ok) return;
        if (mounted && result.newlySubmitted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Katılım talebin gönderildi. Admin onayı bekleniyor.',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Grup talebi gönderilemedi: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _isGroupSaving = false);
      }
    }

    _nextPage();
  }

  void _previousPage() {
    if (_currentPage <= 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int index) {
    if (widget.mode == AppOnboardingFlowMode.full) {
      var targetPage = index;
      if (!_isProfileComplete && index > _profilePageIndex) {
        targetPage = _profilePageIndex;
      } else if (!_isGroupSelectionComplete && index > _groupPageIndex) {
        targetPage = _groupPageIndex;
      }

      if (targetPage != index) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _pageController.jumpToPage(targetPage);
          setState(() => _currentPage = targetPage);
        });
        return;
      }
    }

    setState(() => _currentPage = index);
  }

  Future<void> _openStore() async {
    final url = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
        ? AppConstants.stravaAppStoreUrl
        : AppConstants.stravaPlayStoreUrl;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _connectStrava() async {
    if (_isConnecting) return;
    setState(() => _isConnecting = true);
    try {
      final success =
          await ref.read(stravaNotifierProvider.notifier).connectStrava();
      if (!mounted) return;
      if (success) {
        widget.onClose();
      } else {
        final error = ref.read(stravaNotifierProvider).error;
        if (error != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  List<Widget> _buildPages() {
    final educationAndActionPages = <Widget>[
      _InfoPage(
        pageIndex: 0,
        title: 'Strava Nedir?',
        body:
            'Koşu, bisiklet ve yürüyüş aktivitelerini kaydeden dünya çapında bir spor platformudur. Milyonlarca sporcu antrenmanlarını Strava ile takip eder.\n\n'
            'Strava\'yı bağla, koşunu kaydet. Aktivitelerin TCR\'ye aktarılır; raporlar ve etkinliklerle uyumlu şekilde kullanılır.',
        showStravaLogo: true,
      ),
      _ActionPage(
        pageIndex: 1,
        isConnecting: _isConnecting,
        onDownload: _openStore,
        onConnect: _connectStrava,
      ),
    ];

    if (widget.mode == AppOnboardingFlowMode.stravaOnly) {
      return [
        const _InfoPage(
          pageIndex: 0,
          title: 'TCR\'de Antrenmanların Önemli',
          body:
              'Strava bağlantısıyla antrenmanların otomatik aktarılır, performansın düzenli takip edilir ve seviyene uygun programlar ile doğru gruba yerleştirilmen sağlanır.',
          showAppLogo: true,
        ),
        ...educationAndActionPages,
      ];
    }

    final authState = ref.watch(authNotifierProvider);
    final initialUser =
        authState is AuthAuthenticated ? authState.user : null;

    return [
      const _InfoPage(
        pageIndex: 0,
        title: 'TCR\'ye Hoş Geldin! 👋',
        body:
            'Seni burada görmek çok güzel! Birlikte profilini tamamlayıp grubunu seçeceğiz; ardından antrenmanlarını kolayca takip edebileceksin. Hadi başlayalım!',
        showAppLogo: true,
      ),
      const _InfoPage(
        pageIndex: 1,
        icon: Icons.insights_rounded,
        gradientColors: [
          AppColors.primary,
          AppColors.primaryLight,
        ],
        title: 'TCR\'de Antrenmanların Önemli',
        body:
            'Strava bağlantısıyla antrenmanların otomatik aktarılır, performansın düzenli takip edilir ve seviyene uygun programlar ile doğru gruba yerleştirilmen sağlanır.',
      ),
      OnboardingProfileForm(
        key: _profileFormKey,
        initialUser: initialUser,
        onCompletenessChanged: (complete) {
          if (_isProfileComplete == complete) return;
          setState(() => _isProfileComplete = complete);
        },
      ),
      OnboardingGroupSelection(
        key: _groupSelectionKey,
        onCompletenessChanged: (complete) {
          if (_isGroupSelectionComplete == complete) return;
          setState(() => _isGroupSelectionComplete = complete);
        },
      ),
      ...educationAndActionPages,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_currentPage > 0) {
          _previousPage();
        }
      },
      child: Material(
        color: ThemeBrightnessHolder.scaffoldBackground,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      AppColors.backgroundDark,
                      AppColors.primaryDark.withValues(alpha: 0.35),
                    ]
                  : [
                      const Color(0xFFF8FAFC),
                      AppColors.primaryContainer.withValues(alpha: 0.25),
                    ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                if (widget.topBanner != null) widget.topBanner!,
                _OnboardingHeader(
                  currentPage: _currentPage,
                  pageCount: _pageCount,
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: _pagePhysics,
                    onPageChanged: _onPageChanged,
                    children: _buildPages(),
                  ),
                ),
                _OnboardingNavBar(
                  currentPage: _currentPage,
                  pageCount: _pageCount,
                  onBack: _previousPage,
                  onNext: _handleNext,
                  isNextLoading: _isProfileSaving || _isGroupSaving,
                  isNextEnabled:
                      !_isOnIncompleteProfilePage && !_isOnIncompleteGroupPage,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({
    required this.currentPage,
    required this.pageCount,
  });

  final int currentPage;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Center(
                  child: _OnboardingPageIndicator(
                    current: currentPage,
                    total: pageCount,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Text(
              'Adım ${currentPage + 1} / $pageCount',
              key: ValueKey<int>(currentPage),
              style: AppTypography.labelSmall.copyWith(
                color: isDark ? AppColors.neutral400 : AppColors.neutral500,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPageIndicator extends StatelessWidget {
  const _OnboardingPageIndicator({
    required this.current,
    required this.total,
  });

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark
        ? AppColors.neutral600.withValues(alpha: 0.45)
        : AppColors.neutral300.withValues(alpha: 0.9);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (index) {
        final isActive = index == current;
        final isPast = index < current;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.only(left: index == 0 ? 0 : 6),
          width: isActive ? 36 : 8,
          height: isActive ? 7 : 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isActive || isPast ? AppColors.primary : inactiveColor,
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _OnboardingNavBar extends StatelessWidget {
  const _OnboardingNavBar({
    required this.currentPage,
    required this.pageCount,
    required this.onBack,
    required this.onNext,
    this.isNextLoading = false,
    this.isNextEnabled = true,
  });

  final int currentPage;
  final int pageCount;
  final VoidCallback onBack;
  final Future<void> Function() onNext;
  final bool isNextLoading;
  final bool isNextEnabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showBack = currentPage > 0;
    final showNext = currentPage < pageCount - 1;

    if (!showBack && !showNext) {
      return const SizedBox(height: 20);
    }

    final nextLabel =
        currentPage == pageCount - 2 ? 'Devam Et' : 'İleri';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceDark.withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark
                ? AppColors.neutral700.withValues(alpha: 0.35)
                : AppColors.neutral200,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: isDark ? 0.12 : 0.06),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: showBack
                    ? _NavCircleButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: onBack,
                        isDark: isDark,
                      )
                    : const SizedBox.shrink(),
              ),
              if (showBack && showNext) const SizedBox(width: 8),
              if (showNext)
                Expanded(
                  child: _NavPrimaryButton(
                    label: nextLabel,
                    onTap: isNextLoading ? () {} : () => onNext(),
                    isLoading: isNextLoading,
                    enabled: isNextEnabled,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavCircleButton extends StatelessWidget {
  const _NavCircleButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppColors.surfaceVariantDark : AppColors.neutral200,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            size: 22,
            color: isDark ? AppColors.onSurfaceDark : AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _NavPrimaryButton extends StatelessWidget {
  const _NavPrimaryButton({
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.showArrow = true,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool isLoading;
  final bool showArrow;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isInteractive = enabled && !isLoading;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isInteractive ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: isInteractive
                ? const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [AppColors.primary, AppColors.primaryLight],
                  )
                : null,
            color: isInteractive ? null : AppColors.neutral300,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              else ...[
                Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(
                    color: isInteractive
                        ? Colors.white
                        : AppColors.neutral500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (showArrow) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: isInteractive
                        ? Colors.white.withValues(alpha: 0.95)
                        : AppColors.neutral500,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPage extends StatefulWidget {
  const _InfoPage({
    required this.pageIndex,
    this.icon,
    this.gradientColors,
    required this.title,
    required this.body,
    this.showStravaLogo = false,
    this.showAppLogo = false,
  });

  final int pageIndex;
  final IconData? icon;
  final List<Color>? gradientColors;
  final String title;
  final String body;
  final bool showStravaLogo;
  final bool showAppLogo;

  @override
  State<_InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<_InfoPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _scale = Tween<double>(begin: 0.94, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Column(
            children: [
              const Spacer(flex: 2),
              ScaleTransition(
                scale: _scale,
                child: _buildIllustration(),
              ),
              const Spacer(),
              Text(
                widget.title,
                style: AppTypography.headlineSmall.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Text(
                widget.body,
                style: AppTypography.bodyMedium.copyWith(
                  color: ThemeBrightnessHolder.onSurfaceVariant,
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIllustration() {
    if (widget.showStravaLogo) {
      return const _StravaCircleLogo();
    }
    if (widget.showAppLogo) {
      return const _TcrCircleLogo();
    }

    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.gradientColors!,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.gradientColors!.last.withValues(alpha: 0.32),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Icon(widget.icon, size: 80, color: Colors.white),
    );
  }
}

class _TcrCircleLogo extends StatelessWidget {
  const _TcrCircleLogo();

  static const _size = 200.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipOval(
        child: SizedBox(
          width: _size,
          height: _size,
          child: Transform.scale(
            scale: 1.55,
            child: Image.asset(
              AssetPaths.tcrLogoWithText,
              width: _size,
              height: _size,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

class _StravaCircleLogo extends StatelessWidget {
  const _StravaCircleLogo();

  static const _size = 200.0;

  @override
  Widget build(BuildContext context) {
    const stravaOrange = Color(0xFFFC4C02);

    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: stravaOrange.withValues(alpha: 0.32),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipOval(
        child: SvgPicture.asset(
          AssetPaths.stravaIcon,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _ActionPage extends StatefulWidget {
  const _ActionPage({
    required this.pageIndex,
    required this.isConnecting,
    required this.onDownload,
    required this.onConnect,
  });

  static const buttonHeight = 48.0;
  static const buttonRadius = 12.0;

  final int pageIndex;
  final bool isConnecting;
  final VoidCallback onDownload;
  final VoidCallback onConnect;

  @override
  State<_ActionPage> createState() => _ActionPageState();
}

class _ActionPageState extends State<_ActionPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storeLabel = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
        ? 'App Store\'dan İndir'
        : 'Play Store\'dan İndir';

    return FadeTransition(
      opacity: _fade,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          children: [
            const Spacer(flex: 2),
            const _StravaCircleLogo(),
            const SizedBox(height: 20),
            Text(
              'Hazırsan bağlan',
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Strava hesabın yoksa önce uygulamayı indir, ardından bağlantıyı tamamla.',
              style: AppTypography.bodySmall.copyWith(
                color: ThemeBrightnessHolder.onSurfaceVariant,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            _ActionPageButton(
              height: _ActionPage.buttonHeight,
              radius: _ActionPage.buttonRadius,
              onTap: widget.onDownload,
              border: Border.all(color: ThemeBrightnessHolder.outlineVariant),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
                        ? Icons.apple
                        : Icons.android,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    storeLabel,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ActionPageButton(
              height: _ActionPage.buttonHeight,
              radius: _ActionPage.buttonRadius,
              onTap: widget.isConnecting ? null : widget.onConnect,
              backgroundColor: const Color(0xFFFC5200),
              child: widget.isConnecting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : SvgPicture.asset(
                      AssetPaths.btnStravaConnectOrange,
                      height: 32,
                      fit: BoxFit.contain,
                    ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

class _ActionPageButton extends StatelessWidget {
  const _ActionPageButton({
    required this.height,
    required this.radius,
    required this.child,
    this.onTap,
    this.backgroundColor,
    this.border,
  });

  final double height;
  final double radius;
  final Widget child;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? ThemeBrightnessHolder.surface,
        borderRadius: BorderRadius.circular(radius),
        border: border,
      ),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(radius),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
