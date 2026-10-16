import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../marketplace/data/models/order_model.dart';
import '../models/event_finance_model.dart';
import '../models/finance_report_model.dart';

/// Kasa / ücretli etkinlik veri kaynağı (yalnızca super_admin)
abstract class FinanceRemoteDataSource {
  Future<EventFinanceSettings?> getEventFinanceSettings(String eventId);

  Future<void> setEventFinance({
    required String eventId,
    required bool isPaid,
    double? ticketPrice,
    String? partnerName,
    PartnerShareType partnerShareType = PartnerShareType.fixed,
    double partnerShareValue = 0,
    String? notes,
    bool applyToUnpaid = false,
    List<EventFinanceCost> costs = const [],
  });

  Future<EventFinanceDetail> getEventFinanceDetail(String eventId);

  Future<List<EventFinanceOverviewRow>> getEventFinanceOverview({
    DateTime? from,
    DateTime? to,
  });

  Future<List<FinanceOverviewRow>> getFinanceOverview({
    DateTime? from,
    DateTime? to,
  });

  /// Manuel katılımcı ekler. [userId] verilmezse [buyerName] zorunludur.
  Future<void> addEventSale({
    required String eventId,
    String? userId,
    String? buyerName,
    int quantity = 1,
    SaleType saleType = SaleType.regular,
    double? unitPrice,
    String? notes,
    String? menuChoice,
  });

  Future<void> updateEventSale(String saleId, Map<String, dynamic> changes);

  Future<void> deleteEventSale(String saleId);

  Future<void> setEventSaleAttendance(String saleId, bool checkedIn);
}

class FinanceRemoteDataSourceImpl implements FinanceRemoteDataSource {
  final SupabaseClient _supabase;

  FinanceRemoteDataSourceImpl(this._supabase);

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<T> _guard<T>(String fallback, Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: '$fallback: $e');
    }
  }

  @override
  Future<EventFinanceSettings?> getEventFinanceSettings(String eventId) {
    return _guard('Ücret ayarları alınamadı', () async {
      final response = await _supabase
          .from('event_finance_settings')
          .select()
          .eq('event_id', eventId)
          .maybeSingle();
      if (response == null) return null;
      final costs = await _supabase
          .from('event_finance_costs')
          .select()
          .eq('event_id', eventId)
          .order('sort_order');
      return EventFinanceSettings.fromJson({
        ...response,
        'costs': costs,
      });
    });
  }

  @override
  Future<void> setEventFinance({
    required String eventId,
    required bool isPaid,
    double? ticketPrice,
    String? partnerName,
    PartnerShareType partnerShareType = PartnerShareType.fixed,
    double partnerShareValue = 0,
    String? notes,
    bool applyToUnpaid = false,
    List<EventFinanceCost> costs = const [],
  }) {
    return _guard('Ücret ayarları kaydedilemedi', () async {
      await _supabase.rpc('set_event_finance', params: {
        'p_event_id': eventId,
        'p_is_paid': isPaid,
        'p_ticket_price': ticketPrice,
        'p_partner_name': partnerName,
        'p_partner_share_type': partnerShareType.value,
        'p_partner_share_value': partnerShareValue,
        'p_notes': notes,
        'p_apply_to_unpaid': applyToUnpaid,
        'p_costs': costs.map((c) => c.toJson()).toList(),
      });
    });
  }

  @override
  Future<EventFinanceDetail> getEventFinanceDetail(String eventId) {
    return _guard('Etkinlik finans raporu alınamadı', () async {
      final response = await _supabase.rpc(
        'get_event_finance_detail',
        params: {'p_event_id': eventId},
      );
      return EventFinanceDetail.fromJson(response as Map<String, dynamic>);
    });
  }

  @override
  Future<List<EventFinanceOverviewRow>> getEventFinanceOverview({
    DateTime? from,
    DateTime? to,
  }) {
    return _guard('Etkinlik finans özeti alınamadı', () async {
      final response = await _supabase.rpc(
        'get_event_finance_overview',
        params: {
          'p_from': from != null ? _dateOnly(from) : null,
          'p_to': to != null ? _dateOnly(to) : null,
        },
      );
      final List<dynamic> data = response as List<dynamic>? ?? [];
      return data
          .map((json) =>
              EventFinanceOverviewRow.fromJson(json as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<List<FinanceOverviewRow>> getFinanceOverview({
    DateTime? from,
    DateTime? to,
  }) {
    return _guard('Kasa raporu alınamadı', () async {
      final response = await _supabase.rpc(
        'get_finance_overview',
        params: {
          'p_from': from != null ? _dateOnly(from) : null,
          'p_to': to != null ? _dateOnly(to) : null,
        },
      );
      final List<dynamic> data = response as List<dynamic>? ?? [];
      return data
          .map((json) =>
              FinanceOverviewRow.fromJson(json as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<void> addEventSale({
    required String eventId,
    String? userId,
    String? buyerName,
    int quantity = 1,
    SaleType saleType = SaleType.regular,
    double? unitPrice,
    String? notes,
    String? menuChoice,
  }) {
    return _guard('Katılımcı eklenemedi', () async {
      final name = buyerName?.trim() ?? '';
      if (userId == null && name.isEmpty) {
        throw ServerException(message: 'Üye seçin veya ad-soyad girin');
      }
      try {
        await _supabase.from('event_sales').insert({
          'event_id': eventId,
          'user_id': userId,
          // Boş ad üyeler için DB tarafında kullanıcı adıyla doldurulur
          'buyer_name': name,
          'source': 'manual',
          'quantity': quantity,
          'sale_type': saleType.value,
          'unit_price': unitPrice ?? 0,
          'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
          'menu_choice': menuChoice,
        });
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          throw ServerException(
            message: 'Bu üye zaten katılımcı listesinde',
            code: e.code,
          );
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> updateEventSale(String saleId, Map<String, dynamic> changes) {
    return _guard('Kayıt güncellenemedi', () async {
      await _supabase.from('event_sales').update(changes).eq('id', saleId);
    });
  }

  @override
  Future<void> deleteEventSale(String saleId) {
    return _guard('Kayıt silinemedi', () async {
      await _supabase.from('event_sales').delete().eq('id', saleId);
    });
  }

  @override
  Future<void> setEventSaleAttendance(String saleId, bool checkedIn) {
    return _guard('Katılım güncellenemedi', () async {
      await _supabase.rpc('set_event_sale_attendance', params: {
        'p_sale_id': saleId,
        'p_checked_in': checkedIn,
      });
    });
  }
}
