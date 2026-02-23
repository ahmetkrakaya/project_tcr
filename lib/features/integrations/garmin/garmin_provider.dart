import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/integration_entity.dart';
import 'garmin_auth_service.dart';

class GarminState {
  final IntegrationEntity? integration;
  final bool isLoading;
  final bool isConnecting;
  final String? error;
  final int? sentWorkoutsCount;
  final DateTime? lastSyncAt;

  const GarminState({
    this.integration,
    this.isLoading = false,
    this.isConnecting = false,
    this.error,
    this.sentWorkoutsCount,
    this.lastSyncAt,
  });

  bool get isConnected => integration != null;

  GarminState copyWith({
    IntegrationEntity? integration,
    bool? isLoading,
    bool? isConnecting,
    String? error,
    int? sentWorkoutsCount,
    DateTime? lastSyncAt,
    bool clearIntegration = false,
    bool clearError = false,
  }) {
    return GarminState(
      integration: clearIntegration ? null : (integration ?? this.integration),
      isLoading: isLoading ?? this.isLoading,
      isConnecting: isConnecting ?? this.isConnecting,
      error: clearError ? null : (error ?? this.error),
      sentWorkoutsCount: sentWorkoutsCount ?? this.sentWorkoutsCount,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}

class GarminNotifier extends StateNotifier<GarminState> {
  final GarminAuthService _authService;

  GarminNotifier(Ref ref, this._authService) : super(const GarminState()) {
    loadIntegration();
  }

  Future<void> loadIntegration() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        state = state.copyWith(isLoading: false, clearIntegration: true);
        return;
      }

      final res = await Supabase.instance.client
          .from('user_integrations')
          .select()
          .eq('user_id', userId)
          .eq('provider', 'garmin')
          .maybeSingle();

      if (res == null) {
        state = state.copyWith(isLoading: false, clearIntegration: true);
        return;
      }

      final integration = IntegrationEntity(
        id: res['id'],
        userId: res['user_id'],
        provider: IntegrationProvider.garmin,
        providerUserId: res['provider_user_id'],
        connectedAt: DateTime.parse(res['connected_at']),
        lastSyncAt: res['last_sync_at'] != null
            ? DateTime.parse(res['last_sync_at'])
            : null,
        syncEnabled: res['sync_enabled'] ?? true,
      );

      // Gönderilen workout sayısını al
      final countRes = await Supabase.instance.client
          .from('garmin_sent_workouts')
          .select('id')
          .eq('user_id', userId);

      state = state.copyWith(
        isLoading: false,
        integration: integration,
        sentWorkoutsCount: (countRes as List).length,
        lastSyncAt: integration.lastSyncAt,
      );
    } catch (e) {
      debugPrint('GarminNotifier loadIntegration error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Garmin bağlantısı yüklenemedi',
      );
    }
  }

  Future<bool> connectGarmin() async {
    state = state.copyWith(isConnecting: true, clearError: true);
    try {
      await _authService.connectGarmin();
      await loadIntegration();
      state = state.copyWith(isConnecting: false);
      return true;
    } catch (e) {
      debugPrint('GarminNotifier connectGarmin error: $e');
      state = state.copyWith(
        isConnecting: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  Future<bool> disconnectGarmin() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _authService.disconnectGarmin();
      state = state.copyWith(
        isLoading: false,
        clearIntegration: true,
        sentWorkoutsCount: 0,
      );
      return true;
    } catch (e) {
      debugPrint('GarminNotifier disconnectGarmin error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Garmin bağlantısı kaldırılamadı',
      );
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final garminNotifierProvider =
    StateNotifierProvider<GarminNotifier, GarminState>((ref) {
  final authService = ref.watch(garminAuthServiceProvider);
  return GarminNotifier(ref, authService);
});
