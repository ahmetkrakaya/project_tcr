import '../../../../core/enums/gender.dart';

/// Order Status Enum
enum OrderStatus {
  pending('pending', 'Beklemede'),
  confirmed('confirmed', 'Onaylandı'),
  cancelled('cancelled', 'İptal'),
  completed('completed', 'Tamamlandı');

  final String value;
  final String label;
  const OrderStatus(this.value, this.label);

  static OrderStatus fromString(String value) {
    return OrderStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => OrderStatus.pending,
    );
  }
}

/// Satış tipi: raporlarda satılan / indirimli / hediye ayrımı için kullanılır.
enum SaleType {
  regular('regular', 'Normal'),
  discounted('discounted', 'İndirimli'),
  gift('gift', 'Hediye');

  final String value;
  final String label;
  const SaleType(this.value, this.label);

  static SaleType fromString(String? value) {
    return SaleType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SaleType.regular,
    );
  }
}

/// Ödeme şekli
enum PaymentMethod {
  cash('cash', 'Nakit'),
  transfer('transfer', 'Havale/EFT'),
  card('card', 'Kart'),
  hand('hand', 'Elden'),
  other('other', 'Diğer');

  final String value;
  final String label;
  const PaymentMethod(this.value, this.label);

  static PaymentMethod? fromString(String? value) {
    if (value == null) return null;
    for (final method in PaymentMethod.values) {
      if (method.value == value) return method;
    }
    return null;
  }
}

/// Marketplace Order Model
class OrderModel {
  final String id;
  final String listingId;

  /// Kayıtlı kullanıcı alıcı. Elden satışlarda null olabilir.
  final String? buyerId;
  final String? buyerName;
  final String? buyerAvatarUrl;

  /// Kayıtlı kullanıcı seçilmediğinde serbest girilen ad-soyad.
  final String? manualBuyerName;
  final String? sellerId;
  final String? sellerName;
  final String? sellerAvatarUrl;
  final int quantity;
  final double totalPrice;
  final String currency;
  final OrderStatus status;
  final String? buyerNote;
  final String? sellerNote;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancellationReason;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String? updatedByName;
  final String? updatedByAvatarUrl;
  final String? selectedSize; // Siparişte seçilen beden
  final ListingGender? selectedGender; // Siparişte seçilen cinsiyet

  /// Uygulama dışı (elden) satış işareti
  final bool isManual;
  final SaleType saleType;
  final double? unitPrice;
  final double? unitCost;
  final DateTime? orderDate;
  final DateTime? deliveryDate;
  final DateTime? paymentDate;
  final PaymentMethod? paymentMethod;
  final double paidAmount;
  final bool affectsStock;

  const OrderModel({
    required this.id,
    required this.listingId,
    this.buyerId,
    this.buyerName,
    this.buyerAvatarUrl,
    this.manualBuyerName,
    this.sellerId,
    this.sellerName,
    this.sellerAvatarUrl,
    this.quantity = 1,
    required this.totalPrice,
    this.currency = 'TRY',
    this.status = OrderStatus.pending,
    this.buyerNote,
    this.sellerNote,
    this.confirmedAt,
    this.cancelledAt,
    this.cancelledBy,
    this.cancellationReason,
    this.completedAt,
    required this.createdAt,
    this.updatedAt,
    this.updatedBy,
    this.updatedByName,
    this.updatedByAvatarUrl,
    this.selectedSize,
    this.selectedGender,
    this.isManual = false,
    this.saleType = SaleType.regular,
    this.unitPrice,
    this.unitCost,
    this.orderDate,
    this.deliveryDate,
    this.paymentDate,
    this.paymentMethod,
    this.paidAmount = 0,
    this.affectsStock = true,
  });

  /// Alıcı görünen adı: kayıtlı kullanıcı adı, yoksa serbest girilen ad.
  String get buyerDisplayName {
    final name = buyerName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final manual = manualBuyerName?.trim();
    if (manual != null && manual.isNotEmpty) return manual;
    return 'Bilinmiyor';
  }

