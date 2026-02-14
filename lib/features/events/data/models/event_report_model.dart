/// Event Report Model
class EventReportModel {
  final String eventId;
  final String eventTitle;
  final DateTime eventDate;
  final int participantCount;
  final String eventType;
  final String? participationType;

  const EventReportModel({
    required this.eventId,
    required this.eventTitle,
    required this.eventDate,
    required this.participantCount,
    required this.eventType,
    this.participationType,
  });

  factory EventReportModel.fromJson(Map<String, dynamic> json) {
    return EventReportModel(
      eventId: json['event_id'] as String,
      eventTitle: json['event_title'] as String,
      eventDate: DateTime.parse(json['event_date'] as String),
      participantCount: json['participant_count'] as int,
      eventType: json['event_type'] as String,
      participationType: json['participation_type'] as String?,
    );
  }
}

/// Event Report Summary Model
class EventReportSummaryModel {
  final int totalEvents;
  final int totalParticipants;
  final double averageParticipants;
  final List<EventReportModel> events;

  const EventReportSummaryModel({
    required this.totalEvents,
    required this.totalParticipants,
    required this.averageParticipants,
    required this.events,
  });

  factory EventReportSummaryModel.fromJson(Map<String, dynamic> json) {
    final eventsList = json['events'] as List<dynamic>;
    final events = eventsList
        .map((e) => EventReportModel.fromJson(e as Map<String, dynamic>))
        .toList();

    return EventReportSummaryModel(
      totalEvents: json['total_events'] as int,
      totalParticipants: json['total_participants'] as int,
      averageParticipants: (json['average_participants'] as num).toDouble(),
      events: events,
    );
  }
}
