import 'package:shared_preferences/shared_preferences.dart';

class HealthConnectSettingsStorage {
  static const _kLastSyncAt = 'health_connect.lastSyncAt';
  static const _kSentKeys = 'health_connect.sentKeys';

  Future<DateTime?> loadLastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastSyncAt);
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  Future<void> saveLastSyncAt(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSyncAt, dt.toIso8601String());
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
}
