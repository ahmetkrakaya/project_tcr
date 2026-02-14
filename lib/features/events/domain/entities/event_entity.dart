/// Tek kulvar tanımı (pace aralığı)
class LaneEntity {
  final int laneNumber;
  final int paceMinSecPerKm;
  final int paceMaxSecPerKm;
  final String? label;

  const LaneEntity({
    required this.laneNumber,
    required this.paceMinSecPerKm,
    required this.paceMaxSecPerKm,
    this.label,
  });

  /// paceSecPerKm bu kulvarın aralığına düşüyor mu (min <= pace <= max)
  bool containsPace(int paceSecPerKm) {
    return paceSecPerKm >= paceMinSecPerKm && paceSecPerKm <= paceMaxSecPerKm;
  }

  static LaneEntity? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final laneNumber = json['lane_number'] as int?;
    final paceMin = json['pace_min_sec_per_km'] as int?;
    final paceMax = json['pace_max_sec_per_km'] as int?;
    if (laneNumber == null || paceMin == null || paceMax == null) return null;
    return LaneEntity(
      laneNumber: laneNumber,
      paceMinSecPerKm: paceMin,
      paceMaxSecPerKm: paceMax,
      label: json['label'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lane_number': laneNumber,
      'pace_min_sec_per_km': paceMinSecPerKm,
      'pace_max_sec_per_km': paceMaxSecPerKm,
      if (label != null && label!.isNotEmpty) 'label': label,
    };
  }
}

/// Pist kulvar config (event seviyesinde)
class LaneConfigEntity {
  final double? trackLengthKm;
  final List<LaneEntity> lanes;

  const LaneConfigEntity({
    this.trackLengthKm,
    required this.lanes,
  });

  bool get isEmpty => lanes.isEmpty;

  /// Kullanıcının pace'ı (sn/km) hangi kulvara düşüyor; yoksa null
  int? laneNumberForPace(int paceSecPerKm) {
    for (final lane in lanes) {
      if (lane.containsPace(paceSecPerKm)) return lane.laneNumber;
    }
    return null;
  }

  static LaneConfigEntity? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final lanesList = json['lanes'] as List<dynamic>?;
    final lanes = <LaneEntity>[];
    if (lanesList != null) {
      for (final e in lanesList) {
        final lane = LaneEntity.fromJson(e as Map<String, dynamic>?);
        if (lane != null) lanes.add(lane);
      }
    }
    if (lanes.isEmpty) return null;
    return LaneConfigEntity(
      trackLengthKm: (json['track_length_km'] as num?)?.toDouble(),
      lanes: lanes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (trackLengthKm != null) 'track_length_km': trackLengthKm,
      'lanes': lanes.map((e) => e.toJson()).toList(),
    };
  }
}

/// Event Entity
class EventEntity {
  final String id;
  final String title;
  final String? description;
  final EventType eventType;
  final EventStatus status;
  final DateTime startTime;
  final DateTime? endTime;
  final String? locationName;
  final String? locationAddress;
  final double? locationLat;
  final double? locationLng;
  final String? routeId;
  final String? trainingGroupId;
  final String? trainingTypeId;
  final String? trainingTypeName;
  final String? trainingTypeDescription;
  final String? trainingTypeColor;
  /// Eşik temposuna göre minimum sapma (saniye). Negatif = daha hızlı.
  final int? thresholdOffsetMinSeconds;
  /// Eşik temposuna göre maksimum sapma (saniye). Pozitif = daha yavaş.
  final int? thresholdOffsetMaxSeconds;
  final String? weatherNote;
  final String? coachNotes;
  final String? bannerImageUrl;
  final String createdBy;
  final DateTime createdAt;
  final int participantCount;
  final bool isUserParticipating;
  /// team: toplu antrenman (Katılıyorum/RSVP); individual: isteğe bağlı bireysel (katılım kaydı yok). null = team sayılır.
  final String? participationType;
  /// Pist rotada pace bazlı kulvar ataması (track ise dolu olabilir)
  final LaneConfigEntity? laneConfig;
  /// Etkinlik pinlenmiş mi (ana sayfada en üstte gösterilir)
  final bool isPinned;
  /// Pinleme zamanı (sıralama için)
  final DateTime? pinnedAt;
  /// Tekrarlayan etkinlik mi
  final bool isRecurring;
  /// iCal RRULE (örn. FREQ=WEEKLY;BYDAY=TU)
  final String? recurrenceRule;
  /// Seri kök etkinlik id (tekrarlayanlarda)
  final String? parentEventId;
  /// Tekrarlama bitiş tarihi (opsiyonel)
  final DateTime? recurrenceEndDate;
  /// Sadece bu tekrar düzenlendi; sonraki oluşturulurken şablon kullanılmaz
  final bool isRecurrenceException;

