class EventResultEntity {
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

  const EventResultEntity({
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

  /// Süreyi kullanıcıya gösterilecek formatta döndür (mm:ss veya hh:mm:ss)
  String? get formattedFinishTime {
    final seconds = finishTimeSeconds;
    if (seconds == null || seconds <= 0) return null;

    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

