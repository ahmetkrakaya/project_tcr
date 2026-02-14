import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'apple_watch_integration_settings.dart';
import 'apple_watch_settings_storage.dart';
import 'apple_watch_workoutkit_channel.dart';

class AppleWatchIntegrationState {
  final bool isSupported;
  final String authorizationStatus;
  final AppleWatchIntegrationSettings settings;
  final bool isSyncing;
  final String? error;

  const AppleWatchIntegrationState({
    required this.isSupported,
    required this.authorizationStatus,
    required this.settings,
    this.isSyncing = false,
    this.error,
  });

  AppleWatchIntegrationState copyWith({
    bool? isSupported,
    String? authorizationStatus,
    AppleWatchIntegrationSettings? settings,
    bool? isSyncing,
    String? error,
  }) {
    return AppleWatchIntegrationState(
      isSupported: isSupported ?? this.isSupported,
      authorizationStatus: authorizationStatus ?? this.authorizationStatus,
      settings: settings ?? this.settings,
      isSyncing: isSyncing ?? this.isSyncing,
      error: error,
    );
  }
}

final _appleWatchStorageProvider = Provider<AppleWatchSettingsStorage>((ref) {
  return AppleWatchSettingsStorage();
});

final appleWatchIntegrationProvider =
    StateNotifierProvider<AppleWatchIntegrationNotifier, AppleWatchIntegrationState>((ref) {
  return AppleWatchIntegrationNotifier(ref, ref.watch(_appleWatchStorageProvider));
});

class AppleWatchIntegrationNotifier extends StateNotifier<AppleWatchIntegrationState> {
  final AppleWatchSettingsStorage _storage;

  AppleWatchIntegrationNotifier(Ref ref, this._storage)
      : super(
          const AppleWatchIntegrationState(
            isSupported: false,
            authorizationStatus: 'unknown',
            settings: AppleWatchIntegrationSettings.defaults,
          ),
        ) {
    _init();
  }

  Future<void> _init() async {
    final loaded = await _storage.load();

    // Otomatik gönderim her zaman açık ve mod her zaman autoSend olacak şekilde normalize et
    final normalized = AppleWatchIntegrationSettings(
      enabled: true,
      mode: AppleWatchSendMode.autoSend,
      lastSyncAt: loaded.lastSyncAt,
    );

    await _storage.save(normalized);
    state = state.copyWith(settings: normalized);
    await refreshPlatformState();
  }

  Future<void> refreshPlatformState() async {
    try {
      final supported = await AppleWatchWorkoutKitChannel.isSupported();
      final status = supported ? await AppleWatchWorkoutKitChannel.getAuthorizationStatus() : 'notSupported';
      state = state.copyWith(isSupported: supported, authorizationStatus: status, error: null);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> connectAndAuthorize() async {
    try {
      final supported = await AppleWatchWorkoutKitChannel.isSupported();
      if (!supported) {
        state = state.copyWith(isSupported: false, authorizationStatus: 'notSupported');
        return;
      }
      final result = await AppleWatchWorkoutKitChannel.requestAuthorization();
      state = state.copyWith(isSupported: true, authorizationStatus: result, error: null);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    // Özellik her zaman açık kalmalı
    final next = state.settings.copyWith(enabled: true);
    await _storage.save(next);
    state = state.copyWith(settings: next);
  }

  Future<void> setMode(AppleWatchSendMode mode) async {
    // Gönderim modu her zaman autoSend kalmalı
    final next = state.settings.copyWith(mode: AppleWatchSendMode.autoSend);
    await _storage.save(next);
    state = state.copyWith(settings: next);
  }

  Future<void> setLastSyncNow() async {
    final next = state.settings.copyWith(lastSyncAt: DateTime.now());
    await _storage.save(next);
    state = state.copyWith(settings: next);
  }

  Future<void> setSyncing(bool isSyncing) async {
    // Hata bilgisini koruyarak sadece isSyncing alanını güncelle
    state = state.copyWith(
      isSyncing: isSyncing,
      error: state.error,
    );
  }

  void clearError() => state = state.copyWith(error: null);
}

