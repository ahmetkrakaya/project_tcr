import '../../../../core/enums/gender.dart';
import 'order_model.dart';

double _toDouble(dynamic value) => (value as num?)?.toDouble() ?? 0;

int _toInt(dynamic value) => (value as num?)?.toInt() ?? 0;

DateTime? _toDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value as String);
}

/// Genel market raporundaki tek ürün satırı.
class MarketOverviewRow {
  final String listingId;
  final String title;
  final String? imageUrl;
  final String currency;
  final double? price;
  final int producedQuantity;
  final double? avgUnitCost;
  final double totalProductionCost;
  final int soldQuantity;
  final int regularQuantity;
  final int discountedQuantity;
  final int giftQuantity;
  final double totalSales;
  final double totalPaid;
  final double outstanding;
  final double totalCogs;
  final double profitVsCogs;
  final double profitVsProduction;
  final int remainingQuantity;
  final int currentStock;

  const MarketOverviewRow({
    required this.listingId,
    required this.title,
    this.imageUrl,
    this.currency = 'TRY',
    this.price,
    required this.producedQuantity,
    this.avgUnitCost,
    required this.totalProductionCost,
    required this.soldQuantity,
    required this.regularQuantity,
    required this.discountedQuantity,
    required this.giftQuantity,
    required this.totalSales,
    required this.totalPaid,
    required this.outstanding,
    required this.totalCogs,
    required this.profitVsCogs,
    required this.profitVsProduction,
    required this.remainingQuantity,
    required this.currentStock,
  });

  factory MarketOverviewRow.fromJson(Map<String, dynamic> json) {
    return MarketOverviewRow(
      listingId: json['listing_id'] as String,
      title: json['title'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      currency: json['currency'] as String? ?? 'TRY',
      price: (json['price'] as num?)?.toDouble(),
      producedQuantity: _toInt(json['produced_quantity']),
      avgUnitCost: (json['avg_unit_cost'] as num?)?.toDouble(),
      totalProductionCost: _toDouble(json['total_production_cost']),
      soldQuantity: _toInt(json['sold_quantity']),
      regularQuantity: _toInt(json['regular_quantity']),
      discountedQuantity: _toInt(json['discounted_quantity']),
      giftQuantity: _toInt(json['gift_quantity']),
      totalSales: _toDouble(json['total_sales']),
      totalPaid: _toDouble(json['total_paid']),
      outstanding: _toDouble(json['outstanding']),
      totalCogs: _toDouble(json['total_cogs']),
      profitVsCogs: _toDouble(json['profit_vs_cogs']),
      profitVsProduction: _toDouble(json['profit_vs_production']),
      remainingQuantity: _toInt(json['remaining_quantity']),
      currentStock: _toInt(json['current_stock']),
    );
  }
}

/// Ürün raporundaki beden bazlı kırılım satırı.
class ProductSizeBreakdown {
  final String size;
  final ListingGender gender;
  final int produced;
  final int sold;
  final int remaining;
  final int stock;

  const ProductSizeBreakdown({
    required this.size,
    required this.gender,
    required this.produced,
    required this.sold,
    required this.remaining,
    required this.stock,
  });

  factory ProductSizeBreakdown.fromJson(Map<String, dynamic> json) {
    return ProductSizeBreakdown(
      size: json['size'] as String? ?? '',
      gender: ListingGender.fromString(json['gender'] as String? ?? 'unisex'),
      produced: _toInt(json['produced']),
      sold: _toInt(json['sold']),
      remaining: _toInt(json['remaining']),
      stock: _toInt(json['stock']),
    );
  }
}

/// Tek ürünün üretim / satış / kar-zarar özeti (Excel'in sağ blokları).
class ProductReportSummary {
  final String listingId;
  final String title;
  final String? imageUrl;
  final String currency;
  final double? price;
  final ListingGenderMode stockGenderMode;

  final int producedQuantity;
  final double productionCost;
  final double? avgUnitCost;

  final int totalSoldQuantity;
  final int regularQuantity;
  final int discountedQuantity;
  final int giftQuantity;
  final double regularTotal;
  final double discountedTotal;
  final double totalSales;
  final double totalPaid;
  final double outstanding;
  final double totalCogs;
  final double profitVsCogs;
  final double profitVsProduction;

  final int remainingQuantity;
  final int currentStock;
  final List<ProductSizeBreakdown> sizeBreakdown;

  const ProductReportSummary({
    required this.listingId,
    required this.title,
    this.imageUrl,
    this.currency = 'TRY',
    this.price,
    this.stockGenderMode = ListingGenderMode.unisex,
    required this.producedQuantity,
    required this.productionCost,
    this.avgUnitCost,
    required this.totalSoldQuantity,
    required this.regularQuantity,
    required this.discountedQuantity,
    required this.giftQuantity,
    required this.regularTotal,
    required this.discountedTotal,
    required this.totalSales,
    required this.totalPaid,
    required this.outstanding,
    required this.totalCogs,
    required this.profitVsCogs,
    required this.profitVsProduction,
    required this.remainingQuantity,
    required this.currentStock,
    this.sizeBreakdown = const [],
  });

