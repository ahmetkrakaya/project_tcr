import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/partner_campaign_remote_datasource.dart';
import '../../data/models/partner_campaign_model.dart';
import '../../data/models/partner_redemption_models.dart';

final _partnerCampaignDataSourceProvider =
    Provider<PartnerCampaignRemoteDataSource>((ref) {
  return PartnerCampaignRemoteDataSource(Supabase.instance.client);
});

/// Tüm kampanyalar (admin için).
final allPartnerCampaignsProvider =
    FutureProvider<List<PartnerCampaignModel>>((ref) async {
  final ds = ref.watch(_partnerCampaignDataSourceProvider);
  return ds.getAllCampaigns();
});

/// Şu an aktif kampanyalar (üye ekranları için, sıra no artan).
final activePartnerCampaignsProvider =
    FutureProvider<List<PartnerCampaignModel>>((ref) async {
  final campaigns = await ref.watch(allPartnerCampaignsProvider.future);
  final active =
      campaigns.where((campaign) => campaign.isCurrentlyActive()).toList()
        ..sort((a, b) {
          final orderCompare = a.sortOrder.compareTo(b.sortOrder);
          if (orderCompare != 0) return orderCompare;
          return a.partnerName.compareTo(b.partnerName);
        });
  return active;
});

/// Tek kampanya detayı.
final partnerCampaignByIdProvider =
    FutureProvider.family<PartnerCampaignModel?, String>((ref, id) async {
  final ds = ref.watch(_partnerCampaignDataSourceProvider);
  return ds.getCampaignById(id);
});

final partnerCampaignRepositoryProvider =
    Provider<PartnerCampaignRepository>((ref) {
  return PartnerCampaignRepository(ref.watch(_partnerCampaignDataSourceProvider));
});

/// Kampanya kullanım hakkı (QR ekranı).
final partnerPerkEntitlementProvider =
    FutureProvider.family<PartnerPerkEntitlement, String>((ref, campaignId) async {
  final ds = ref.watch(_partnerCampaignDataSourceProvider);
  return ds.getEntitlement(campaignId);
});

/// Dinamik QR token (60 sn geçerli).
final partnerRedemptionTokenProvider =
    FutureProvider.family<PartnerRedemptionToken, String>((ref, campaignId) async {
  final ds = ref.watch(_partnerCampaignDataSourceProvider);
  return ds.createRedemptionToken(campaignId);
});

/// Admin kullanım raporu.
final partnerRedemptionReportProvider = FutureProvider.family<
    PartnerRedemptionReport, PartnerRedemptionReportFilters>((ref, filters) async {
  final ds = ref.watch(_partnerCampaignDataSourceProvider);
  return ds.getRedemptionReport(
    campaignId: filters.campaignId,
    from: _startOfDayUtc(filters.fromDate),
    to: _endOfDayUtc(filters.toDate),
  );
});

/// Admin dashboard özeti.
final partnerRedemptionDashboardProvider = FutureProvider.family<
    PartnerRedemptionDashboard, PartnerRedemptionReportFilters>((ref, filters) async {
  final ds = ref.watch(_partnerCampaignDataSourceProvider);
  return ds.getRedemptionDashboard(
    campaignId: filters.campaignId,
    from: _startOfDayUtc(filters.fromDate),
    to: _endOfDayUtc(filters.toDate),
  );
});

DateTime? _startOfDayUtc(DateTime? date) {
  if (date == null) return null;
  return DateTime(date.year, date.month, date.day).toUtc();
}

DateTime? _endOfDayUtc(DateTime? date) {
  if (date == null) return null;
  return DateTime(date.year, date.month, date.day, 23, 59, 59, 999).toUtc();
}

class PartnerCampaignRepository {
  PartnerCampaignRepository(this._dataSource);

  final PartnerCampaignRemoteDataSource _dataSource;

