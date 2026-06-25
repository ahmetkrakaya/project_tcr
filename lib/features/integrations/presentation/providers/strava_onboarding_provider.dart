import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/strava_onboarding_storage.dart';

final stravaOnboardingStorageProvider = Provider<StravaOnboardingStorage>((ref) {
  return StravaOnboardingStorage();
});