  factory ProductReportSummary.fromJson(Map<String, dynamic> json) {
    final listing = json['listing'] as Map<String, dynamic>? ?? const {};
    final production = json['production'] as Map<String, dynamic>? ?? const {};
    final sales = json['sales'] as Map<String, dynamic>? ?? const {};
    final sizes = json['size_breakdown'] as List<dynamic>? ?? const [];

    return ProductReportSummary(
      listingId: listing['id'] as String? ?? '',
      title: listing['title'] as String? ?? '',
      imageUrl: listing['image_url'] as String?,
      currency: listing['currency'] as String? ?? 'TRY',
      price: (listing['price'] as num?)?.toDouble(),
      stockGenderMode: ListingGenderMode.fromString(
        listing['stock_gender_mode'] as String? ?? 'unisex',
      ),
      producedQuantity: _toInt(production['total_quantity']),
      productionCost: _toDouble(production['total_cost']),
      avgUnitCost: (production['avg_unit_cost'] as num?)?.toDouble(),
      totalSoldQuantity: _toInt(sales['total_quantity']),
      regularQuantity: _toInt(sales['regular_quantity']),
      discountedQuantity: _toInt(sales['discounted_quantity']),
      giftQuantity: _toInt(sales['gift_quantity']),
      regularTotal: _toDouble(sales['regular_total']),
      discountedTotal: _toDouble(sales['discounted_total']),
      totalSales: _toDouble(sales['total_sales']),
      totalPaid: _toDouble(sales['total_paid']),
      outstanding: _toDouble(sales['outstanding']),
      totalCogs: _toDouble(sales['total_cogs']),
      profitVsCogs: _toDouble(sales['profit_vs_cogs']),
      profitVsProduction: _toDouble(sales['profit_vs_production']),
      remainingQuantity: _toInt(json['remaining_quantity']),
      currentStock: _toInt(json['current_stock']),
      sizeBreakdown: sizes
          .map((e) => ProductSizeBreakdown.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Ürün satış geçmişindeki tek satır (Excel tablosunun bir satırı).
class ProductSalesRow {
  final String orderId;
  final int rowNo;
  final String? buyerId;
  final String buyerName;
  final bool isManual;
  final SaleType saleType;
  final String? size;
  final ListingGender? gender;
  final int quantity;
  final DateTime? orderDate;
  final DateTime? deliveryDate;
  final DateTime? paymentDate;
  final double? unitCost;
  final double totalCost;
  final double? unitPrice;
  final double totalPrice;
  final double paidAmount;
  final double outstanding;
  final double profit;
  final PaymentMethod? paymentMethod;
  final OrderStatus status;
  final String? note;

  const ProductSalesRow({
    required this.orderId,
    required this.rowNo,
    this.buyerId,
    required this.buyerName,
    required this.isManual,
    required this.saleType,
    this.size,
    this.gender,
    required this.quantity,
    this.orderDate,
    this.deliveryDate,
    this.paymentDate,
    this.unitCost,
    required this.totalCost,
    this.unitPrice,
    required this.totalPrice,
    required this.paidAmount,
    required this.outstanding,
    required this.profit,
    this.paymentMethod,
    required this.status,
    this.note,
  });

  factory ProductSalesRow.fromJson(Map<String, dynamic> json) {
    return ProductSalesRow(
      orderId: json['order_id'] as String,
      rowNo: _toInt(json['row_no']),
      buyerId: json['buyer_id'] as String?,
      buyerName: json['buyer_name'] as String? ?? 'Bilinmiyor',
      isManual: json['is_manual'] as bool? ?? false,
      saleType: SaleType.fromString(json['sale_type'] as String?),
      size: json['size'] as String?,
      gender: json['gender'] != null
          ? ListingGender.fromString(json['gender'] as String)
          : null,
      quantity: _toInt(json['quantity']),
      orderDate: _toDate(json['order_date']),
      deliveryDate: _toDate(json['delivery_date']),
      paymentDate: _toDate(json['payment_date']),
      unitCost: (json['unit_cost'] as num?)?.toDouble(),
      totalCost: _toDouble(json['total_cost']),
      unitPrice: (json['unit_price'] as num?)?.toDouble(),
      totalPrice: _toDouble(json['total_price']),
      paidAmount: _toDouble(json['paid_amount']),
      outstanding: _toDouble(json['outstanding']),
      profit: _toDouble(json['profit']),
      paymentMethod: PaymentMethod.fromString(json['payment_method'] as String?),
      status: OrderStatus.fromString(json['status'] as String? ?? 'pending'),
      note: json['note'] as String?,
    );
  }
}
