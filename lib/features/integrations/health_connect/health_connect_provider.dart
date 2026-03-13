import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'health_connect_channel.dart';
import 'health_connect_settings_storage.dart';

class HealthConnectIntegrationState {
  final bool isSupported;
  final String authorizationStatus;
  final DateTime? lastSyncAt;
  final bool isSyncing;
  final String? error;

  const HealthConnectIntegrationState({
    this.isSupported = false,
    this.authorizationStatus = 'unknown',
    this.lastSyncAt,
    this.isSyncing = false,
    this.error,
  });

  bool get isConnected => isSupported && authorizationStatus == 'authorized';

  HealthConnectIntegrationState copyWith({
    bool? isSupported,
    String? authorizationStatus,
    DateTime? lastSyncAt,
    bool? isSyncing,
    String? error,
  }) {
    return HealthConnectIntegrationState(
      isSupported: isSupported ?? this.isSupported,
      authorizationStatus: authorizationStatus ?? this.authorizationStatus,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      isSyncing: isSyncing ?? this.isSyncing,
      error: error,
    );
  }
}

class HealthConnectIntegrationNotifier extends StateNotifier<HealthConnectIntegrationState> {
  final HealthConnectSettingsStorage _storage;

  HealthConnectIntegrationNotifier(this._storage)
      : super(const HealthConnectIntegrationState()) {
    _init();
  }

  Future<void> _init() async {
    await refreshPlatformState();
    final lastSync = await _storage.loadLastSyncAt();
    state = state.copyWith(lastSyncAt: lastSync);
  }

  Future<void> refreshPlatformState() async {
    try {
      final supported = await HealthConnectChannel.isSupported();
      final status =
          supported ? await HealthConnectChannel.getAuthorizationStatus() : 'notSupported';
      state = state.copyWith(
        isSupported: supported,
        authorizationStatus: status,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> connectAndAuthorize() async {
    try {
      final supported = await HealthConnectChannel.isSupported();
      if (!supported) {
        state = state.copyWith(isSupported: false, authorizationStatus: 'notSupported');
        return;
      }
      final result = await HealthConnectChannel.requestAuthorization();
      state = state.copyWith(
        isSupported: true,
        authorizationStatus: result,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> setSyncing(bool syncing) async {
    state = state.copyWith(isSyncing: syncing);
  }

  Future<void> setLastSyncNow() async {
    final now = DateTime.now();
    await _storage.saveLastSyncAt(now);
    state = state.copyWith(lastSyncAt: now);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final healthConnectIntegrationProvider =
    StateNotifierProvider<HealthConnectIntegrationNotifier, HealthConnectIntegrationState>((ref) {
  return HealthConnectIntegrationNotifier(HealthConnectSettingsStorage());
});
