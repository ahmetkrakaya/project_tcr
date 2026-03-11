/// Kullanıcı Bağış Kaydı
class DonationEntity {
  final String id;
  final String userId;
  final String? eventId;
  final String? raceName;
  final DateTime? raceDate;
  final String foundationName;
  final double amount;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Join alanları
  final String userName;
  final String? userAvatarUrl;
  final String? eventTitle;
  final DateTime? eventStartTime;

  const DonationEntity({
    required this.id,
    required this.userId,
    this.eventId,
    this.raceName,
    this.raceDate,
    required this.foundationName,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
    required this.userName,
    this.userAvatarUrl,
    this.eventTitle,
    this.eventStartTime,
  });

  /// Etkinlikten mi yoksa manuel mi girilmiş
  bool get isFromEvent => eventId != null;

  /// Gösterilecek yarış adı
  String get displayRaceName => eventTitle ?? raceName ?? '';

  /// Yarış/etkinlik tarihi
  DateTime get effectiveRaceDate =>
      eventStartTime ?? raceDate ?? createdAt;

  /// Güncelleme yapılabilir mi (yarış tarihinden sonra 5 gün içinde)
  bool get canEdit {
    final deadline = effectiveRaceDate.add(const Duration(days: 5));
    return DateTime.now().isBefore(deadline);
  }
}
