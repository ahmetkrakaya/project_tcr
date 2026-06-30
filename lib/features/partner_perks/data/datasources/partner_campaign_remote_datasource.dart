import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/partner_campaign_model.dart';
import '../models/partner_redemption_models.dart';

class PartnerCampaignRemoteDataSource {
  PartnerCampaignRemoteDataSource(this._supabase);

  final SupabaseClient _supabase;

  Future<List<PartnerCampaignModel>> getAllCampaigns() async {
    final response = await _supabase
        .from('partner_campaigns')
        .select()
        .order('sort_order')
        .order('starts_at', ascending: false);

    return (response as List)
        .map((row) =>
            PartnerCampaignModel.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<PartnerCampaignModel?> getCampaignById(String id) async {
    final response = await _supabase
        .from('partner_campaigns')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return PartnerCampaignModel.fromJson(response);
  }

  Future<PartnerCampaignModel> createCampaign(Map<String, dynamic> data) async {
    final userId = _supabase.auth.currentUser?.id;
    final payload = Map<String, dynamic>.from(data);
    if (userId != null) {
      payload['created_by'] = userId;
    }

    final response = await _supabase
        .from('partner_campaigns')
        .insert(payload)
        .select()
        .single();

    return PartnerCampaignModel.fromJson(response);
  }

  Future<PartnerCampaignModel> updateCampaign(
    String id,
    Map<String, dynamic> data,
  ) async {
    final response = await _supabase
        .from('partner_campaigns')
        .update(data)
        .eq('id', id)
        .select()
        .single();

    return PartnerCampaignModel.fromJson(response);
  }

  Future<void> deleteCampaign(String id) async {
    await _supabase.from('partner_campaigns').delete().eq('id', id);
  }

  Future<void> setCampaignActive(String id, bool isActive) async {
    await _supabase
        .from('partner_campaigns')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  Future<String> uploadLogo({
    required String slug,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final ext = contentType.contains('png') ? 'png' : 'jpg';
    final fileName =
        '$slug/logo_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _supabase.storage.from('partner-logos').uploadBinary(
          fileName,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: contentType,
          ),
        );

    return _supabase.storage.from('partner-logos').getPublicUrl(fileName);
  }

  Future<PartnerPerkEntitlement> getEntitlement(String campaignId) async {
    final response = await _supabase.rpc(
      'get_partner_perk_entitlement',
      params: {'p_campaign_id': campaignId},
    );
    return PartnerPerkEntitlement.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<PartnerRedemptionToken> createRedemptionToken(String campaignId) async {
    try {
      final response = await _supabase.rpc(
        'create_partner_redemption_token',
        params: {'p_campaign_id': campaignId},
      );
      return PartnerRedemptionToken.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (e) {
      throw Exception(
        e.message.isNotEmpty ? e.message : 'QR token oluşturulamadı (${e.code})',
      );
    }
  }

  Future<PartnerRedemptionReport> getRedemptionReport({
    String? campaignId,
    int limit = 100,
    DateTime? from,
    DateTime? to,
  }) async {
    final response = await _supabase.rpc(
      'get_partner_redemption_report',
      params: {
        'p_campaign_id': campaignId,
        'p_limit': limit,
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to?.toUtc().toIso8601String(),
      },
    );
    return PartnerRedemptionReport.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<PartnerRedemptionDashboard> getRedemptionDashboard({
    String? campaignId,
    DateTime? from,
    DateTime? to,
  }) async {
    final response = await _supabase.rpc(
      'get_partner_redemption_dashboard',
      params: {
        'p_campaign_id': campaignId,
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to?.toUtc().toIso8601String(),
      },
    );
    return PartnerRedemptionDashboard.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }
}
