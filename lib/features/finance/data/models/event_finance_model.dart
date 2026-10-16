import '../../../marketplace/data/models/order_model.dart';

double _toDouble(dynamic value) => (value as num?)?.toDouble() ?? 0;

int _toInt(dynamic value) => (value as num?)?.toInt() ?? 0;

DateTime? _toDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value as String);
}

List<String> _menuOptionsFromJson(dynamic raw) {
  if (raw is! List) return const [];
  final names = <String>[];
  for (final item in raw) {
    final name = item?.toString().trim() ?? '';
    if (name.isNotEmpty) names.add(name);
  }
  return names;
}

/// Ortak (mekan) payı hesaplama tipi
enum PartnerShareType {
  fixed('fixed', 'Sabit tutar'),
  percent('percent', 'Yüzde');

  final String value;
  final String label;
  const PartnerShareType(this.value, this.label);

  static PartnerShareType fromString(String? value) {
    return PartnerShareType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => PartnerShareType.fixed,
    );
  }
}

/// Giderin kapsamı: bilet başına veya etkinlik geneli
enum EventCostScope {
  perPerson('per_person', 'Kişi başı'),
  event('event', 'Etkinlik');

  final String value;
  final String label;
  const EventCostScope(this.value, this.label);

  static EventCostScope fromString(String? value) {
    return EventCostScope.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EventCostScope.perPerson,
    );
  }
}

/// Tek gider kalemi (mekan, DJ, ses, vb.)
class EventFinanceCost {
  final String? id;
  final String name;
  final EventCostScope scope;
  final PartnerShareType shareType;
  final double shareValue;

  const EventFinanceCost({
    this.id,
    required this.name,
    this.scope = EventCostScope.perPerson,
    this.shareType = PartnerShareType.fixed,
    this.shareValue = 0,
  });

  factory EventFinanceCost.fromJson(Map<String, dynamic> json) {
    return EventFinanceCost(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Gider',
      scope: EventCostScope.fromString(json['scope'] as String?),
      shareType: PartnerShareType.fromString(json['share_type'] as String?),
      shareValue: _toDouble(json['share_value']),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'scope': scope.value,
        'share_type': shareType.value,
        'share_value': shareValue,
      };

  double amountFor(double unitPrice) {
    if (scope == EventCostScope.event) return shareValue;
    return switch (shareType) {
      PartnerShareType.fixed => shareValue,
      PartnerShareType.percent =>
        (unitPrice * shareValue / 100 * 100).roundToDouble() / 100,
    };
  }
}

/// Etkinlik satış durumu
enum EventSaleStatus {
  pending('pending', 'Bekliyor'),
  confirmed('confirmed', 'Katıldı'),
  cancelled('cancelled', 'İptal');

  final String value;
  final String label;
  const EventSaleStatus(this.value, this.label);

  static EventSaleStatus fromString(String? value) {
    return EventSaleStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EventSaleStatus.pending,
    );
  }
}

/// Ücretli etkinlik ayarları (event_finance_settings + costs)
class EventFinanceSettings {
  final String eventId;
  final bool isPaid;
  final String? partnerName;
  final PartnerShareType partnerShareType;
  final double partnerShareValue;
  final String? notes;
  final List<EventFinanceCost> costs;

  const EventFinanceSettings({
    required this.eventId,
    required this.isPaid,
    this.partnerName,
    this.partnerShareType = PartnerShareType.fixed,
    this.partnerShareValue = 0,
    this.notes,
    this.costs = const [],
  });

  factory EventFinanceSettings.fromJson(Map<String, dynamic> json) {
    final rawCosts = json['costs'] as List<dynamic>? ?? const [];
    var costs = rawCosts
        .map((e) => EventFinanceCost.fromJson(e as Map<String, dynamic>))
        .toList();
    if (costs.isEmpty &&
        ((json['partner_share_value'] as num?)?.toDouble() ?? 0) > 0) {
      costs = [
        EventFinanceCost(
          name: (json['partner_name'] as String?)?.trim().isNotEmpty == true
              ? json['partner_name'] as String
              : 'Mekan',
          shareType:
              PartnerShareType.fromString(json['partner_share_type'] as String?),
          shareValue: _toDouble(json['partner_share_value']),
        ),
      ];
    }
    return EventFinanceSettings(
      eventId: json['event_id'] as String? ?? '',
      isPaid: json['is_paid'] as bool? ?? false,
      partnerName: json['partner_name'] as String?,
      partnerShareType:
          PartnerShareType.fromString(json['partner_share_type'] as String?),
      partnerShareValue: _toDouble(json['partner_share_value']),
      notes: json['notes'] as String?,
      costs: costs,
    );
  }

