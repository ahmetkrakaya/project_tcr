import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../events/data/datasources/event_remote_datasource.dart';
import '../../events/domain/entities/event_entity.dart';
import '../../events/presentation/providers/event_provider.dart';
import '../../members_groups/domain/entities/group_entity.dart';
import '../../members_groups/data/datasources/group_remote_datasource.dart';
import '../../members_groups/presentation/providers/group_provider.dart';
import '../../auth/presentation/providers/auth_notifier.dart';
import '../../workout/domain/entities/workout_entity.dart';
import 'apple_watch_settings_storage.dart';
import 'apple_watch_workoutkit_channel.dart';

class AppleWatchWorkoutSyncService {
  final Ref _ref;
  final EventRemoteDataSource _eventDs;
  final GroupRemoteDataSource _groupDs;
  final AppleWatchSettingsStorage _storage;

  AppleWatchWorkoutSyncService(
    this._ref, {
    required EventRemoteDataSource eventDs,
    required GroupRemoteDataSource groupDs,
    required AppleWatchSettingsStorage storage,
  })  : _eventDs = eventDs,
        _groupDs = groupDs,
        _storage = storage;

  /// Bugün + 6 gün içindeki antrenman etkinliklerini alır ve kullanıcının grubuna
  /// uygun programları Apple Watch'a schedule eder.
  Future<void> syncNext7Days() async {
    final supported = await AppleWatchWorkoutKitChannel.isSupported();
    if (!supported) {
      throw Exception('Apple Watch antrenman gönderimi bu cihazda desteklenmiyor (iOS 17+ gerekiyor).');
    }

    // Bu hafta event'lerini al (data source 0..7 gün aralığı)
    final eventModels = await _eventDs.getThisWeekEvents();
    final events = eventModels.map((m) => m.toEntity()).where((e) => e.eventType == EventType.training).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final sentKeys = await _storage.loadSentKeys();
    final payloads = <AppleWatchScheduledWorkoutPayload>[];

    for (final event in events) {
      // Her event için kullanıcı grubuna göre programları çek
      final programModels = await _groupDs.getUserEventGroupPrograms(event.id);
      final programs = programModels.map((m) => m.toEntity()).toList();

      for (final p in programs) {
        WorkoutDefinitionEntity? def = p.workoutDefinition;
        if (def == null || def.isEmpty) {
          def = _buildFallbackDefinition(event, p);
          if (def == null) {
            continue;
          }
        }

        // Event+program bazlı idempotency anahtarı
        final key = '${event.id}:${p.id}';
        if (sentKeys.contains(key)) continue;

        final title = _workoutTitle(event, p);
        final userVdot = _ref.read(userVdotProvider);
        payloads.add(
          AppleWatchScheduledWorkoutPayload(
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

    // WorkoutKit pratik limit: 15 scheduled workout. En yakın 15'i gönder.
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

    // lastSyncAt ayarı provider üzerinden güncellenecek; burada sadece depoya yazmayalım.
  }

  /// Tekil programı (on-demand) Apple Watch'a gönderir.
  Future<void> sendSingleProgram({
    required AppleWatchScheduledWorkoutPayload payload,
  }) async {
    final supported = await AppleWatchWorkoutKitChannel.isSupported();
    if (!supported) {
      throw Exception('Apple Watch antrenman gönderimi bu cihazda desteklenmiyor (iOS 17+ gerekiyor).');
    }

    // On-demand: aynı key'i tekrar göndermeyi engellemeyelim; kullanıcı isteyebilir.
    await AppleWatchWorkoutKitChannel.syncScheduledWorkouts(payloads: [payload]);
  }

  /// Tek bir event+program çifti için (on-demand) Apple Watch'a gönderim.
  Future<void> sendSingleProgramForEvent({
    required EventEntity event,
    required EventGroupProgramEntity program,
  }) async {
    final supported = await AppleWatchWorkoutKitChannel.isSupported();
    if (!supported) {
      throw Exception('Apple Watch antrenman gönderimi bu cihazda desteklenmiyor (iOS 17+ gerekiyor).');
    }

    WorkoutDefinitionEntity? def = program.workoutDefinition;
    if (def == null || def.isEmpty) {
      def = _buildFallbackDefinition(event, program);
    }
    if (def == null || def.isEmpty) {
      throw Exception('Bu program için gönderilebilir antrenman tanımı bulunamadı.');
    }

    final userVdot = _ref.read(userVdotProvider);
    final payload = AppleWatchScheduledWorkoutPayload(
      id: '${event.id}:${program.id}:${DateTime.now().millisecondsSinceEpoch}',
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

  /// WorkoutKit entegrasyonunu test etmek için sabit bir örnek antrenman gönderir.
  ///
  /// Yapı:
  /// - 5 dk ısınma
  /// - 10 dk ana bölüm
  /// - Açık soğuma
  Future<void> sendDebugSampleWorkout() async {
    final supported = await AppleWatchWorkoutKitChannel.isSupported();
    if (!supported) {
      throw Exception('Apple Watch antrenman gönderimi bu cihazda desteklenmiyor (iOS 17+ gerekiyor).');
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

  String _workoutTitle(EventEntity event, EventGroupProgramEntity programEntity) {
    final groupName = programEntity.groupName;
    final typeName = programEntity.trainingTypeName;
    final base = (typeName != null && typeName.isNotEmpty) ? typeName : (groupName ?? 'Antrenman');
    return '${event.shortDayOfWeek} • $base';
  }

  /// Eğer programda yapılandırılmış antrenman yoksa, etkinliğin süresine göre
  /// basit bir warmup-main-cooldown yapısı üretir.
  WorkoutDefinitionEntity? _buildFallbackDefinition(
    EventEntity event,
    EventGroupProgramEntity program,
  ) {
    final totalSeconds = () {
      if (event.endTime != null && event.endTime!.isAfter(event.startTime)) {
        final diff = event.endTime!.difference(event.startTime).inSeconds;
        if (diff >= 15 * 60) return diff;
      }
      return 45 * 60; // Varsayılan 45 dk
    }();

    int warmup = 10 * 60;
    int cooldown = 5 * 60;
    int main = totalSeconds - warmup - cooldown;
    if (main <= 0) {
      // Çok kısa etkinlikler için basitleştir
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

final appleWatchWorkoutSyncServiceProvider = Provider<AppleWatchWorkoutSyncService>((ref) {
  final eventDs = ref.watch(eventDataSourceProvider);
  final groupDs = ref.watch(groupDataSourceProvider);
  final storage = AppleWatchSettingsStorage();
  return AppleWatchWorkoutSyncService(
    ref,
    eventDs: eventDs,
    groupDs: groupDs,
    storage: storage,
  );
});