  const EventEntity({
    required this.id,
    required this.title,
    this.description,
    required this.eventType,
    required this.status,
    required this.startTime,
    this.endTime,
    this.locationName,
    this.locationAddress,
    this.locationLat,
    this.locationLng,
    this.routeId,
    this.trainingGroupId,
    this.trainingTypeId,
    this.trainingTypeName,
    this.trainingTypeDescription,
    this.trainingTypeColor,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
    this.weatherNote,
    this.coachNotes,
    this.bannerImageUrl,
    required this.createdBy,
    required this.createdAt,
    this.participantCount = 0,
    this.isUserParticipating = false,
    this.participationType,
    this.laneConfig,
    this.isPinned = false,
    this.pinnedAt,
    this.isRecurring = false,
    this.recurrenceRule,
    this.parentEventId,
    this.recurrenceEndDate,
    this.isRecurrenceException = false,
  });

  /// Tekrarlayan seriye ait mi (kökte veya child)
  bool get isPartOfRecurringSeries => isRecurring || (parentEventId != null && parentEventId!.isNotEmpty);

  /// Etkinlik bugün mü?
  bool get isToday {
    final now = DateTime.now();
    return startTime.year == now.year &&
        startTime.month == now.month &&
        startTime.day == now.day;
  }

  /// Etkinlik geçmiş mi?
  bool get isPast => startTime.isBefore(DateTime.now());

  /// Etkinlik bu hafta mı?
  bool get isThisWeek {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    return startTime.isAfter(weekStart) && startTime.isBefore(weekEnd);
  }

  /// Formatlanmış tarih
  String get formattedDate {
    final months = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
    ];
    return '${startTime.day} ${months[startTime.month - 1]}';
  }

  /// Formatlanmış saat
  String get formattedTime {
    return '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
  }

  /// Haftanın günü
  String get dayOfWeek {
    final days = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
    return days[startTime.weekday - 1];
  }

  /// Kısa gün adı
  String get shortDayOfWeek {
    final days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return days[startTime.weekday - 1];
  }
}

/// Etkinlik türleri
enum EventType {
  training,
  race,
  social,
  workshop,
  other;

  static EventType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'training':
        return EventType.training;
      case 'race':
        return EventType.race;
      case 'social':
        return EventType.social;
      case 'workshop':
        return EventType.workshop;
      default:
        return EventType.other;
    }
  }

  String get displayName {
    switch (this) {
      case EventType.training:
        return 'Antrenman';
      case EventType.race:
        return 'Yarış';
      case EventType.social:
        return 'Sosyal';
      case EventType.workshop:
        return 'Workshop';
      case EventType.other:
        return 'Diğer';
    }
  }
}

/// Etkinlik durumları
enum EventStatus {
  draft,
  published,
  cancelled,
  completed;

  static EventStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'draft':
        return EventStatus.draft;
      case 'published':
        return EventStatus.published;
      case 'cancelled':
        return EventStatus.cancelled;
      case 'completed':
        return EventStatus.completed;
      default:
        return EventStatus.draft;
    }
  }
}

/// RSVP durumu
enum RsvpStatus {
  going,
  notGoing,
  maybe;

  static RsvpStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'going':
        return RsvpStatus.going;
      case 'not_going':
        return RsvpStatus.notGoing;
      case 'maybe':
        return RsvpStatus.maybe;
      default:
        return RsvpStatus.maybe;
    }
  }

  String toDbString() {
    switch (this) {
      case RsvpStatus.going:
        return 'going';
      case RsvpStatus.notGoing:
        return 'not_going';
      case RsvpStatus.maybe:
        return 'maybe';
    }
  }
}

/// Etkinlik katılımcısı
class EventParticipantEntity {
  final String id;
  final String eventId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final RsvpStatus status;
  final String? note;
  final DateTime respondedAt;
  final bool checkedIn;
  final DateTime? checkedInAt;

  const EventParticipantEntity({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.status,
    this.note,
    required this.respondedAt,
    this.checkedIn = false,
    this.checkedInAt,
  });
}

/// Antrenman grubu
class TrainingGroupEntity {
  final String id;
  final String name;
  final String? description;
  final String? targetDistance;
  final int difficultyLevel;
  final String color;
  final String icon;
  final bool isActive;

  const TrainingGroupEntity({
    required this.id,
    required this.name,
    this.description,
    this.targetDistance,
    this.difficultyLevel = 1,
    this.color = '#3B82F6',
    this.icon = 'running',
    this.isActive = true,
  });
}

/// Antrenman türü (Recovery Run, Interval, vb.)
class TrainingTypeEntity {
  final String id;
  final String name;
  final String displayName;
  final String description;
  final String icon;
  final String color;
  final int sortOrder;
  final bool isActive;
  /// Eşik temposuna göre minimum sapma (saniye). Negatif = daha hızlı.
  final int? thresholdOffsetMinSeconds;
  /// Eşik temposuna göre maksimum sapma (saniye). Pozitif = daha yavaş.
  final int? thresholdOffsetMaxSeconds;

  const TrainingTypeEntity({
    required this.id,
    required this.name,
    required this.displayName,
    required this.description,
    this.icon = 'directions_run',
    this.color = '#3B82F6',
    this.sortOrder = 0,
    this.isActive = true,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
  });
}
