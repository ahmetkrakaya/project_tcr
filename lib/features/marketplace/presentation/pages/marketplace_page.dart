import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/listing_model.dart';
import '../../utils/listing_price_utils.dart';
import '../providers/marketplace_provider.dart';

/// Marketplace Page
class MarketplacePage extends ConsumerStatefulWidget {
  const MarketplacePage({super.key});

  @override
  ConsumerState<MarketplacePage> createState() => _MarketplacePageState();
}

enum _StockFilter { all, inStock, outOfStock }

const _marketCategories = <(ListingCategory, IconData, String)>[
  (ListingCategory.runningShoes, Icons.directions_run_rounded, 'Ayakkabı'),
  (ListingCategory.sportsWear, Icons.checkroom_rounded, 'Giyim'),
  (ListingCategory.watchesTrackers, Icons.watch_rounded, 'Saat'),
  (ListingCategory.accessories, Icons.backpack_rounded, 'Aksesuar'),
  (ListingCategory.nutrition, Icons.restaurant_rounded, 'Beslenme'),
  (ListingCategory.equipment, Icons.fitness_center_rounded, 'Ekipman'),
  (ListingCategory.other, Icons.more_horiz_rounded, 'Diğer'),
];

class _MarketplacePageState extends ConsumerState<MarketplacePage> {
  final _searchController = TextEditingController();
  ListingCategory? _selectedCategory;
  _StockFilter _stockFilter = _StockFilter.all;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  void _loadListings() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final searchQuery = _searchController.text.trim();
      ref.read(listingsProvider.notifier).loadListings(
            type: ListingType.tcrProduct,
            category: _selectedCategory,
            searchQuery: searchQuery.isEmpty ? null : searchQuery,
          );
    });
  }

  void _onSearchChanged(String value) {
    // Debounce: 500ms bekle, sonra sorgu at
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _loadListings();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<ListingModel> _applyStockFilter(List<ListingModel> listings) {
    switch (_stockFilter) {
      case _StockFilter.all:
        return listings;
      case _StockFilter.inStock:
        return listings.where(isListingInStock).toList();
      case _StockFilter.outOfStock:
        return listings.where(isListingOutOfStock).toList();
    }
  }

  bool get _hasActiveFilters =>
      _selectedCategory != null || _stockFilter != _StockFilter.all;

  int get _activeFilterCount =>
      (_selectedCategory != null ? 1 : 0) +
      (_stockFilter != _StockFilter.all ? 1 : 0);

  String _categoryLabel(ListingCategory category) {
    for (final item in _marketCategories) {
      if (item.$1 == category) return item.$3;
    }
    return 'Diğer';
  }

  String _stockFilterLabel(_StockFilter filter) {
    switch (filter) {
      case _StockFilter.all:
        return 'Tümü';
      case _StockFilter.inStock:
        return 'Stokta';
      case _StockFilter.outOfStock:
        return 'Tükendi';
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedCategory = null;
      _stockFilter = _StockFilter.all;
    });
    _loadListings();
  }

  void _showFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MarketFilterSheet(
        selectedCategory: _selectedCategory,
        selectedStock: _stockFilter,
        onApply: (category, stock) {
          setState(() {
            _selectedCategory = category;
            _stockFilter = stock;
          });
          _loadListings();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('TCR Market'),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final isAdmin = ref.watch(isAdminProvider);
              if (isAdmin) {
                return PopupMenuButton<_MarketMenuAction>(
                  tooltip: 'Menü',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) {
                    switch (action) {
                      case _MarketMenuAction.favorites:
                        context.pushNamed(RouteNames.favorites);
                      case _MarketMenuAction.myOrders:
                        context.pushNamed(RouteNames.myOrders);
                      case _MarketMenuAction.ordersManagement:
                        context.pushNamed(RouteNames.ordersManagement);
                      case _MarketMenuAction.stockAlerts:
                        context.pushNamed(RouteNames.stockAlertsAdmin);
                      case _MarketMenuAction.createListing:
                        context.pushNamed(RouteNames.listingCreate);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: _MarketMenuAction.createListing,
                      child: Row(
                        children: [
                          Icon(Icons.add),
                          SizedBox(width: 12),
                          Text('Yeni İlan'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: _MarketMenuAction.ordersManagement,
                      child: Row(
                        children: [
                          Icon(Icons.shopping_cart_outlined),
                          SizedBox(width: 12),
                          Text('Sipariş Yönetimi'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: _MarketMenuAction.stockAlerts,
                      child: Row(
                        children: [
                          Icon(Icons.notifications_active_outlined),
                          SizedBox(width: 12),
                          Text('Stok Talepleri'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _MarketMenuAction.favorites,
                      child: Row(
                        children: [
                          Icon(Icons.favorite_outline),
                          SizedBox(width: 12),
                          Text('Favorilerim'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: _MarketMenuAction.myOrders,
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long_outlined),
                          SizedBox(width: 12),
                          Text('Siparişlerim'),
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.favorite),
                    tooltip: 'Favorilerim',
                    onPressed: () => context.pushNamed(RouteNames.favorites),
                  ),
                  IconButton(
                    icon: const Icon(Icons.receipt_long_outlined),
                    tooltip: 'Siparişlerim',
                    onPressed: () => context.pushNamed(RouteNames.myOrders),
                  ),
                ],
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: AppSearchField(
                    controller: _searchController,
                    hint: 'Ürün ara...',
                    onChanged: _onSearchChanged,
                  ),
                ),
                const SizedBox(width: 10),
                _FilterButton(
                  activeCount: _activeFilterCount,
                  onTap: _showFilterSheet,
                ),
              ],
            ),
          ),
        ),
      ),
      body: _buildListingGrid(ListingType.tcrProduct),
    );
  }

  Widget _buildListingGrid(ListingType type) {
    final listingsState = ref.watch(listingsProvider);
    final filteredListings = _applyStockFilter(listingsState.listings);

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(listingsProvider.notifier).refresh();
      },
      child: CustomScrollView(
        slivers: [
          if (_hasActiveFilters)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: _ActiveFilterChips(
                  categoryLabel: _selectedCategory != null
                      ? _categoryLabel(_selectedCategory!)
                      : null,
                  stockLabel: _stockFilter != _StockFilter.all
                      ? _stockFilterLabel(_stockFilter)
                      : null,
                  onRemoveCategory: () {
                    setState(() => _selectedCategory = null);
                    _loadListings();
                  },
                  onRemoveStock: () {
                    setState(() => _stockFilter = _StockFilter.all);
                  },
                  onClearAll: _clearFilters,
                ),
              ),
            ),

          // Listings Grid
          if (listingsState.isLoading && listingsState.listings.isEmpty)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (listingsState.error != null && listingsState.listings.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: AppColors.error),
                    const SizedBox(height: 16),
                    Text(
                      'Bir hata oluştu',
                      style: AppTypography.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      listingsState.error!,
                      style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref.read(listingsProvider.notifier).refresh(),
                      child: const Text('Tekrar Dene'),
                    ),
                  ],
                ),
              ),
            )
          else if (listingsState.listings.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_bag_outlined, size: 64, color: AppColors.neutral400),
                    const SizedBox(height: 16),
                    Text(
                      'Henüz ilan yok',
                      style: AppTypography.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'İlk ilanı sen oluştur!',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
                    ),
                  ],
                ),
              ),
            )
          else if (filteredListings.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 56, color: AppColors.neutral400),
                    const SizedBox(height: 16),
                    Text(
                      'Bu filtrede ürün yok',
                      style: AppTypography.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Filtreleri değiştirmeyi deneyin',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                    if (_hasActiveFilters) ...[
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _clearFilters,
                        child: const Text('Filtreleri temizle'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: _ListingsGrid(
                listings: filteredListings,
                hasMore: _stockFilter == _StockFilter.all && listingsState.hasMore,
                onLoadMore: () {
                  ref.read(listingsProvider.notifier).loadMore();
                },
              ),
            ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 16),
          ),
        ],
      ),
    );
  }

}

