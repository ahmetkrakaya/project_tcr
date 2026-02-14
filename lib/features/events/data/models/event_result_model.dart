import '../../domain/entities/event_result_entity.dart';

class EventResultModel {
  final String id;
  final String eventId;
  final String userId;
  final String fullName;
  final String? avatarUrl;
  final String? gender;
  final int? finishTimeSeconds;
  final int? rankOverall;
  final int? rankGender;
  final String? notes;

  const EventResultModel({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.fullName,
    this.avatarUrl,
    this.gender,
    this.finishTimeSeconds,
    this.rankOverall,
    this.rankGender,
    this.notes,
  });

  factory EventResultModel.fromJson(Map<String, dynamic> json) {
    return EventResultModel(
      id: json['result_id'] as String? ?? json['id'] as String,
      eventId: json['event_id'] as String,
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String? ??
          (json['users'] != null
              ? '${(json['users'] as Map<String, dynamic>)['first_name'] ?? ''} ${(json['users'] as Map<String, dynamic>)['last_name'] ?? ''}'
                  .trim()
              : ''),
      avatarUrl: (json['avatar_url'] ??
              (json['users'] != null
                  ? (json['users'] as Map<String, dynamic>)['avatar_url']
                  : null))
          as String?,
      gender: json['gender'] as String?,
      finishTimeSeconds: json['finish_time_seconds'] as int?,
      rankOverall: json['rank_overall'] as int?,
      rankGender: json['rank_gender'] as int?,
      notes: json['notes'] as String?,
    );
  }

  EventResultEntity toEntity() {
    return EventResultEntity(
      id: id,
      eventId: eventId,
      userId: userId,
      fullName: fullName.isEmpty ? 'Anonim' : fullName,
      avatarUrl: avatarUrl,
      gender: gender,
      finishTimeSeconds: finishTimeSeconds,
      rankOverall: rankOverall,
      rankGender: rankGender,
      notes: notes,
    );
  }
}

