import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/enums/gender.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/listing_model.dart';
import '../models/market_report_model.dart';
import '../models/order_model.dart';
import '../models/production_batch_model.dart';
import '../models/stock_alert_model.dart';

/// Marketplace Remote Data Source
abstract class MarketplaceRemoteDataSource {
  /// Tüm aktif ilanları getir
  Future<List<ListingModel>> getListings({
    ListingType? type,
    ListingCategory? category,
    String? searchQuery,
    int limit = 20,
    int offset = 0,
  });

  /// Tek bir ilan getir
  Future<ListingModel> getListingById(String id);

  /// Kullanıcının ilanlarını getir
  Future<List<ListingModel>> getUserListings(String userId);

  /// İlan oluştur
  Future<ListingModel> createListing(ListingModel listing, List<String> imageUrls);

  /// İlan güncelle
  Future<ListingModel> updateListing(ListingModel listing, List<String>? imageUrls);

  /// İlan sil
  Future<void> deleteListing(String id);

  /// İlan görüntülenme sayısını artır
  Future<void> incrementViewCount(String listingId);

  /// Favorilere ekle/çıkar
  Future<void> toggleFavorite(String listingId);

  /// Favori durumunu kontrol et
  Future<bool> isFavorite(String listingId);

  /// Birden fazla ilanın favori durumunu tek seferde kontrol et (performans için)
  Future<Set<String>> getFavoriteListingIds(List<String> listingIds);

  /// Kullanıcının favori ilanlarını getir
  Future<List<ListingModel>> getFavoriteListings();

  /// Sipariş oluştur
  Future<OrderModel> createOrder(OrderModel order);

  /// Sipariş getir
  Future<OrderModel> getOrderById(String orderId);

  /// Kullanıcının siparişlerini getir (alıcı olarak)
  Future<List<OrderModel>> getBuyerOrders();

  /// Kullanıcının siparişlerini getir (satıcı olarak)
  Future<List<OrderModel>> getSellerOrders();

  /// Sipariş durumunu güncelle
  Future<OrderModel> updateOrderStatus(String orderId, OrderStatus status, {String? note});

  /// Tüm siparişleri getir (admin için)
  Future<List<OrderModel>> getAllOrders({OrderStatus? status});

  /// Manuel (elden) satış kaydı oluştur
  Future<OrderModel> createManualSale(OrderModel sale);

  /// Satış detaylarını güncelle (tarihler, ödeme, fiyat, alıcı)
  Future<OrderModel> updateSale(String orderId, OrderModel sale);

  /// Siparişi/satışı sil (admin)
  Future<void> deleteOrder(String orderId);

  /// Ürünün üretim partilerini getir
  Future<List<ProductionBatch>> getProductionBatches(String listingId);

  /// Üretim partisi oluştur veya güncelle (batchId null ise yeni kayıt)
  Future<void> saveProductionBatch({
    String? batchId,
    required String listingId,
    required double unitCost,
    required DateTime producedAt,
    String? note,
    required List<ProductionBatchItem> items,
  });

  /// Üretim partisini sil (stok delta geri alınır)
  Future<void> deleteProductionBatch(String batchId);

  /// Ürünün beden listesini ve stok cinsiyet modunu güncelle
  Future<void> updateListingSizesAndGenderMode({
    required String listingId,
    required String? size,
    required ListingGenderMode stockGenderMode,
  });

  /// Ürünün ağırlıklı ortalama birim maliyeti (parti yoksa null)
  Future<double?> getListingAvgUnitCost(String listingId);

  /// Genel market raporu
  Future<List<MarketOverviewRow>> getMarketOverview({
    DateTime? from,
    DateTime? to,
  });

  /// Tek ürün için üretim/satış/kar özeti
  Future<ProductReportSummary> getProductReport(String listingId);

  /// Ürünün satış geçmişi (Excel satırları)
  Future<List<ProductSalesRow>> getProductSalesRows(String listingId);

  /// Stok miktarını güncelle
  Future<void> updateStockQuantity(String listingId, int? stockQuantity);
  
  /// Beden bazlı stok miktarlarını getir
  Future<Map<String, int>> getStockBySize(String listingId);
  
  /// Beden bazlı stok miktarlarını güncelle
  Future<void> updateStockBySize(String listingId, Map<String, int> stockBySize);

  /// Cinsiyet + beden bazlı stok miktarlarını getir
  Future<Map<String, Map<ListingGender, int>>> getStockBySizeAndGender(String listingId);

  /// Cinsiyet + beden bazlı stok miktarlarını güncelle
  Future<void> updateStockBySizeAndGender(
    String listingId,
    Map<String, Map<ListingGender, int>> stockBySizeGender,
  );

  /// Ürünün stok gender modunu güncelle (unisex / gendered)
  Future<void> updateListingStockGenderMode(
    String listingId,
    ListingGenderMode mode,
  );

  /// İndirim bilgilerini güncelle (null = indirimi kaldır)
  Future<void> updateListingDiscount(
    String listingId, {
    int? discountPercent,
    DateTime? discountStartsAt,
    DateTime? discountEndsAt,
  });

  /// Stok bildirimi aboneliği oluştur
  Future<void> subscribeStockAlert(
    String listingId, {
    String? size,
    ListingGender? gender,
  });

  /// Stok bildirimi aboneliğini kaldır
  Future<void> unsubscribeStockAlert(
    String listingId, {
    String? size,
    ListingGender? gender,
  });

  /// Kullanıcının bir ürün için aktif aboneliklerini getir
  Future<List<StockAlertSubscription>> getUserStockAlertsForListing(
    String listingId,
  );

