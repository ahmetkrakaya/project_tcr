import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../activity/data/datasources/activity_remote_datasource.dart';
import '../../../activity/domain/entities/activity_entity.dart';
import '../../domain/entities/period_statistics_entity.dart';

/// Supabase client provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Activity datasource provider
final _activityDataSourceProvider = Provider<ActivityRemoteDataSource>((ref) {
  return ActivityRemoteDataSourceImpl(ref.watch(_supabaseProvider));
});

/// Haftalık İstatistikler Provider (family - userId ile)
final weeklyStatisticsProvider = FutureProvider.family<PeriodStatisticsEntity, String>((ref, userId) async {
  final dataSource = ref.watch(_activityDataSourceProvider);
  
  // Bu haftanın başlangıcı (Pazartesi)
  final now = DateTime.now();
  final weekStart = now.subtract(Duration(days: now.weekday - 1));
  final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
  final weekEndDate = weekStartDate.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

  // Tüm aktiviteleri al (limit yok, çünkü haftalık veri az olacak)
  final activities = <ActivityEntity>[];
  int offset = 0;
  const limit = 100;
  
  while (true) {
    final models = await dataSource.getUserActivities(userId, limit: limit, offset: offset, activityType: 'running');
    if (models.isEmpty) break;
    
    final entities = models.map((m) => m.toEntity()).toList();
    activities.addAll(entities);
    
    // Son aktivite bu haftadan önceyse dur
    if (entities.last.startTime.isBefore(weekStartDate)) break;
    if (models.length < limit) break;
    
    offset += limit;
  }

  // Bu hafta içindeki aktiviteleri filtrele
  final weekActivities = activities.where((activity) {
    return activity.startTime.isAfter(weekStartDate.subtract(const Duration(days: 1))) &&
           activity.startTime.isBefore(weekEndDate.add(const Duration(days: 1)));
  }).toList();

  return _calculatePeriodStatistics(
    weekStartDate,
    weekEndDate,
    weekActivities,
  );
});

/// Aylık İstatistikler Provider (family - userId ile)
final monthlyStatisticsProvider = FutureProvider.family<PeriodStatisticsEntity, String>((ref, userId) async {
  final dataSource = ref.watch(_activityDataSourceProvider);
  
  // Bu ayın başlangıcı
  final now = DateTime.now();
  final monthStartDate = DateTime(now.year, now.month, 1);
  final monthEndDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

  // Tüm aktiviteleri al
  final activities = <ActivityEntity>[];
  int offset = 0;
  const limit = 100;
  
  while (true) {
    final models = await dataSource.getUserActivities(userId, limit: limit, offset: offset, activityType: 'running');
    if (models.isEmpty) break;
    
    final entities = models.map((m) => m.toEntity()).toList();
    activities.addAll(entities);
    
    // Son aktivite bu aydan önceyse dur
    if (entities.last.startTime.isBefore(monthStartDate)) break;
    if (models.length < limit) break;
    
    offset += limit;
  }

  // Bu ay içindeki aktiviteleri filtrele
  final monthActivities = activities.where((activity) {
    return activity.startTime.isAfter(monthStartDate.subtract(const Duration(days: 1))) &&
           activity.startTime.isBefore(monthEndDate.add(const Duration(days: 1)));
  }).toList();

  return _calculatePeriodStatistics(
    monthStartDate,
    monthEndDate,
    monthActivities,
  );
});

/// Dönem istatistiklerini hesapla
PeriodStatisticsEntity _calculatePeriodStatistics(
  DateTime periodStart,
  DateTime periodEnd,
  List<ActivityEntity> activities,
) {
  // Günlük bazlı grupla
  final dailyStatsMap = <DateTime, DailyStatisticsEntity>{};
  
  // Tüm günleri başlat (boş verilerle)
  final days = periodEnd.difference(periodStart).inDays + 1;
  for (int i = 0; i < days; i++) {
    final date = periodStart.add(Duration(days: i));
    final dateOnly = DateTime(date.year, date.month, date.day);
    dailyStatsMap[dateOnly] = DailyStatisticsEntity(
      date: dateOnly,
      activityCount: 0,
      distanceKm: 0,
      durationSeconds: 0,
      elevationGain: 0,
    );
  }

  // Aktivite verilerini günlere dağıt
  for (final activity in activities) {
    final activityDate = DateTime(
      activity.startTime.year,
      activity.startTime.month,
      activity.startTime.day,
    );

    if (dailyStatsMap.containsKey(activityDate)) {
      final existing = dailyStatsMap[activityDate]!;
      dailyStatsMap[activityDate] = DailyStatisticsEntity(
        date: activityDate,
        activityCount: existing.activityCount + 1,
        distanceKm: existing.distanceKm + activity.distanceKm,
        durationSeconds: existing.durationSeconds + (activity.durationSeconds ?? 0),
        elevationGain: existing.elevationGain + (activity.elevationGain ?? 0),
      );
    }
  }

  // Toplam istatistikleri hesapla
  final totalActivities = activities.length;
  final totalDistanceKm = activities.fold<double>(
    0,
    (sum, activity) => sum + activity.distanceKm,
  );
  final totalDurationSeconds = activities.fold<int>(
    0,
    (sum, activity) => sum + (activity.durationSeconds ?? 0),
  );
  final totalElevationGain = activities.fold<double>(
    0,
    (sum, activity) => sum + (activity.elevationGain ?? 0),
  );

  // Ortalama pace hesapla (saniye/km)
  double averagePaceSeconds = 0;
  if (totalDistanceKm > 0 && totalDurationSeconds > 0) {
    averagePaceSeconds = totalDurationSeconds / totalDistanceKm;
  }

  // Günlük istatistikleri sırala
  final dailyStats = dailyStatsMap.values.toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  return PeriodStatisticsEntity(
    periodStart: periodStart,
    periodEnd: periodEnd,
    totalActivities: totalActivities,
    totalDistanceKm: totalDistanceKm,
    totalDurationSeconds: totalDurationSeconds,
    totalElevationGain: totalElevationGain,
    averagePaceSeconds: averagePaceSeconds,
    dailyStats: dailyStats,
  );
}
