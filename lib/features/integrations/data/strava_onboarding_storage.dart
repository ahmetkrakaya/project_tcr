import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';

/// Strava onboarding için yerel bayraklar.
/// Bağlantı zorunluluğu sunucudaki Strava durumuna göre gate'te yönetilir.
class StravaOnboardingStorage {
  Future<void> clearLegacyFlags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.stravaOnboardingFirstCompleted);
    await prefs.remove(StorageKeys.stravaOnboardingPermanentlyDismissed);
    await prefs.remove(StorageKeys.stravaOnboardingLastShownAt);
  }
}
