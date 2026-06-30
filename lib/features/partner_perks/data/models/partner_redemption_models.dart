class PartnerPerkEntitlement {
  const PartnerPerkEntitlement({
    required this.canRedeem,
    this.reason,
    required this.usesToday,
    required this.usesTotal,
    required this.usesWeek,
    this.nextAvailableAt,
    required this.qrEnabled,
    required this.usageLimitType,
    this.usageLimitCount,
  });

  final bool canRedeem;
  final String? reason;
  final int usesToday;
  final int usesTotal;
  final int usesWeek;
  final DateTime? nextAvailableAt;
  final bool qrEnabled;
  final String usageLimitType;
  final int? usageLimitCount;

  factory PartnerPerkEntitlement.fromJson(Map<String, dynamic> json) {
    return PartnerPerkEntitlement(
      canRedeem: json['can_redeem'] as bool? ?? false,
      reason: json['reason'] as String?,
      usesToday: json['uses_today'] as int? ?? 0,
      usesTotal: json['uses_total'] as int? ?? 0,
      usesWeek: json['uses_week'] as int? ?? 0,
      nextAvailableAt: json['next_available_at'] != null
          ? DateTime.tryParse(json['next_available_at'] as String)
          : null,
      qrEnabled: json['qr_enabled'] as bool? ?? false,
      usageLimitType: json['usage_limit_type'] as String? ?? 'once_per_day',
      usageLimitCount: json['usage_limit_count'] as int?,
    );
  }

  String get statusMessage {
    if (canRedeem) return 'Kasada okutulmasını isteyin';

    switch (reason) {
      case 'daily_limit_reached':
        return 'Bugün bu avantajı kullandınız';
      case 'lifetime_limit_reached':
        return 'Bu avantajdan yararlandınız';
      case 'weekly_limit_reached':
        return 'Haftalık kullanım hakkınız doldu';
      case 'total_limit_reached':
        return 'Toplam kullanım hakkınız doldu';
      case 'campaign_inactive':
      case 'campaign_ended':
      case 'campaign_not_started':
        return 'Kampanya şu an geçerli değil';
      default:
        return 'Şu an kullanılamıyor';
    }
  }
}

class PartnerRedemptionToken {
  const PartnerRedemptionToken({
    required this.token,
    required this.redeemUrl,
    required this.expiresAt,
  });

  final String token;
  final String redeemUrl;
  final DateTime expiresAt;

  factory PartnerRedemptionToken.fromJson(Map<String, dynamic> json) {
    return PartnerRedemptionToken(
      token: json['token'] as String,
      redeemUrl: json['redeem_url'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

class PartnerRedemptionReportSummary {
  const PartnerRedemptionReportSummary({
    required this.totalSuccess,
    required this.uniqueUsers,
  });

  final int totalSuccess;
  final int uniqueUsers;

  factory PartnerRedemptionReportSummary.fromJson(Map<String, dynamic> json) {
    return PartnerRedemptionReportSummary(
      totalSuccess: json['total_success'] as int? ?? 0,
      uniqueUsers: json['unique_users'] as int? ?? 0,
    );
  }
}

class PartnerRedemptionReportItem {
  const PartnerRedemptionReportItem({
    required this.id,
    required this.redeemedAt,
    required this.status,
    required this.campaignId,
    required this.partnerName,
    this.discountLabel,
    required this.userId,
    required this.userName,
  });

  final String id;
  final DateTime redeemedAt;
  final String status;
  final String campaignId;
  final String partnerName;
  final String? discountLabel;
  final String userId;
  final String userName;

  factory PartnerRedemptionReportItem.fromJson(Map<String, dynamic> json) {
    return PartnerRedemptionReportItem(
      id: json['id'] as String,
      redeemedAt: DateTime.parse(json['redeemed_at'] as String),
      status: json['status'] as String,
      campaignId: json['campaign_id'] as String,
      partnerName: json['partner_name'] as String? ?? '',
      discountLabel: json['discount_label'] as String?,
      userId: json['user_id'] as String,
      userName: (json['user_name'] as String? ?? '').trim(),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'success':
        return 'Başarılı';
      case 'rejected_expired':
        return 'Süresi dolmuş';
      case 'rejected_limit':
        return 'Limit aşıldı';
      case 'rejected_inactive':
        return 'Kampanya pasif';
      case 'rejected_already_used':
        return 'Zaten kullanılmış';
      default:
        return status;
    }
  }

  bool get isSuccess => status == 'success';
}

class PartnerRedemptionReport {
  const PartnerRedemptionReport({
    required this.summary,
    required this.items,
  });

  final PartnerRedemptionReportSummary summary;
  final List<PartnerRedemptionReportItem> items;

  factory PartnerRedemptionReport.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'];
    return PartnerRedemptionReport(
      summary: PartnerRedemptionReportSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? {},
      ),
      items: itemsJson is List
          ? itemsJson
              .map((e) => PartnerRedemptionReportItem.fromJson(
                    e as Map<String, dynamic>,
                  ))
              .toList()
          : const [],
    );
  }
}
