import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/enums/gender.dart';
import '../../data/datasources/marketplace_remote_datasource.dart';
import '../../data/models/listing_model.dart';
import '../../data/models/market_report_model.dart';
import '../../data/models/order_model.dart';
import '../../data/models/production_batch_model.dart';
import '../../data/models/stock_alert_model.dart';
import '../../utils/listing_price_utils.dart';

/// Supabase client provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Marketplace datasource provider
final marketplaceDataSourceProvider = Provider<MarketplaceRemoteDataSource>((ref) {
  return MarketplaceRemoteDataSourceImpl(ref.watch(_supabaseProvider));
});

/// Satış / üretim / ilan mutasyonları sonrası ve edit ekranı açılışında çağır.
/// Tüm market FutureProvider cache'lerini temizler; listings grid'i refresh eder.
void invalidateMarketplaceCaches(
  Ref ref, {
  String? listingId,
  String? orderId,
  bool refreshListingsGrid = true,
}) {
  if (listingId != null) {
    ref.invalidate(listingByIdProvider(listingId));
    ref.invalidate(stockBySizeProvider(listingId));
    ref.invalidate(productionBatchesProvider(listingId));
    ref.invalidate(listingAvgUnitCostProvider(listingId));
    ref.invalidate(productReportProvider(listingId));
    ref.invalidate(productSalesRowsProvider(listingId));
    ref.invalidate(userStockAlertsForListingProvider(listingId));
  }
  if (orderId != null) {
    ref.invalidate(orderByIdProvider(orderId));
  }

  ref.invalidate(adminListingsProvider);
  ref.invalidate(marketOverviewProvider);
  ref.invalidate(allOrdersProvider);
  ref.invalidate(buyerOrdersProvider);
  ref.invalidate(sellerOrdersProvider);
  ref.invalidate(myOrdersProvider);
  ref.invalidate(pendingStockAlertGroupsProvider);
  ref.invalidate(favoriteListingsProvider);
  ref.invalidate(userListingsProvider);

  if (refreshListingsGrid) {
    // invalidate listingsProvider boş state bırakır; refresh mevcut filtreyi korur
    ref.read(listingsProvider.notifier).refresh();
  }
}

/// WidgetRef için aynı invalidation (sayfa açılışları).
void invalidateMarketplaceCachesForWidget(
  WidgetRef ref, {
  String? listingId,
  String? orderId,
  bool refreshListingsGrid = true,
}) {
  if (listingId != null) {
    ref.invalidate(listingByIdProvider(listingId));
    ref.invalidate(stockBySizeProvider(listingId));
    ref.invalidate(productionBatchesProvider(listingId));
    ref.invalidate(listingAvgUnitCostProvider(listingId));
    ref.invalidate(productReportProvider(listingId));
    ref.invalidate(productSalesRowsProvider(listingId));
    ref.invalidate(userStockAlertsForListingProvider(listingId));
  }
  if (orderId != null) {
    ref.invalidate(orderByIdProvider(orderId));
  }

  ref.invalidate(adminListingsProvider);
  ref.invalidate(marketOverviewProvider);
  ref.invalidate(allOrdersProvider);
  ref.invalidate(buyerOrdersProvider);
  ref.invalidate(sellerOrdersProvider);
  ref.invalidate(myOrdersProvider);
  ref.invalidate(pendingStockAlertGroupsProvider);
  ref.invalidate(favoriteListingsProvider);
  ref.invalidate(userListingsProvider);

  if (refreshListingsGrid) {
    ref.read(listingsProvider.notifier).refresh();
  }
}

/// Listings State
class ListingsState {
  final List<ListingModel> listings;
  final bool isLoading;
  final String? error;
  final bool hasMore;
  final int offset;

  const ListingsState({
    this.listings = const [],
    this.isLoading = false,
    this.error,
    this.hasMore = true,
    this.offset = 0,
  });

  ListingsState copyWith({
    List<ListingModel>? listings,
    bool? isLoading,
    String? error,
    bool? hasMore,
    int? offset,
  }) {
    return ListingsState(
      listings: listings ?? this.listings,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
    );
  }
}

