import '../../../../core/enums/gender.dart';

/// Üretim partisinin beden ve cinsiyet bazlı adet kırılımı.
class ProductionBatchItem {
  final String? id;
  final String size;
  final ListingGender gender;
  final int quantity;

  const ProductionBatchItem({
    this.id,
    required this.size,
    this.gender = ListingGender.unisex,
    required this.quantity,
  });

  factory ProductionBatchItem.fromJson(Map<String, dynamic> json) {
    return ProductionBatchItem(
      id: json['id'] as String?,
      size: json['size'] as String,
      gender: ListingGender.fromString(json['gender'] as String? ?? 'unisex'),
      quantity: json['quantity'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'size': size,
        'gender': gender.value,
        'quantity': quantity,
      };

  ProductionBatchItem copyWith({
    String? size,
    ListingGender? gender,
    int? quantity,
  }) {
    return ProductionBatchItem(
      id: id,
      size: size ?? this.size,
      gender: gender ?? this.gender,
      quantity: quantity ?? this.quantity,
    );
  }
}

/// Bir ürünün üretim partisi. Parti başına tek birim maliyet tutulur.
class ProductionBatch {
  final String id;
  final String listingId;
  final double unitCost;
  final String currency;
  final DateTime producedAt;
  final String? note;
  final String? createdBy;
  final DateTime createdAt;
  final List<ProductionBatchItem> items;

  const ProductionBatch({
    required this.id,
    required this.listingId,
    required this.unitCost,
    this.currency = 'TRY',
    required this.producedAt,
    this.note,
    this.createdBy,
    required this.createdAt,
    this.items = const [],
  });

  int get totalQuantity =>
      items.fold(0, (sum, item) => sum + item.quantity);

  double get totalCost => totalQuantity * unitCost;

  factory ProductionBatch.fromJson(Map<String, dynamic> json) {
    final rawItems = json['production_batch_items'] as List<dynamic>? ?? [];
    return ProductionBatch(
      id: json['id'] as String,
      listingId: json['listing_id'] as String,
      unitCost: (json['unit_cost'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'TRY',
      producedAt: DateTime.parse(json['produced_at'] as String),
      note: json['note'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      items: rawItems
          .map((e) => ProductionBatchItem.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.size.compareTo(b.size)),
    );
  }
}