/// Optimized Listings Grid - Favori durumlarını batch olarak yükler
class _ListingsGrid extends ConsumerStatefulWidget {
  final List<ListingModel> listings;
  final bool hasMore;
  final VoidCallback onLoadMore;

  const _ListingsGrid({
    required this.listings,
    required this.hasMore,
    required this.onLoadMore,
  });

  @override
  ConsumerState<_ListingsGrid> createState() => _ListingsGridState();
}

class _ListingsGridState extends ConsumerState<_ListingsGrid> {
  bool _hasLoadedFavorites = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFavoriteIds();
    });
  }

  @override
  void didUpdateWidget(_ListingsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Listings değiştiğinde favori ID'lerini yükle
    if (widget.listings != oldWidget.listings && widget.listings.isNotEmpty) {
      // Yeni liste geldiğinde flag'i sıfırla
      final oldIds = oldWidget.listings.map((l) => l.id).toSet();
      final newIds = widget.listings.map((l) => l.id).toSet();
      if (oldIds != newIds) {
        _hasLoadedFavorites = false;
        _loadFavoriteIds();
      }
    }
  }

  void _loadFavoriteIds() {
    if (_hasLoadedFavorites || widget.listings.isEmpty) return;
    
    final listingIds = widget.listings.map((l) => l.id).toList();
    ref.read(favoriteIdsProvider.notifier).loadFavoriteIds(listingIds);
    _hasLoadedFavorites = true;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = 32.0;
    const spacing = 12.0;
    // Web'de daha fazla sütun (kartlar çok geniş olmasın); mobilde 2 sütun
    final crossAxisCount = kIsWeb
        ? (width / 280).floor().clamp(2, 6)
        : 2;
    final cardWidth = (width - padding - spacing * (crossAxisCount - 1)) / crossAxisCount;
    final cardHeight = cardWidth / 0.62;
    final childAspectRatio = cardWidth / cardHeight;

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: childAspectRatio,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < widget.listings.length) {
            return _buildListingCard(context, widget.listings[index]);
          } else if (index == widget.listings.length && widget.hasMore) {
            // Load more
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onLoadMore();
            });
            return const Center(child: CircularProgressIndicator());
          }
          return const SizedBox.shrink();
        },
        childCount: widget.listings.length + (widget.hasMore ? 1 : 0),
      ),
    );
  }

  Widget _buildListingCard(BuildContext context, ListingModel listing) {
    final isTcrProduct = listing.listingType == ListingType.tcrProduct;
    final isOutOfStock = isListingOutOfStock(listing);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isOutOfStock
            ? (isDark
                ? AppColors.neutral400.withValues(alpha: 0.2)
                : AppColors.neutral300)
            : (isDark
                ? AppColors.neutral400.withValues(alpha: 0.12)
                : AppColors.neutral200),
      ),
      elevation: isOutOfStock ? 0 : 1,
      onTap: () {
        ref.read(marketplaceDataSourceProvider).incrementViewCount(listing.id);
        context.pushNamed(
          RouteNames.listingDetail,
          pathParameters: {'listingId': listing.id},
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Görsel yüksekliği: kartın ~%58'i; web'de büyük kartlarda daha yüksek üst sınır
          final maxImageHeight = kIsWeb && constraints.maxHeight > 320 ? 240.0 : 160.0;
          final imageHeight = (constraints.maxHeight * 0.58).clamp(100.0, maxImageHeight);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Image
              Stack(
                children: [
                  SizedBox(
                    height: imageHeight,
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.neutral200,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: listing.primaryImageUrl != null
                          ? ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Opacity(
                                    opacity: isOutOfStock ? 0.45 : 1,
                                    child: Image.network(
                                      listing.primaryImageUrl!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: imageHeight,
                                      loadingBuilder:
                                          (context, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        );
                                      },
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Center(
                                        child: Icon(
                                          Icons.image,
                                          size: 48,
                                          color: AppColors.neutral400,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isOutOfStock)
                                    Container(
                                      color: Colors.black.withValues(alpha: 0.18),
                                      alignment: Alignment.center,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.92),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Stokta Yok',
                                          style: AppTypography.labelSmall
                                              .copyWith(
                                            color: AppColors.neutral700,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : Center(
                              child: Icon(
                                Icons.image,
                                size: 48,
                                color: isOutOfStock
                                    ? AppColors.neutral400
                                    : AppColors.neutral400,
                              ),
                            ),
                    ),
                  ),
                  if (isTcrProduct)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified,
                              size: 11,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'TCR',
                              style: AppTypography.labelSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (isListingDiscountActive(listing) && !isOutOfStock)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '%${listing.discountPercent}',
                          style: AppTypography.labelSmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _FavoriteButton(listingId: listing.id, listing: listing),
                  ),
                ],
              ),
              // Info - kalan alanı doldurur, taşma olmaz
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          listing.title,
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isOutOfStock
                                ? AppColors.neutral500
                                : null,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_buildSubtitle(listing).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _buildSubtitle(listing),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const Spacer(),
                      Opacity(
                        opacity: isOutOfStock ? 0.55 : 1,
                        child: ListingPriceDisplay(
                          listing: listing,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _buildSubtitle(ListingModel listing) {
    final parts = <String>[];
    if (listing.size != null) parts.add(listing.size!);
    if (listing.brand != null) parts.add(listing.brand!);
    return parts.join(' • ');
  }
}

/// Favorite Button Widget - Optimized with cache
class _FavoriteButton extends ConsumerWidget {
  final String listingId;
  final ListingModel? listing;

  const _FavoriteButton({required this.listingId, this.listing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriteIds = ref.watch(favoriteIdsProvider);
    final isFavorite = favoriteIds.contains(listingId);

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: IconButton(
          key: ValueKey(isFavorite),
          icon: Icon(
            isFavorite ? Icons.favorite : Icons.favorite_border,
            size: 16,
            color: isFavorite ? AppColors.error : AppColors.neutral600,
          ),
          padding: EdgeInsets.zero,
          onPressed: () {
            final wasFavorite = isFavorite;

            // Hemen UI'ı güncelle (optimistic update)
            if (wasFavorite) {
              ref.read(favoriteIdsProvider.notifier).removeFavorite(listingId);
              // Favoriler sayfasından da hemen kaldır
              ref.read(favoriteListingsProvider.notifier).removeFavoriteOptimistically(listingId);
            } else {
              ref.read(favoriteIdsProvider.notifier).addFavorite(listingId);
            }

            // API çağrısını arka planda yap (await etme)
            ref.read(toggleFavoriteProvider.notifier).toggleFavorite(listingId).then((_) {
              // API çağrısı başarılı olduğunda favoriler listesini güncelle
              if (!wasFavorite) {
                // Favori eklendi, optimistic update yap
                if (listing != null) {
                  ref.read(favoriteListingsProvider.notifier).addFavoriteOptimistically(listing!);
                } else {
                  // Listing bilgisi yoksa refresh et
                  ref.read(favoriteListingsProvider.notifier).refresh();
                }
              }
            }).catchError((e) {
              // Hata durumunda geri al
              if (wasFavorite) {
                ref.read(favoriteIdsProvider.notifier).addFavorite(listingId);
                ref.read(favoriteListingsProvider.notifier).refresh();
              } else {
                ref.read(favoriteIdsProvider.notifier).removeFavorite(listingId);
              }
            });
          },
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;

  const _FilterButton({
    required this.activeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? AppColors.surfaceDark : AppColors.neutral100,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: activeCount > 0
                  ? AppColors.primary
                  : (isDark
                      ? AppColors.neutral400.withValues(alpha: 0.2)
                      : AppColors.neutral300),
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 22,
                color: activeCount > 0
                    ? AppColors.primary
                    : AppColors.neutral700,
              ),
              if (activeCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveFilterChips extends StatelessWidget {
  final String? categoryLabel;
  final String? stockLabel;
  final VoidCallback onRemoveCategory;
  final VoidCallback onRemoveStock;
  final VoidCallback onClearAll;

  const _ActiveFilterChips({
    required this.categoryLabel,
    required this.stockLabel,
    required this.onRemoveCategory,
    required this.onRemoveStock,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (categoryLabel != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ActiveFilterChip(
                label: categoryLabel!,
                onRemove: onRemoveCategory,
              ),
            ),
          if (stockLabel != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ActiveFilterChip(
                label: stockLabel!,
                onRemove: onRemoveStock,
              ),
            ),
          TextButton(
            onPressed: onClearAll,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Temizle',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ActiveFilterChip({
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.close,
                size: 16,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketFilterSheet extends StatefulWidget {
  final ListingCategory? selectedCategory;
  final _StockFilter selectedStock;
  final void Function(ListingCategory? category, _StockFilter stock) onApply;

  const _MarketFilterSheet({
    required this.selectedCategory,
    required this.selectedStock,
    required this.onApply,
  });

  @override
  State<_MarketFilterSheet> createState() => _MarketFilterSheetState();
}

class _MarketFilterSheetState extends State<_MarketFilterSheet> {
  late ListingCategory? _category;
  late _StockFilter _stock;

  @override
  void initState() {
    super.initState();
    _category = widget.selectedCategory;
    _stock = widget.selectedStock;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? AppColors.neutral400.withValues(alpha: 0.2)
        : AppColors.neutral300;
    final fieldFill = isDark ? AppColors.backgroundDark : AppColors.neutral100;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.neutral300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Filtrele',
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _FilterDropdownField<ListingCategory?>(
                label: 'Kategori',
                value: _category,
                fillColor: fieldFill,
                borderColor: borderColor,
                items: [
                  DropdownMenuItem<ListingCategory?>(
                    value: null,
                    child: _FilterDropdownRow(
                      icon: Icons.apps_rounded,
                      label: 'Tümü',
                    ),
                  ),
                  ..._marketCategories.map(
                    (item) => DropdownMenuItem<ListingCategory?>(
                      value: item.$1,
                      child: _FilterDropdownRow(
                        icon: item.$2,
                        label: item.$3,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _category = value),
              ),
              const SizedBox(height: 16),
              _FilterDropdownField<_StockFilter>(
                label: 'Stok durumu',
                value: _stock,
                fillColor: fieldFill,
                borderColor: borderColor,
                items: const [
                  DropdownMenuItem(
                    value: _StockFilter.all,
                    child: _FilterDropdownRow(
                      icon: Icons.inventory_2_outlined,
                      label: 'Tümü',
                    ),
                  ),
                  DropdownMenuItem(
                    value: _StockFilter.inStock,
                    child: _FilterDropdownRow(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Stokta',
                    ),
                  ),
                  DropdownMenuItem(
                    value: _StockFilter.outOfStock,
                    child: _FilterDropdownRow(
                      icon: Icons.block_outlined,
                      label: 'Tükendi',
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _stock = value);
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _category = null;
                          _stock = _StockFilter.all;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        shape: buttonShape,
                        side: BorderSide(color: borderColor),
                        foregroundColor: AppColors.neutral800,
                      ),
                      child: const Text('Sıfırla'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        widget.onApply(_category, _stock);
                        Navigator.pop(context);
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: AppColors.primary,
                        shape: buttonShape,
                      ),
                      child: const Text('Uygula'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterDropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final Color fillColor;
  final Color borderColor;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _FilterDropdownField({
    required this.label,
    required this.value,
    required this.fillColor,
    required this.borderColor,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: borderColor),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.neutral600,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.neutral600,
          ),
          borderRadius: BorderRadius.circular(12),
          dropdownColor: Theme.of(context).brightness == Brightness.dark
              ? AppColors.surfaceDark
              : Colors.white,
          items: items,
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: fillColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterDropdownRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FilterDropdownRow({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.neutral700),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

enum _MarketMenuAction {
  favorites,
  myOrders,
  ordersManagement,
  stockAlerts,
  createListing,
}
