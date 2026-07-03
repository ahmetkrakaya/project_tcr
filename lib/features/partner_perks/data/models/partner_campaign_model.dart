class PartnerCampaignModel {
  const PartnerCampaignModel({
    required this.id,
    required this.slug,
    required this.partnerName,
    this.tagline,
    this.logoUrl,
    required this.brandColor,
    required this.discountPercent,
    required this.discountLabel,
    this.terms,
    required this.redemptionHint,
    this.locationName,
    this.locationAddress,
    this.locationLat,
    this.locationLng,
    this.promoCode,
    this.websiteUrl,
    required this.startsAt,
    this.endsAt,
    required this.isActive,
    required this.sortOrder,
    this.qrRedemptionEnabled = false,
    this.adminOnly = false,
    this.usageLimitType = 'once_per_day',
    this.usageLimitCount,
    this.successMessage,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String slug;
  final String partnerName;
  final String? tagline;
  final String? logoUrl;
  final String brandColor;
  final int discountPercent;
  final String discountLabel;
  final String? terms;
  final String redemptionHint;
  final String? locationName;
  final String? locationAddress;
  final double? locationLat;
  final double? locationLng;
  final String? promoCode;
  final String? websiteUrl;
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool isActive;
  final int sortOrder;
  final bool qrRedemptionEnabled;
  final bool adminOnly;
  final String usageLimitType;
  final int? usageLimitCount;
  final String? successMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool isCurrentlyActive({DateTime? at}) {
    if (!isActive) return false;
    final now = at ?? DateTime.now();
    if (now.isBefore(startsAt)) return false;
    if (endsAt != null && now.isAfter(endsAt!)) return false;
    return true;
  }

  factory PartnerCampaignModel.fromJson(Map<String, dynamic> json) {
    return PartnerCampaignModel(
      id: json['id'] as String,
      slug: json['slug'] as String,
      partnerName: json['partner_name'] as String,
      tagline: json['tagline'] as String?,
      logoUrl: json['logo_url'] as String?,
      brandColor: json['brand_color'] as String? ?? '#1B4332',
      discountPercent: json['discount_percent'] as int? ?? 0,
      discountLabel: json['discount_label'] as String? ?? '',
      terms: json['terms'] as String?,
      redemptionHint:
          json['redemption_hint'] as String? ?? 'Bu ekranı kasada gösterin',
      locationName: json['location_name'] as String?,
      locationAddress: json['location_address'] as String?,
      locationLat: (json['location_lat'] as num?)?.toDouble(),
      locationLng: (json['location_lng'] as num?)?.toDouble(),
      promoCode: json['promo_code'] as String?,
      websiteUrl: json['website_url'] as String?,
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: json['ends_at'] != null
          ? DateTime.parse(json['ends_at'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
      qrRedemptionEnabled: json['qr_redemption_enabled'] as bool? ?? false,
      adminOnly: json['admin_only'] as bool? ?? false,
      usageLimitType: json['usage_limit_type'] as String? ?? 'once_per_day',
      usageLimitCount: json['usage_limit_count'] as int?,
      successMessage: json['success_message'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slug': slug,
      'partner_name': partnerName,
      'tagline': tagline,
      'logo_url': logoUrl,
      'brand_color': brandColor,
      'discount_percent': discountPercent,
      'discount_label': discountLabel,
      'terms': terms,
      'redemption_hint': redemptionHint,
      'location_name': locationName,
      'location_address': locationAddress,
      'location_lat': locationLat,
      'location_lng': locationLng,
      'promo_code': promoCode,
      'website_url': websiteUrl,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt?.toUtc().toIso8601String(),
      'is_active': isActive,
      'sort_order': sortOrder,
      'qr_redemption_enabled': qrRedemptionEnabled,
      'admin_only': adminOnly,
      'usage_limit_type': usageLimitType,
      'usage_limit_count': usageLimitCount,
      'success_message': successMessage,
    };
  }

  PartnerCampaignModel copyWith({
    String? id,
    String? slug,
    String? partnerName,
    String? tagline,
    String? logoUrl,
    String? brandColor,
    int? discountPercent,
    String? discountLabel,
    String? terms,
    String? redemptionHint,
    String? locationName,
    String? locationAddress,
    double? locationLat,
    double? locationLng,
    String? promoCode,
    String? websiteUrl,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? isActive,
    int? sortOrder,
    bool? qrRedemptionEnabled,
    bool? adminOnly,
    String? usageLimitType,
    int? usageLimitCount,
    String? successMessage,
  }) {
    return PartnerCampaignModel(
      id: id ?? this.id,
      slug: slug ?? this.slug,
      partnerName: partnerName ?? this.partnerName,
      tagline: tagline ?? this.tagline,
      logoUrl: logoUrl ?? this.logoUrl,
      brandColor: brandColor ?? this.brandColor,
      discountPercent: discountPercent ?? this.discountPercent,
      discountLabel: discountLabel ?? this.discountLabel,
      terms: terms ?? this.terms,
      redemptionHint: redemptionHint ?? this.redemptionHint,
      locationName: locationName ?? this.locationName,
      locationAddress: locationAddress ?? this.locationAddress,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      promoCode: promoCode ?? this.promoCode,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      qrRedemptionEnabled: qrRedemptionEnabled ?? this.qrRedemptionEnabled,
      adminOnly: adminOnly ?? this.adminOnly,
      usageLimitType: usageLimitType ?? this.usageLimitType,
      usageLimitCount: usageLimitCount ?? this.usageLimitCount,
      successMessage: successMessage ?? this.successMessage,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
