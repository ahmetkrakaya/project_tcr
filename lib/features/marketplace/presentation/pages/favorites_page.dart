import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../data/models/listing_model.dart';
import '../providers/marketplace_provider.dart';

/// Favorites Page
class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  @override
  void initState() {
    super.initState();
    // Favoriler listesi değiştiğinde cache'i güncelle
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // İlk yüklemede cache'i güncelle
      final favoritesState = ref.read(favoriteListingsProvider);
      favoritesState.whenData((listings) {
        if (listings.isNotEmpty) {
          final listingIds = listings.map((l) => l.id).toList();
          ref.read(favoriteIdsProvider.notifier).loadFavoriteIds(listingIds);
        }
      });
      
      // Sonraki değişikliklerde de cache'i güncelle
      ref.listen<AsyncValue<List<ListingModel>>>(favoriteListingsProvider, (previous, next) {
        next.whenData((listings) {
          if (listings.isNotEmpty) {
            final listingIds = listings.map((l) => l.id).toList();
            ref.read(favoriteIdsProvider.notifier).loadFavoriteIds(listingIds);
          } else {
            // Liste boşsa cache'i temizle
            ref.read(favoriteIdsProvider.notifier).clear();
          }
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final favoritesState = ref.watch(favoriteListingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorilerim'),
      ),
      body: favoritesState.when(
        data: (listings) {
          if (listings.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 64, color: AppColors.neutral400),
                  const SizedBox(height: 16),
                  Text(
                    'Henüz favori ürün yok',
                    style: AppTypography.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Beğendiğin ürünleri favorilere ekleyebilirsin',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final width = MediaQuery.sizeOf(context).width;
          const padding = 32.0;
          const spacing = 12.0;
          final crossAxisCount = kIsWeb
              ? (width / 280).floor().clamp(2, 6)
              : 2;
          final cardWidth = (width - padding - spacing * (crossAxisCount - 1)) / crossAxisCount;
          final cardHeight = cardWidth / 0.62;
          final childAspectRatio = cardWidth / cardHeight;

          return RefreshIndicator(
            onRefresh: () async {
              ref.read(favoriteListingsProvider.notifier).refresh();
            },
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: childAspectRatio,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _buildListingCard(
                            context,
                            listings[index],
                            ref,
                            key: ValueKey(listings[index].id),
                          ),
                        );
                      },
                      childCount: listings.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 16),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
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
                error.toString(),
                style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.invalidate(favoriteListingsProvider);
                },
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListingCard(BuildContext context, ListingModel listing, WidgetRef ref, {Key? key}) {
    final isTcrProduct = listing.listingType == ListingType.tcrProduct;

    return AppCard(
      key: key,
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
          final maxImageHeight = kIsWeb && constraints.maxHeight > 320 ? 240.0 : 160.0;
          final imageHeight = (constraints.maxHeight * 0.58).clamp(100.0, maxImageHeight);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
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
                    child: _FavoriteButton(listingId: listing.id),
                  ),
                ],
              ),
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

  const _FavoriteButton({required this.listingId});

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
              // Favoriler listesinden hemen kaldır
              ref.read(favoriteListingsProvider.notifier).removeFavoriteOptimistically(listingId);
            } else {
              ref.read(favoriteIdsProvider.notifier).addFavorite(listingId);
            }

            // API çağrısını arka planda yap (await etme)
            ref.read(toggleFavoriteProvider.notifier).toggleFavorite(listingId).then((_) {
              // API çağrısı başarılı olduğunda favoriler listesini güncelle
              // (zaten optimistic update yapıldı ama senkronizasyon için refresh)
              ref.read(favoriteListingsProvider.notifier).refresh();
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
