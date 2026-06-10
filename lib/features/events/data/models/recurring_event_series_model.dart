import '../../domain/entities/event_entity.dart';

/// Tekrarlayan serideki rota özeti.
class RecurringEventRouteInfo {
  final String name;
  final String? label;
  final double? distanceKm;

  const RecurringEventRouteInfo({
    required this.name,
    this.label,
    this.distanceKm,
  });

  String get displayText {
    final buffer = StringBuffer(name);
    if (label != null && label!.trim().isNotEmpty) {
      buffer.write(' ($label)');
    }
    if (distanceKm != null && distanceKm! > 0) {
      final km = distanceKm! >= 10
          ? distanceKm!.toStringAsFixed(1)
          : distanceKm!.toStringAsFixed(2);
      buffer.write(' · $km km');
    }
    return buffer.toString();
  }
}

/// Tekrarlayan etkinlik serisi özeti (admin listesi için).
class RecurringEventSeriesModel {
  final String rootEventId;
  final String latestEventId;
  final String title;
  final String? description;
  final String createdByName;
  final List<RecurringEventRouteInfo> routes;
  final EventType eventType;
  final String? recurrenceRule;
  final DateTime? recurrenceEndDate;
  final DateTime latestStartTime;
  final DateTime firstStartTime;
  final int occurrenceCount;
  final bool isActive;

  const RecurringEventSeriesModel({
    required this.rootEventId,
    required this.latestEventId,
    required this.title,
    this.description,
    required this.createdByName,
    this.routes = const [],
    required this.eventType,
    this.recurrenceRule,
    this.recurrenceEndDate,
    required this.latestStartTime,
    required this.firstStartTime,
    required this.occurrenceCount,
    required this.isActive,
  });
}
