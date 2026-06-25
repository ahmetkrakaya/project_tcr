import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../integrations/presentation/pages/strava_onboarding_overlay.dart';

/// İlk giriş: profil + Strava tek akışta.
class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppOnboardingFlow(
      mode: AppOnboardingFlowMode.full,
      onClose: () {
        if (context.mounted) context.go('/home');
      },
    );
  }
}