  List<EventFinanceCost> get perPersonCosts =>
      costs.where((c) => c.scope == EventCostScope.perPerson).toList();

  List<EventFinanceCost> get eventCosts =>
      costs.where((c) => c.scope == EventCostScope.event).toList();

  /// Verilen birim fiyat için kişi başı gider toplamı
  double shareFor(double unitPrice) {
    if (costs.isNotEmpty) {
      return perPersonCosts.fold<double>(0, (sum, c) => sum + c.amountFor(unitPrice));
    }
    return switch (partnerShareType) {
      PartnerShareType.fixed => partnerShareValue,
      PartnerShareType.percent =>
        (unitPrice * partnerShareValue / 100 * 100).roundToDouble() / 100,
    };
  }

  double get eventFixedTotal =>
      eventCosts.fold<double>(0, (sum, c) => sum + c.shareValue);
}

/// Etkinlik finans özetindeki tek etkinlik satırı
class EventFinanceOverviewRow {
  final String eventId;
  final String title;
  final DateTime startTime;
  final String eventStatus;
  final bool isPaid;
  final double? ticketPrice;
  final String? partnerName;
  final int participantCount;
  final int paidCount;
  final int giftCount;
  final double totalSales;
  final double totalPartnerShare;
  final double netProfit;
  final double totalPaid;
  final double outstanding;

  const EventFinanceOverviewRow({
    required this.eventId,
    required this.title,
    required this.startTime,
    required this.eventStatus,
    required this.isPaid,
    this.ticketPrice,
    this.partnerName,
    required this.participantCount,
    required this.paidCount,
    required this.giftCount,
    required this.totalSales,
    required this.totalPartnerShare,
    required this.netProfit,
    required this.totalPaid,
    required this.outstanding,
  });

  factory EventFinanceOverviewRow.fromJson(Map<String, dynamic> json) {
    return EventFinanceOverviewRow(
      eventId: json['event_id'] as String,
      title: json['title'] as String? ?? '',
      startTime: DateTime.parse(json['start_time'] as String).toLocal(),
      eventStatus: json['event_status'] as String? ?? '',
      isPaid: json['is_paid'] as bool? ?? false,
      ticketPrice: (json['ticket_price'] as num?)?.toDouble(),
      partnerName: json['partner_name'] as String?,
      participantCount: _toInt(json['participant_count']),
      paidCount: _toInt(json['paid_count']),
      giftCount: _toInt(json['gift_count']),
      totalSales: _toDouble(json['total_sales']),
      totalPartnerShare: _toDouble(json['total_partner_share']),
      netProfit: _toDouble(json['net_profit']),
      totalPaid: _toDouble(json['total_paid']),
      outstanding: _toDouble(json['outstanding']),
    );
  }
}

/// Etkinlik finans detayındaki tek satış (katılımcı) satırı
class EventSaleRow {
  final String id;
  final String eventId;
  final String? userId;
  final String buyerName;
  final String? avatarUrl;
  final bool isManual;
  final int quantity;
  final double unitPrice;
  final double partnerShareAmount;
  final double totalPrice;
  final double totalPartnerShare;
  final double net;
  final SaleType saleType;
  final EventSaleStatus status;
  final double paidAmount;
  final double outstanding;
  final PaymentMethod? paymentMethod;
  final DateTime? paymentDate;
  final String? notes;
  final String? menuChoice;
  final DateTime? createdAt;
  final String? rsvpStatus;
  final bool checkedIn;

  const EventSaleRow({
    required this.id,
    required this.eventId,
    this.userId,
    required this.buyerName,
    this.avatarUrl,
    required this.isManual,
    required this.quantity,
    required this.unitPrice,
    required this.partnerShareAmount,
    required this.totalPrice,
    required this.totalPartnerShare,
    required this.net,
    required this.saleType,
    required this.status,
    required this.paidAmount,
    required this.outstanding,
    this.paymentMethod,
    this.paymentDate,
    this.notes,
    this.menuChoice,
    this.createdAt,
    this.rsvpStatus,
    this.checkedIn = false,
  });

  bool get isCancelled => status == EventSaleStatus.cancelled;

  bool get isFullyPaid => paidAmount >= totalPrice;