/// Listings Notifier
class ListingsNotifier extends StateNotifier<ListingsState> {
  final MarketplaceRemoteDataSource _dataSource;
  ListingType? _currentType;
  ListingCategory? _currentCategory;
  String? _searchQuery;

  ListingsNotifier(this._dataSource) : super(const ListingsState());

  Future<void> loadListings({
    ListingType? type,
    ListingCategory? category,
    String? searchQuery,
  }) async {
    if (state.isLoading) return;

    _currentType = type;
    _currentCategory = category;
    _searchQuery = searchQuery;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final listings = await _dataSource.getListings(
        type: type,
        category: category,
        searchQuery: searchQuery,
        limit: 20,
        offset: 0,
      );

      state = state.copyWith(
        listings: sortListingsInStockFirst(listings),
        isLoading: false,
        hasMore: listings.length >= 20,
        offset: listings.length,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final listings = await _dataSource.getListings(
        type: _currentType,
        category: _currentCategory,
        searchQuery: _searchQuery,
        limit: 20,
        offset: state.offset,
      );

      state = state.copyWith(
        listings: sortListingsInStockFirst([...state.listings, ...listings]),
        isLoading: false,
        hasMore: listings.length >= 20,
        offset: state.offset + listings.length,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    state = const ListingsState();
    await loadListings(
      type: _currentType,
      category: _currentCategory,
      searchQuery: _searchQuery,
    );
  }
}

/// Listings Provider
final listingsProvider = StateNotifierProvider<ListingsNotifier, ListingsState>((ref) {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return ListingsNotifier(dataSource);
});

/// Single Listing Provider
final listingByIdProvider = FutureProvider.family<ListingModel, String>((ref, listingId) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return await dataSource.getListingById(listingId);
});

/// User Listings Provider
final userListingsProvider = FutureProvider.family<List<ListingModel>, String>((ref, userId) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return await dataSource.getUserListings(userId);
});

/// Favorite Listings Notifier - Optimistic updates için
class FavoriteListingsNotifier extends StateNotifier<AsyncValue<List<ListingModel>>> {
  final MarketplaceRemoteDataSource _dataSource;

  FavoriteListingsNotifier(this._dataSource) : super(const AsyncValue.loading()) {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final favorites = await _dataSource.getFavoriteListings();
      state = AsyncValue.data(favorites);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _loadFavorites();
  }

  /// Optimistic update: Favori çıkarıldığında listeden hemen kaldır
  void removeFavoriteOptimistically(String listingId) {
    state.whenData((listings) {
      final updatedListings = listings.where((l) => l.id != listingId).toList();
      state = AsyncValue.data(updatedListings);
    });
  }

  /// Optimistic update: Favori eklendiğinde listeye ekle (eğer listing bilgisi varsa)
  void addFavoriteOptimistically(ListingModel listing) {
    state.whenData((listings) {
      if (!listings.any((l) => l.id == listing.id)) {
        final updatedListings = [listing, ...listings];
        state = AsyncValue.data(updatedListings);
      }
    });
  }
}

/// Favorite Listings Provider
final favoriteListingsProvider = StateNotifierProvider<FavoriteListingsNotifier, AsyncValue<List<ListingModel>>>((ref) {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return FavoriteListingsNotifier(dataSource);
});

/// Create Listing Notifier
class CreateListingNotifier extends StateNotifier<AsyncValue<ListingModel?>> {
  final Ref _ref;
  final MarketplaceRemoteDataSource _dataSource;

  CreateListingNotifier(this._ref, this._dataSource)
      : super(const AsyncValue.data(null));

