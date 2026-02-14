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
import '../providers/marketplace_provider.dart';

/// Marketplace Page
class MarketplacePage extends ConsumerStatefulWidget {
  const MarketplacePage({super.key});

  @override
  ConsumerState<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends ConsumerState<MarketplacePage> {
  final _searchController = TextEditingController();
  ListingCategory? _selectedCategory;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TCR Market'),
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite),
            tooltip: 'Favorilerim',
            onPressed: () {
              context.pushNamed(RouteNames.favorites);
            },
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Siparişlerim',
            onPressed: () {
              context.pushNamed(RouteNames.myOrders);
            },
          ),
          Consumer(
            builder: (context, ref, child) {
              final isAdmin = ref.watch(isAdminProvider);
              if (!isAdmin) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.shopping_cart),
                    tooltip: 'Sipariş Yönetimi',
                    onPressed: () {
                      context.pushNamed(RouteNames.ordersManagement);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Yeni İlan',
                    onPressed: () {
                      context.pushNamed(RouteNames.listingCreate);
                    },
                  ),
                ],
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppSearchField(
              controller: _searchController,
              hint: 'Ürün ara...',
              onChanged: _onSearchChanged,
            ),
          ),
        ),
      ),
      body: _buildListingGrid(ListingType.tcrProduct),
    );
  }

  Widget _buildListingGrid(ListingType type) {
    final listingsState = ref.watch(listingsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(listingsProvider.notifier).refresh();
      },
      child: CustomScrollView(
        slivers: [
          // Categories - AllTrails style animated chips
          SliverToBoxAdapter(
            child: SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                clipBehavior: Clip.none,
                children: [
                  _AnimatedCategoryChip(
                    icon: Icons.directions_run_rounded,
                    label: 'Ayakkabı',
                    isSelected: _selectedCategory == ListingCategory.runningShoes,
                    onTap: () => _onCategoryTap(ListingCategory.runningShoes),
                  ),
                  _AnimatedCategoryChip(
                    icon: Icons.checkroom_rounded,
                    label: 'Giyim',
                    isSelected: _selectedCategory == ListingCategory.sportsWear,
                    onTap: () => _onCategoryTap(ListingCategory.sportsWear),
                  ),
                  _AnimatedCategoryChip(
                    icon: Icons.watch_rounded,
                    label: 'Saat',
                    isSelected: _selectedCategory == ListingCategory.watchesTrackers,
                    onTap: () => _onCategoryTap(ListingCategory.watchesTrackers),
                  ),
                  _AnimatedCategoryChip(
                    icon: Icons.backpack_rounded,
                    label: 'Aksesuar',
                    isSelected: _selectedCategory == ListingCategory.accessories,
                    onTap: () => _onCategoryTap(ListingCategory.accessories),
                  ),
                  _AnimatedCategoryChip(
                    icon: Icons.restaurant_rounded,
                    label: 'Beslenme',
                    isSelected: _selectedCategory == ListingCategory.nutrition,
                    onTap: () => _onCategoryTap(ListingCategory.nutrition),
                  ),
                  _AnimatedCategoryChip(
                    icon: Icons.fitness_center_rounded,
                    label: 'Ekipman',
                    isSelected: _selectedCategory == ListingCategory.equipment,
                    onTap: () => _onCategoryTap(ListingCategory.equipment),
                  ),
                  _AnimatedCategoryChip(
                    icon: Icons.more_horiz_rounded,
                    label: 'Diğer',
                    isSelected: _selectedCategory == ListingCategory.other,
                    onTap: () => _onCategoryTap(ListingCategory.other),
                  ),
                ],
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
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: _ListingsGrid(
                listings: listingsState.listings,
                hasMore: listingsState.hasMore,
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

  void _onCategoryTap(ListingCategory category) {
    setState(() {
      _selectedCategory = _selectedCategory == category ? null : category;
    });
    _loadListings();
  }
}

/// AllTrails tarzı animasyonlu kategori chip'i
class _AnimatedCategoryChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _AnimatedCategoryChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_AnimatedCategoryChip> createState() => _AnimatedCategoryChipState();
}

class _AnimatedCategoryChipState extends State<_AnimatedCategoryChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _iconRotateAnim;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.9), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.05), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0), weight: 25),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _iconRotateAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.05), weight: 30),
      TweenSequenceItem(tween: Tween(begin: -0.05, end: 0.05), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.05, end: 0.0), weight: 30),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(_AnimatedCategoryChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final selectedBg = isDark ? AppColors.primaryLight : AppColors.primary;
    final unselectedBg = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.neutral200;
    final selectedFg = Colors.white;
    final unselectedFg = isDark ? AppColors.onSurfaceDark : AppColors.neutral800;
    final selectedBorder = Colors.transparent;
    final unselectedBorder = isDark
        ? AppColors.surfaceVariantDark.withValues(alpha: 0.5)
        : AppColors.neutral300;

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _controller.isAnimating
                ? _scaleAnim.value
                : (_isPressed ? 0.93 : 1.0),
            child: child,
          );
        },
        child: GestureDetector(
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          onTap: () {
            _controller.forward(from: 0);
            widget.onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: widget.isSelected ? 16 : 14,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: widget.isSelected ? selectedBg : unselectedBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: widget.isSelected ? selectedBorder : unselectedBorder,
                width: widget.isSelected ? 0 : 1,
              ),
              boxShadow: widget.isSelected
                  ? [
                      BoxShadow(
                        color: selectedBg.withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 0,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _iconRotateAnim,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _controller.isAnimating ? _iconRotateAnim.value : 0,
                      child: child,
                    );
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(
                        scale: animation,
                        child: child,
                      );
                    },
                    child: Icon(
                      widget.icon,
                      key: ValueKey(widget.isSelected),
                      size: 18,
                      color: widget.isSelected ? selectedFg : unselectedFg,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    color: widget.isSelected ? selectedFg : unselectedFg,
                    fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                    letterSpacing: 0.1,
                  ),
                  child: Text(widget.label),
                ),
              ],
            ),
          ),
        ),
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

    return AppCard(
      padding: EdgeInsets.zero,
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
                          top: Radius.circular(12),
                        ),
                      ),
                      child: listing.primaryImageUrl != null
                          ? ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                              child: Image.network(
                                listing.primaryImageUrl!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: imageHeight,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) => const Center(
                                  child: Icon(
                                    Icons.image,
                                    size: 48,
                                    color: AppColors.neutral400,
                                  ),
                                ),
                              ),
                            )
                          : const Center(
                              child: Icon(
                                Icons.image,
                                size: 48,
                                color: AppColors.neutral400,
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
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'TCR',
                              style: AppTypography.labelSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          listing.title,
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w600,
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              listing.price != null
                                  ? '₺${listing.price!.toStringAsFixed(0)}'
                                  : 'Fiyat Sorunuz',
                              style: AppTypography.titleMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
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
