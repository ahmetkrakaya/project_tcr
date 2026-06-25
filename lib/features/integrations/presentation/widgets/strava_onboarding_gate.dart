import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../pages/strava_onboarding_overlay.dart';
import '../providers/strava_onboarding_provider.dart';
import '../providers/strava_provider.dart';

/// Profil tamam ve Strava bağlı değilken zorunlu Strava onboarding overlay'i.
class StravaOnboardingGate extends ConsumerStatefulWidget {
  const StravaOnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StravaOnboardingGate> createState() =>
      _StravaOnboardingGateState();
}

class _StravaOnboardingGateState extends ConsumerState<StravaOnboardingGate>
    with WidgetsBindingObserver {
  bool _showOverlay = false;
  String? _lastScheduledLocation;
  GoRouter? _router;
  VoidCallback? _routerListener;

  static const _blockedPrefixes = [
    '/login',
    '/register',
    '/onboarding',
    '/verify-email',
    '/reset-password',
    '/complete-profile',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(stravaOnboardingStorageProvider).clearLegacyFlags();
      _attachRouterListener();
      _evaluate();
    });
  }

  void _attachRouterListener() {
    if (_routerListener != null) return;

    _router = ref.read(appRouterProvider);
    _routerListener = () {
      if (!mounted || _router == null) return;
      _scheduleEvaluateForLocation(_router!.state.matchedLocation);
    };
    _router!.routerDelegate.addListener(_routerListener!);
  }

  String _currentLocation() {
    return ref.read(appRouterProvider).state.matchedLocation;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_routerListener != null && _router != null) {
      _router!.routerDelegate.removeListener(_routerListener!);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _evaluate();
    }
  }

  bool _isBlockedRoute(String location) {
    if (location == '/') return true;
    for (final prefix in _blockedPrefixes) {
      if (location.startsWith(prefix)) return true;
    }
    return false;
  }

  bool _isProfileComplete() {
    final user = ref.read(currentUserProfileProvider);
    final firstName = user?.firstName;
    return firstName != null && firstName.trim().isNotEmpty;
  }

  void _scheduleEvaluateForLocation(String location) {
    if (_lastScheduledLocation == location) return;
    _lastScheduledLocation = location;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _evaluate();
    });
  }

  void _evaluate() {
    if (!mounted) return;

    final isLoggedIn = ref.read(isLoggedInProvider);
    if (!isLoggedIn || !_isProfileComplete()) {
      if (_showOverlay) setState(() => _showOverlay = false);
      return;
    }

    final stravaState = ref.read(stravaNotifierProvider);
    if (stravaState.isLoading) return;
    if (stravaState.isConnected) {
      if (_showOverlay) setState(() => _showOverlay = false);
      return;
    }

    final location = _currentLocation();
    if (_isBlockedRoute(location)) {
      if (_showOverlay) setState(() => _showOverlay = false);
      return;
    }

    if (!_showOverlay) {
      setState(() => _showOverlay = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(isLoggedInProvider);
    ref.watch(isStravaConnectedProvider);
    ref.watch(stravaNotifierProvider);
    ref.watch(currentUserProfileProvider);

    ref.listen<bool>(isStravaConnectedProvider, (prev, next) {
      if (next) {
        if (_showOverlay) setState(() => _showOverlay = false);
      } else if (prev == true && next == false) {
        _evaluate();
      }
    });

    ref.listen(stravaNotifierProvider, (prev, next) {
      if (prev?.isLoading == true && !next.isLoading) {
        _evaluate();
      }
    });

    return Stack(
      children: [
        widget.child,
        if (_showOverlay)
          Positioned.fill(
            child: StravaOnboardingOverlay(
              onClose: () {
                if (ref.read(isStravaConnectedProvider)) {
                  if (mounted) setState(() => _showOverlay = false);
                }
              },
            ),
          ),
      ],
    );
  }
}
