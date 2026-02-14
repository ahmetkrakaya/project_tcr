/// Listing Type Enum
enum ListingType {
  tcrProduct('tcr_product');

  final String value;
  const ListingType(this.value);

  static ListingType fromString(String value) {
    return ListingType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ListingType.tcrProduct,
    );
  }
}

/// Listing Status Enum
enum ListingStatus {
  active('active'),
  sold('sold'),
  reserved('reserved'),
  expired('expired'),
  deleted('deleted');

  final String value;
  const ListingStatus(this.value);

  static ListingStatus fromString(String value) {
    return ListingStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ListingStatus.active,
    );
  }
}

/// Listing Category Enum
enum ListingCategory {
  runningShoes('running_shoes'),
  sportsWear('sports_wear'),
  accessories('accessories'),
  watchesTrackers('watches_trackers'),
  nutrition('nutrition'),
  equipment('equipment'),
  books('books'),
  other('other');

  final String value;
  const ListingCategory(this.value);

  static ListingCategory fromString(String value) {
    return ListingCategory.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ListingCategory.other,
    );
  }
}

/// Item Condition Enum
enum ItemCondition {
  new_('new'),
  likeNew('like_new'),
  good('good'),
  fair('fair'),
  poor('poor');

  final String value;
  const ItemCondition(this.value);

  static ItemCondition? fromString(String? value) {
    if (value == null) return null;
    return ItemCondition.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ItemCondition.good,
    );
  }
}

/// Marketplace Listing Model
class ListingModel {
  final String id;
  final String sellerId;
  final String? sellerName;
  final String? sellerAvatarUrl;
  final ListingType listingType;
  final ListingCategory category;
  final String title;
  final String? description;
  final double? price;
  final String currency;
  final ItemCondition? condition;
  final String? brand;
  final String? size;
  final String? externalUrl;
  final ListingStatus status;
  final int viewCount;
  final int? stockQuantity; // NULL = sınırsız, 0 = stok yok, >0 = mevcut stok (deprecated - use stockBySize)
  final Map<String, int>? stockBySize; // Beden bazlı stok: {"S": 3, "L": 7}
  final DateTime? expiresAt;
  final List<String> imageUrls;
  final String? primaryImageUrl;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const ListingModel({
    required this.id,
    required this.sellerId,
    this.sellerName,
    this.sellerAvatarUrl,
    required this.listingType,
    required this.category,
    required this.title,
    this.description,
    this.price,
    this.currency = 'TRY',
    this.condition,
    this.brand,
    this.size,
    this.externalUrl,
    this.status = ListingStatus.active,
    this.viewCount = 0,
    this.stockQuantity,
    this.stockBySize,
    this.expiresAt,
    this.imageUrls = const [],
    this.primaryImageUrl,
    this.isFavorite = false,
    required this.createdAt,
    this.updatedAt,
  });

  factory ListingModel.fromJson(Map<String, dynamic> json) {
    return ListingModel(
      id: json['id'] as String,
      sellerId: json['seller_id'] as String,
      sellerName: json['seller_name'] as String?,
      sellerAvatarUrl: json['seller_avatar'] as String?,
      listingType: ListingType.fromString(json['listing_type'] as String),
      category: ListingCategory.fromString(json['category'] as String),
      title: json['title'] as String,
      description: json['description'] as String?,
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      currency: json['currency'] as String? ?? 'TRY',
      condition: ItemCondition.fromString(json['condition'] as String?),
      brand: json['brand'] as String?,
      size: json['size'] as String?,
      externalUrl: json['external_url'] as String?,
      status: ListingStatus.fromString(json['status'] as String),
      viewCount: json['view_count'] as int? ?? 0,
      stockQuantity: json['stock_quantity'] as int?,
      stockBySize: json['stock_by_size'] != null
          ? Map<String, int>.from(
              (json['stock_by_size'] as Map).map(
                (key, value) => MapEntry(key.toString(), value as int),
              ),
            )
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      imageUrls: json['image_urls'] != null
          ? List<String>.from(json['image_urls'] as List)
          : [],
      primaryImageUrl: json['primary_image'] as String?,
      isFavorite: json['is_favorite'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'seller_id': sellerId,
      'listing_type': listingType.value,
      'category': category.value,
      'title': title,
      'description': description,
      'price': price,
      'currency': currency,
      'condition': condition?.value,
      'brand': brand,
      'size': size,
      'external_url': externalUrl,
      'status': status.value,
      'stock_quantity': stockQuantity,
      'expires_at': expiresAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toJsonWithId() {
    return {
      'id': id,
      ...toJson(),
    };
  }

  ListingModel copyWith({
    String? id,
    String? sellerId,
    String? sellerName,
    String? sellerAvatarUrl,
    ListingType? listingType,
    ListingCategory? category,
    String? title,
    String? description,
    double? price,
    String? currency,
    ItemCondition? condition,
    String? brand,
    String? size,
    String? externalUrl,
    ListingStatus? status,
    int? viewCount,
    int? stockQuantity,
    DateTime? expiresAt,
    List<String>? imageUrls,
    String? primaryImageUrl,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ListingModel(
      id: id ?? this.id,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      sellerAvatarUrl: sellerAvatarUrl ?? this.sellerAvatarUrl,
      listingType: listingType ?? this.listingType,
      category: category ?? this.category,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      condition: condition ?? this.condition,
      brand: brand ?? this.brand,
      size: size ?? this.size,
      externalUrl: externalUrl ?? this.externalUrl,
      status: status ?? this.status,
      viewCount: viewCount ?? this.viewCount,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      expiresAt: expiresAt ?? this.expiresAt,
      imageUrls: imageUrls ?? this.imageUrls,
      primaryImageUrl: primaryImageUrl ?? this.primaryImageUrl,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