  Future<PartnerCampaignModel> createCampaign({
    required String slug,
    required String partnerName,
    String? tagline,
    String? logoUrl,
    required String brandColor,
    required int discountPercent,
    required String discountLabel,
    String? terms,
    required String redemptionHint,
    String? locationName,
    String? locationAddress,
    double? locationLat,
    double? locationLng,
    DateTime? startsAt,
    DateTime? endsAt,
    bool isActive = true,
    int sortOrder = 0,
    bool qrRedemptionEnabled = false,
    String usageLimitType = 'once_per_day',
    int? usageLimitCount,
    String? successMessage,
  }) {
    return _dataSource.createCampaign({
      'slug': slug,
      'partner_name': partnerName,
      'tagline': _nullIfEmpty(tagline),
      'logo_url': _nullIfEmpty(logoUrl),
      'brand_color': brandColor,
      'discount_percent': discountPercent,
      'discount_label': discountLabel,
      'terms': _nullIfEmpty(terms),
      'redemption_hint': redemptionHint,
      'location_name': _nullIfEmpty(locationName),
      'location_address': _nullIfEmpty(locationAddress),
      'location_lat': locationLat,
      'location_lng': locationLng,
      'starts_at': (startsAt ?? DateTime.now()).toUtc().toIso8601String(),
      'ends_at': endsAt?.toUtc().toIso8601String(),
      'is_active': isActive,
      'sort_order': sortOrder,
      'qr_redemption_enabled': qrRedemptionEnabled,
      'usage_limit_type': usageLimitType,
      'usage_limit_count': usageLimitCount,
      'success_message': _nullIfEmpty(successMessage),
    });
  }

  Future<PartnerCampaignModel> updateCampaign({
    required String id,
    required String slug,
    required String partnerName,
    String? tagline,
    String? logoUrl,
    required String brandColor,
    required int discountPercent,
    required String discountLabel,
    String? terms,
    required String redemptionHint,
    String? locationName,
    String? locationAddress,
    double? locationLat,
    double? locationLng,
    DateTime? startsAt,
    DateTime? endsAt,
    required bool isActive,
    int sortOrder = 0,
    bool qrRedemptionEnabled = false,
    String usageLimitType = 'once_per_day',
    int? usageLimitCount,
    String? successMessage,
    bool clearEndsAt = false,
  }) {
    final data = <String, dynamic>{
      'slug': slug,
      'partner_name': partnerName,
      'tagline': _nullIfEmpty(tagline),
      'logo_url': _nullIfEmpty(logoUrl),
      'brand_color': brandColor,
      'discount_percent': discountPercent,
      'discount_label': discountLabel,
      'terms': _nullIfEmpty(terms),
      'redemption_hint': redemptionHint,
      'location_name': _nullIfEmpty(locationName),
      'location_address': _nullIfEmpty(locationAddress),
      'location_lat': locationLat,
      'location_lng': locationLng,
      'is_active': isActive,
      'sort_order': sortOrder,
      'qr_redemption_enabled': qrRedemptionEnabled,
      'usage_limit_type': usageLimitType,
      'usage_limit_count': usageLimitCount,
      'success_message': _nullIfEmpty(successMessage),
    };

    // starts_at NOT NULL — null göndermeyelim, mevcut değer korunsun
    if (startsAt != null) {
      data['starts_at'] = startsAt.toUtc().toIso8601String();
    }
    if (endsAt != null) {
      data['ends_at'] = endsAt.toUtc().toIso8601String();
    } else if (clearEndsAt) {
      data['ends_at'] = null;
    }

    return _dataSource.updateCampaign(id, data);
  }

  Future<void> deleteCampaign(String id) => _dataSource.deleteCampaign(id);

  Future<void> setCampaignActive(String id, bool isActive) =>
      _dataSource.setCampaignActive(id, isActive);

  Future<String> uploadLogo({
    required String slug,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) {
    return _dataSource.uploadLogo(
      slug: slug,
      bytes: bytes,
      contentType: contentType,
    );
  }

  String? _nullIfEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