  /// Admin: bekleyen stok taleplerini ürün bazında grupla
  Future<List<ListingStockAlertGroup>> getPendingStockAlertGroups();
}

/// Marketplace Remote Data Source Implementation
class MarketplaceRemoteDataSourceImpl implements MarketplaceRemoteDataSource {
  final SupabaseClient _supabase;

  MarketplaceRemoteDataSourceImpl(this._supabase);

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  @override
  Future<List<ListingModel>> getListings({
    ListingType? type,
    ListingCategory? category,
    String? searchQuery,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      var query = _supabase
          .from('marketplace_listings')
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url),
            listing_images(image_url, sort_order),
            listing_stock_by_size(size, gender, quantity)
          ''')
          .eq('status', 'active');

      if (type != null) {
        query = query.eq('listing_type', type.value);
      }

      if (category != null) {
        query = query.eq('category', category.value);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('title.ilike.%$searchQuery%,description.ilike.%$searchQuery%');
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) {
        final listingJson = json as Map<String, dynamic>;
        final userJson = listingJson['users'] as Map<String, dynamic>;
        final imagesJson = listingJson['listing_images'] as List<dynamic>?;
        final stockRows = listingJson['listing_stock_by_size'] as List<dynamic>?;
        final stock = ListingModel.stockFromRows(stockRows);
        final discount = ListingModel.discountFromRow(listingJson);

        final sortedImageUrls = imagesJson != null
            ? () {
                final imageList = imagesJson
                    .map((img) {
                      final imgMap = img as Map<String, dynamic>;
                      return {
                        'url': imgMap['image_url'] as String,
                        'order': imgMap['sort_order'] as int? ?? 0,
                      };
                    })
                    .toList();
                imageList.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
                return imageList.map((item) => item['url'] as String).toList();
              }()
            : <String>[];

        return ListingModel(
          id: listingJson['id'] as String,
          sellerId: listingJson['seller_id'] as String,
          sellerName: '${userJson['first_name'] ?? ''} ${userJson['last_name'] ?? ''}'.trim(),
          sellerAvatarUrl: userJson['avatar_url'] as String?,
          listingType: ListingType.fromString(listingJson['listing_type'] as String),
          category: ListingCategory.fromString(listingJson['category'] as String),
          title: listingJson['title'] as String,
          description: listingJson['description'] as String?,
          price: listingJson['price'] != null ? (listingJson['price'] as num).toDouble() : null,
          currency: listingJson['currency'] as String? ?? 'TRY',
          condition: ItemCondition.fromString(listingJson['condition'] as String?),
          brand: listingJson['brand'] as String?,
          size: listingJson['size'] as String?,
          externalUrl: listingJson['external_url'] as String?,
          status: ListingStatus.fromString(listingJson['status'] as String),
          viewCount: listingJson['view_count'] as int? ?? 0,
          stockQuantity: listingJson['stock_quantity'] as int?,
          stockBySize: stock.stockBySize,
          stockGenderMode: listingJson['stock_gender_mode'] != null
              ? ListingGenderMode.fromString(listingJson['stock_gender_mode'] as String)
              : ListingGenderMode.unisex,
          stockBySizeAndGender: stock.stockBySizeAndGender,
          expiresAt: listingJson['expires_at'] != null
              ? DateTime.parse(listingJson['expires_at'] as String)
              : null,
          discountPercent: discount.discountPercent,
          discountStartsAt: discount.discountStartsAt,
          discountEndsAt: discount.discountEndsAt,
          imageUrls: sortedImageUrls,
          primaryImageUrl: sortedImageUrls.isNotEmpty ? sortedImageUrls.first : null,
          createdAt: DateTime.parse(listingJson['created_at'] as String),
          updatedAt: listingJson['updated_at'] != null
              ? DateTime.parse(listingJson['updated_at'] as String)
              : null,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'İlanlar alınamadı: $e');
    }
  }

  @override
  Future<ListingModel> getListingById(String id) async {
    try {
      final response = await _supabase
          .from('marketplace_listings')
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url),
            listing_images(image_url, sort_order)
          ''')
          .eq('id', id)
          .single();

      final Map<String, dynamic> listingJson = response;
      final userJson = listingJson['users'] as Map<String, dynamic>;
      final imagesJson = listingJson['listing_images'] as List<dynamic>?;

      final sortedImageUrls = imagesJson != null
          ? () {
              final imageList = imagesJson
                  .map((img) {
                    final imgMap = img as Map<String, dynamic>;
                    return {
                      'url': imgMap['image_url'] as String,
                      'order': imgMap['sort_order'] as int? ?? 0,
                    };
                  })
                  .toList();
              imageList.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
              return imageList.map((item) => item['url'] as String).toList();
            }()
          : <String>[];

      // Favori durumunu kontrol et
      bool isFavorite = false;
      if (_currentUserId != null) {
        try {
          final favoriteResponse = await _supabase
              .from('listing_favorites')
              .select('id')
              .eq('listing_id', id)
              .eq('user_id', _currentUserId!)
              .maybeSingle();
          isFavorite = favoriteResponse != null;
        } catch (_) {
          // Favori kontrolü başarısız olursa devam et
        }
      }

