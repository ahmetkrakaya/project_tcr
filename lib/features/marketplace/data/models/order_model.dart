/// Order Status Enum
enum OrderStatus {
  pending('pending'),
  confirmed('confirmed'),
  cancelled('cancelled'),
  completed('completed');

  final String value;
  const OrderStatus(this.value);

  static OrderStatus fromString(String value) {
    return OrderStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => OrderStatus.pending,
    );
  }
}

/// Marketplace Order Model
class OrderModel {
  final String id;
  final String listingId;
  final String buyerId;
  final String? buyerName;
  final String? buyerAvatarUrl;
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

  const OrderModel({
    required this.id,
    required this.listingId,
    required this.buyerId,
    this.buyerName,
    this.buyerAvatarUrl,
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
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'] as String,
      listingId: json['listing_id'] as String,
      buyerId: json['buyer_id'] as String,
      buyerName: json['buyer_name'] as String?,
      buyerAvatarUrl: json['buyer_avatar'] as String?,
      sellerId: json['seller_id'] as String?,
      sellerName: json['seller_name'] as String?,
      sellerAvatarUrl: json['seller_avatar'] as String?,
      quantity: json['quantity'] as int? ?? 1,
      totalPrice: (json['total_price'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'TRY',
      status: OrderStatus.fromString(json['status'] as String),
      buyerNote: json['buyer_note'] as String?,
      sellerNote: json['seller_note'] as String?,
      confirmedAt: json['confirmed_at'] != null
          ? DateTime.parse(json['confirmed_at'] as String)
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'] as String)
          : null,
      cancelledBy: json['cancelled_by'] as String?,
      cancellationReason: json['cancellation_reason'] as String?,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      updatedBy: json['updated_by'] as String?,
      updatedByName: json['updated_by_name'] as String?,
      updatedByAvatarUrl: json['updated_by_avatar'] as String?,
      selectedSize: json['selected_size'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'listing_id': listingId,
      'buyer_id': buyerId,
      if (sellerId != null) 'seller_id': sellerId,
      'quantity': quantity,
      'total_price': totalPrice,
      'currency': currency,
      'status': status.value,
      'buyer_note': buyerNote,
      'seller_note': sellerNote,
      if (selectedSize != null) 'selected_size': selectedSize,
    };
  }

  OrderModel copyWith({
    String? id,
    String? listingId,
    String? buyerId,
    String? buyerName,
    String? buyerAvatarUrl,
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
  }) {
    return OrderModel(
      id: id ?? this.id,
      listingId: listingId ?? this.listingId,
      buyerId: buyerId ?? this.buyerId,
      buyerName: buyerName ?? this.buyerName,
      buyerAvatarUrl: buyerAvatarUrl ?? this.buyerAvatarUrl,
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
    );
  }
}
