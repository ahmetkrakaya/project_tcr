import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/providers/auth_notifier.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../events/data/datasources/event_remote_datasource.dart';
import '../../events/presentation/providers/event_provider.dart';
import '../shared/weekly_program_device_sync.dart';
import 'health_connect_channel.dart';
import 'health_connect_settings_storage.dart';

/// Bugün + 7 gün içindeki haftalık plan satırlarını Health Connect'e gönderir.
class HealthConnectWorkoutSyncService {
  final Ref _ref;
  final EventRemoteDataSource _eventDs;
  final HealthConnectSettingsStorage _storage;

  HealthConnectWorkoutSyncService(
    this._ref, {
    required EventRemoteDataSource eventDs,
    required HealthConnectSettingsStorage storage,
  })  : _eventDs = eventDs,
        _storage = storage;

  Future<void> syncNext7Days() async {
    final supported = await HealthConnectChannel.isSupported();
    if (!supported) {
      throw Exception(
        'Health Connect antrenman gönderimi bu cihazda desteklenmiyor. '
        'Health Connect uygulamasının güncel olduğundan emin olun.',
      );
    }

    final userId = _ref.read(userIdProvider);
    if (userId == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 7));

    final rows = await _eventDs.getMonthlyProgramsForUserInRange(
      userId: userId,
      startDate: today,
      endDate: end,
    );
    final items = mapMonthlyRowsToDeviceSyncItems(rows);

    final sentKeys = await _storage.loadSentKeys();
    final payloads = <HealthConnectWorkoutPayload>[];
    final userVdot = _ref.read(userVdotProvider);

    for (final item in items) {
      final key = weeklyProgramSyncKey(item.entryId);
      if (sentKeys.contains(key)) continue;

      payloads.add(
        HealthConnectWorkoutPayload(
          id: key,
          title: item.title,
          scheduledAt: item.scheduledAt,
          definition: item.definition,
          trainingTypeName: item.trainingTypeName,
          userVdot: userVdot,
          thresholdOffsetMinSeconds: item.thresholdOffsetMinSeconds,
          thresholdOffsetMaxSeconds: item.thresholdOffsetMaxSeconds,
        ),
      );
    }

    payloads.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final limited = payloads.take(15).toList();

    if (limited.isEmpty) {
      await _storage.saveSentKeys(sentKeys);
      return;
    }

    await HealthConnectChannel.syncScheduledWorkouts(payloads: limited);

    for (final p in limited) {
      sentKeys.add(p.id);
    }
    await _storage.saveSentKeys(sentKeys);
  }
}

final healthConnectWorkoutSyncServiceProvider =
    Provider<HealthConnectWorkoutSyncService>((ref) {
  final eventDs = ref.watch(eventDataSourceProvider);
  return HealthConnectWorkoutSyncService(
    ref,
    eventDs: eventDs,
    storage: HealthConnectSettingsStorage(),
  );
});
