import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppVersionRow {
  final String platform;
  final String minimumVersion;
  final bool isForceUpdate;
  final String? message;
  final String? appStoreUrl;
  final String? playStoreUrl;
  final DateTime? updatedAt;

  const AppVersionRow({
    required this.platform,
    required this.minimumVersion,
    required this.isForceUpdate,
    this.message,
    this.appStoreUrl,
    this.playStoreUrl,
    this.updatedAt,
  });

  factory AppVersionRow.fromJson(Map<String, dynamic> json) {
    return AppVersionRow(
      platform: (json['platform'] as String).toLowerCase(),
      minimumVersion: json['minimum_version'] as String? ?? '',
      isForceUpdate: json['is_force_update'] as bool? ?? false,
      message: json['message'] as String?,
      appStoreUrl: json['app_store_url'] as String?,
      playStoreUrl: json['play_store_url'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }
}

final appVersionsAdminProvider =
    FutureProvider<Map<String, AppVersionRow>>((ref) async {
  final supabase = Supabase.instance.client;
  final rows = await supabase
      .from('app_versions')
      .select()
      .inFilter('platform', ['android', 'ios']);

  final map = <String, AppVersionRow>{};
  for (final row in rows as List<dynamic>) {
    final parsed = AppVersionRow.fromJson(row as Map<String, dynamic>);
    map[parsed.platform] = parsed;
  }
  return map;
});

class AppVersionsAdminRepository {
  AppVersionsAdminRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<void> upsertIos({
    required String minimumVersion,
    required bool isForceUpdate,
    String? message,
    String? appStoreUrl,
  }) async {
    await _supabase.from('app_versions').upsert(
      {
        'platform': 'ios',
        'minimum_version': minimumVersion,
        'is_force_update': isForceUpdate,
        'message': _nullIfEmpty(message),
        'app_store_url': _nullIfEmpty(appStoreUrl),
      },
      onConflict: 'platform',
    );
  }

  Future<void> upsertAndroid({
    required String minimumVersion,
    required bool isForceUpdate,
    String? message,
    String? playStoreUrl,
  }) async {
    await _supabase.from('app_versions').upsert(
      {
        'platform': 'android',
        'minimum_version': minimumVersion,
        'is_force_update': isForceUpdate,
        'message': _nullIfEmpty(message),
        'play_store_url': _nullIfEmpty(playStoreUrl),
      },
      onConflict: 'platform',
    );
  }

  String? _nullIfEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

final appVersionsAdminRepositoryProvider =
    Provider<AppVersionsAdminRepository>((ref) {
  return AppVersionsAdminRepository(Supabase.instance.client);
});
