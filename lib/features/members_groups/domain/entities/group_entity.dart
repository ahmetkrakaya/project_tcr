import '../../../workout/domain/entities/workout_entity.dart' show WorkoutDefinitionEntity;

/// Training Group Entity - Antrenman Grubu
class TrainingGroupEntity {
  final String id;
  final String name;
  final String? description;
  final String? targetDistance;
  final int difficultyLevel;
  final String color;
  final String icon;
  final bool isActive;
  final int memberCount;
  final bool isUserMember;
  final String? createdBy;
  final DateTime createdAt;

  const TrainingGroupEntity({
    required this.id,
    required this.name,
    this.description,
    this.targetDistance,
    this.difficultyLevel = 1,
    this.color = '#3B82F6',
    this.icon = 'directions_run',
    this.isActive = true,
    this.memberCount = 0,
    this.isUserMember = false,
    this.createdBy,
    required this.createdAt,
  });

  /// Zorluk seviyesi metni
  String get difficultyText {
    switch (difficultyLevel) {
      case 1:
        return 'Başlangıç';
      case 2:
        return 'Kolay';
      case 3:
        return 'Orta';
      case 4:
        return 'Zor';
      case 5:
        return 'Çok Zor';
      default:
        return 'Bilinmiyor';
    }
  }
}

/// Group Member Entity - Grup Üyesi
class GroupMemberEntity {
  final String id;
  final String groupId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final DateTime joinedAt;

  const GroupMemberEntity({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.joinedAt,
  });
}


/// Event Group Program Entity - Etkinlik Grup Programı
class EventGroupProgramEntity {
  final String id;
  final String eventId;
  final String trainingGroupId;
  final String? groupName;
  final String? groupColor;
  final String programContent;
  /// Yapılandırılmış antrenman (segment, hedef, yineleme). FIT/TCX export için.
  final WorkoutDefinitionEntity? workoutDefinition;
  final String? routeId;
  final String? routeName;
  final String? trainingTypeId;
  final String? trainingTypeName;
  final String? trainingTypeDescription;
  final String? trainingTypeColor;
  /// Eşik temposuna göre minimum sapma (saniye). Negatif = daha hızlı.
  final int? thresholdOffsetMinSeconds;
  /// Eşik temposuna göre maksimum sapma (saniye). Pozitif = daha yavaş.
  final int? thresholdOffsetMaxSeconds;
  final int orderIndex;
  final DateTime createdAt;

  const EventGroupProgramEntity({
    required this.id,
    required this.eventId,
    required this.trainingGroupId,
    this.groupName,
    this.groupColor,
    required this.programContent,
    this.workoutDefinition,
    this.routeId,
    this.routeName,
    this.trainingTypeId,
    this.trainingTypeName,
    this.trainingTypeDescription,
    this.trainingTypeColor,
    this.thresholdOffsetMinSeconds,
    this.thresholdOffsetMaxSeconds,
    this.orderIndex = 0,
    required this.createdAt,
  });
}