  /// Tahsil edilmemiş tutar
  double get outstandingAmount {
    final remaining = totalPrice - paidAmount;
    return remaining > 0 ? remaining : 0;
  }

  bool get isFullyPaid => paidAmount >= totalPrice;

  /// Satış tarihinde etkin olan tarih (geçmiş kayıtlarda order_date dolu olur).
  DateTime get effectiveOrderDate => orderDate ?? createdAt;

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'] as String,
      listingId: json['listing_id'] as String,
      buyerId: json['buyer_id'] as String?,
      buyerName: json['buyer_name'] as String?,
      buyerAvatarUrl: json['buyer_avatar'] as String?,
      manualBuyerName: json['manual_buyer_name'] as String?,
      sellerId: json['seller_id'] as String?,
      sellerName: json['seller_name'] as String?,
      sellerAvatarUrl: json['seller_avatar'] as String?,
      quantity: json['quantity'] as int? ?? 1,
      totalPrice: (json['total_price'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'TRY',
      status: OrderStatus.fromString(json['status'] as String),
      buyerNote: json['buyer_note'] as String?,
      sellerNote: json['seller_note'] as String?,
      confirmedAt: _parseDate(json['confirmed_at']),
      cancelledAt: _parseDate(json['cancelled_at']),
      cancelledBy: json['cancelled_by'] as String?,
      cancellationReason: json['cancellation_reason'] as String?,
      completedAt: _parseDate(json['completed_at']),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: _parseDate(json['updated_at']),
      updatedBy: json['updated_by'] as String?,
      updatedByName: json['updated_by_name'] as String?,
      updatedByAvatarUrl: json['updated_by_avatar'] as String?,
      selectedSize: json['selected_size'] as String?,
      selectedGender: json['selected_gender'] != null
          ? ListingGender.fromString(json['selected_gender'] as String)
          : null,
      isManual: json['is_manual'] as bool? ?? false,
      saleType: SaleType.fromString(json['sale_type'] as String?),
      unitPrice: (json['unit_price'] as num?)?.toDouble(),
      unitCost: (json['unit_cost'] as num?)?.toDouble(),
      orderDate: _parseDate(json['order_date']),
      deliveryDate: _parseDate(json['delivery_date']),
      paymentDate: _parseDate(json['payment_date']),
      paymentMethod: PaymentMethod.fromString(json['payment_method'] as String?),
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
      affectsStock: json['affects_stock'] as bool? ?? true,
    );
  }

  /// Supabase join'li sorgulardan gelen kaydı parse eder.
  /// `buyer`, `seller` ve `updated_by_user` ilişkileri beklenir.
  factory OrderModel.fromJoinedJson(Map<String, dynamic> json) {
    final buyerJson = json['buyer'] as Map<String, dynamic>?;
    final sellerJson = json['seller'] as Map<String, dynamic>?;
    final updatedByJson = json['updated_by_user'] as Map<String, dynamic>?;

    return OrderModel.fromJson({
      ...json,
      'buyer_name': _fullName(buyerJson),
      'buyer_avatar': buyerJson?['avatar_url'],
      'seller_name': _fullName(sellerJson),
      'seller_avatar': sellerJson?['avatar_url'],
      'updated_by_name': _fullName(updatedByJson),
      'updated_by_avatar': updatedByJson?['avatar_url'],
    });
  }

