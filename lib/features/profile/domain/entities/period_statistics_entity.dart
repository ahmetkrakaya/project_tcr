/// Dönem İstatistikleri Entity
/// Haftalık veya aylık istatistikleri temsil eder
class PeriodStatisticsEntity {
  final DateTime periodStart;
  final DateTime periodEnd;
  final int totalActivities;
  final double totalDistanceKm;
  final int totalDurationSeconds;
  final double totalElevationGain;
  final double averagePaceSeconds;
  final List<DailyStatisticsEntity> dailyStats;

  const PeriodStatisticsEntity({
    required this.periodStart,
    required this.periodEnd,
    this.totalActivities = 0,
    this.totalDistanceKm = 0,
    this.totalDurationSeconds = 0,
    this.totalElevationGain = 0,
    this.averagePaceSeconds = 0,
    this.dailyStats = const [],
  });

  /// Ortalama pace formatla (mm:ss /km)
  String get formattedAveragePace {
    if (averagePaceSeconds <= 0) return '--:--';
    final minutes = (averagePaceSeconds / 60).floor();
    final seconds = (averagePaceSeconds % 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Toplam süreyi formatla
  String get formattedTotalDuration {
    if (totalDurationSeconds <= 0) return '0m';
    final hours = totalDurationSeconds ~/ 3600;
    final minutes = (totalDurationSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}s ${minutes}d';
    }
    return '${minutes}d';
  }

  /// Günlük ortalama mesafe
  double get averageDailyDistanceKm {
    if (dailyStats.isEmpty) return 0;
    return totalDistanceKm / dailyStats.length;
  }
}

/// Günlük İstatistikler Entity
class DailyStatisticsEntity {
  final DateTime date;
  final int activityCount;
  final double distanceKm;
  final int durationSeconds;
  final double elevationGain;

  const DailyStatisticsEntity({
    required this.date,
    this.activityCount = 0,
    this.distanceKm = 0,
    this.durationSeconds = 0,
    this.elevationGain = 0,
  });

  /// Gün adı (Pazartesi, Salı, vb.)
  String get dayName {
    const days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return days[date.weekday - 1];
  }

  /// Ayın günü
  int get dayOfMonth => date.day;
}
