import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;

import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// App version information from Supabase
class AppVersionInfo {
  final String minimumVersion;
  final bool isForceUpdate;
  final String? message;
  final String? appStoreUrl;
  final String? playStoreUrl;

  const AppVersionInfo({
    required this.minimumVersion,
    required this.isForceUpdate,
    this.message,
    this.appStoreUrl,
    this.playStoreUrl,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      minimumVersion: json['minimum_version'] as String,
      isForceUpdate: json['is_force_update'] as bool? ?? false,
      message: json['message'] as String?,
      appStoreUrl: json['app_store_url'] as String?,
      playStoreUrl: json['play_store_url'] as String?,
    );
  }
}

/// Update check result
class UpdateCheckResult {
  final bool needsUpdate;
  final bool isForceUpdate;
  final AppVersionInfo? versionInfo;
  final String? storeUrl;

  const UpdateCheckResult({
    required this.needsUpdate,
    required this.isForceUpdate,
    this.versionInfo,
    this.storeUrl,
  });
}

/// Service for checking app version updates from Supabase
class UpdateCheckService {
  UpdateCheckService._();

  static final _supabase = Supabase.instance.client;

  /// Get current platform string
  static String _getPlatform() {
    if (kIsWeb) return 'web';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    if (defaultTargetPlatform == TargetPlatform.android) return 'android';
    throw UnsupportedError('Platform not supported');
  }

  /// Compare two version strings (semver format: major.minor.patch)
  /// Returns: -1 if version1 < version2, 0 if equal, 1 if version1 > version2
  static int _compareVersions(String version1, String version2) {
    final v1Parts = version1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final v2Parts = version2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // Pad with zeros if lengths differ
    while (v1Parts.length < v2Parts.length) {
      v1Parts.add(0);
    }
    while (v2Parts.length < v1Parts.length) {
      v2Parts.add(0);
    }

    for (int i = 0; i < v1Parts.length; i++) {
      if (v1Parts[i] < v2Parts[i]) return -1;
      if (v1Parts[i] > v2Parts[i]) return 1;
    }
    return 0;
  }

  /// Check if update is required
  static Future<UpdateCheckResult> checkForUpdate() async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Get platform
      final platform = _getPlatform();

      // Fetch version info from Supabase
      final response = await _supabase
          .from('app_versions')
          .select()
          .eq('platform', platform)
          .maybeSingle();

      if (response == null) {
        // No version info found, allow app to continue
        return const UpdateCheckResult(
          needsUpdate: false,
          isForceUpdate: false,
        );
      }

      final versionInfo = AppVersionInfo.fromJson(response);

      // Compare versions
      final versionComparison = _compareVersions(currentVersion, versionInfo.minimumVersion);

      final needsUpdate = versionComparison < 0;
      final isForceUpdate = needsUpdate && versionInfo.isForceUpdate;

      // Determine store URL
      String? storeUrl;
      if (!kIsWeb) {
        if (defaultTargetPlatform == TargetPlatform.iOS && versionInfo.appStoreUrl != null) {
          storeUrl = versionInfo.appStoreUrl;
        } else if (defaultTargetPlatform == TargetPlatform.android && versionInfo.playStoreUrl != null) {
          storeUrl = versionInfo.playStoreUrl;
        }
      }

      return UpdateCheckResult(
        needsUpdate: needsUpdate,
        isForceUpdate: isForceUpdate,
        versionInfo: versionInfo,
        storeUrl: storeUrl,
      );
    } catch (e) {
      // On error, allow app to continue (fail gracefully)
      // In production, you might want to log this error
      return const UpdateCheckResult(
        needsUpdate: false,
        isForceUpdate: false,
      );
    }
  }
}
