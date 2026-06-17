import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/providers/auth_notifier.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../events/data/datasources/event_remote_datasource.dart';
import '../../events/domain/entities/event_entity.dart';
import '../../events/presentation/providers/event_provider.dart';
import '../../members_groups/domain/entities/group_entity.dart';
import '../../workout/domain/entities/workout_entity.dart';
import '../shared/weekly_program_device_sync.dart';
import 'apple_watch_settings_storage.dart';
import 'apple_watch_workoutkit_channel.dart';

class AppleWatchWorkoutSyncService {
  final Ref _ref;
  final EventRemoteDataSource _eventDs;
  final AppleWatchSettingsStorage _storage;

  AppleWatchWorkoutSyncService(
    this._ref, {
    required EventRemoteDataSource eventDs,
    required AppleWatchSettingsStorage storage,
  })  : _eventDs = eventDs,
        _storage = storage;

  /// Bugün + 7 gün içindeki haftalık plan satırlarını Apple Watch'a gönderir.
  Future<void> syncNext7Days() async {
    final supported = await AppleWatchWorkoutKitChannel.isSupported();
    if (!supported) {
      throw Exception(
        'Apple Watch antrenman gönderimi bu cihazda desteklenmiyor (iOS 17+ gerekiyor).',
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
    final payloads = <AppleWatchScheduledWorkoutPayload>[];
    final userVdot = _ref.read(userVdotProvider);

    for (final item in items) {
      final key = weeklyProgramSyncKey(item.entryId, viewLane: item.viewLane);
      if (sentKeys.contains(key)) continue;

      payloads.add(
        AppleWatchScheduledWorkoutPayload(
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

    await AppleWatchWorkoutKitChannel.syncScheduledWorkouts(payloads: limited);

    for (final p in limited) {
      sentKeys.add(p.id);
    }
    await _storage.saveSentKeys(sentKeys);
  }

  /// Kulvar ayarlı tek plan satırını Apple Watch'a gönderir (önceki kulvar sürümünün üzerine yazar).
  Future<void> syncSingleMonthlyProgram(WeeklyProgramDeviceSyncItem item) async {
    final userVdot = _ref.read(userVdotProvider);
    final key = weeklyProgramSyncKey(item.entryId, viewLane: item.viewLane);
    final payload = AppleWatchScheduledWorkoutPayload(
      id: key,
      title: item.title,
      scheduledAt: item.scheduledAt,
      definition: item.definition,
      trainingTypeName: item.trainingTypeName,
      userVdot: userVdot,
      thresholdOffsetMinSeconds: item.thresholdOffsetMinSeconds,
      thresholdOffsetMaxSeconds: item.thresholdOffsetMaxSeconds,
    );

    await sendSingleProgram(payload: payload);

    final sentKeys = await _storage.loadSentKeys();
    sentKeys.removeWhere((k) => k.startsWith('monthly:${item.entryId}'));
    sentKeys.add(key);
    await _storage.saveSentKeys(sentKeys);
  }

  Future<void> sendSingleProgram({
    required AppleWatchScheduledWorkoutPayload payload,
  }) async {
    final supported = await AppleWatchWorkoutKitChannel.isSupported();
    if (!supported) {
      throw Exception(
        'Apple Watch antrenman gönderimi bu cihazda desteklenmiyor (iOS 17+ gerekiyor).',
      );
    }

    await AppleWatchWorkoutKitChannel.syncScheduledWorkouts(payloads: [payload]);
  }

  /// Plan satırını (veya program entity) doğrudan Apple Watch'a gönderir.
  Future<void> sendSingleProgramForEvent({
    required EventEntity event,
    required EventGroupProgramEntity program,
  }) async {
    WorkoutDefinitionEntity? def = program.workoutDefinition;
    if (def == null || def.isEmpty) {
      throw Exception('Bu program için gönderilebilir antrenman tanımı bulunamadı.');
    }

    final userVdot = _ref.read(userVdotProvider);
    final payload = AppleWatchScheduledWorkoutPayload(
      id: '${weeklyProgramSyncKey(program.id)}:${DateTime.now().millisecondsSinceEpoch}',
      title: program.trainingTypeName ?? (program.groupName ?? 'Antrenman'),
      scheduledAt: event.startTime,
      definition: def,
      trainingTypeName: program.trainingTypeName,
      userVdot: userVdot,
      thresholdOffsetMinSeconds: program.thresholdOffsetMinSeconds,
      thresholdOffsetMaxSeconds: program.thresholdOffsetMaxSeconds,
    );
    await sendSingleProgram(payload: payload);
  }

  Future<void> sendDebugSampleWorkout() async {
    final supported = await AppleWatchWorkoutKitChannel.isSupported();
    if (!supported) {
      throw Exception(
        'Apple Watch antrenman gönderimi bu cihazda desteklenmiyor (iOS 17+ gerekiyor).',
      );
    }

    final warmupSeg = WorkoutSegmentEntity(
      segmentType: WorkoutSegmentType.warmup,
      targetType: WorkoutTargetType.duration,
      target: WorkoutTarget.none,
      durationSeconds: 5 * 60,
    );
    final mainSeg = WorkoutSegmentEntity(
      segmentType: WorkoutSegmentType.main,
      targetType: WorkoutTargetType.duration,
      target: WorkoutTarget.none,
      durationSeconds: 10 * 60,
    );
    final cooldownSeg = WorkoutSegmentEntity(
      segmentType: WorkoutSegmentType.cooldown,
      targetType: WorkoutTargetType.open,
      target: WorkoutTarget.none,
    );

    final definition = WorkoutDefinitionEntity(
      steps: [
        WorkoutStepEntity(type: 'segment', segment: warmupSeg),
        WorkoutStepEntity(type: 'segment', segment: mainSeg),
        WorkoutStepEntity(type: 'segment', segment: cooldownSeg),
      ],
    );

    final payload = AppleWatchScheduledWorkoutPayload(
      id: 'debug-${DateTime.now().millisecondsSinceEpoch}',
      title: 'TCR Debug Run',
      scheduledAt: DateTime.now().add(const Duration(minutes: 10)),
      definition: definition,
      trainingTypeName: 'Debug Run',
    );

    await AppleWatchWorkoutKitChannel.syncScheduledWorkouts(payloads: [payload]);
  }
}

final appleWatchWorkoutSyncServiceProvider = Provider<AppleWatchWorkoutSyncService>((ref) {
  final eventDs = ref.watch(eventDataSourceProvider);
  final storage = AppleWatchSettingsStorage();
  return AppleWatchWorkoutSyncService(
    ref,
    eventDs: eventDs,
    storage: storage,
  );
});