  factory EventSaleRow.fromJson(Map<String, dynamic> json) {
    return EventSaleRow(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      userId: json['user_id'] as String?,
      buyerName: json['buyer_name'] as String? ?? 'Bilinmiyor',
      avatarUrl: json['avatar_url'] as String?,
      isManual: json['source'] == 'manual',
      quantity: _toInt(json['quantity']),
      unitPrice: _toDouble(json['unit_price']),
      partnerShareAmount: _toDouble(json['partner_share_amount']),
      totalPrice: _toDouble(json['total_price']),
      totalPartnerShare: _toDouble(json['total_partner_share']),
      net: _toDouble(json['net']),
      saleType: SaleType.fromString(json['sale_type'] as String?),
      status: EventSaleStatus.fromString(json['status'] as String?),
      paidAmount: _toDouble(json['paid_amount']),
      outstanding: _toDouble(json['outstanding']),
      paymentMethod:
          PaymentMethod.fromString(json['payment_method'] as String?),
      paymentDate: _toDate(json['payment_date']),
      notes: json['notes'] as String?,
      menuChoice: json['menu_choice'] as String?,
      createdAt: _toDate(json['created_at']),
      rsvpStatus: json['rsvp_status'] as String?,
      checkedIn: json['checked_in'] as bool? ?? false,
    );
  }
}

/// Etkinlik finans özeti (iptal edilmemiş satışlar)
class EventFinanceSummary {
  final int participantCount;
  final int regularCount;
  final int discountedCount;
  final int giftCount;
  final double totalSales;
  final double totalPartnerShare;
  final double perPersonCost;
  final double eventFixedCost;
  final double netProfit;
  final double totalPaid;
  final double outstanding;

  const EventFinanceSummary({
    this.participantCount = 0,
    this.regularCount = 0,
    this.discountedCount = 0,
    this.giftCount = 0,
    this.totalSales = 0,
    this.totalPartnerShare = 0,
    this.perPersonCost = 0,
    this.eventFixedCost = 0,
    this.netProfit = 0,
    this.totalPaid = 0,
    this.outstanding = 0,
  });

  factory EventFinanceSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const EventFinanceSummary();
    final total = _toDouble(json['total_partner_share']);
    return EventFinanceSummary(
      participantCount: _toInt(json['participant_count']),
      regularCount: _toInt(json['regular_count']),
      discountedCount: _toInt(json['discounted_count']),
      giftCount: _toInt(json['gift_count']),
      totalSales: _toDouble(json['total_sales']),
      totalPartnerShare: total,
      perPersonCost: _toDouble(json['per_person_cost'] ?? json['total_partner_share']),
      eventFixedCost: _toDouble(json['event_fixed_cost']),
      netProfit: _toDouble(json['net_profit']),
      totalPaid: _toDouble(json['total_paid']),
      outstanding: _toDouble(json['outstanding']),
    );
  }
}

/// get_event_finance_detail RPC sonucu
class EventFinanceDetail {
  final String eventId;
  final String title;
  final DateTime startTime;
  final String? locationName;
  final double? ticketPrice;
  final List<String> menuOptions;
  final EventFinanceSettings? settings;
  final List<EventFinanceCost> costs;
  final EventFinanceSummary summary;
  final List<EventSaleRow> sales;

  const EventFinanceDetail({
    required this.eventId,
    required this.title,
    required this.startTime,
    this.locationName,
    this.ticketPrice,
    this.menuOptions = const [],
    this.settings,
    this.costs = const [],
    required this.summary,
    required this.sales,
  });

  factory EventFinanceDetail.fromJson(Map<String, dynamic> json) {
    final event = json['event'] as Map<String, dynamic>? ?? const {};
    final settings = json['settings'] as Map<String, dynamic>?;
    final sales = json['sales'] as List<dynamic>? ?? const [];
    final rawCosts = json['costs'] as List<dynamic>? ??
        settings?['costs'] as List<dynamic>? ??
        const [];
    final costs = rawCosts
        .map((e) => EventFinanceCost.fromJson(e as Map<String, dynamic>))
        .toList();

    return EventFinanceDetail(
      eventId: event['id'] as String,
      title: event['title'] as String? ?? '',
      startTime: DateTime.parse(event['start_time'] as String).toLocal(),
      locationName: event['location_name'] as String?,
      ticketPrice: (event['ticket_price'] as num?)?.toDouble(),
      menuOptions: _menuOptionsFromJson(event['menu_options']),
      settings: settings != null
          ? EventFinanceSettings.fromJson({
              ...settings,
              'event_id': settings['event_id'] ?? event['id'],
              'costs': settings['costs'] ?? rawCosts,
            })
          : null,
      costs: costs,
      summary: EventFinanceSummary.fromJson(
        json['summary'] as Map<String, dynamic>?,
      ),
      sales: sales
          .map((e) => EventSaleRow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
