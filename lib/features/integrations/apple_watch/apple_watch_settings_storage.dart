import 'package:shared_preferences/shared_preferences.dart';

import 'apple_watch_integration_settings.dart';

class AppleWatchSettingsStorage {
  static const _kEnabled = 'apple_watch.enabled';
  static const _kMode = 'apple_watch.mode';
  static const _kLastSyncAt = 'apple_watch.lastSyncAt';
  static const _kSentKeys = 'apple_watch.sentKeys';

  Future<AppleWatchIntegrationSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEnabled) ?? AppleWatchIntegrationSettings.defaults.enabled;
    final mode = AppleWatchSendMode.fromString(prefs.getString(_kMode));
    final lastSyncRaw = prefs.getString(_kLastSyncAt);
    final lastSyncAt = lastSyncRaw != null ? DateTime.tryParse(lastSyncRaw) : null;
    return AppleWatchIntegrationSettings(
      enabled: enabled,
      mode: mode,
      lastSyncAt: lastSyncAt,
    );
  }

  Future<void> save(AppleWatchIntegrationSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, s.enabled);
    await prefs.setString(_kMode, s.mode.asString);
    if (s.lastSyncAt != null) {
      await prefs.setString(_kLastSyncAt, s.lastSyncAt!.toIso8601String());
    }
  }

  Future<Set<String>> loadSentKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kSentKeys) ?? const <String>[];
    return list.toSet();
  }

  Future<void> saveSentKeys(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kSentKeys, keys.toList()..sort());
  }

  Future<void> clearSentKeys() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSentKeys);
  }
}