      // Beden + cinsiyet bazlı stokları getir
      Map<String, int>? stockBySize;
      Map<String, Map<ListingGender, int>>? stockBySizeAndGender;
      try {
        final stockResponse = await _supabase
            .from('listing_stock_by_size')
            .select('size, gender, quantity')
            .eq('listing_id', id);
        
        if (stockResponse.isNotEmpty) {
          for (final row in stockResponse) {
            final size = row['size'] as String;
            final genderStr = row['gender'] as String?;
            final quantity = row['quantity'] as int;

            final gender = genderStr != null
                ? ListingGender.fromString(genderStr)
                : ListingGender.unisex;

            stockBySizeAndGender ??= {};
            final byGender = stockBySizeAndGender.putIfAbsent(
              size,
              () => <ListingGender, int>{},
            );
            byGender[gender] = quantity;
          }

          if (stockBySizeAndGender != null && stockBySizeAndGender.isNotEmpty) {
            // Unisex kayıtları eski tek boyutlu map'e yansıt (geriye dönük uyumluluk için)
            final flattened = <String, int>{};
            stockBySizeAndGender.forEach((size, genderMap) {
              final unisexQty = genderMap[ListingGender.unisex];
              if (unisexQty != null) {
                flattened[size] = unisexQty;
              }
            });
            if (flattened.isNotEmpty) {
              stockBySize = flattened;
            }
          }
        }
      } catch (_) {
        // Stok kontrolü başarısız olursa devam et
      }

      final discount = ListingModel.discountFromRow(listingJson);

