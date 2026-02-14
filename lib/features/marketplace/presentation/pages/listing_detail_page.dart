import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/listing_model.dart';
import '../providers/marketplace_provider.dart';

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
  int _currentPageIndex = 0;
  String? _selectedSize;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(_onPageChanged);
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
                    color: AppColors.neutral500,
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

    final screenHeight = MediaQuery.sizeOf(context).height;
    final appBarHeight = (screenHeight * 0.34).clamp(240.0, 360.0);

    return Scaffold(
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
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: listing.imageUrls.isEmpty
                  ? Container(
                      color: AppColors.neutral200,
                      child: const Center(
                        child: Icon(
                          Icons.image,
                          size: 80,
                          color: AppColors.neutral400,
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        GestureDetector(
                          onTap: () => _openFullScreenImageViewer(context, listing.imageUrls, _currentPageIndex),
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
                                      child: const Icon(
                                        Icons.image,
                                        size: 80,
                                        color: AppColors.neutral400,
                                      ),
                                    ),
                              );
                            },
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
              // Stock Management Button (Admin only)
              Consumer(
                builder: (context, ref, child) {
                  final isAdmin = ref.watch(isAdminProvider);
                  if (!isAdmin) return const SizedBox.shrink();
                  
                  return Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.inventory_2),
                      color: Colors.white,
                      tooltip: 'Stok Yönetimi',
                      onPressed: () => _showStockManagementDialog(context, listing),
                    ),
                  );
                },
              ),
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
                  onPressed: () {
                    final wasFavorite = isFavorite;
                    final messenger = ScaffoldMessenger.of(context);
                    
                    // Hemen UI'ı güncelle (optimistic update)
                    if (wasFavorite) {
                      ref.read(favoriteIdsProvider.notifier).removeFavorite(listing.id);
                      // Favoriler sayfasından da hemen kaldır
                      ref.read(favoriteListingsProvider.notifier).removeFavoriteOptimistically(listing.id);
                    } else {
                      ref.read(favoriteIdsProvider.notifier).addFavorite(listing.id);
                    }

                    // API çağrısını arka planda yap (await etme)
                    ref.read(toggleFavoriteProvider.notifier).toggleFavorite(listing.id).then((_) {
                      // API çağrısı başarılı olduğunda favoriler listesini güncelle
                      if (!wasFavorite) {
                        // Favori eklendi, optimistic update yap
                        ref.read(favoriteListingsProvider.notifier).addFavoriteOptimistically(listing);
                      }
                    }).catchError((e) {
                      // Hata durumunda geri al
                      if (wasFavorite) {
                        ref.read(favoriteIdsProvider.notifier).addFavorite(listing.id);
                        ref.read(favoriteListingsProvider.notifier).refresh();
                      } else {
                        ref.read(favoriteIdsProvider.notifier).removeFavorite(listing.id);
                      }
                      
                      // Hata mesajı göster
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Favori işlemi başarısız: ${e.toString()}'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    });
                  },
                ),
              ),
              Builder(
                builder: (ctx) {
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.share),
                      splashRadius: 24,
                      onPressed: () async {
                        try {
                          // Kısa link kullan (Supabase'den bilgileri çekecek)
                          final shareUrl = AppConstants.listingShareUrlShort(listing.id);
                          
                          // Share position origin (iOS için)
                          final box = ctx.findRenderObject() as RenderBox?;
                          final shareOrigin = box != null
                              ? Rect.fromPoints(
                                  box.localToGlobal(Offset.zero),
                                  box.localToGlobal(box.size.bottomRight(Offset.zero)),
                                )
                              : const Rect.fromLTWH(0, 0, 1, 1);
                          
                          // Paylaşım başlığı
                          final priceText = listing.price != null
                              ? '₺${_formatPrice(listing.price!)}'
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
                                content: Text(
                                  'Paylaşım açılamadı: ${e.toString()}',
                                ),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  );
                },
              ),
            ],
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Price Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              listing.title,
                              style: AppTypography.headlineSmall.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (listing.price != null)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '₺',
                                      style: AppTypography.titleLarge.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    _formatPrice(listing.price!),
                                    style: AppTypography.titleLarge.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                'Fiyat Sorunuz',
                                style: AppTypography.titleLarge.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Stock Status - Compact
                      _buildStockStatusCompact(listing),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Badges Row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildCompactBadge(
                        icon: Icons.verified,
                        label: 'TCR Ürünü',
                        color: AppColors.primary,
                      ),
                      _buildCompactBadge(
                        label: _getCategoryName(listing.category),
                        color: AppColors.secondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Size Selection
                  if (listing.size != null) ...[
                    _buildSizeSelector(listing.size!),
                    const SizedBox(height: 24),
                  ],

                  // Brand
                  if (listing.brand != null) ...[
                    _buildSpecItem(
                      label: 'Marka',
                      value: listing.brand!,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Description
                  if (listing.description != null) ...[
                    Text(
                      listing.description!,
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.neutral700,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Order Button
                  _buildOrderButton(context, listing),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  void _showStockManagementDialog(BuildContext context, ListingModel listing) {
    // Eğer beden varsa beden bazlı stok yönetimi, yoksa genel stok yönetimi
    if (listing.size != null) {
      _showStockBySizeDialog(context, listing);
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
                color: AppColors.neutral600,
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
                color: AppColors.neutral500,
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
    // Beden bazlı stok varsa seçilen bedenin stok durumunu göster
    if (listing.stockBySize != null && listing.stockBySize!.isNotEmpty) {
      if (_selectedSize != null && listing.stockBySize!.containsKey(_selectedSize)) {
        final stockForSize = listing.stockBySize![_selectedSize]!;
        if (stockForSize > 0) {
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
                  '$stockForSize',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.warning,
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
              Icon(Icons.info_outline, size: 14, color: AppColors.neutral500),
              const SizedBox(width: 6),
              Text(
                'Beden seç',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.neutral500,
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
              '$stockQuantity',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.warning,
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

  Widget _buildSizeSelector(String sizeString) {
    // Beden string'ini parse et (virgülle ayrılmış olabilir)
    final sizes = sizeString.split(',').map((s) => s.trim()).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Beden Seçiniz',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.neutral700,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: sizes.map((size) {
            final isSelected = _selectedSize == size;
            return InkWell(
              onTap: () {
                setState(() {
                  _selectedSize = isSelected ? null : size;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.neutral100,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.neutral300,
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  size,
                  style: AppTypography.bodyMedium.copyWith(
                    color: isSelected
                        ? Colors.white
                        : AppColors.neutral700,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSpecItem({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.neutral500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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

  Widget _buildOrderButton(BuildContext context, ListingModel listing) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    
    if (currentUserId == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.lock_outline,
              size: 32,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Sipariş Vermek İçin Giriş Yapın',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  context.pushNamed(RouteNames.login);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Giriş Yap'),
              ),
            ),
          ],
        ),
      );
    }

    // Stok kontrolü - beden bazlı veya genel
    bool isOutOfStock = false;
    if (listing.stockBySize != null && listing.stockBySize!.isNotEmpty) {
      // Beden bazlı stok kontrolü
      if (_selectedSize != null) {
        final stockForSize = listing.stockBySize![_selectedSize] ?? 0;
        isOutOfStock = stockForSize <= 0;
      } else {
        // Beden seçilmemiş
        isOutOfStock = false; // Buton zaten devre dışı olacak
      }
    } else {
      // Genel stok kontrolü
      isOutOfStock = listing.stockQuantity != null && listing.stockQuantity! <= 0;
    }
    
    // Beden kontrolü - eğer ürünün bedeni varsa ve seçilmemişse buton devre dışı
    final isSizeNotSelected = listing.size != null && _selectedSize == null;
    final isButtonDisabled = isOutOfStock || isSizeNotSelected;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: isButtonDisabled
            ? null
            : LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: isButtonDisabled ? AppColors.neutral200 : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isButtonDisabled
            ? null
            : [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isButtonDisabled ? null : () => _showOrderDialog(context, listing),
          borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isOutOfStock
                        ? Icons.cancel_outlined
                        : isSizeNotSelected
                            ? Icons.info_outline
                            : Icons.shopping_cart_outlined,
                    color: isButtonDisabled ? AppColors.neutral500 : Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isOutOfStock
                        ? 'Stokta Yok'
                        : isSizeNotSelected
                            ? 'Beden Seçiniz'
                            : 'Sipariş Ver',
                    style: AppTypography.titleLarge.copyWith(
                      color: isButtonDisabled ? AppColors.neutral500 : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ),
      ),
    );
  }

  void _showOrderDialog(BuildContext context, ListingModel listing) {
    final noteController = TextEditingController();

    // Maksimum adet hesapla - beden bazlı stok varsa onu kullan, yoksa genel stok
    int maxQuantity = 5;
    if (listing.stockBySize != null && listing.stockBySize!.isNotEmpty && _selectedSize != null) {
      // Beden bazlı stok
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

  const _OrderDialogContent({
    required this.listing,
    required this.noteController,
    required this.quantityOptions,
    required this.maxQuantity,
    required this.selectedSize,
  });

  @override
  State<_OrderDialogContent> createState() => _OrderDialogContentState();
}

class _OrderDialogContentState extends State<_OrderDialogContent> {
  int selectedQuantity = 1;

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
                      child: const Icon(
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
                          if (widget.listing.price != null)
                            Text(
                              '₺${_formatPrice(widget.listing.price!)}',
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
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
                                color: AppColors.neutral600,
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
                    border: Border.all(color: AppColors.neutral300),
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
                // Stok bilgisi göster
                if (widget.listing.stockBySize != null && 
                    widget.listing.stockBySize!.isNotEmpty && 
                    widget.selectedSize != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Mevcut stok: ${widget.listing.stockBySize![widget.selectedSize] ?? 0} adet',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.neutral500,
                    ),
                  ),
                ] else if (widget.listing.stockQuantity != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Mevcut stok: ${widget.listing.stockQuantity} adet',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.neutral500,
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
                    color: AppColors.neutral500,
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

                                // Stok kontrolü - beden bazlı veya genel
                                bool stockCheckFailed = false;
                                String stockMessage = '';
                                
                                if (widget.listing.stockBySize != null && 
                                    widget.listing.stockBySize!.isNotEmpty && 
                                    widget.selectedSize != null) {
                                  // Beden bazlı stok kontrolü
                                  final stockForSize = widget.listing.stockBySize![widget.selectedSize] ?? 0;
                                  if (selectedQuantity > stockForSize) {
                                    stockCheckFailed = true;
                                    stockMessage = 'Stokta sadece $stockForSize adet var';
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
                                
                                final totalPrice = (widget.listing.price ?? 0) * selectedQuantity;

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
    return Dialog(
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
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.inventory_2,
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
                        'Stok Yönetimi',
                        style: AppTypography.titleLarge.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.listing.title,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
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
                            color: AppColors.neutral500,
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

                      await ref
                          .read(updateStockBySizeProvider.notifier)
                          .updateStockBySize(widget.listing.id, stockBySize);

                      if (mounted) {
                        final result = ref.read(updateStockBySizeProvider);
                        result.when(
                          data: (_) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Stok güncellendi!'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                            // Refresh listing
                            ref.invalidate(listingByIdProvider(widget.listing.id));
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
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
                            const Icon(
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
                            icon: const Icon(Icons.close, color: Colors.white),
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
