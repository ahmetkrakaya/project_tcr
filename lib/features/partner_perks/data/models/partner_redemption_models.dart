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
    this.successMessage,
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
  final String? successMessage;

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
      successMessage: json['success_message'] as String?,
    );
  }

  bool get _hasUsageLimitReached {
    switch (reason) {
      case 'daily_limit_reached':
      case 'lifetime_limit_reached':
      case 'weekly_limit_reached':
      case 'total_limit_reached':
        return true;
      default:
        return false;
    }
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

  /// Üye uygulamasında gösterilecek mesaj (başarı mesajı öncelikli).
  String get memberDisplayMessage {
    if (canRedeem) return statusMessage;

    final custom = successMessage?.trim();
    if (custom != null && custom.isNotEmpty && _hasUsageLimitReached) {
      return custom;
    }

    return statusMessage;
  }

  bool get showRedemptionSuccess => !canRedeem && _hasUsageLimitReached;
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
    final expiresRaw = json['expires_at'];
    DateTime? expiresAt;
    if (expiresRaw is String) {
      expiresAt = DateTime.tryParse(expiresRaw);
    } else if (expiresRaw != null) {
      expiresAt = DateTime.tryParse(expiresRaw.toString());
    }

    if (expiresAt == null) {
      throw FormatException('Invalid expires_at: $expiresRaw');
    }

    return PartnerRedemptionToken(
      token: json['token'] as String,
      redeemUrl: json['redeem_url'] as String,
      expiresAt: expiresAt.toLocal(),
    );
  }
}

class PartnerRedemptionReportSummary {
  const PartnerRedemptionReportSummary({
    required this.totalSuccess,
    required this.uniqueUsers,
    this.totalAttempts = 0,
    this.rejectedCount = 0,
  });

  final int totalSuccess;
  final int uniqueUsers;
  final int totalAttempts;
  final int rejectedCount;

  factory PartnerRedemptionReportSummary.fromJson(Map<String, dynamic> json) {
    return PartnerRedemptionReportSummary(
      totalSuccess: json['total_success'] as int? ?? 0,
      uniqueUsers: json['unique_users'] as int? ?? 0,
      totalAttempts: json['total_attempts'] as int? ?? 0,
      rejectedCount: json['rejected_count'] as int? ?? 0,
    );
  }

  double get successRate =>
      totalAttempts == 0 ? 0 : (totalSuccess / totalAttempts) * 100;
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
      redeemedAt:
          DateTime.parse(json['redeemed_at'] as String).toLocal(),
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

class PartnerRedemptionReportFilters {
  const PartnerRedemptionReportFilters({
    this.campaignId,
    this.fromDate,
    this.toDate,
  });

  final String? campaignId;
  final DateTime? fromDate;
  final DateTime? toDate;

  PartnerRedemptionReportFilters copyWith({
    String? campaignId,
    bool clearCampaignId = false,
    DateTime? fromDate,
    bool clearFromDate = false,
    DateTime? toDate,
    bool clearToDate = false,
  }) {
    return PartnerRedemptionReportFilters(
      campaignId: clearCampaignId ? null : (campaignId ?? this.campaignId),
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PartnerRedemptionReportFilters &&
        other.campaignId == campaignId &&
        other.fromDate == fromDate &&
        other.toDate == toDate;
  }

  @override
  int get hashCode => Object.hash(campaignId, fromDate, toDate);
}

class PartnerRedemptionDashboardUsage {
  const PartnerRedemptionDashboardUsage({
    required this.totalSuccess,
    required this.totalAttempts,
    required this.uniqueUsers,
    required this.rejectedAlreadyUsed,
    required this.rejectedExpired,
    required this.rejectedLimit,
    required this.rejectedInactive,
  });

  final int totalSuccess;
  final int totalAttempts;
  final int uniqueUsers;
  final int rejectedAlreadyUsed;
  final int rejectedExpired;
  final int rejectedLimit;
  final int rejectedInactive;

  factory PartnerRedemptionDashboardUsage.fromJson(Map<String, dynamic> json) {
    return PartnerRedemptionDashboardUsage(
      totalSuccess: json['total_success'] as int? ?? 0,
      totalAttempts: json['total_attempts'] as int? ?? 0,
      uniqueUsers: json['unique_users'] as int? ?? 0,
      rejectedAlreadyUsed: json['rejected_already_used'] as int? ?? 0,
      rejectedExpired: json['rejected_expired'] as int? ?? 0,
      rejectedLimit: json['rejected_limit'] as int? ?? 0,
      rejectedInactive: json['rejected_inactive'] as int? ?? 0,
    );
  }

  int get totalRejected =>
      rejectedAlreadyUsed +
      rejectedExpired +
      rejectedLimit +
      rejectedInactive;

  double get successRate =>
      totalAttempts == 0 ? 0 : (totalSuccess / totalAttempts) * 100;
}

class PartnerRedemptionCampaignUsage {
  const PartnerRedemptionCampaignUsage({
    required this.campaignId,
    required this.partnerName,
    required this.isActive,
    required this.successCount,
    required this.totalCount,
  });

  final String campaignId;
  final String partnerName;
  final bool isActive;
  final int successCount;
  final int totalCount;

  factory PartnerRedemptionCampaignUsage.fromJson(Map<String, dynamic> json) {
    return PartnerRedemptionCampaignUsage(
      campaignId: json['campaign_id'] as String,
      partnerName: json['partner_name'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? false,
      successCount: json['success_count'] as int? ?? 0,
      totalCount: json['total_count'] as int? ?? 0,
    );
  }
}

class PartnerRedemptionDashboard {
  const PartnerRedemptionDashboard({
    required this.usage,
    required this.byCampaign,
  });

  final PartnerRedemptionDashboardUsage usage;
  final List<PartnerRedemptionCampaignUsage> byCampaign;

  factory PartnerRedemptionDashboard.fromJson(Map<String, dynamic> json) {
    final byCampaignJson = json['by_campaign'];
    return PartnerRedemptionDashboard(
      usage: PartnerRedemptionDashboardUsage.fromJson(
        json['usage'] as Map<String, dynamic>? ?? {},
      ),
      byCampaign: byCampaignJson is List
          ? byCampaignJson
              .map((e) => PartnerRedemptionCampaignUsage.fromJson(
                    e as Map<String, dynamic>,
                  ))
              .toList()
          : const [],
    );
  }
}
