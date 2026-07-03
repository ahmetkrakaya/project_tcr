import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/enums/gender.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/listing_model.dart';
import '../../utils/listing_price_utils.dart';
import '../providers/marketplace_provider.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// Listing Detail Page
class ListingDetailPage extends ConsumerStatefulWidget {
  final String listingId;

  const ListingDetailPage({super.key, required this.listingId});

  @override
  ConsumerState<ListingDetailPage> createState() => _ListingDetailPageState();
}

class _ListingDetailPageState extends ConsumerState<ListingDetailPage> {
  final PageController _pageController = PageController();
  bool _hasLoadedFavorite = false;
  String? _autoSelectedForListingId;
  int _currentPageIndex = 0;
  String? _selectedSize;
  ListingGender? _selectedGender;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(_onPageChanged);
  }

  @override
  void didUpdateWidget(ListingDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listingId != widget.listingId) {
      _selectedSize = null;
      _selectedGender = null;
      _autoSelectedForListingId = null;
      _hasLoadedFavorite = false;
    }
  }

  void _onPageChanged() {
    if (_pageController.page != null) {
      setState(() {
        _currentPageIndex = _pageController.page!.round();
      });
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listingAsync = ref.watch(listingByIdProvider(widget.listingId));

    return Scaffold(
      body: listingAsync.when(
        data: (listing) => _buildContent(context, listing),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) {
          if (isContentNotFoundError(error)) {
            return ContentNotFoundWidget(
              onGoToNotifications: () =>
                  context.goNamed(RouteNames.notifications),
              onBack: () => context.pop(),
            );
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: AppColors.error),
                const SizedBox(height: 16),
                Text('Bir hata oluştu', style: AppTypography.titleMedium),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: AppTypography.bodySmall.copyWith(
                    color: ThemeBrightnessHolder.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Geri Dön'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, ListingModel listing) {
    // Favori durumunu cache'den kontrol et
    final favoriteIds = ref.watch(favoriteIdsProvider);
    final currentUser = ref.watch(currentUserProfileProvider);
    final isFavorite = favoriteIds.contains(listing.id);

    // İlk kez render edildiğinde favori durumunu yükle (cache'de yoksa)
    if (!_hasLoadedFavorite && !favoriteIds.contains(listing.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(favoriteIdsProvider.notifier).loadFavoriteIds([listing.id]);
          _hasLoadedFavorite = true;
        }
      });
    } else if (!_hasLoadedFavorite) {
      _hasLoadedFavorite = true;
    }

    final hasAutoSelectOptions =
        (listing.size != null && listing.size!.trim().isNotEmpty) ||
            listing.stockGenderMode == ListingGenderMode.gendered;

    if (_autoSelectedForListingId != listing.id && hasAutoSelectOptions) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _autoSelectOptionsFromProfile(listing, currentUser);
        }
      });
    }

    final screenHeight = MediaQuery.sizeOf(context).height;
    final appBarHeight = (screenHeight * 0.34).clamp(240.0, 360.0);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final pageBackground = cs.surface;

    return Scaffold(
      backgroundColor: pageBackground,
      body: CustomScrollView(
        slivers: [
          // Image Gallery
          SliverAppBar(
            expandedHeight: appBarHeight,
            pinned: true,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: listing.imageUrls.isEmpty
                  ? Container(
                      color: AppColors.neutral200,
                      child: Center(
                        child: Icon(
                          Icons.image,
                          size: 80,
                          color: ThemeBrightnessHolder.outline,
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        GestureDetector(
                          onTap: () => _openFullScreenImageViewer(context, listing.imageUrls, _currentPageIndex),
                          child: Opacity(
                            opacity: isListingOutOfStock(listing) ? 0.45 : 1,
                            child: PageView.builder(
                              controller: _pageController,
                              itemCount: listing.imageUrls.length,
                              itemBuilder: (context, index) {
                                return Image.network(
                                  listing.imageUrls[index],
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        color: AppColors.neutral200,
                                        child: Icon(
                                          Icons.image,
                                          size: 80,
                                          color: ThemeBrightnessHolder.outline,
                                        ),
                                      ),
                                );
                              },
                            ),
                          ),
                        ),
                        if (isListingOutOfStock(listing))
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.18),
                              alignment: Alignment.center,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surface.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Stokta Yok',
                                  style: AppTypography.titleSmall.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // Page Indicators
                        if (listing.imageUrls.length > 1)
                          Positioned(
                            bottom: 16,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                listing.imageUrls.length,
                                (index) {
                                  final isActive = index == _currentPageIndex;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    width: isActive ? 24 : 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite ? AppColors.error : Colors.white,
                  ),
                  onPressed: () => _toggleFavorite(context, listing, isFavorite),
                ),
              ),
              Consumer(
                builder: (context, ref, _) {
                  final isAdmin = ref.watch(isAdminProvider);
                  if (isAdmin) return const SizedBox.shrink();

                  return Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.share, color: Colors.white),
                      splashRadius: 24,
                      onPressed: () => _shareListing(context, listing),
                    ),
                  );
                },
              ),
              Consumer(
                builder: (context, ref, _) {
                  final isAdmin = ref.watch(isAdminProvider);
                  if (!isAdmin) return const SizedBox.shrink();

                  return Container(
                    margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: PopupMenuButton<_ListingMenuAction>(
                      tooltip: 'Menü',
                      icon: Icon(Icons.more_vert, color: Colors.white),
                      onSelected: (action) {
                        switch (action) {
                          case _ListingMenuAction.edit:
                            context.pushNamed(
                              RouteNames.listingEdit,
                              pathParameters: {'listingId': listing.id},
                            );
                          case _ListingMenuAction.stock:
                            _showStockManagementDialog(context, listing);
                          case _ListingMenuAction.discount:
                            _showDiscountDialog(context, listing);
                          case _ListingMenuAction.share:
                            _shareListing(context, listing);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _ListingMenuAction.edit,
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined),
                              SizedBox(width: 12),
                              Text('Düzenle'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: _ListingMenuAction.stock,
                          child: Row(
                            children: [
                              Icon(Icons.inventory_2_outlined),
                              SizedBox(width: 12),
                              Text('Stok Yönetimi'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: _ListingMenuAction.discount,
                          child: Row(
                            children: [
                              Icon(Icons.local_offer_outlined),
                              SizedBox(width: 12),
                              Text('İndirim Uygula'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: _ListingMenuAction.share,
                          child: Row(
                            children: [
                              Icon(Icons.share_outlined),
                              SizedBox(width: 12),
                              Text('Paylaş'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),

          // Content
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                decoration: BoxDecoration(
                  color: ThemeBrightnessHolder.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProductHeader(context, listing),
                      if (listing.size != null ||
                          listing.stockGenderMode == ListingGenderMode.gendered) ...[
                        const SizedBox(height: 28),
                        _buildOptionsPanel(context, listing),
                      ],
                      if (listing.description != null &&
                          listing.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: 28),
                        _buildDescriptionSection(listing),
                      ],
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildStickyOrderBar(context, listing),
    );
  }

  Widget _buildProductHeader(BuildContext context, ListingModel listing) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _getCategoryName(listing.category).toUpperCase(),
          style: AppTypography.labelSmall.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          listing.title,
          style: AppTypography.headlineMedium.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.2,
            letterSpacing: -0.3,
            color: cs.onSurface,
          ),
        ),
        if (listing.brand != null) ...[
          const SizedBox(height: 8),
          Text(
            listing.brand!,
            style: AppTypography.bodyLarge.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildCompactBadge(
              icon: Icons.verified,
              label: 'TCR Ürünü',
              color: cs.primary,
            ),
            if (isListingDiscountActive(listing))
              _buildCompactBadge(
                icon: Icons.local_offer_outlined,
                label: '%${listing.discountPercent} indirim',
                color: AppColors.error,
              ),
            _buildStockStatusCompact(listing),
          ],
        ),
      ],
    );
  }

  Widget _buildOptionsPanel(BuildContext context, ListingModel listing) {
    final cs = Theme.of(context).colorScheme;
    final panelColor = cs.surfaceContainerHighest;
    final borderColor = cs.outlineVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (listing.size != null) ...[
            _buildSizeSelector(listing.size!),
            if (listing.stockGenderMode == ListingGenderMode.gendered)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Divider(
                  height: 1,
                  color: borderColor,
                ),
              ),
          ],
          if (listing.stockGenderMode == ListingGenderMode.gendered)
            _buildGenderSelector(listing),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(ListingModel listing) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Açıklama',
          style: AppTypography.labelMedium.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          listing.description!,
          style: AppTypography.bodyLarge.copyWith(
            color: cs.onSurface,
            height: 1.65,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionLabel(String label) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      label,
      style: AppTypography.labelMedium.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildStickyOrderBar(BuildContext context, ListingModel listing) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final barColor = cs.surface;

    if (currentUserId == null) {
      return SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(
            color: barColor,
            border: Border(
              top: BorderSide(color: cs.outlineVariant),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.pushNamed(RouteNames.login),
              icon: Icon(Icons.login_rounded),
              label: const Text('Sipariş için giriş yap'),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final orderState = _resolveOrderState(listing);
    final stockAlertScope = _resolveStockAlertScope(listing);
    final stockAlertsAsync =
        ref.watch(userStockAlertsForListingProvider(listing.id));
    final subscribedKeys = stockAlertsAsync.maybeWhen(
      data: (alerts) => alerts.map((a) => a.scopeKey).toSet(),
      orElse: () => <String>{},
    );
    final isSubscribed = stockAlertScope.canSubscribe &&
        subscribedKeys.contains(
          stockAlertScopeKey(
            listing.id,
            size: stockAlertScope.size,
            gender: stockAlertScope.gender,
          ),
        );

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: barColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: listing.price != null ? 120 : 100,
              child: ListingPriceDisplay(
                listing: listing,
                priceStyle: AppTypography.headlineSmall.copyWith(
                  color: isListingDiscountActive(listing)
                      ? AppColors.error
                      : cs.primary,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: stockAlertScope.canSubscribe
                  ? OutlinedButton.icon(
                      onPressed: () => _toggleStockAlert(
                        context,
                        listing,
                        stockAlertScope,
                        isSubscribed,
                      ),
                      icon: Icon(
                        isSubscribed
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_outlined,
                      ),
                      label: Text(
                        isSubscribed ? 'Haberdar Edileceksin' : 'Gelince Haber Ver',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            isSubscribed ? cs.primary : cs.onSurface,
                        side: BorderSide(
                          color: isSubscribed
                              ? cs.primary
                              : cs.outlineVariant,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: orderState.enabled
                          ? () => _showOrderDialog(context, listing)
                          : null,
                      icon: Icon(orderState.icon),
                      label: Text(orderState.label),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        disabledBackgroundColor: cs.surfaceContainerHigh,
                        disabledForegroundColor: cs.onSurfaceVariant,
                        foregroundColor: cs.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  ({
    bool canSubscribe,
    String? size,
    ListingGender? gender,
  }) _resolveStockAlertScope(ListingModel listing) {
    if (isListingOutOfStock(listing)) {
      return (canSubscribe: true, size: null, gender: null);
    }

    if (listing.stockGenderMode == ListingGenderMode.gendered &&
        listing.stockBySizeAndGender != null &&
        listing.stockBySizeAndGender!.isNotEmpty) {
      if (_selectedSize == null || _selectedGender == null) {
        return (canSubscribe: false, size: null, gender: null);
      }
      final stockForCombo =
          listing.stockBySizeAndGender![_selectedSize!]?[_selectedGender!] ?? 0;
      if (stockForCombo <= 0) {
        return (
          canSubscribe: true,
          size: _selectedSize,
          gender: _selectedGender,
        );
      }
      return (canSubscribe: false, size: null, gender: null);
    }

    if (listing.stockBySize != null && listing.stockBySize!.isNotEmpty) {
      if (_selectedSize == null) {
        return (canSubscribe: false, size: null, gender: null);
      }
      final stockForSize = listing.stockBySize![_selectedSize] ?? 0;
      if (stockForSize <= 0) {
        return (
          canSubscribe: true,
          size: _selectedSize,
          gender: ListingGender.unisex,
        );
      }
      return (canSubscribe: false, size: null, gender: null);
    }

    if (listing.stockQuantity != null && listing.stockQuantity! <= 0) {
      return (canSubscribe: true, size: null, gender: null);
    }

    return (canSubscribe: false, size: null, gender: null);
  }

  Future<void> _toggleStockAlert(
    BuildContext context,
    ListingModel listing,
    ({
      bool canSubscribe,
      String? size,
      ListingGender? gender,
    }) scope,
    bool isSubscribed,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final notifier = ref.read(toggleStockAlertProvider.notifier);
      if (isSubscribed) {
        await notifier.unsubscribe(
          listingId: listing.id,
          size: scope.size,
          gender: scope.gender,
        );
        messenger.showSnackBar(
          const SnackBar(content: Text('Stok bildirimi kaldırıldı')),
        );
      } else {
        await notifier.subscribe(
          listingId: listing.id,
          size: scope.size,
          gender: scope.gender,
        );
        messenger.showSnackBar(
          const SnackBar(content: Text('Stok gelince haber vereceğiz')),
        );
      }
      ref.invalidate(userStockAlertsForListingProvider(listing.id));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('İşlem başarısız: $e')),
      );
    }
  }

  ({bool enabled, String label, IconData icon}) _resolveOrderState(
    ListingModel listing,
  ) {
    if (isListingOutOfStock(listing)) {
      return (enabled: false, label: 'Stokta Yok', icon: Icons.block);
    }

    bool isOutOfStock = false;
    if (listing.stockGenderMode == ListingGenderMode.gendered &&
        listing.stockBySizeAndGender != null &&
        listing.stockBySizeAndGender!.isNotEmpty &&
        _selectedSize != null &&
        _selectedGender != null) {
      final genderMap = listing.stockBySizeAndGender![_selectedSize!];
      final stockForCombo = genderMap?[_selectedGender!] ?? 0;
      isOutOfStock = stockForCombo <= 0;
    } else if (listing.stockBySize != null && listing.stockBySize!.isNotEmpty) {
      if (_selectedSize != null) {
        final stockForSize = listing.stockBySize![_selectedSize] ?? 0;
        isOutOfStock = stockForSize <= 0;
      }
    } else {
      isOutOfStock =
          listing.stockQuantity != null && listing.stockQuantity! <= 0;
    }

    final isSizeNotSelected = listing.size != null && _selectedSize == null;
    final isGenderNotSelected =
        listing.stockGenderMode == ListingGenderMode.gendered &&
        listing.stockBySizeAndGender != null &&
        listing.stockBySizeAndGender!.isNotEmpty &&
        _selectedGender == null;
    if (isOutOfStock) {
      return (enabled: false, label: 'Stokta Yok', icon: Icons.block);
    }
    if (isSizeNotSelected) {
      return (enabled: false, label: 'Beden Seçin', icon: Icons.straighten);
    }
    if (isGenderNotSelected) {
      return (enabled: false, label: 'Cinsiyet Seçin', icon: Icons.person_outline);
    }
    return (enabled: true, label: 'Sipariş Ver', icon: Icons.shopping_bag_outlined);
  }

  void _toggleFavorite(
    BuildContext context,
    ListingModel listing,
    bool isFavorite,
  ) {
    final wasFavorite = isFavorite;
    final messenger = ScaffoldMessenger.of(context);

    if (wasFavorite) {
      ref.read(favoriteIdsProvider.notifier).removeFavorite(listing.id);
      ref.read(favoriteListingsProvider.notifier).removeFavoriteOptimistically(listing.id);
    } else {
      ref.read(favoriteIdsProvider.notifier).addFavorite(listing.id);
    }

    ref.read(toggleFavoriteProvider.notifier).toggleFavorite(listing.id).then((_) {
      if (!wasFavorite) {
        ref.read(favoriteListingsProvider.notifier).addFavoriteOptimistically(listing);
      }
    }).catchError((e) {
      if (wasFavorite) {
        ref.read(favoriteIdsProvider.notifier).addFavorite(listing.id);
        ref.read(favoriteListingsProvider.notifier).refresh();
      } else {
        ref.read(favoriteIdsProvider.notifier).removeFavorite(listing.id);
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text('Favori işlemi başarısız: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    });
  }

  Future<void> _shareListing(BuildContext context, ListingModel listing) async {
    try {
      final shareUrl = AppConstants.listingShareUrlShort(listing.id);
      final box = context.findRenderObject() as RenderBox?;
      final shareOrigin = box != null
          ? Rect.fromPoints(
              box.localToGlobal(Offset.zero),
              box.localToGlobal(box.size.bottomRight(Offset.zero)),
            )
          : const Rect.fromLTWH(0, 0, 1, 1);
      final displayPrice = listingDisplayPrice(listing);
      final priceText = displayPrice != null
          ? '₺${formatListingPrice(displayPrice)}'
          : 'Fiyat Sorunuz';
      final subject = 'TCR Market: ${listing.title} - $priceText';

      await Share.share(
        shareUrl,
        subject: subject,
        sharePositionOrigin: shareOrigin,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Paylaşım açılamadı: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showDiscountDialog(BuildContext context, ListingModel listing) {
    showDialog(
      context: context,
      builder: (context) => _QuickDiscountDialog(listing: listing),
    );
  }

  void _showStockManagementDialog(BuildContext context, ListingModel listing) {
    // Eğer beden varsa stok tipi (unisex / erkek-kadın) popup içinde seçilir, yoksa genel stok yönetimi
    if (listing.size != null) {
      _showStockBySizeModeDialog(context, listing);
    } else {
      _showGeneralStockDialog(context, listing);
    }
  }

  void _showGeneralStockDialog(BuildContext context, ListingModel listing) {
    final stockController = TextEditingController(
      text: listing.stockQuantity?.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stok Yönetimi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ürün: ${listing.title}',
              style: AppTypography.bodyMedium.copyWith(
                color: ThemeBrightnessHolder.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: stockController,
              label: 'Stok Miktarı',
              hint: 'Boş = sınırsız',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            Text(
              'Not: Stok miktarını boş bırakırsanız stok sınırsız olur.',
              style: AppTypography.bodySmall.copyWith(
                color: ThemeBrightnessHolder.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              stockController.dispose();
              Navigator.pop(context);
            },
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final stockText = stockController.text.trim();
              final stockQuantity = stockText.isEmpty
                  ? null
                  : int.tryParse(stockText);

              if (stockQuantity != null && stockQuantity < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Stok miktarı negatif olamaz'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }

              await ref
                  .read(updateStockQuantityProvider.notifier)
                  .updateStockQuantity(listing.id, stockQuantity);

              if (mounted) {
                final result = ref.read(updateStockQuantityProvider);
                result.when(
                  data: (_) {
                    stockController.dispose();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Stok güncellendi!'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                    // Refresh listing
                    ref.invalidate(listingByIdProvider(listing.id));
                  },
                  loading: () {},
                  error: (error, _) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Hata: $error'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  },
                );
              }
            },
            child: const Text('Güncelle'),
          ),
        ],
      ),
    );
  }

  void _showStockBySizeDialog(BuildContext context, ListingModel listing) {
    // Bedenleri parse et
    final sizes = listing.size!.split(',').map((s) => s.trim()).toList();
    
    showDialog(
      context: context,
      builder: (context) => _StockBySizeDialog(
        listing: listing,
        sizes: sizes,
        initialStock: listing.stockBySize ?? {},
      ),
    );
  }

  void _showStockBySizeModeDialog(BuildContext context, ListingModel listing) {
    // Bedenleri parse et
    final sizes = listing.size!.split(',').map((s) => s.trim()).toList();

    showDialog(
      context: context,
      builder: (context) => _StockBySizeModeDialog(
        listing: listing,
        sizes: sizes,
        initialStockBySize: listing.stockBySize ?? {},
        initialStockByGender: listing.stockBySizeAndGender ?? {},
      ),
    );
  }

  void _openFullScreenImageViewer(BuildContext context, List<String> imageUrls, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullScreenImageViewer(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
        ),
        fullscreenDialog: true,
      ),
    );
  }


  Widget _buildCompactBadge({
    IconData? icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockStatusCompact(ListingModel listing) {
    if (isListingOutOfStock(listing)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 14, color: AppColors.error),
            const SizedBox(width: 6),
            Text(
              'Stokta Yok',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // Cinsiyet + beden bazlı stok varsa önce onu kontrol et
    if (listing.stockGenderMode == ListingGenderMode.gendered &&
        listing.stockBySizeAndGender != null &&
        listing.stockBySizeAndGender!.isNotEmpty) {
      if (_selectedSize != null && _selectedGender != null) {
        final genderMap = listing.stockBySizeAndGender![_selectedSize!];
        final stockForCombo = genderMap?[_selectedGender!] ?? 0;

        if (stockForCombo > 0) {
          return _buildAvailableStockBadge(stockForCombo);
        } else {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cancel, size: 14, color: AppColors.error),
                const SizedBox(width: 6),
                Text(
                  'Yok',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }
      } else if (_selectedSize != null && _selectedGender == null) {
        // Beden seçili ama cinsiyet seçilmemiş
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.neutral200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 14, color: ThemeBrightnessHolder.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Cinsiyet seç',
                style: AppTypography.labelSmall.copyWith(
                  color: ThemeBrightnessHolder.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      } else {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.neutral200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 14, color: ThemeBrightnessHolder.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Beden seç',
                style: AppTypography.labelSmall.copyWith(
                  color: ThemeBrightnessHolder.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }
    }

    // Beden bazlı stok varsa seçilen bedenin stok durumunu göster
    if (listing.stockBySize != null && listing.stockBySize!.isNotEmpty) {
      if (_selectedSize != null && listing.stockBySize!.containsKey(_selectedSize)) {
        final stockForSize = listing.stockBySize![_selectedSize]!;
        if (stockForSize > 0) {
          return _buildAvailableStockBadge(stockForSize);
        } else {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cancel, size: 14, color: AppColors.error),
                const SizedBox(width: 6),
                Text(
                  'Yok',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }
      } else {
        // Beden seçilmemiş veya stok yok
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.neutral200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 14, color: ThemeBrightnessHolder.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Beden seç',
                style: AppTypography.labelSmall.copyWith(
                  color: ThemeBrightnessHolder.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }
    }
    
    // Eski sistem (genel stok)
    final stockQuantity = listing.stockQuantity;
    
    if (stockQuantity == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 14, color: AppColors.success),
            const SizedBox(width: 6),
            Text(
              'Stokta',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    } else if (stockQuantity > 0) {
      return _buildAvailableStockBadge(stockQuantity);
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel, size: 14, color: AppColors.error),
            const SizedBox(width: 6),
            Text(
              'Yok',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildAvailableStockBadge(int stock) {
    if (!shouldShowListingLowStockWarning(stock)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2, size: 14, color: AppColors.warning),
          const SizedBox(width: 6),
          Text(
            listingLowStockLabel(stock),
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _autoSelectOptionsFromProfile(ListingModel listing, UserEntity? user) {
    if (_autoSelectedForListingId == listing.id) return;

    final hasSizeOptions =
        listing.size != null && listing.size!.trim().isNotEmpty;
    final hasGenderOptions =
        listing.stockGenderMode == ListingGenderMode.gendered;

    if (!hasSizeOptions && !hasGenderOptions) {
      _autoSelectedForListingId = listing.id;
      return;
    }

    if (user == null) return;

    final needsSize = hasSizeOptions && _selectedSize == null;
    final needsGender = hasGenderOptions && _selectedGender == null;

    if (!needsSize && !needsGender) {
      _autoSelectedForListingId = listing.id;
      return;
    }

    _autoSelectedForListingId = listing.id;

    final matchedSize =
        needsSize ? _findProfileSizeMatch(listing.size!, user) : null;
    final matchedGender = needsGender ? _findProfileGenderMatch(user) : null;

    if (matchedSize != null || matchedGender != null) {
      setState(() {
        if (matchedSize != null) _selectedSize = matchedSize;
        if (matchedGender != null) _selectedGender = matchedGender;
      });
    }
  }

  ListingGender? _findProfileGenderMatch(UserEntity user) {
    return switch (user.gender) {
      Gender.male => ListingGender.male,
      Gender.female => ListingGender.female,
      Gender.unknown || null => null,
    };
  }

  String? _findProfileSizeMatch(String listingSizes, UserEntity user) {
    final availableSizes = listingSizes
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (availableSizes.isEmpty) return null;

    final profileSizes = <String>[
      if (user.tshirtSize != null) user.tshirtSize!.name.toUpperCase(),
      if (user.shoeSize != null && user.shoeSize!.trim().isNotEmpty)
        user.shoeSize!.trim(),
    ];
    if (profileSizes.isEmpty) return null;

    for (final profileSize in profileSizes) {
      for (final size in availableSizes) {
        if (size.toUpperCase() == profileSize.toUpperCase()) {
          return size;
        }
      }
    }
    return null;
  }

  Widget _buildSizeSelector(String sizeString) {
    final cs = Theme.of(context).colorScheme;
    final sizes = sizeString.split(',').map((s) => s.trim()).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOptionLabel('Beden'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final maxPerRow = sizes.length <= 5 ? sizes.length : 5;
            final chipWidth =
                (constraints.maxWidth - spacing * (maxPerRow - 1)) / maxPerRow;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: sizes.map((size) {
                final isSelected = _selectedSize == size;
                return SizedBox(
                  width: chipWidth,
                  height: 48,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedSize = isSelected ? null : size;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? cs.primary
                                : cs.outlineVariant,
                          ),
                        ),
                        child: Text(
                          size,
                          style: AppTypography.titleSmall.copyWith(
                            color: isSelected
                                ? cs.onPrimary
                                : cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildGenderSelector(ListingModel listing) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOptionLabel('Cinsiyet'),
        const SizedBox(height: 12),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              Expanded(
                child: _buildGenderSegment(ListingGender.male, 'Erkek'),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildGenderSegment(ListingGender.female, 'Kadın'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGenderSegment(ListingGender gender, String label) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedGender == gender;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedGender = isSelected ? null : gender;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: AppTypography.titleSmall.copyWith(
              color: isSelected ? cs.onPrimary : cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    // Binlik ayırıcı ile formatla (Türkçe format: 1.234.567)
    final priceString = price.toStringAsFixed(0);
    final buffer = StringBuffer();
    
    for (int i = 0; i < priceString.length; i++) {
      if (i > 0 && (priceString.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(priceString[i]);
    }
    
    return buffer.toString();
  }

  String _getCategoryName(ListingCategory category) {
    switch (category) {
      case ListingCategory.runningShoes:
        return 'Koşu Ayakkabısı';
      case ListingCategory.sportsWear:
        return 'Spor Giyim';
      case ListingCategory.accessories:
        return 'Aksesuar';
      case ListingCategory.watchesTrackers:
        return 'Saat/Takip Cihazı';
      case ListingCategory.nutrition:
        return 'Beslenme';
      case ListingCategory.equipment:
        return 'Ekipman';
      case ListingCategory.books:
        return 'Kitap';
      case ListingCategory.other:
        return 'Diğer';
    }
  }

  void _showOrderDialog(BuildContext context, ListingModel listing) {
    final noteController = TextEditingController();

    // Maksimum adet hesapla - cinsiyet + beden bazlı stok varsa onu kullan, yoksa genel stok
    int maxQuantity = 5;
    if (listing.stockGenderMode == ListingGenderMode.gendered &&
        listing.stockBySizeAndGender != null &&
        listing.stockBySizeAndGender!.isNotEmpty &&
        _selectedSize != null &&
        _selectedGender != null) {
      // Cinsiyet + beden bazlı stok
      final genderMap = listing.stockBySizeAndGender![_selectedSize!];
      final stockForCombo = genderMap?[_selectedGender!] ?? 0;
      maxQuantity = stockForCombo > 5 ? 5 : stockForCombo;
    } else if (listing.stockBySize != null &&
        listing.stockBySize!.isNotEmpty &&
        _selectedSize != null) {
      // Beden bazlı stok (unisex)
      final stockForSize = listing.stockBySize![_selectedSize] ?? 0;
      maxQuantity = stockForSize > 5 ? 5 : stockForSize;
    } else if (listing.stockQuantity != null) {
      // Genel stok
      maxQuantity = listing.stockQuantity! > 5 ? 5 : listing.stockQuantity!;
    }
    
    // Adet seçenekleri oluştur
    final quantityOptions = maxQuantity > 0 
        ? List.generate(maxQuantity, (index) => index + 1)
        : [1];

    showDialog(
      context: context,
      builder: (context) {
        return _OrderDialogContent(
          listing: listing,
          noteController: noteController,
          quantityOptions: quantityOptions,
          maxQuantity: maxQuantity,
          selectedSize: _selectedSize,
          selectedGender: _selectedGender,
        );
      },
    );
  }
}

class _OrderDialogContent extends StatefulWidget {
  final ListingModel listing;
  final TextEditingController noteController;
  final List<int> quantityOptions;
  final int maxQuantity;
  final String? selectedSize;
   final ListingGender? selectedGender;

  const _OrderDialogContent({
    required this.listing,
    required this.noteController,
    required this.quantityOptions,
    required this.maxQuantity,
    required this.selectedSize,
    required this.selectedGender,
  });

  @override
  State<_OrderDialogContent> createState() => _OrderDialogContentState();
}

class _OrderDialogContentState extends State<_OrderDialogContent> {
  int selectedQuantity = 1;

  String? _orderDialogLowStockLabel() {
    int? stock;

    if (widget.listing.stockGenderMode == ListingGenderMode.gendered &&
        widget.listing.stockBySizeAndGender != null &&
        widget.listing.stockBySizeAndGender!.isNotEmpty &&
        widget.selectedSize != null &&
        widget.selectedGender != null) {
      final genderMap =
          widget.listing.stockBySizeAndGender![widget.selectedSize!];
      stock = genderMap?[widget.selectedGender!];
    } else if (widget.listing.stockBySize != null &&
        widget.listing.stockBySize!.isNotEmpty &&
        widget.selectedSize != null) {
      stock = widget.listing.stockBySize![widget.selectedSize];
    } else {
      stock = widget.listing.stockQuantity;
    }

    if (stock == null || !shouldShowListingLowStockWarning(stock)) {
      return null;
    }

    return listingLowStockLabel(stock);
  }

  String _formatPrice(double price) {
    // Binlik ayırıcı ile formatla (Türkçe format: 1.234.567)
    final priceString = price.toStringAsFixed(0);
    final buffer = StringBuffer();
    
    for (int i = 0; i < priceString.length; i++) {
      if (i > 0 && (priceString.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(priceString[i]);
    }
    
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.shopping_cart,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                        Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sipariş Oluştur',
                            style: AppTypography.titleLarge.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (listingDisplayPrice(widget.listing) != null)
                            ListingPriceDisplay(
                              listing: widget.listing,
                              compact: true,
                              priceStyle: AppTypography.bodyMedium.copyWith(
                                color: isListingDiscountActive(widget.listing)
                                    ? AppColors.error
                                    : AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Product Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.neutral100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.listing.title,
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.listing.size != null && widget.selectedSize != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Beden: ',
                              style: AppTypography.bodySmall.copyWith(
                                color: ThemeBrightnessHolder.onSurfaceVariant,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.selectedSize!,
                                style: AppTypography.labelMedium.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (widget.listing.stockGenderMode == ListingGenderMode.gendered &&
                          widget.selectedGender != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Cinsiyet: ',
                              style: AppTypography.bodySmall.copyWith(
                                color: ThemeBrightnessHolder.onSurfaceVariant,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.secondary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.selectedGender == ListingGender.male
                                    ? 'Erkek'
                                    : widget.selectedGender == ListingGender.female
                                        ? 'Kadın'
                                        : 'Unisex',
                                style: AppTypography.labelMedium.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Size Warning (if size not selected)
                if (widget.listing.size != null && widget.selectedSize == null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.warningContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Lütfen beden seçiniz',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Quantity Selection
                Text(
                  'Adet',
                  style: AppTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: ThemeBrightnessHolder.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonFormField<int>(
                    value: selectedQuantity,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: InputBorder.none,
                    ),
                    items: widget.quantityOptions.map((qty) {
                      return DropdownMenuItem<int>(
                        value: qty,
                        child: Text(
                          '$qty adet',
                          style: AppTypography.bodyMedium,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedQuantity = value;
                        });
                      }
                    },
                  ),
                ),
                if (_orderDialogLowStockLabel() case final label?) ...[
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // Note Field
                Text(
                  'Not (İletişim bilgisi, teslimat adresi vb.)',
                  style: AppTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: widget.noteController,
                  decoration: InputDecoration(
                    hintText: 'Örn: Telefon: 0555 123 45 67',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                Text(
                  'Not: Ödeme ve teslimat elden yapılacaktır.',
                  style: AppTypography.bodySmall.copyWith(
                    color: ThemeBrightnessHolder.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('İptal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: widget.listing.size != null && widget.selectedSize == null
                            ? null
                            : () async {
                                // Async işlemler sonrası context kullanmamak için referansları başta al
                                final messenger = ScaffoldMessenger.of(context);
                                final navigator = Navigator.of(context);

                                // Stok kontrolü - cinsiyet + beden bazlı veya genel
                                bool stockCheckFailed = false;
                                String stockMessage = '';
                                
                                if (widget.listing.stockGenderMode == ListingGenderMode.gendered &&
                                    widget.listing.stockBySizeAndGender != null &&
                                    widget.listing.stockBySizeAndGender!.isNotEmpty &&
                                    widget.selectedSize != null &&
                                    widget.selectedGender != null) {
                                  // Cinsiyet + beden bazlı stok kontrolü
                                  final genderMap = widget
                                      .listing
                                      .stockBySizeAndGender![widget.selectedSize!];
                                  final stockForCombo =
                                      genderMap?[widget.selectedGender!] ?? 0;
                                  if (selectedQuantity > stockForCombo) {
                                    stockCheckFailed = true;
                                    stockMessage =
                                        'Stokta sadece $stockForCombo adet var';
                                  }
                                } else if (widget.listing.stockBySize != null && 
                                    widget.listing.stockBySize!.isNotEmpty && 
                                    widget.selectedSize != null) {
                                  // Beden bazlı stok kontrolü (unisex)
                                  final stockForSize =
                                      widget.listing.stockBySize![widget.selectedSize] ?? 0;
                                  if (selectedQuantity > stockForSize) {
                                    stockCheckFailed = true;
                                    stockMessage =
                                        'Stokta sadece $stockForSize adet var';
                                  }
                                } else if (widget.listing.stockQuantity != null) {
                                  // Genel stok kontrolü
                                  if (selectedQuantity > widget.listing.stockQuantity!) {
                                    stockCheckFailed = true;
                                    stockMessage = 'Stokta sadece ${widget.listing.stockQuantity} adet var';
                                  }
                                }
                                
                                if (stockCheckFailed) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(stockMessage),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                  return;
                                }
                                
                                final unitPrice =
                                    listingDisplayPrice(widget.listing) ?? 0;
                                final totalPrice = unitPrice * selectedQuantity;

                                await ref
                                    .read(createOrderProvider.notifier)
                                    .createOrder(
                                      listingId: widget.listing.id,
                                      totalPrice: totalPrice,
                                      quantity: selectedQuantity,
                                      buyerNote: widget.noteController.text.isEmpty
                                          ? null
                                          : widget.noteController.text,
                                      selectedSize: widget.selectedSize,
                                      selectedGender: widget.selectedGender,
                                    );

                                final result = ref.read(createOrderProvider);

                                navigator.pop();

                                result.when(
                                  data: (order) {
                                    if (order != null) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Sipariş oluşturuldu! Satıcı ile iletişime geçeceksiniz.',
                                          ),
                                          backgroundColor: AppColors.success,
                                        ),
                                      );
                                    }
                                  },
                                  loading: () {},
                                  error: (error, stackTrace) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Hata: $error'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  },
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Sipariş Ver'),
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

/// Beden Bazlı Stok Yönetimi Dialog
class _StockBySizeDialog extends ConsumerStatefulWidget {
  final ListingModel listing;
  final List<String> sizes;
  final Map<String, int> initialStock;

  const _StockBySizeDialog({
    required this.listing,
    required this.sizes,
    required this.initialStock,
  });

  @override
  ConsumerState<_StockBySizeDialog> createState() => _StockBySizeDialogState();
}

class _StockBySizeDialogState extends ConsumerState<_StockBySizeDialog> {
  late Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    for (final size in widget.sizes) {
      _controllers[size] = TextEditingController(
        text: widget.initialStock[size]?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.inventory_2,
                    color: cs.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stok Yönetimi',
                        style: AppTypography.titleLarge.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        widget.listing.title,
                        style: AppTypography.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Stock Inputs
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: widget.sizes.map((size) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: AppTextField(
                        controller: _controllers[size]!,
                        label: '$size Beden',
                        hint: 'Boş = stok yok',
                        keyboardType: TextInputType.number,
                        suffix: Text(
                          'adet',
                          style: AppTypography.bodySmall.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: cs.outlineVariant),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('İptal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () async {
                      final stockBySize = <String, int>{};
                      
                      for (final size in widget.sizes) {
                        final text = _controllers[size]!.text.trim();
                        if (text.isNotEmpty) {
                          final quantity = int.tryParse(text);
                          if (quantity != null && quantity >= 0) {
                            stockBySize[size] = quantity;
                          } else if (quantity != null && quantity < 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$size beden için stok negatif olamaz'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                            return;
                          }
                        }
                      }

                      final dataSource =
                          ref.read(marketplaceDataSourceProvider);

                      try {
                        // Unisex moda al ve stokları güncelle
                        await dataSource.updateStockBySize(
                          widget.listing.id,
                          stockBySize,
                        );
                        await dataSource.updateListingStockGenderMode(
                          widget.listing.id,
                          ListingGenderMode.unisex,
                        );

                        if (!mounted) return;

                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Stok güncellendi! (Unisex mod)'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        // Refresh listing
                        ref.invalidate(
                            listingByIdProvider(widget.listing.id));
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Hata: $e'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Güncelle'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// _StockBySizeGenderDialog kaldırıldı, yerine _StockBySizeModeDialog kullanılmaktadır.

class _StockBySizeModeDialog extends ConsumerStatefulWidget {
  final ListingModel listing;
  final List<String> sizes;
  final Map<String, int> initialStockBySize;
  final Map<String, Map<ListingGender, int>> initialStockByGender;

  const _StockBySizeModeDialog({
    required this.listing,
    required this.sizes,
    required this.initialStockBySize,
    required this.initialStockByGender,
  });

  @override
  ConsumerState<_StockBySizeModeDialog> createState() =>
      _StockBySizeModeDialogState();
}

class _StockBySizeModeDialogState
    extends ConsumerState<_StockBySizeModeDialog> {
  late ListingGenderMode _mode;
  late Map<String, TextEditingController> _unisexControllers;
  late Map<String, Map<ListingGender, TextEditingController>>
      _genderControllers;

  @override
  void initState() {
    super.initState();
    _mode = widget.listing.stockGenderMode;
    _unisexControllers = {};
    _genderControllers = {};

    for (final size in widget.sizes) {
      final unisexQty = widget.initialStockBySize[size];
      _unisexControllers[size] = TextEditingController(
        text: unisexQty?.toString() ?? '',
      );

      final genderStock = widget.initialStockByGender[size] ?? {};
      _genderControllers[size] = {
        ListingGender.male: TextEditingController(
          text: genderStock[ListingGender.male]?.toString() ?? '',
        ),
        ListingGender.female: TextEditingController(
          text: genderStock[ListingGender.female]?.toString() ?? '',
        ),
      };
    }
  }

  @override
  void dispose() {
    for (final c in _unisexControllers.values) {
      c.dispose();
    }
    for (final genderMap in _genderControllers.values) {
      for (final c in genderMap.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.inventory_2,
                    color: cs.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stok Yönetimi',
                        style: AppTypography.titleLarge.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        widget.listing.title,
                        style: AppTypography.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Stok tipi seçimi
            Text(
              'Stok Tipi',
              style: AppTypography.labelMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildModeChip(
                    mode: ListingGenderMode.unisex,
                    label: 'Unisex',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildModeChip(
                    mode: ListingGenderMode.gendered,
                    label: 'Erkek / Kadın',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Stock Inputs
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: widget.sizes.map((size) {
                    if (_mode == ListingGenderMode.unisex) {
                      final controller = _unisexControllers[size]!;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: AppTextField(
                          controller: controller,
                          label: '$size Beden',
                          hint: 'Boş = stok yok',
                          keyboardType: TextInputType.number,
                          suffix: Text(
                            'adet',
                            style: AppTypography.bodySmall.copyWith(
                              color: ThemeBrightnessHolder.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    } else {
                      final controllers = _genderControllers[size]!;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              size,
                              style: AppTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: AppTextField(
                                    controller:
                                        controllers[ListingGender.male]!,
                                    label: 'Erkek',
                                    hint: 'Boş = stok yok',
                                    keyboardType: TextInputType.number,
                                    suffix: Text(
                                      'adet',
                                      style:
                                          AppTypography.bodySmall.copyWith(
                                        color: ThemeBrightnessHolder.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: AppTextField(
                                    controller:
                                        controllers[ListingGender.female]!,
                                    label: 'Kadın',
                                    hint: 'Boş = stok yok',
                                    keyboardType: TextInputType.number,
                                    suffix: Text(
                                      'adet',
                                      style:
                                          AppTypography.bodySmall.copyWith(
                                        color: ThemeBrightnessHolder.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: cs.outlineVariant),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('İptal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () async {
                      final dataSource =
                          ref.read(marketplaceDataSourceProvider);

                      try {
                        if (_mode == ListingGenderMode.unisex) {
                          // Unisex stok haritasını oluştur
                          final stockBySize = <String, int>{};
                          for (final size in widget.sizes) {
                            final text =
                                _unisexControllers[size]!.text.trim();
                            if (text.isNotEmpty) {
                              final qty = int.tryParse(text);
                              if (qty != null && qty >= 0) {
                                stockBySize[size] = qty;
                              } else if (qty != null && qty < 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '$size beden için stok negatif olamaz'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                                return;
                              }
                            }
                          }

                          await dataSource.updateStockBySize(
                            widget.listing.id,
                            stockBySize,
                          );
                          await dataSource.updateListingStockGenderMode(
                            widget.listing.id,
                            ListingGenderMode.unisex,
                          );
                        } else {
                          // Erkek/Kadın stok haritasını oluştur
                          final stockBySizeGender =
                              <String, Map<ListingGender, int>>{};

                          for (final size in widget.sizes) {
                            final controllers = _genderControllers[size]!;
                            final maleText =
                                controllers[ListingGender.male]!.text.trim();
                            final femaleText =
                                controllers[ListingGender.female]!
                                    .text
                                    .trim();

                            final byGender = <ListingGender, int>{};

                            if (maleText.isNotEmpty) {
                              final qty = int.tryParse(maleText);
                              if (qty != null && qty >= 0) {
                                byGender[ListingGender.male] = qty;
                              } else if (qty != null && qty < 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '$size beden için erkek stok negatif olamaz'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                                return;
                              }
                            }

                            if (femaleText.isNotEmpty) {
                              final qty = int.tryParse(femaleText);
                              if (qty != null && qty >= 0) {
                                byGender[ListingGender.female] = qty;
                              } else if (qty != null && qty < 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '$size beden için kadın stok negatif olamaz'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                                return;
                              }
                            }

                            if (byGender.isNotEmpty) {
                              stockBySizeGender[size] = byGender;
                            }
                          }

                          await dataSource.updateStockBySizeAndGender(
                            widget.listing.id,
                            stockBySizeGender,
                          );
                          await dataSource.updateListingStockGenderMode(
                            widget.listing.id,
                            ListingGenderMode.gendered,
                          );
                        }

                        if (!mounted) return;

                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Stok güncellendi!'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        // Refresh listing
                        ref.invalidate(
                            listingByIdProvider(widget.listing.id));
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Hata: $e'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Güncelle'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeChip({
    required ListingGenderMode mode,
    required String label,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _mode == mode;
    return InkWell(
      onTap: () {
        setState(() {
          _mode = mode;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: isSelected ? cs.onPrimary : cs.onSurface,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tam Ekran Görsel Görüntüleyici
class _FullScreenImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _FullScreenImageViewer({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Images
            PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemCount: widget.imageUrls.length,
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.network(
                      widget.imageUrls[index],
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                            color: Colors.white,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.white54,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Görsel yüklenemedi',
                              style: AppTypography.bodyMedium.copyWith(
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // Controls
            if (_showControls) ...[
              // Top Bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                        const Spacer(),
                        if (widget.imageUrls.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${_currentIndex + 1} / ${widget.imageUrls.length}',
                              style: AppTypography.bodyMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom Indicators
              if (widget.imageUrls.length > 1)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          widget.imageUrls.length,
                          (index) {
                            final isActive = index == _currentIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: isActive ? 24 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickDiscountDialog extends ConsumerStatefulWidget {
  final ListingModel listing;

  const _QuickDiscountDialog({required this.listing});

  @override
  ConsumerState<_QuickDiscountDialog> createState() =>
      _QuickDiscountDialogState();
}

class _QuickDiscountDialogState extends ConsumerState<_QuickDiscountDialog> {
  late bool _enabled;
  late final TextEditingController _percentController;
  DateTime? _startsAt;
  DateTime? _endsAt;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final listing = widget.listing;
    _enabled = listing.discountPercent != null;
    _percentController = TextEditingController(
      text: listing.discountPercent?.toString() ?? '',
    );
    _startsAt = listing.discountStartsAt?.toLocal();
    _endsAt = listing.discountEndsAt?.toLocal();
  }

  @override
  void dispose() {
    _percentController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart
        ? (_startsAt ?? DateTime.now())
        : (_endsAt ?? _startsAt?.add(const Duration(days: 7)) ?? DateTime.now());

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    setState(() {
      final picked = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (isStart) {
        _startsAt = picked;
        if (_endsAt != null && !_endsAt!.isAfter(picked)) {
          _endsAt = picked.add(const Duration(days: 1));
        }
      } else {
        _endsAt = picked;
      }
    });
  }

  Future<void> _save() async {
    int? percent;
    DateTime? startsAt;
    DateTime? endsAt;

    if (_enabled) {
      percent = int.tryParse(_percentController.text.trim());
      if (percent == null || percent < 1 || percent > 100) {
        _showError('1-100 arası geçerli bir indirim oranı girin');
        return;
      }
      if (_startsAt == null || _endsAt == null) {
        _showError('Başlangıç ve bitiş tarihlerini seçin');
        return;
      }
      if (!_endsAt!.isAfter(_startsAt!)) {
        _showError('Bitiş tarihi başlangıçtan sonra olmalı');
        return;
      }
      if (widget.listing.price == null) {
        _showError('Fiyatı olmayan ürüne indirim uygulanamaz');
        return;
      }
      startsAt = _startsAt;
      endsAt = _endsAt;
    }

    setState(() => _isSaving = true);

    await ref.read(updateListingDiscountProvider.notifier).updateDiscount(
          listingId: widget.listing.id,
          discountPercent: percent,
          discountStartsAt: startsAt,
          discountEndsAt: endsAt,
        );

    if (!mounted) return;

    final result = ref.read(updateListingDiscountProvider);
    result.when(
      data: (_) {
        ref.invalidate(listingByIdProvider(widget.listing.id));
        ref.read(listingsProvider.notifier).refresh();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _enabled ? 'İndirim kaydedildi' : 'İndirim kaldırıldı',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      },
      loading: () {},
      error: (error, _) {
        setState(() => _isSaving = false);
        _showError('Hata: $error');
      },
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMM yyyy, HH:mm', 'tr_TR');
    final listing = widget.listing;
    final percent = int.tryParse(_percentController.text.trim());
    final previewListing = (_enabled &&
            listing.price != null &&
            percent != null &&
            _startsAt != null &&
            _endsAt != null)
        ? ListingModel(
            id: listing.id,
            sellerId: listing.sellerId,
            listingType: listing.listingType,
            category: listing.category,
            title: listing.title,
            price: listing.price,
            discountPercent: percent,
            discountStartsAt: _startsAt,
            discountEndsAt: _endsAt,
            createdAt: listing.createdAt,
          )
        : null;
    final previewPrice =
        previewListing != null ? listingDisplayPrice(previewListing) : null;
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: cs.surface,
      title: Text(
        'İndirim Uygula',
        style: TextStyle(color: cs.onSurface),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              listing.title,
              style: AppTypography.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (listing.price != null) ...[
              const SizedBox(height: 4),
              Text(
                'Liste fiyatı: ₺${formatListingPrice(listing.price!)}',
                style: AppTypography.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('İndirim aktif', style: TextStyle(color: cs.onSurface)),
              value: _enabled,
              activeThumbColor: cs.primary,
              activeTrackColor: cs.primary.withValues(alpha: 0.35),
              onChanged: (value) {
                setState(() {
                  _enabled = value;
                  if (value && _startsAt == null) {
                    final now = DateTime.now();
                    _startsAt = DateTime(
                      now.year,
                      now.month,
                      now.day,
                      now.hour,
                      now.minute,
                    );
                    _endsAt = _startsAt!.add(const Duration(days: 7));
                  }
                });
              },
            ),
            if (_enabled) ...[
              const SizedBox(height: 8),
              AppTextField(
                controller: _percentController,
                hint: 'İndirim oranı (%)',
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              _DiscountDateTile(
                label: 'Başlangıç',
                value: _startsAt,
                dateFormat: dateFormat,
                onTap: () => _pickDateTime(isStart: true),
              ),
              const SizedBox(height: 8),
              _DiscountDateTile(
                label: 'Bitiş',
                value: _endsAt,
                dateFormat: dateFormat,
                onTap: () => _pickDateTime(isStart: false),
              ),
              if (previewPrice != null) ...[
                const SizedBox(height: 12),
                Text(
                  'İndirimli fiyat: ₺${formatListingPrice(previewPrice)}',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: Text('İptal', style: TextStyle(color: cs.primary)),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Kaydet'),
        ),
      ],
    );
  }
}

class _DiscountDateTile extends StatelessWidget {
  final String label;
  final DateTime? value;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  const _DiscountDateTile({
    required this.label,
    required this.value,
    required this.dateFormat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeBrightnessHolder.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.labelSmall.copyWith(
                      color: ThemeBrightnessHolder.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value != null ? dateFormat.format(value!) : 'Tarih seçin',
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.calendar_today_outlined, size: 18),
          ],
        ),
      ),
    );
  }
}

enum _ListingMenuAction {
  edit,
  stock,
  discount,
  share,
}
