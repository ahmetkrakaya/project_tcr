import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/providers/auth_provider.dart';
import '../shared/weekly_program_device_sync.dart';

class GarminWorkoutSyncService {
  final Ref _ref;

  GarminWorkoutSyncService(this._ref);

  Future<bool> pushMonthlyProgram({
    required String programId,
    Map<String, dynamic>? workoutDefinition,
    int? viewLane,
  }) async {
    final userId = _ref.read(userIdProvider);
    if (userId == null) {
      throw Exception('Oturum açmanız gerekiyor');
    }

    final body = <String, dynamic>{
      'mode': 'single',
      'user_id': userId,
      'program_id': programId,
    };
    if (workoutDefinition != null) {
      body['workout_definition'] = workoutDefinition;
    }
    if (viewLane != null) {
      body['view_lane'] = viewLane;
    }

    final response = await Supabase.instance.client.functions.invoke(
      'garmin-push-workout',
      body: body,
    );

    if (response.status != 200) {
      final data = response.data;
      final message = data is Map ? data['error']?.toString() : null;
      throw Exception(message ?? 'Garmin senkronizasyonu başarısız (${response.status})');
    }

    final data = response.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }

    debugPrint('Garmin monthly program push ok: $programId lane=$viewLane');
    return true;
  }

  Future<bool> pushMonthlySyncItem(WeeklyProgramDeviceSyncItem item) async {
    return pushMonthlyProgram(
      programId: item.entryId,
      workoutDefinition: workoutDefinitionJson(item.definition),
      viewLane: item.viewLane,
    );
  }
}

final garminWorkoutSyncServiceProvider = Provider<GarminWorkoutSyncService>((ref) {
  return GarminWorkoutSyncService(ref);
});
