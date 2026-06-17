import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/providers/auth_notifier.dart';
import '../apple_watch/apple_watch_provider.dart';
import '../apple_watch/apple_watch_workout_sync_service.dart';
import '../garmin/garmin_provider.dart';
import '../garmin/garmin_workout_sync_service.dart';
import '../health_connect/health_connect_provider.dart';
import '../health_connect/health_connect_workout_sync_service.dart';
import 'weekly_program_device_sync.dart';

class MonthlyProgramDeviceSyncResult {
  final List<String> syncedTargets;
  final List<String> skippedTargets;
  final List<String> errors;

  const MonthlyProgramDeviceSyncResult({
    this.syncedTargets = const [],
    this.skippedTargets = const [],
    this.errors = const [],
  });

  bool get hasSuccess => syncedTargets.isNotEmpty;
  bool get hasError => errors.isNotEmpty;
}

class MonthlyProgramDeviceSyncService {
  final Ref _ref;

  MonthlyProgramDeviceSyncService(this._ref);

  bool get _garminConnected => _ref.read(garminNotifierProvider).isConnected;

  bool get _appleWatchConnected {
    final s = _ref.read(appleWatchIntegrationProvider);
    return s.isSupported && s.authorizationStatus == 'authorized';
  }

  bool get _healthConnectConnected =>
      _ref.read(healthConnectIntegrationProvider).isConnected;

  bool get hasAnyDeviceTarget {
    if (kIsWeb) return _garminConnected;
    if (Platform.isIOS) return _garminConnected || _appleWatchConnected;
    if (Platform.isAndroid) return _garminConnected || _healthConnectConnected;
    return _garminConnected;
  }

  List<String> get availableTargetLabels {
    final out = <String>[];
    if (_garminConnected) out.add('Garmin');
    if (!kIsWeb && Platform.isIOS && _appleWatchConnected) out.add('Apple Watch');
    if (!kIsWeb && Platform.isAndroid && _healthConnectConnected) {
      out.add('Health Connect');
    }
    return out;
  }

  Future<MonthlyProgramDeviceSyncResult> syncEntry({
    required Map<String, dynamic> row,
    int? viewLane,
  }) async {
    final item = buildMonthlySyncItem(row, viewLane: viewLane);
    if (item == null) {
      throw Exception('Bu antrenman cihaza gönderilebilir formatta değil');
    }

    final synced = <String>[];
    final skipped = <String>[];
    final errors = <String>[];

    if (_garminConnected) {
      try {
        await _ref.read(garminWorkoutSyncServiceProvider).pushMonthlySyncItem(item);
        synced.add('Garmin');
        await _ref.read(garminNotifierProvider.notifier).loadIntegration();
      } catch (e) {
        errors.add('Garmin: $e');
      }
    } else {
      skipped.add('Garmin');
    }

    if (!kIsWeb && Platform.isIOS && _appleWatchConnected) {
      try {
        await _ref
            .read(appleWatchWorkoutSyncServiceProvider)
            .syncSingleMonthlyProgram(item);
        synced.add('Apple Watch');
        await _ref.read(appleWatchIntegrationProvider.notifier).setLastSyncNow();
      } catch (e) {
        errors.add('Apple Watch: $e');
      }
    } else if (!kIsWeb && Platform.isIOS) {
      skipped.add('Apple Watch');
    }

    if (!kIsWeb && Platform.isAndroid && _healthConnectConnected) {
      try {
        await _ref
            .read(healthConnectWorkoutSyncServiceProvider)
            .syncSingleMonthlyProgram(item);
        synced.add('Health Connect');
        await _ref.read(healthConnectIntegrationProvider.notifier).setLastSyncNow();
      } catch (e) {
        errors.add('Health Connect: $e');
      }
    } else if (!kIsWeb && Platform.isAndroid) {
      skipped.add('Health Connect');
    }

    if (synced.isEmpty && errors.isEmpty) {
      throw Exception(
        'Bağlı cihaz bulunamadı. Bağlantılar ekranından Garmin, '
        'Apple Watch veya Health Connect bağlayın.',
      );
    }

    return MonthlyProgramDeviceSyncResult(
      syncedTargets: synced,
      skippedTargets: skipped,
      errors: errors,
    );
  }
}

final monthlyProgramDeviceSyncServiceProvider =
    Provider<MonthlyProgramDeviceSyncService>((ref) {
  return MonthlyProgramDeviceSyncService(ref);
});
