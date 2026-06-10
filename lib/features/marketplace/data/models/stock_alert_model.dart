import '../../../../core/enums/gender.dart';

class StockAlertSubscription {
  final String id;
  final String listingId;
  final String? size;
  final ListingGender? gender;

  const StockAlertSubscription({
    required this.id,
    required this.listingId,
    this.size,
    this.gender,
  });

  factory StockAlertSubscription.fromJson(Map<String, dynamic> json) {
    final genderStr = json['gender'] as String?;
    return StockAlertSubscription(
      id: json['id'] as String,
      listingId: json['listing_id'] as String,
      size: json['size'] as String?,
      gender: genderStr != null ? ListingGender.fromString(genderStr) : null,
    );
  }

  String get scopeKey =>
      '$listingId::${size ?? ''}::${gender?.value ?? ''}';
}

class ListingStockAlertGroup {
  final String listingId;
  final String listingTitle;
  final String? imageUrl;
  final int alertCount;
  final List<StockAlertRequest> requests;

  const ListingStockAlertGroup({
    required this.listingId,
    required this.listingTitle,
    this.imageUrl,
    required this.alertCount,
    required this.requests,
  });
}

class StockAlertRequest {
  final String id;
  final String userId;
  final String userName;
  final String? avatarUrl;
  final String? size;
  final ListingGender? gender;
  final DateTime createdAt;

  const StockAlertRequest({
    required this.id,
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.size,
    this.gender,
    required this.createdAt,
  });

  factory StockAlertRequest.fromJson(Map<String, dynamic> json) {
    final user = json['users'] as Map<String, dynamic>?;
    final firstName = user?['first_name'] as String? ?? '';
    final lastName = user?['last_name'] as String? ?? '';
    final genderStr = json['gender'] as String?;

    return StockAlertRequest(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      userName: '$firstName $lastName'.trim(),
      avatarUrl: user?['avatar_url'] as String?,
      size: json['size'] as String?,
      gender: genderStr != null ? ListingGender.fromString(genderStr) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get scopeLabel {
    if (size == null) return 'Tüm ürün';
    final genderLabel = switch (gender) {
      ListingGender.male => 'Erkek',
      ListingGender.female => 'Kadın',
      _ => null,
    };
    if (genderLabel != null) return '$genderLabel $size';
    return size!;
  }
}
