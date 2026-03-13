import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../events/data/datasources/event_remote_datasource.dart';
import '../../events/domain/entities/event_entity.dart';
import '../../events/presentation/providers/event_provider.dart';
import '../../members_groups/data/datasources/group_remote_datasource.dart';
import '../../members_groups/domain/entities/group_entity.dart';
import '../../members_groups/presentation/providers/group_provider.dart';
import '../../auth/presentation/providers/auth_notifier.dart';
import '../../workout/domain/entities/workout_entity.dart';
import 'health_connect_channel.dart';
import 'health_connect_settings_storage.dart';

/// Bugün + 6 gün içindeki antrenman etkinliklerini Health Connect'e gönderir.
class HealthConnectWorkoutSyncService {
  final Ref _ref;
  final EventRemoteDataSource _eventDs;
  final GroupRemoteDataSource _groupDs;
  final HealthConnectSettingsStorage _storage;

  HealthConnectWorkoutSyncService(
    this._ref, {
    required EventRemoteDataSource eventDs,
    required GroupRemoteDataSource groupDs,
    required HealthConnectSettingsStorage storage,
  })  : _eventDs = eventDs,
        _groupDs = groupDs,
        _storage = storage;

  Future<void> syncNext7Days() async {
    final supported = await HealthConnectChannel.isSupported();
    if (!supported) {
      throw Exception(
        'Health Connect antrenman gönderimi bu cihazda desteklenmiyor. '
        'Health Connect uygulamasının güncel olduğundan emin olun.',
      );
    }

    final eventModels = await _eventDs.getThisWeekEvents();
    final events = eventModels
            .map((m) => m.toEntity())
            .where((e) => e.eventType == EventType.training)
            .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final sentKeys = await _storage.loadSentKeys();
    final payloads = <HealthConnectWorkoutPayload>[];

    for (final event in events) {
      final programModels = await _groupDs.getUserEventGroupPrograms(event.id);
      final programs = programModels.map((m) => m.toEntity()).toList();

      for (final p in programs) {
        WorkoutDefinitionEntity? def = p.workoutDefinition;
        if (def == null || def.isEmpty) {
          def = _buildFallbackDefinition(event, p);
          if (def == null) continue;
        }

        final key = '${event.id}:${p.id}';
        if (sentKeys.contains(key)) continue;

        final title = _workoutTitle(event, p);
        final userVdot = _ref.read(userVdotProvider);
        payloads.add(
          HealthConnectWorkoutPayload(
            id: key,
            title: title,
            scheduledAt: event.startTime,
            definition: def,
            trainingTypeName: p.trainingTypeName,
            userVdot: userVdot,
            thresholdOffsetMinSeconds: p.thresholdOffsetMinSeconds,
            thresholdOffsetMaxSeconds: p.thresholdOffsetMaxSeconds,
          ),
        );
      }
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

  String _workoutTitle(EventEntity event, EventGroupProgramEntity programEntity) {
    final groupName = programEntity.groupName;
    final typeName = programEntity.trainingTypeName;
    final base = (typeName != null && typeName.isNotEmpty)
        ? typeName
        : (groupName ?? 'Antrenman');
    return '${event.shortDayOfWeek} • $base';
  }

  WorkoutDefinitionEntity? _buildFallbackDefinition(
    EventEntity event,
    EventGroupProgramEntity program,
  ) {
    final totalSeconds = () {
      if (event.endTime != null && event.endTime!.isAfter(event.startTime)) {
        final diff = event.endTime!.difference(event.startTime).inSeconds;
        if (diff >= 15 * 60) return diff;
      }
      return 45 * 60;
    }();

    int warmup = 10 * 60;
    int cooldown = 5 * 60;
    int main = totalSeconds - warmup - cooldown;
    if (main <= 0) {
      warmup = 5 * 60;
      cooldown = 5 * 60;
      main = totalSeconds - warmup - cooldown;
      if (main <= 0) {
        main = totalSeconds - 5 * 60;
        if (main <= 0) main = totalSeconds;
        cooldown = 0;
      }
    }

    if (totalSeconds <= 0) return null;

    final steps = <WorkoutStepEntity>[];
    if (warmup > 0) {
      steps.add(
        WorkoutStepEntity(
          type: 'segment',
          segment: WorkoutSegmentEntity(
            segmentType: WorkoutSegmentType.warmup,
            targetType: WorkoutTargetType.duration,
            target: WorkoutTarget.none,
            durationSeconds: warmup,
          ),
        ),
      );
    }
    steps.add(
      WorkoutStepEntity(
        type: 'segment',
        segment: WorkoutSegmentEntity(
          segmentType: WorkoutSegmentType.main,
          targetType: WorkoutTargetType.duration,
          target: WorkoutTarget.none,
          durationSeconds: main,
        ),
      ),
    );
    if (cooldown > 0) {
      steps.add(
        WorkoutStepEntity(
          type: 'segment',
          segment: WorkoutSegmentEntity(
            segmentType: WorkoutSegmentType.cooldown,
            targetType: WorkoutTargetType.duration,
            target: WorkoutTarget.none,
            durationSeconds: cooldown,
          ),
        ),
      );
    }

    return WorkoutDefinitionEntity(steps: steps);
  }
}

final healthConnectWorkoutSyncServiceProvider =
    Provider<HealthConnectWorkoutSyncService>((ref) {
  final eventDs = ref.watch(eventDataSourceProvider);
  final groupDs = ref.watch(groupDataSourceProvider);
  return HealthConnectWorkoutSyncService(
    ref,
    eventDs: eventDs,
    groupDs: groupDs,
    storage: HealthConnectSettingsStorage(),
  );
});
