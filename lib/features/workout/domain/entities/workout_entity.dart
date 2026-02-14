/// Segment türü: Isınma, Ana Antrenman, Toparlanma, Soğuma
enum WorkoutSegmentType {
  warmup,
  main,
  recovery,
  cooldown;

  /// Enum değerinin string adı (VDOT/API için)
  String get name {
    switch (this) {
      case WorkoutSegmentType.warmup:
        return 'warmup';
      case WorkoutSegmentType.main:
        return 'main';
      case WorkoutSegmentType.recovery:
        return 'recovery';
      case WorkoutSegmentType.cooldown:
        return 'cooldown';
    }
  }

  String get displayName {
    switch (this) {
      case WorkoutSegmentType.warmup:
        return 'Isınma';
      case WorkoutSegmentType.main:
        return 'Ana Antrenman';
      case WorkoutSegmentType.recovery:
        return 'Toparlanma';
      case WorkoutSegmentType.cooldown:
        return 'Soğuma';
    }
  }
}

/// Hedef türü: Süre, Mesafe, Açık
enum WorkoutTargetType {
  duration,
  distance,
  open;

  String get displayName {
    switch (this) {
      case WorkoutTargetType.duration:
        return 'Süre';
      case WorkoutTargetType.distance:
        return 'Mesafe';
      case WorkoutTargetType.open:
        return 'Açık';
    }
  }
}

/// Hedef: Hedef Yok, Tempo, Kalp Atış Hızı, Kadans, Güç
enum WorkoutTarget {
  none,
  pace,
  heartRate,
  cadence,
  power;

  String get displayName {
    switch (this) {
      case WorkoutTarget.none:
        return 'Hedef Yok';
      case WorkoutTarget.pace:
        return 'Tempo';
      case WorkoutTarget.heartRate:
        return 'Kalp Atış Hızı';
      case WorkoutTarget.cadence:
        return 'Kadans';
      case WorkoutTarget.power:
        return 'Güç';
    }
  }
}

/// Tek bir antrenman segmenti (Isınma, Ana, Toparlanma, Soğuma)
class WorkoutSegmentEntity {
  final WorkoutSegmentType segmentType;
  final WorkoutTargetType targetType;
  final WorkoutTarget target;
  final int? durationSeconds;
  final double? distanceMeters;
  /// Pace saniye/km (tek değer veya ortalama)
  final int? paceSecondsPerKm;
  final int? paceSecondsPerKmMin;
  final int? paceSecondsPerKmMax;
  /// VDOT override: kullanıcı özel pace girdiyse
  final int? customPaceSecondsPerKm;
  /// VDOT bazlı pace kullan: true = her kullanıcı kendi VDOT'una göre pace görecek, false/null = manuel pace
  final bool? useVdotForPace;
  final int? heartRateBpmMin;
  final int? heartRateBpmMax;
  final int? cadenceMin;
  final int? cadenceMax;
  final int? powerWattsMin;
  final int? powerWattsMax;

  const WorkoutSegmentEntity({
    required this.segmentType,
    required this.targetType,
    required this.target,
    this.durationSeconds,
    this.distanceMeters,
    this.paceSecondsPerKm,
    this.paceSecondsPerKmMin,
    this.paceSecondsPerKmMax,
    this.customPaceSecondsPerKm,
    this.useVdotForPace,
    this.heartRateBpmMin,
    this.heartRateBpmMax,
    this.cadenceMin,
    this.cadenceMax,
    this.powerWattsMin,
    this.powerWattsMax,
  });

  /// Etkili pace (özel pace varsa onu, yoksa paceSecondsPerKm veya min/max kullan)
  int? get effectivePaceSecondsPerKm =>
      customPaceSecondsPerKm ?? paceSecondsPerKm ?? paceSecondsPerKmMin;
}

/// Adım: tek segment veya yineleme bloğu
class WorkoutStepEntity {
  final String type; // 'segment' | 'repeat'
  final WorkoutSegmentEntity? segment;
  final int? repeatCount;
  final List<WorkoutStepEntity>? steps;

  const WorkoutStepEntity({
    required this.type,
    this.segment,
    this.repeatCount,
    this.steps,
  });

  bool get isSegment => type == 'segment';
  bool get isRepeat => type == 'repeat';
}

/// Yapılandırılmış antrenman tanımı (FIT/TCX/JSONV2 export için)
class WorkoutDefinitionEntity {
  final List<WorkoutStepEntity> steps;

  const WorkoutDefinitionEntity({required this.steps});

  bool get isEmpty => steps.isEmpty;
}