  static String? _fullName(Map<String, dynamic>? json) {
    if (json == null) return null;
    final name =
        '${json['first_name'] ?? ''} ${json['last_name'] ?? ''}'.trim();
    return name.isEmpty ? null : name;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value as String);
  }

  static String _formatDateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Map<String, dynamic> toJson() {
    return {
      'listing_id': listingId,
      'buyer_id': buyerId,
      if (manualBuyerName != null) 'manual_buyer_name': manualBuyerName,
      if (sellerId != null) 'seller_id': sellerId,
      'quantity': quantity,
      'total_price': totalPrice,
      'currency': currency,
      'status': status.value,
      'buyer_note': buyerNote,
      'seller_note': sellerNote,
      if (selectedSize != null) 'selected_size': selectedSize,
      if (selectedGender != null) 'selected_gender': selectedGender!.value,
    };
  }

  /// Manuel satış kaydı için insert/update payload'ı.
  Map<String, dynamic> toSalePayload() {
    return {
      'listing_id': listingId,
      'buyer_id': buyerId,
      'manual_buyer_name': manualBuyerName,
      if (sellerId != null) 'seller_id': sellerId,
      'quantity': quantity,
      'total_price': totalPrice,
      'currency': currency,
      'status': status.value,
      'seller_note': sellerNote,
      'selected_size': selectedSize,
      'selected_gender': selectedGender?.value,
      'is_manual': isManual,
      'sale_type': saleType.value,
      'unit_price': unitPrice,
      // unit_cost yazılmaz: raporlar canlı ortalama birim maliyeti kullanır
      'order_date': orderDate != null ? _formatDateOnly(orderDate!) : null,
      'delivery_date':
          deliveryDate != null ? _formatDateOnly(deliveryDate!) : null,
      'payment_date':
          paymentDate != null ? _formatDateOnly(paymentDate!) : null,
      'payment_method': paymentMethod?.value,
      'paid_amount': paidAmount,
      'affects_stock': affectsStock,
    };
  }

  OrderModel copyWith({
    String? id,
    String? listingId,
    String? buyerId,
    String? buyerName,
    String? buyerAvatarUrl,
    String? manualBuyerName,
    String? sellerId,
    String? sellerName,
    String? sellerAvatarUrl,
    int? quantity,
    double? totalPrice,
    String? currency,
    OrderStatus? status,
    String? buyerNote,
    String? sellerNote,
    DateTime? confirmedAt,
    DateTime? cancelledAt,
    String? cancelledBy,
    String? cancellationReason,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? updatedBy,
    String? updatedByName,
    String? updatedByAvatarUrl,
    String? selectedSize,
    ListingGender? selectedGender,
    bool? isManual,
    SaleType? saleType,
    double? unitPrice,
    double? unitCost,
    DateTime? orderDate,
    DateTime? deliveryDate,
    DateTime? paymentDate,
    PaymentMethod? paymentMethod,
    double? paidAmount,
    bool? affectsStock,
  }) {
    return OrderModel(
      id: id ?? this.id,
      listingId: listingId ?? this.listingId,
      buyerId: buyerId ?? this.buyerId,
      buyerName: buyerName ?? this.buyerName,
      buyerAvatarUrl: buyerAvatarUrl ?? this.buyerAvatarUrl,
      manualBuyerName: manualBuyerName ?? this.manualBuyerName,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      sellerAvatarUrl: sellerAvatarUrl ?? this.sellerAvatarUrl,
      quantity: quantity ?? this.quantity,
      totalPrice: totalPrice ?? this.totalPrice,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      buyerNote: buyerNote ?? this.buyerNote,
      sellerNote: sellerNote ?? this.sellerNote,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedByName: updatedByName ?? this.updatedByName,
      updatedByAvatarUrl: updatedByAvatarUrl ?? this.updatedByAvatarUrl,
      selectedSize: selectedSize ?? this.selectedSize,
      selectedGender: selectedGender ?? this.selectedGender,
      isManual: isManual ?? this.isManual,
      saleType: saleType ?? this.saleType,
      unitPrice: unitPrice ?? this.unitPrice,
      unitCost: unitCost ?? this.unitCost,
      orderDate: orderDate ?? this.orderDate,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      paymentDate: paymentDate ?? this.paymentDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paidAmount: paidAmount ?? this.paidAmount,
      affectsStock: affectsStock ?? this.affectsStock,
    );
  }
}
