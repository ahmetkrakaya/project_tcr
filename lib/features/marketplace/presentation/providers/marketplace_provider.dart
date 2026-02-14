import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/marketplace_remote_datasource.dart';
import '../../data/models/listing_model.dart';
import '../../data/models/order_model.dart';

/// Supabase client provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Marketplace datasource provider
final marketplaceDataSourceProvider = Provider<MarketplaceRemoteDataSource>((ref) {
  return MarketplaceRemoteDataSourceImpl(ref.watch(_supabaseProvider));
});

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
        listings: listings,
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
        listings: [...state.listings, ...listings],
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
  final MarketplaceRemoteDataSource _dataSource;

  CreateListingNotifier(this._dataSource) : super(const AsyncValue.data(null));

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
        stockQuantity: stockQuantity,
        stockBySize: stockBySize,
        imageUrls: imageUrls,
        createdAt: DateTime.now(),
      );

      final created = await _dataSource.createListing(listing, imageUrls);
      
      // Beden bazlı stok varsa kaydet
      if (stockBySize != null && stockBySize.isNotEmpty) {
        await _dataSource.updateStockBySize(created.id, stockBySize);
        // Güncellenmiş listing'i tekrar getir
        final updated = await _dataSource.getListingById(created.id);
        state = AsyncValue.data(updated);
      } else {
        state = AsyncValue.data(created);
      }
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
        stockQuantity: stockQuantity,
        stockBySize: stockBySize,
        imageUrls: imageUrls ?? [],
        createdAt: DateTime.now(),
      );

      final updated = await _dataSource.updateListing(listing, imageUrls);
      
      // Beden bazlı stok varsa kaydet
      if (stockBySize != null) {
        await _dataSource.updateStockBySize(listingId, stockBySize);
        // Güncellenmiş listing'i tekrar getir
        final finalUpdated = await _dataSource.getListingById(listingId);
        state = AsyncValue.data(finalUpdated);
      } else {
        state = AsyncValue.data(updated);
      }
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
  return CreateListingNotifier(dataSource);
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
  final MarketplaceRemoteDataSource _dataSource;

  CreateOrderNotifier(this._dataSource) : super(const AsyncValue.data(null));

  Future<void> createOrder({
    required String listingId,
    required double totalPrice,
    int quantity = 1,
    String currency = 'TRY',
    String? buyerNote,
    String? selectedSize,
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
        createdAt: DateTime.now(),
      );

      final created = await _dataSource.createOrder(order);
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
  return CreateOrderNotifier(dataSource);
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
  final MarketplaceRemoteDataSource _dataSource;

  UpdateOrderStatusNotifier(this._dataSource) : super(const AsyncValue.data(null));

  Future<void> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    String? note,
  }) async {
    state = const AsyncValue.loading();

    try {
      final updated = await _dataSource.updateOrderStatus(orderId, status, note: note);
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
  return UpdateOrderStatusNotifier(dataSource);
});

/// Update Stock Quantity Notifier
class UpdateStockQuantityNotifier extends StateNotifier<AsyncValue<void>> {
  final MarketplaceRemoteDataSource _dataSource;

  UpdateStockQuantityNotifier(this._dataSource) : super(const AsyncValue.data(null));

  Future<void> updateStockQuantity(String listingId, int? stockQuantity) async {
    state = const AsyncValue.loading();

    try {
      await _dataSource.updateStockQuantity(listingId, stockQuantity);
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
  return UpdateStockQuantityNotifier(dataSource);
});

/// Get Stock By Size Provider
final stockBySizeProvider = FutureProvider.family<Map<String, int>, String>((ref, listingId) async {
  final dataSource = ref.watch(marketplaceDataSourceProvider);
  return await dataSource.getStockBySize(listingId);
});

/// Update Stock By Size Notifier
class UpdateStockBySizeNotifier extends StateNotifier<AsyncValue<void>> {
  final MarketplaceRemoteDataSource _dataSource;

  UpdateStockBySizeNotifier(this._dataSource) : super(const AsyncValue.data(null));

  Future<void> updateStockBySize(String listingId, Map<String, int> stockBySize) async {
    state = const AsyncValue.loading();

    try {
      await _dataSource.updateStockBySize(listingId, stockBySize);
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
  return UpdateStockBySizeNotifier(dataSource);
});
