import '../../domain/entities/donation_entity.dart';

/// Donation Model - Supabase JSON mapping
class DonationModel {
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

  const DonationModel({
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

  static String _parseFoundationName(Map<String, dynamic> json) {
    final foundations = json['foundations'] as Map<String, dynamic>?;
    if (foundations != null && foundations['name'] != null) {
      return foundations['name'] as String;
    }
    return json['foundation_name'] as String? ?? '';
  }

  factory DonationModel.fromJson(Map<String, dynamic> json) {
    final user = json['users'] as Map<String, dynamic>?;
    final event = json['events'] as Map<String, dynamic>?;

    final firstName = user?['first_name'] as String? ?? '';
    final lastName = user?['last_name'] as String? ?? '';
    final fullName = '$firstName $lastName'.trim();

    return DonationModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      eventId: json['event_id'] as String?,
      raceName: json['race_name'] as String?,
      raceDate: json['race_date'] != null
          ? DateTime.parse(json['race_date'] as String)
          : null,
      foundationName: _parseFoundationName(json),
      amount: (json['amount'] as num).toDouble(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      userName: fullName.isNotEmpty ? fullName : 'Bilinmeyen',
      userAvatarUrl: user?['avatar_url'] as String?,
      eventTitle: event?['title'] as String?,
      eventStartTime: event?['start_time'] != null
          ? DateTime.parse(event!['start_time'] as String)
          : null,
    );
  }

  DonationEntity toEntity() {
    return DonationEntity(
      id: id,
      userId: userId,
      eventId: eventId,
      raceName: raceName,
      raceDate: raceDate,
      foundationName: foundationName,
      amount: amount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      userName: userName,
      userAvatarUrl: userAvatarUrl,
      eventTitle: eventTitle,
      eventStartTime: eventStartTime,
    );
  }
}