  Future<void> createListing({
    required ListingType listingType,
    required ListingCategory category,
    required String title,
    String? description,
    double? price,
    String currency = 'TRY',
    ItemCondition? condition,
    String? brand,
    String? size,
    String? externalUrl,
    int? stockQuantity,
    Map<String, int>? stockBySize,
    List<String> imageUrls = const [],
    ListingGenderMode stockGenderMode = ListingGenderMode.unisex,
    Map<String, Map<ListingGender, int>>? stockBySizeAndGender,
    int? discountPercent,
    DateTime? discountStartsAt,
    DateTime? discountEndsAt,
  }) async {
    state = const AsyncValue.loading();

    try {
      final listing = ListingModel(
        id: '',
        sellerId: '',
        listingType: listingType,
        category: category,
        title: title,
        description: description,
        price: price,
        currency: currency,
        condition: condition,
        brand: brand,
        size: size,
        externalUrl: externalUrl,
        status: ListingStatus.active,
        stockQuantity: 0,
        stockGenderMode: stockGenderMode,
        discountPercent: discountPercent,
        discountStartsAt: discountStartsAt,
        discountEndsAt: discountEndsAt,
        imageUrls: imageUrls,
        createdAt: DateTime.now(),
      );

      final created = await _dataSource.createListing(listing, imageUrls);
      invalidateMarketplaceCaches(_ref, listingId: created.id);
      state = AsyncValue.data(created);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateListing({
    required String listingId,
    required ListingType listingType,
    required ListingCategory category,
    required String title,
    String? description,
    double? price,
    String currency = 'TRY',
    ItemCondition? condition,
    String? brand,
    String? size,
    String? externalUrl,
    int? stockQuantity,
    Map<String, int>? stockBySize,
    List<String>? imageUrls,
    ListingGenderMode stockGenderMode = ListingGenderMode.unisex,
    Map<String, Map<ListingGender, int>>? stockBySizeAndGender,
    int? discountPercent,
    DateTime? discountStartsAt,
    DateTime? discountEndsAt,
  }) async {
    state = const AsyncValue.loading();

    try {
      final listing = ListingModel(
        id: listingId,
        sellerId: '',
        listingType: listingType,
        category: category,
        title: title,
        description: description,
        price: price,
        currency: currency,
        condition: condition,
        brand: brand,
        size: size,
        externalUrl: externalUrl,
        status: ListingStatus.active,
        stockGenderMode: stockGenderMode,
        discountPercent: discountPercent,
        discountStartsAt: discountStartsAt,
        discountEndsAt: discountEndsAt,
        imageUrls: imageUrls ?? [],
        createdAt: DateTime.now(),
      );

      final updated = await _dataSource.updateListing(listing, imageUrls);
      invalidateMarketplaceCaches(_ref, listingId: listingId);
      state = AsyncValue.data(updated);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

/// Create Listing Provider
final createListingProvider = StateNotifierProvider<CreateListingNotifier, AsyncValue<ListingModel?>>((ref) {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return CreateListingNotifier(ref, dataSource);
});

/// Toggle Favorite Notifier
class ToggleFavoriteNotifier extends StateNotifier<AsyncValue<bool>> {
  final MarketplaceRemoteDataSource _dataSource;

  ToggleFavoriteNotifier(this._dataSource) : super(const AsyncValue.data(false));

  Future<void> toggleFavorite(String listingId) async {
    try {
      await _dataSource.toggleFavorite(listingId);
      final isFavorite = await _dataSource.isFavorite(listingId);
      state = AsyncValue.data(isFavorite);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> checkFavorite(String listingId) async {
    try {
      final isFavorite = await _dataSource.isFavorite(listingId);
      state = AsyncValue.data(isFavorite);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Toggle Favorite Provider
final toggleFavoriteProvider = StateNotifierProvider<ToggleFavoriteNotifier, AsyncValue<bool>>((ref) {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return ToggleFavoriteNotifier(dataSource);
});

/// Favorite IDs Cache Provider - Tüm favori ID'lerini cache'ler
class FavoriteIdsNotifier extends StateNotifier<Set<String>> {
  final MarketplaceRemoteDataSource _dataSource;

  FavoriteIdsNotifier(this._dataSource) : super({});

  Future<void> loadFavoriteIds(List<String> listingIds) async {
    if (listingIds.isEmpty) return;
    
    try {
      final favoriteIds = await _dataSource.getFavoriteListingIds(listingIds);
      state = {...state, ...favoriteIds};
    } catch (e) {
      // Hata durumunda sessizce devam et
    }
  }

  void addFavorite(String listingId) {
    state = {...state, listingId};
  }

  void removeFavorite(String listingId) {
    final newState = {...state};
    newState.remove(listingId);
    state = newState;
  }

  void clear() {
    state = {};
  }

  bool isFavorite(String listingId) {
    return state.contains(listingId);
  }
}

/// Favorite IDs Provider
final favoriteIdsProvider = StateNotifierProvider<FavoriteIdsNotifier, Set<String>>((ref) {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return FavoriteIdsNotifier(dataSource);
});

/// Create Order Notifier
class CreateOrderNotifier extends StateNotifier<AsyncValue<OrderModel?>> {
  final Ref _ref;
  final MarketplaceRemoteDataSource _dataSource;

  CreateOrderNotifier(this._ref, this._dataSource)
      : super(const AsyncValue.data(null));

  Future<void> createOrder({
    required String listingId,
    required double totalPrice,
    int quantity = 1,
    String currency = 'TRY',
    String? buyerNote,
    String? selectedSize,
    ListingGender? selectedGender,
  }) async {
    state = const AsyncValue.loading();

    try {
      final order = OrderModel(
        id: '',
        listingId: listingId,
        buyerId: '',
        sellerId: null, // Admin sipariş oluştururken satıcı ID'sine gerek yok
        quantity: quantity,
        totalPrice: totalPrice,
        currency: currency,
        status: OrderStatus.pending,
        buyerNote: buyerNote,
        selectedSize: selectedSize,
        selectedGender: selectedGender,
        createdAt: DateTime.now(),
      );

      final created = await _dataSource.createOrder(order);
      invalidateMarketplaceCaches(_ref, listingId: listingId, orderId: created.id);
      state = AsyncValue.data(created);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

/// Create Order Provider
final createOrderProvider = StateNotifierProvider<CreateOrderNotifier, AsyncValue<OrderModel?>>((ref) {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return CreateOrderNotifier(ref, dataSource);
});

/// Buyer Orders Provider
final buyerOrdersProvider = FutureProvider<List<OrderModel>>((ref) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return await dataSource.getBuyerOrders();
});

/// Seller Orders Provider
final sellerOrdersProvider = FutureProvider<List<OrderModel>>((ref) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return await dataSource.getSellerOrders();
});

/// Kendi siparişlerim (alıcı + satıcı, tarihe göre sıralı) - normal kullanıcı ve koçlar için
final myOrdersProvider = FutureProvider<List<OrderModel>>((ref) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  final buyerOrders = await dataSource.getBuyerOrders();
  final sellerOrders = await dataSource.getSellerOrders();
  final combined = [...buyerOrders, ...sellerOrders];
  combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return combined;
});

/// All Orders Provider (Admin)
final allOrdersProvider = FutureProvider.family<List<OrderModel>, OrderStatus?>((ref, status) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return await dataSource.getAllOrders(status: status);
});

/// Update Order Status Notifier
class UpdateOrderStatusNotifier extends StateNotifier<AsyncValue<OrderModel?>> {
  final Ref _ref;
  final MarketplaceRemoteDataSource _dataSource;

  UpdateOrderStatusNotifier(this._ref, this._dataSource)
      : super(const AsyncValue.data(null));

  Future<void> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    String? note,
  }) async {
    state = const AsyncValue.loading();

    try {
      final updated =
          await _dataSource.updateOrderStatus(orderId, status, note: note);
      invalidateMarketplaceCaches(
        _ref,
        listingId: updated.listingId,
        orderId: orderId,
      );
      state = AsyncValue.data(updated);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

/// Update Order Status Provider
final updateOrderStatusProvider = StateNotifierProvider<UpdateOrderStatusNotifier, AsyncValue<OrderModel?>>((ref) {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return UpdateOrderStatusNotifier(ref, dataSource);
});

/// Update Stock Quantity Notifier
class UpdateStockQuantityNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  final MarketplaceRemoteDataSource _dataSource;

  UpdateStockQuantityNotifier(this._ref, this._dataSource)
      : super(const AsyncValue.data(null));

  Future<void> updateStockQuantity(String listingId, int? stockQuantity) async {
    state = const AsyncValue.loading();

    try {
      await _dataSource.updateStockQuantity(listingId, stockQuantity);
      invalidateMarketplaceCaches(_ref, listingId: listingId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

/// Update Stock Quantity Provider
final updateStockQuantityProvider = StateNotifierProvider<UpdateStockQuantityNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return UpdateStockQuantityNotifier(ref, dataSource);
});

/// Update Listing Discount Notifier
class UpdateListingDiscountNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  final MarketplaceRemoteDataSource _dataSource;

  UpdateListingDiscountNotifier(this._ref, this._dataSource)
      : super(const AsyncValue.data(null));

  Future<void> updateDiscount({
    required String listingId,
    int? discountPercent,
    DateTime? discountStartsAt,
    DateTime? discountEndsAt,
  }) async {
    state = const AsyncValue.loading();

    try {
      await _dataSource.updateListingDiscount(
        listingId,
        discountPercent: discountPercent,
        discountStartsAt: discountStartsAt,
        discountEndsAt: discountEndsAt,
      );
      invalidateMarketplaceCaches(_ref, listingId: listingId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

/// Update Listing Discount Provider
final updateListingDiscountProvider =
    StateNotifierProvider<UpdateListingDiscountNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return UpdateListingDiscountNotifier(ref, dataSource);
});

/// Get Stock By Size Provider
final stockBySizeProvider = FutureProvider.family<Map<String, int>, String>((ref, listingId) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return await dataSource.getStockBySize(listingId);
});

/// Update Stock By Size Notifier
class UpdateStockBySizeNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  final MarketplaceRemoteDataSource _dataSource;

  UpdateStockBySizeNotifier(this._ref, this._dataSource)
      : super(const AsyncValue.data(null));

  Future<void> updateStockBySize(String listingId, Map<String, int> stockBySize) async {
    state = const AsyncValue.loading();

    try {
      await _dataSource.updateStockBySize(listingId, stockBySize);
      invalidateMarketplaceCaches(_ref, listingId: listingId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

/// Update Stock By Size Provider
final updateStockBySizeProvider = StateNotifierProvider<UpdateStockBySizeNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return UpdateStockBySizeNotifier(ref, dataSource);
});

String stockAlertScopeKey(
  String listingId, {
  String? size,
  ListingGender? gender,
}) {
  return '$listingId::${size ?? ''}::${gender?.value ?? ''}';
}

/// Kullanıcının bir ürün için aktif stok bildirim abonelikleri
final userStockAlertsForListingProvider =
    FutureProvider.family<List<StockAlertSubscription>, String>((ref, listingId) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return dataSource.getUserStockAlertsForListing(listingId);
});

/// Admin: bekleyen stok talepleri
final pendingStockAlertGroupsProvider =
    FutureProvider<List<ListingStockAlertGroup>>((ref) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return dataSource.getPendingStockAlertGroups();
});

/// Stok bildirimi aboneliği toggle
final toggleStockAlertProvider =
    StateNotifierProvider<ToggleStockAlertNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return ToggleStockAlertNotifier(dataSource);
});

class ToggleStockAlertNotifier extends StateNotifier<AsyncValue<void>> {
  final MarketplaceRemoteDataSource _dataSource;

  ToggleStockAlertNotifier(this._dataSource) : super(const AsyncValue.data(null));

  Future<void> subscribe({
    required String listingId,
    String? size,
    ListingGender? gender,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.subscribeStockAlert(
        listingId,
        size: size,
        gender: gender,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> unsubscribe({
    required String listingId,
    String? size,
    ListingGender? gender,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.unsubscribeStockAlert(
        listingId,
        size: size,
        gender: gender,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

// ============================================================
// Manuel satış, üretim maliyeti ve raporlama
// ============================================================

/// Rapor tarih aralığı filtresi. Null alanlar "sınırsız" anlamına gelir.
class ReportDateRange {
  final DateTime? from;
  final DateTime? to;

  const ReportDateRange({this.from, this.to});

  static const ReportDateRange all = ReportDateRange();

  @override
  bool operator ==(Object other) =>
      other is ReportDateRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// Admin ekranlarında ürün seçimi için tüm aktif ürünler
final adminListingsProvider = FutureProvider<List<ListingModel>>((ref) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return dataSource.getListings(limit: 200);
});

/// Tek sipariş (düzenleme ekranı için)
final orderByIdProvider =
    FutureProvider.family<OrderModel, String>((ref, orderId) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return dataSource.getOrderById(orderId);
});

/// Ürünün üretim partileri
final productionBatchesProvider =
    FutureProvider.family<List<ProductionBatch>, String>((ref, listingId) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return dataSource.getProductionBatches(listingId);
});

/// Ürünün ağırlıklı ortalama birim maliyeti
final listingAvgUnitCostProvider =
    FutureProvider.family<double?, String>((ref, listingId) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return dataSource.getListingAvgUnitCost(listingId);
});

/// Genel market raporu (tarih aralığı filtreli)
final marketOverviewProvider =
    FutureProvider.family<List<MarketOverviewRow>, ReportDateRange>(
        (ref, range) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return dataSource.getMarketOverview(from: range.from, to: range.to);
});

/// Tek ürün özet raporu
final productReportProvider =
    FutureProvider.family<ProductReportSummary, String>((ref, listingId) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return dataSource.getProductReport(listingId);
});

/// Ürün satış geçmişi satırları
final productSalesRowsProvider =
    FutureProvider.family<List<ProductSalesRow>, String>((ref, listingId) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return dataSource.getProductSalesRows(listingId);
});

/// Manuel satış ve üretim partisi yazma işlemleri
class ManualSaleNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  final MarketplaceRemoteDataSource _dataSource;

  ManualSaleNotifier(this._ref, this._dataSource)
      : super(const AsyncValue.data(null));

  Future<bool> createSale(OrderModel sale) async {
    state = const AsyncValue.loading();
    try {
      final created = await _dataSource.createManualSale(sale);
      invalidateMarketplaceCaches(
        _ref,
        listingId: sale.listingId,
        orderId: created.id,
      );
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<bool> updateSale(String orderId, OrderModel sale) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.updateSale(orderId, sale);
      invalidateMarketplaceCaches(
        _ref,
        listingId: sale.listingId,
        orderId: orderId,
      );
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<bool> deleteSale(String orderId, String listingId) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.deleteOrder(orderId);
      invalidateMarketplaceCaches(
        _ref,
        listingId: listingId,
        orderId: orderId,
      );
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<bool> updateListingSizesAndGenderMode({
    required String listingId,
    required String? size,
    required ListingGenderMode stockGenderMode,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.updateListingSizesAndGenderMode(
        listingId: listingId,
        size: size,
        stockGenderMode: stockGenderMode,
      );
      invalidateMarketplaceCaches(_ref, listingId: listingId);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<bool> saveProductionBatch({
    String? batchId,
    required String listingId,
    required double unitCost,
    required DateTime producedAt,
    String? note,
    required List<ProductionBatchItem> items,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.saveProductionBatch(
        batchId: batchId,
        listingId: listingId,
        unitCost: unitCost,
        producedAt: producedAt,
        note: note,
        items: items,
      );
      invalidateMarketplaceCaches(_ref, listingId: listingId);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<bool> deleteProductionBatch(String batchId, String listingId) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.deleteProductionBatch(batchId);
      invalidateMarketplaceCaches(_ref, listingId: listingId);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

final manualSaleProvider =
    StateNotifierProvider<ManualSaleNotifier, AsyncValue<void>>((ref) {
  return ManualSaleNotifier(ref, ref.watch(marketplaceDataSourceProvider));
});