      return ListingModel(
        id: listingJson['id'] as String,
        sellerId: listingJson['seller_id'] as String,
        sellerName: '${userJson['first_name'] ?? ''} ${userJson['last_name'] ?? ''}'.trim(),
        sellerAvatarUrl: userJson['avatar_url'] as String?,
        listingType: ListingType.fromString(listingJson['listing_type'] as String),
        category: ListingCategory.fromString(listingJson['category'] as String),
        title: listingJson['title'] as String,
        description: listingJson['description'] as String?,
        price: listingJson['price'] != null ? (listingJson['price'] as num).toDouble() : null,
        currency: listingJson['currency'] as String? ?? 'TRY',
        condition: ItemCondition.fromString(listingJson['condition'] as String?),
        brand: listingJson['brand'] as String?,
        size: listingJson['size'] as String?,
        externalUrl: listingJson['external_url'] as String?,
        status: ListingStatus.fromString(listingJson['status'] as String),
        viewCount: listingJson['view_count'] as int? ?? 0,
        stockQuantity: listingJson['stock_quantity'] as int?,
        stockBySize: stockBySize,
        stockGenderMode: listingJson['stock_gender_mode'] != null
            ? ListingGenderMode.fromString(listingJson['stock_gender_mode'] as String)
            : ListingGenderMode.unisex,
        stockBySizeAndGender: stockBySizeAndGender,
        expiresAt: listingJson['expires_at'] != null
            ? DateTime.parse(listingJson['expires_at'] as String)
            : null,
        discountPercent: discount.discountPercent,
        discountStartsAt: discount.discountStartsAt,
        discountEndsAt: discount.discountEndsAt,
        imageUrls: sortedImageUrls,
        primaryImageUrl: sortedImageUrls.isNotEmpty ? sortedImageUrls.first : null,
        isFavorite: isFavorite,
        createdAt: DateTime.parse(listingJson['created_at'] as String),
        updatedAt: listingJson['updated_at'] != null
            ? DateTime.parse(listingJson['updated_at'] as String)
            : null,
      );
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'İlan alınamadı: $e');
    }
  }

  @override
  Future<List<ListingModel>> getUserListings(String userId) async {
    try {
      final response = await _supabase
          .from('marketplace_listings')
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url),
            listing_images(image_url, sort_order)
          ''')
          .eq('seller_id', userId)
          .order('created_at', ascending: false);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) {
        final listingJson = json as Map<String, dynamic>;
        final userJson = listingJson['users'] as Map<String, dynamic>;
        final imagesJson = listingJson['listing_images'] as List<dynamic>?;
        final discount = ListingModel.discountFromRow(listingJson);

        final sortedImageUrls = imagesJson != null
            ? () {
                final imageList = imagesJson
                    .map((img) {
                      final imgMap = img as Map<String, dynamic>;
                      return {
                        'url': imgMap['image_url'] as String,
                        'order': imgMap['sort_order'] as int? ?? 0,
                      };
                    })
                    .toList();
                imageList.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
                return imageList.map((item) => item['url'] as String).toList();
              }()
            : <String>[];

        return ListingModel(
          id: listingJson['id'] as String,
          sellerId: listingJson['seller_id'] as String,
          sellerName: '${userJson['first_name'] ?? ''} ${userJson['last_name'] ?? ''}'.trim(),
          sellerAvatarUrl: userJson['avatar_url'] as String?,
          listingType: ListingType.fromString(listingJson['listing_type'] as String),
          category: ListingCategory.fromString(listingJson['category'] as String),
          title: listingJson['title'] as String,
          description: listingJson['description'] as String?,
          price: listingJson['price'] != null ? (listingJson['price'] as num).toDouble() : null,
          currency: listingJson['currency'] as String? ?? 'TRY',
          condition: ItemCondition.fromString(listingJson['condition'] as String?),
          brand: listingJson['brand'] as String?,
          size: listingJson['size'] as String?,
          externalUrl: listingJson['external_url'] as String?,
          status: ListingStatus.fromString(listingJson['status'] as String),
          viewCount: listingJson['view_count'] as int? ?? 0,
          stockQuantity: listingJson['stock_quantity'] as int?,
          expiresAt: listingJson['expires_at'] != null
              ? DateTime.parse(listingJson['expires_at'] as String)
              : null,
          discountPercent: discount.discountPercent,
          discountStartsAt: discount.discountStartsAt,
          discountEndsAt: discount.discountEndsAt,
          imageUrls: sortedImageUrls,
          primaryImageUrl: sortedImageUrls.isNotEmpty ? sortedImageUrls.first : null,
          createdAt: DateTime.parse(listingJson['created_at'] as String),
          updatedAt: listingJson['updated_at'] != null
              ? DateTime.parse(listingJson['updated_at'] as String)
              : null,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Kullanıcı ilanları alınamadı: $e');
    }
  }

  @override
  Future<ListingModel> createListing(ListingModel listing, List<String> imageUrls) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      // İlan oluştur
      final listingResponse = await _supabase
          .from('marketplace_listings')
          .insert({
            ...listing.toJson(),
            'seller_id': _currentUserId,
          })
          .select()
          .single();

      final listingId = listingResponse['id'] as String;

      // Görselleri ekle
      if (imageUrls.isNotEmpty) {
        await _supabase.from('listing_images').insert(
          imageUrls.asMap().entries.map((entry) => {
            'listing_id': listingId,
            'image_url': entry.value,
            'sort_order': entry.key,
          }).toList(),
        );
      }

      // Oluşturulan ilanı getir
      return await getListingById(listingId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'İlan oluşturulamadı: $e');
    }
  }

  @override
  Future<ListingModel> updateListing(ListingModel listing, List<String>? imageUrls) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      // İlan güncelle (seller_id hariç — boş string UUID hatasını önler)
      // stock_quantity üretim partileriyle yönetilir; düzenlemede ezilmesin
      final updateData = Map<String, dynamic>.from(listing.toJson())
        ..remove('seller_id')
        ..remove('stock_quantity');
      await _supabase
          .from('marketplace_listings')
          .update(updateData)
          .eq('id', listing.id);

      // Görselleri güncelle (varsa)
      if (imageUrls != null) {
        // Eski görselleri sil
        await _supabase
            .from('listing_images')
            .delete()
            .eq('listing_id', listing.id);

        // Yeni görselleri ekle
        if (imageUrls.isNotEmpty) {
          await _supabase.from('listing_images').insert(
            imageUrls.asMap().entries.map((entry) => {
              'listing_id': listing.id,
              'image_url': entry.value,
              'sort_order': entry.key,
            }).toList(),
          );
        }
      }

      // Güncellenmiş ilanı getir
      return await getListingById(listing.id);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'İlan güncellenemedi: $e');
    }
  }

  @override
  Future<void> deleteListing(String id) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      await _supabase
          .from('marketplace_listings')
          .delete()
          .eq('id', id)
          .eq('seller_id', _currentUserId!);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'İlan silinemedi: $e');
    }
  }

  @override
  Future<void> incrementViewCount(String listingId) async {
    try {
      await _supabase.rpc('increment_listing_view', params: {'listing_uuid': listingId});
    } catch (e) {
      // Görüntülenme sayısı artırma hatası kritik değil, sessizce devam et
    }
  }

  @override
  Future<void> toggleFavorite(String listingId) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      final existing = await _supabase
          .from('listing_favorites')
          .select('id')
          .eq('listing_id', listingId)
          .eq('user_id', _currentUserId!)
          .maybeSingle();

      if (existing != null) {
        // Favorilerden çıkar
        await _supabase
            .from('listing_favorites')
            .delete()
            .eq('listing_id', listingId)
            .eq('user_id', _currentUserId!);
      } else {
        // Favorilere ekle
        await _supabase.from('listing_favorites').insert({
          'listing_id': listingId,
          'user_id': _currentUserId!,
        });
      }
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Favori işlemi başarısız: $e');
    }
  }

  @override
  Future<bool> isFavorite(String listingId) async {
    try {
      if (_currentUserId == null) return false;

      final response = await _supabase
          .from('listing_favorites')
          .select('id')
          .eq('listing_id', listingId)
          .eq('user_id', _currentUserId!)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Set<String>> getFavoriteListingIds(List<String> listingIds) async {
    try {
      if (_currentUserId == null || listingIds.isEmpty) return {};

      final response = await _supabase
          .from('listing_favorites')
          .select('listing_id')
          .eq('user_id', _currentUserId!)
          .inFilter('listing_id', listingIds);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((item) => item['listing_id'] as String).toSet();
    } catch (e) {
      return {};
    }
  }

  @override
  Future<List<ListingModel>> getFavoriteListings() async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      // Önce favori listing_id'leri al
      final favoritesResponse = await _supabase
          .from('listing_favorites')
          .select('listing_id')
          .eq('user_id', _currentUserId!)
          .order('created_at', ascending: false);

      final List<dynamic> favoritesData = favoritesResponse as List<dynamic>;
      if (favoritesData.isEmpty) {
        return [];
      }

      final listingIds = favoritesData
          .map((fav) => fav['listing_id'] as String)
          .toList();

      // Şimdi bu listing'leri getir
      final response = await _supabase
          .from('marketplace_listings')
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url),
            listing_images(image_url, sort_order)
          ''')
          .inFilter('id', listingIds)
          .eq('status', 'active')
          .order('created_at', ascending: false);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) {
        final listingJson = json as Map<String, dynamic>;
        final userJson = listingJson['users'] as Map<String, dynamic>;
        final imagesJson = listingJson['listing_images'] as List<dynamic>?;
        final discount = ListingModel.discountFromRow(listingJson);

        final sortedImageUrls = imagesJson != null
            ? () {
                final imageList = imagesJson
                    .map((img) {
                      final imgMap = img as Map<String, dynamic>;
                      return {
                        'url': imgMap['image_url'] as String,
                        'order': imgMap['sort_order'] as int? ?? 0,
                      };
                    })
                    .toList();
                imageList.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
                return imageList.map((item) => item['url'] as String).toList();
              }()
            : <String>[];

        return ListingModel(
          id: listingJson['id'] as String,
          sellerId: listingJson['seller_id'] as String,
          sellerName: '${userJson['first_name'] ?? ''} ${userJson['last_name'] ?? ''}'.trim(),
          sellerAvatarUrl: userJson['avatar_url'] as String?,
          title: listingJson['title'] as String,
          description: listingJson['description'] as String?,
          listingType: ListingType.fromString(listingJson['listing_type'] as String),
          category: ListingCategory.fromString(listingJson['category'] as String),
          price: listingJson['price'] != null ? (listingJson['price'] as num).toDouble() : null,
          currency: listingJson['currency'] as String? ?? 'TRY',
          condition: ItemCondition.fromString(listingJson['condition'] as String?),
          size: listingJson['size'] as String?,
          brand: listingJson['brand'] as String?,
          stockQuantity: listingJson['stock_quantity'] as int?,
          stockGenderMode: listingJson['stock_gender_mode'] != null
              ? ListingGenderMode.fromString(listingJson['stock_gender_mode'] as String)
              : ListingGenderMode.unisex,
          discountPercent: discount.discountPercent,
          discountStartsAt: discount.discountStartsAt,
          discountEndsAt: discount.discountEndsAt,
          imageUrls: sortedImageUrls,
          primaryImageUrl: sortedImageUrls.isNotEmpty ? sortedImageUrls.first : null,
          status: ListingStatus.fromString(listingJson['status'] as String),
          viewCount: listingJson['view_count'] as int? ?? 0,
          createdAt: DateTime.parse(listingJson['created_at'] as String),
          updatedAt: listingJson['updated_at'] != null
              ? DateTime.parse(listingJson['updated_at'] as String)
              : null,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Favori ilanlar getirilemedi: $e');
    }
  }

  @override
  Future<OrderModel> createOrder(OrderModel order) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      // Admin kontrolü RLS policy'de yapılıyor
      // seller_id artık opsiyonel (admin sipariş oluştururken gerekmez)
      final orderJson = order.toJson();
      orderJson['buyer_id'] = _currentUserId!;

      final response = await _supabase
          .from('marketplace_orders')
          .insert(orderJson)
          .select('''
            *,
            buyer:users!marketplace_orders_buyer_id_fkey(first_name, last_name, avatar_url),
            seller:users!marketplace_orders_seller_id_fkey(first_name, last_name, avatar_url),
            updated_by_user:users!marketplace_orders_updated_by_fkey(first_name, last_name, avatar_url)
          ''')
          .single();

      return OrderModel.fromJoinedJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Sipariş oluşturulamadı: $e');
    }
  }

  @override
  Future<OrderModel> getOrderById(String orderId) async {
    try {
      final response = await _supabase
          .from('marketplace_orders')
          .select('''
            *,
            buyer:users!marketplace_orders_buyer_id_fkey(first_name, last_name, avatar_url),
            seller:users!marketplace_orders_seller_id_fkey(first_name, last_name, avatar_url),
            updated_by_user:users!marketplace_orders_updated_by_fkey(first_name, last_name, avatar_url)
          ''')
          .eq('id', orderId)
          .single();

      return OrderModel.fromJoinedJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Sipariş alınamadı: $e');
    }
  }

  @override
  Future<List<OrderModel>> getBuyerOrders() async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      final response = await _supabase
          .from('marketplace_orders')
          .select('''
            *,
            buyer:users!marketplace_orders_buyer_id_fkey(first_name, last_name, avatar_url),
            seller:users!marketplace_orders_seller_id_fkey(first_name, last_name, avatar_url),
            updated_by_user:users!marketplace_orders_updated_by_fkey(first_name, last_name, avatar_url)
          ''')
          .eq('buyer_id', _currentUserId!)
          .order('created_at', ascending: false);

      final List<dynamic> data = response as List<dynamic>;
      return data
          .map((json) => OrderModel.fromJoinedJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Siparişler alınamadı: $e');
    }
  }

  @override
  Future<List<OrderModel>> getSellerOrders() async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      final response = await _supabase
          .from('marketplace_orders')
          .select('''
            *,
            buyer:users!marketplace_orders_buyer_id_fkey(first_name, last_name, avatar_url),
            seller:users!marketplace_orders_seller_id_fkey(first_name, last_name, avatar_url),
            updated_by_user:users!marketplace_orders_updated_by_fkey(first_name, last_name, avatar_url)
          ''')
          .eq('seller_id', _currentUserId!)
          .order('created_at', ascending: false);

      final List<dynamic> data = response as List<dynamic>;
      return data
          .map((json) => OrderModel.fromJoinedJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Siparişler alınamadı: $e');
    }
  }

  @override
  Future<OrderModel> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    String? note,
  }) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      final updateData = <String, dynamic>{
        'status': status.value,
        'updated_by': _currentUserId, // Durum güncelleyen kişiyi kaydet
      };

      if (status == OrderStatus.confirmed) {
        updateData['confirmed_at'] = DateTime.now().toIso8601String();
      } else if (status == OrderStatus.cancelled) {
        updateData['cancelled_at'] = DateTime.now().toIso8601String();
        updateData['cancelled_by'] = _currentUserId;
        if (note != null) {
          updateData['cancellation_reason'] = note;
        }
      } else if (status == OrderStatus.completed) {
        updateData['completed_at'] = DateTime.now().toIso8601String();
      }

      if (note != null && status != OrderStatus.cancelled) {
        // Satıcı notu ekle
        updateData['seller_note'] = note;
      }

      final response = await _supabase
          .from('marketplace_orders')
          .update(updateData)
          .eq('id', orderId)
          .select('''
            *,
            buyer:users!marketplace_orders_buyer_id_fkey(first_name, last_name, avatar_url),
            seller:users!marketplace_orders_seller_id_fkey(first_name, last_name, avatar_url),
            updated_by_user:users!marketplace_orders_updated_by_fkey(first_name, last_name, avatar_url)
          ''')
          .single();

      return OrderModel.fromJoinedJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Sipariş güncellenemedi: $e');
    }
  }

  @override
  Future<List<OrderModel>> getAllOrders({OrderStatus? status}) async {
    try {
      var query = _supabase
          .from('marketplace_orders')
          .select('''
            *,
            buyer:users!marketplace_orders_buyer_id_fkey(first_name, last_name, avatar_url),
            seller:users!marketplace_orders_seller_id_fkey(first_name, last_name, avatar_url),
            updated_by_user:users!marketplace_orders_updated_by_fkey(first_name, last_name, avatar_url)
          ''');

      if (status != null) {
        query = query.eq('status', status.value);
      }

      final response = await query.order('created_at', ascending: false);

      final List<dynamic> data = response as List<dynamic>;
      return data
          .map((json) => OrderModel.fromJoinedJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Siparişler alınamadı: $e');
    }
  }

  static const String _orderJoinSelect = '''
            *,
            buyer:users!marketplace_orders_buyer_id_fkey(first_name, last_name, avatar_url),
            seller:users!marketplace_orders_seller_id_fkey(first_name, last_name, avatar_url),
            updated_by_user:users!marketplace_orders_updated_by_fkey(first_name, last_name, avatar_url)
          ''';

  @override
  Future<OrderModel> createManualSale(OrderModel sale) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(
            message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      final payload = sale.toSalePayload();
      payload['is_manual'] = true;
      payload['updated_by'] = _currentUserId;
      // Maliyet raporlarda canlı ortalamadan gelir; snapshot yazılmaz.
      payload.remove('unit_cost');

      if (sale.status == OrderStatus.completed) {
        payload['completed_at'] =
            (sale.paymentDate ?? sale.effectiveOrderDate).toIso8601String();
      } else if (sale.status == OrderStatus.confirmed) {
        payload['confirmed_at'] = sale.effectiveOrderDate.toIso8601String();
      }

      final response = await _supabase
          .from('marketplace_orders')
          .insert(payload)
          .select(_orderJoinSelect)
          .single();

      return OrderModel.fromJoinedJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Satış kaydedilemedi: $e');
    }
  }

  @override
  Future<OrderModel> updateSale(String orderId, OrderModel sale) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(
            message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      final payload = sale.toSalePayload();
      payload['updated_by'] = _currentUserId;
      payload.remove('listing_id');
      // Maliyet raporlarda canlı ortalamadan gelir; snapshot yazılmaz.
      payload.remove('unit_cost');

      final response = await _supabase
          .from('marketplace_orders')
          .update(payload)
          .eq('id', orderId)
          .select(_orderJoinSelect)
          .single();

      return OrderModel.fromJoinedJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Satış güncellenemedi: $e');
    }
  }

  @override
  Future<void> deleteOrder(String orderId) async {
    try {
      await _supabase.from('marketplace_orders').delete().eq('id', orderId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Satış silinemedi: $e');
    }
  }

  @override
  Future<List<ProductionBatch>> getProductionBatches(String listingId) async {
    try {
      final response = await _supabase
          .from('production_batches')
          .select('''
            *,
            production_batch_items(id, size, gender, quantity)
          ''')
          .eq('listing_id', listingId)
          .order('produced_at', ascending: false);

      final List<dynamic> data = response as List<dynamic>;
      return data
          .map((json) => ProductionBatch.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Üretim partileri alınamadı: $e');
    }
  }

  @override
  Future<void> saveProductionBatch({
    String? batchId,
    required String listingId,
    required double unitCost,
    required DateTime producedAt,
    String? note,
    required List<ProductionBatchItem> items,
  }) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(
            message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }
      if (items.isEmpty) {
        throw ServerException(message: 'En az bir beden/adet satırı gerekli');
      }

      final producedDate =
          DateTime(producedAt.year, producedAt.month, producedAt.day)
              .toIso8601String()
              .split('T')
              .first;

      // Düzenlemede stok deltası için eski adetleri al
      final oldQuantities = <String, int>{};
      if (batchId != null) {
        final oldRows = await _supabase
            .from('production_batch_items')
            .select('size, gender, quantity')
            .eq('batch_id', batchId);
        for (final row in oldRows as List) {
          final map = row as Map<String, dynamic>;
          final key =
              '${map['size']}::${map['gender'] as String? ?? 'unisex'}';
          oldQuantities[key] =
              (oldQuantities[key] ?? 0) + (map['quantity'] as int? ?? 0);
        }
      }

      String effectiveBatchId;
      if (batchId == null) {
        final inserted = await _supabase
            .from('production_batches')
            .insert({
              'listing_id': listingId,
              'unit_cost': unitCost,
              'produced_at': producedDate,
              'note': note,
              'created_by': _currentUserId,
            })
            .select('id')
            .single();
        effectiveBatchId = inserted['id'] as String;
      } else {
        await _supabase.from('production_batches').update({
          'unit_cost': unitCost,
          'produced_at': producedDate,
          'note': note,
        }).eq('id', batchId);
        effectiveBatchId = batchId;

        await _supabase
            .from('production_batch_items')
            .delete()
            .eq('batch_id', effectiveBatchId);
      }

      await _supabase.from('production_batch_items').insert(
            items
                .map((item) => {
                      'batch_id': effectiveBatchId,
                      ...item.toJson(),
                    })
                .toList(),
          );

      // Stok delta: yeni - eski
      final newQuantities = <String, int>{};
      for (final item in items) {
        final key = '${item.size}::${item.gender.value}';
        newQuantities[key] = (newQuantities[key] ?? 0) + item.quantity;
      }

      final allKeys = {...oldQuantities.keys, ...newQuantities.keys};
      for (final key in allKeys) {
        final delta = (newQuantities[key] ?? 0) - (oldQuantities[key] ?? 0);
        if (delta == 0) continue;
        final parts = key.split('::');
        await _applyProductionStockDelta(
          listingId: listingId,
          size: parts[0],
          gender: parts.length > 1 ? parts[1] : 'unisex',
          delta: delta,
        );
      }
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException(message: 'Üretim partisi kaydedilemedi: $e');
    }
  }

  @override
  Future<void> deleteProductionBatch(String batchId) async {
    try {
      final batch = await _supabase
          .from('production_batches')
          .select('listing_id')
          .eq('id', batchId)
          .maybeSingle();
      if (batch == null) return;

      final listingId = batch['listing_id'] as String;
      final itemRows = await _supabase
          .from('production_batch_items')
          .select('size, gender, quantity')
          .eq('batch_id', batchId);

      await _supabase.from('production_batches').delete().eq('id', batchId);

      for (final row in itemRows as List) {
        final map = row as Map<String, dynamic>;
        final qty = map['quantity'] as int? ?? 0;
        if (qty == 0) continue;
        await _applyProductionStockDelta(
          listingId: listingId,
          size: map['size'] as String,
          gender: map['gender'] as String? ?? 'unisex',
          delta: -qty,
        );
      }
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException(message: 'Üretim partisi silinemedi: $e');
    }
  }

  Future<void> _applyProductionStockDelta({
    required String listingId,
    required String size,
    required String gender,
    required int delta,
  }) async {
    await _supabase.rpc(
      'apply_production_stock_delta',
      params: {
        'p_listing_id': listingId,
        'p_size': size,
        'p_gender': gender,
        'p_delta': delta,
      },
    );
  }

  @override
  Future<void> updateListingSizesAndGenderMode({
    required String listingId,
    required String? size,
    required ListingGenderMode stockGenderMode,
  }) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(
            message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      await _supabase.from('marketplace_listings').update({
        'size': size,
        'stock_gender_mode': stockGenderMode.value,
      }).eq('id', listingId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(
        message: 'Beden/cinsiyet ayarları güncellenemedi: $e',
      );
    }
  }

  @override
  Future<double?> getListingAvgUnitCost(String listingId) async {
    try {
      final response = await _supabase.rpc(
        'get_listing_avg_unit_cost',
        params: {'p_listing_id': listingId},
      );
      return (response as num?)?.toDouble();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<MarketOverviewRow>> getMarketOverview({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final response = await _supabase.rpc(
        'get_market_overview',
        params: {
          'p_from': from != null ? _dateOnly(from) : null,
          'p_to': to != null ? _dateOnly(to) : null,
        },
      );

      final List<dynamic> data = response as List<dynamic>? ?? [];
      return data
          .map((json) =>
              MarketOverviewRow.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Market raporu alınamadı: $e');
    }
  }

  @override
  Future<ProductReportSummary> getProductReport(String listingId) async {
    try {
      final response = await _supabase.rpc(
        'get_market_product_report',
        params: {'p_listing_id': listingId},
      );

      return ProductReportSummary.fromJson(response as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Ürün raporu alınamadı: $e');
    }
  }

  @override
  Future<List<ProductSalesRow>> getProductSalesRows(String listingId) async {
    try {
      final response = await _supabase.rpc(
        'get_market_product_sales',
        params: {'p_listing_id': listingId},
      );

      final List<dynamic> data = response as List<dynamic>? ?? [];
      return data
          .map((json) => ProductSalesRow.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Satış geçmişi alınamadı: $e');
    }
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  @override
  Future<void> updateStockQuantity(String listingId, int? stockQuantity) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      await _supabase
          .from('marketplace_listings')
          .update({'stock_quantity': stockQuantity})
          .eq('id', listingId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Stok güncellenemedi: $e');
    }
  }

  @override
  Future<Map<String, int>> getStockBySize(String listingId) async {
    try {
      final bySizeGender = await getStockBySizeAndGender(listingId);
      final Map<String, int> stockBySize = {};

      bySizeGender.forEach((size, genderMap) {
        if (genderMap.containsKey(ListingGender.unisex)) {
          stockBySize[size] = genderMap[ListingGender.unisex]!;
        } else {
          // Geriye dönük uyumluluk için diğer cinsiyetlerin toplamı
          final total = genderMap.values.fold<int>(0, (sum, qty) => sum + qty);
          stockBySize[size] = total;
        }
      });

      return stockBySize;
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Beden bazlı stok alınamadı: $e');
    }
  }

  @override
  Future<void> updateStockBySize(String listingId, Map<String, int> stockBySize) async {
    // Eski API: tüm stokları unisex olarak yazar
    final Map<String, Map<ListingGender, int>> stockBySizeGender = {};
    for (final entry in stockBySize.entries) {
      stockBySizeGender[entry.key] = {ListingGender.unisex: entry.value};
    }
    return updateStockBySizeAndGender(listingId, stockBySizeGender);
  }

  @override
  Future<Map<String, Map<ListingGender, int>>> getStockBySizeAndGender(
    String listingId,
  ) async {
    try {
      final response = await _supabase
          .from('listing_stock_by_size')
          .select('size, gender, quantity')
          .eq('listing_id', listingId);

      final Map<String, Map<ListingGender, int>> stockBySizeGender = {};
      for (final row in response) {
        final size = row['size'] as String;
        final genderStr = row['gender'] as String?;
        final quantity = row['quantity'] as int;

        final gender = genderStr != null
            ? ListingGender.fromString(genderStr)
            : ListingGender.unisex;

        final byGender = stockBySizeGender.putIfAbsent(
          size,
          () => <ListingGender, int>{},
        );
        byGender[gender] = quantity;
      }

      return stockBySizeGender;
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Cinsiyet + beden bazlı stok alınamadı: $e');
    }
  }

  @override
  Future<void> updateStockBySizeAndGender(
    String listingId,
    Map<String, Map<ListingGender, int>> stockBySizeGender,
  ) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      // Önce mevcut stokları sil
      await _supabase
          .from('listing_stock_by_size')
          .delete()
          .eq('listing_id', listingId);

      // Yeni stokları ekle
      if (stockBySizeGender.isNotEmpty) {
        final inserts = <Map<String, dynamic>>[];
        stockBySizeGender.forEach((size, genderMap) {
          genderMap.forEach((gender, quantity) {
            inserts.add({
              'listing_id': listingId,
              'size': size,
              'gender': gender.value,
              'quantity': quantity,
            });
          });
        });

        await _supabase
            .from('listing_stock_by_size')
            .insert(inserts);
      }
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Beden bazlı stok güncellenemedi: $e');
    }
  }

  @override
  Future<void> updateListingStockGenderMode(
    String listingId,
    ListingGenderMode mode,
  ) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      await _supabase
          .from('marketplace_listings')
          .update({'stock_gender_mode': mode.value})
          .eq('id', listingId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(
        message: 'Stok gender modu güncellenemedi: $e',
      );
    }
  }

  @override
  Future<void> updateListingDiscount(
    String listingId, {
    int? discountPercent,
    DateTime? discountStartsAt,
    DateTime? discountEndsAt,
  }) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      await _supabase.from('marketplace_listings').update({
        'discount_percent': discountPercent,
        'discount_starts_at': discountStartsAt?.toUtc().toIso8601String(),
        'discount_ends_at': discountEndsAt?.toUtc().toIso8601String(),
      }).eq('id', listingId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'İndirim güncellenemedi: $e');
    }
  }

  @override
  Future<void> subscribeStockAlert(
    String listingId, {
    String? size,
    ListingGender? gender,
  }) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      await _supabase.from('listing_stock_alerts').upsert({
        'listing_id': listingId,
        'user_id': _currentUserId!,
        'size': size,
        'gender': gender?.value,
        'notified_at': null,
      }, onConflict: 'listing_id,user_id,size,gender');
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Stok bildirimi kaydedilemedi: $e');
    }
  }

  @override
  Future<void> unsubscribeStockAlert(
    String listingId, {
    String? size,
    ListingGender? gender,
  }) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      var query = _supabase
          .from('listing_stock_alerts')
          .delete()
          .eq('listing_id', listingId)
          .eq('user_id', _currentUserId!);

      if (size == null) {
        query = query.isFilter('size', null);
      } else {
        query = query.eq('size', size);
      }

      if (gender == null) {
        query = query.isFilter('gender', null);
      } else {
        query = query.eq('gender', gender.value);
      }

      await query;
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Stok bildirimi kaldırılamadı: $e');
    }
  }

  @override
  Future<List<StockAlertSubscription>> getUserStockAlertsForListing(
    String listingId,
  ) async {
    try {
      if (_currentUserId == null) return [];

      final response = await _supabase
          .from('listing_stock_alerts')
          .select('id, listing_id, size, gender')
          .eq('listing_id', listingId)
          .eq('user_id', _currentUserId!)
          .isFilter('notified_at', null);

      final List<dynamic> data = response as List<dynamic>;
      return data
          .map((row) => StockAlertSubscription.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<ListingStockAlertGroup>> getPendingStockAlertGroups() async {
    try {
      final response = await _supabase
          .from('listing_stock_alerts')
          .select('''
            id,
            listing_id,
            user_id,
            size,
            gender,
            created_at,
            users!inner(first_name, last_name, avatar_url),
            marketplace_listings!inner(
              title,
              listing_images(image_url, sort_order)
            )
          ''')
          .isFilter('notified_at', null)
          .order('created_at', ascending: false);

      final List<dynamic> rows = response as List<dynamic>;
      final grouped = <String, ListingStockAlertGroup>{};

      for (final row in rows) {
        final map = row as Map<String, dynamic>;
        final listingId = map['listing_id'] as String;
        final listing = map['marketplace_listings'] as Map<String, dynamic>;
        final title = listing['title'] as String? ?? 'Ürün';
        final images = listing['listing_images'] as List<dynamic>? ?? [];
        images.sort((a, b) =>
            (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));
        final imageUrl =
            images.isNotEmpty ? images.first['image_url'] as String? : null;

        final request = StockAlertRequest.fromJson(map);
        final existing = grouped[listingId];
        if (existing == null) {
          grouped[listingId] = ListingStockAlertGroup(
            listingId: listingId,
            listingTitle: title,
            imageUrl: imageUrl,
            alertCount: 1,
            requests: [request],
          );
        } else {
          grouped[listingId] = ListingStockAlertGroup(
            listingId: listingId,
            listingTitle: title,
            imageUrl: imageUrl,
            alertCount: existing.alertCount + 1,
            requests: [...existing.requests, request],
          );
        }
      }

      final groups = grouped.values.toList()
        ..sort((a, b) => b.alertCount.compareTo(a.alertCount));
      return groups;
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Stok talepleri yüklenemedi: $e');
    }
  }
}
