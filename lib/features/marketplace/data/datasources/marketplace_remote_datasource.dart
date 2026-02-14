import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/listing_model.dart';
import '../models/order_model.dart';

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

  /// Stok miktarını güncelle
  Future<void> updateStockQuantity(String listingId, int? stockQuantity);
  
  /// Beden bazlı stok miktarlarını getir
  Future<Map<String, int>> getStockBySize(String listingId);
  
  /// Beden bazlı stok miktarlarını güncelle
  Future<void> updateStockBySize(String listingId, Map<String, int> stockBySize);
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
            listing_images(image_url, sort_order)
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

      // Beden bazlı stokları getir
      Map<String, int>? stockBySize;
      try {
        final stockResponse = await _supabase
            .from('listing_stock_by_size')
            .select('size, quantity')
            .eq('listing_id', id);
        
        if (stockResponse.isNotEmpty) {
          stockBySize = {};
          for (final row in stockResponse) {
            stockBySize[row['size'] as String] = row['quantity'] as int;
          }
        }
      } catch (_) {
        // Stok kontrolü başarısız olursa devam et
      }

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
        expiresAt: listingJson['expires_at'] != null
            ? DateTime.parse(listingJson['expires_at'] as String)
            : null,
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

      // İlan güncelle
      await _supabase
          .from('marketplace_listings')
          .update(listing.toJson())
          .eq('id', listing.id)
          .eq('seller_id', _currentUserId!);

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

      final Map<String, dynamic> orderJsonResponse = response;
      final buyerJson = orderJsonResponse['buyer'] as Map<String, dynamic>?;
      final sellerJson = orderJsonResponse['seller'] as Map<String, dynamic>?;
      final updatedByJson = orderJsonResponse['updated_by_user'] as Map<String, dynamic>?;

      return OrderModel(
        id: orderJsonResponse['id'] as String,
        listingId: orderJsonResponse['listing_id'] as String,
        buyerId: orderJsonResponse['buyer_id'] as String,
        buyerName: buyerJson != null
            ? '${buyerJson['first_name'] ?? ''} ${buyerJson['last_name'] ?? ''}'.trim()
            : null,
        buyerAvatarUrl: buyerJson?['avatar_url'] as String?,
        sellerId: orderJsonResponse['seller_id'] as String?,
        sellerName: sellerJson != null
            ? '${sellerJson['first_name'] ?? ''} ${sellerJson['last_name'] ?? ''}'.trim()
            : null,
        sellerAvatarUrl: sellerJson?['avatar_url'] as String?,
        quantity: orderJsonResponse['quantity'] as int? ?? 1,
        totalPrice: (orderJsonResponse['total_price'] as num).toDouble(),
        currency: orderJsonResponse['currency'] as String? ?? 'TRY',
        status: OrderStatus.fromString(orderJsonResponse['status'] as String),
        buyerNote: orderJsonResponse['buyer_note'] as String?,
        sellerNote: orderJsonResponse['seller_note'] as String?,
        confirmedAt: orderJsonResponse['confirmed_at'] != null
            ? DateTime.parse(orderJsonResponse['confirmed_at'] as String)
            : null,
        cancelledAt: orderJsonResponse['cancelled_at'] != null
            ? DateTime.parse(orderJsonResponse['cancelled_at'] as String)
            : null,
        cancelledBy: orderJsonResponse['cancelled_by'] as String?,
        cancellationReason: orderJsonResponse['cancellation_reason'] as String?,
        completedAt: orderJsonResponse['completed_at'] != null
            ? DateTime.parse(orderJsonResponse['completed_at'] as String)
            : null,
        createdAt: DateTime.parse(orderJsonResponse['created_at'] as String),
        updatedAt: orderJsonResponse['updated_at'] != null
            ? DateTime.parse(orderJsonResponse['updated_at'] as String)
            : null,
          updatedBy: orderJsonResponse['updated_by'] as String?,
          updatedByName: updatedByJson != null
              ? '${updatedByJson['first_name'] ?? ''} ${updatedByJson['last_name'] ?? ''}'.trim()
              : null,
          updatedByAvatarUrl: updatedByJson?['avatar_url'] as String?,
          selectedSize: orderJsonResponse['selected_size'] as String?,
      );
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

      final Map<String, dynamic> orderJson = response;
      final buyerJson = orderJson['buyer'] as Map<String, dynamic>?;
      final sellerJson = orderJson['seller'] as Map<String, dynamic>?;
      final updatedByJson = orderJson['updated_by_user'] as Map<String, dynamic>?;

      return OrderModel(
        id: orderJson['id'] as String,
        listingId: orderJson['listing_id'] as String,
        buyerId: orderJson['buyer_id'] as String,
        buyerName: buyerJson != null
            ? '${buyerJson['first_name'] ?? ''} ${buyerJson['last_name'] ?? ''}'.trim()
            : null,
        buyerAvatarUrl: buyerJson?['avatar_url'] as String?,
        sellerId: orderJson['seller_id'] as String?,
        sellerName: sellerJson != null
            ? '${sellerJson['first_name'] ?? ''} ${sellerJson['last_name'] ?? ''}'.trim()
            : null,
        sellerAvatarUrl: sellerJson?['avatar_url'] as String?,
        quantity: orderJson['quantity'] as int? ?? 1,
        totalPrice: (orderJson['total_price'] as num).toDouble(),
        currency: orderJson['currency'] as String? ?? 'TRY',
        status: OrderStatus.fromString(orderJson['status'] as String),
        buyerNote: orderJson['buyer_note'] as String?,
        sellerNote: orderJson['seller_note'] as String?,
        confirmedAt: orderJson['confirmed_at'] != null
            ? DateTime.parse(orderJson['confirmed_at'] as String)
            : null,
        cancelledAt: orderJson['cancelled_at'] != null
            ? DateTime.parse(orderJson['cancelled_at'] as String)
            : null,
        cancelledBy: orderJson['cancelled_by'] as String?,
        cancellationReason: orderJson['cancellation_reason'] as String?,
        completedAt: orderJson['completed_at'] != null
            ? DateTime.parse(orderJson['completed_at'] as String)
            : null,
        createdAt: DateTime.parse(orderJson['created_at'] as String),
        updatedAt: orderJson['updated_at'] != null
            ? DateTime.parse(orderJson['updated_at'] as String)
            : null,
        updatedBy: orderJson['updated_by'] as String?,
        updatedByName: updatedByJson != null
            ? '${updatedByJson['first_name'] ?? ''} ${updatedByJson['last_name'] ?? ''}'.trim()
            : null,
        updatedByAvatarUrl: updatedByJson?['avatar_url'] as String?,
        selectedSize: orderJson['selected_size'] as String?,
      );
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
      return data.map((json) {
        final orderJson = json as Map<String, dynamic>;
        final buyerJson = orderJson['buyer'] as Map<String, dynamic>?;
        final sellerJson = orderJson['seller'] as Map<String, dynamic>?;
        final updatedByJson = orderJson['updated_by_user'] as Map<String, dynamic>?;

        return OrderModel(
          id: orderJson['id'] as String,
          listingId: orderJson['listing_id'] as String,
          buyerId: orderJson['buyer_id'] as String,
          buyerName: buyerJson != null
              ? '${buyerJson['first_name'] ?? ''} ${buyerJson['last_name'] ?? ''}'.trim()
              : null,
          buyerAvatarUrl: buyerJson?['avatar_url'] as String?,
          sellerId: orderJson['seller_id'] as String?,
          sellerName: sellerJson != null
              ? '${sellerJson['first_name'] ?? ''} ${sellerJson['last_name'] ?? ''}'.trim()
              : null,
          sellerAvatarUrl: sellerJson?['avatar_url'] as String?,
          quantity: orderJson['quantity'] as int? ?? 1,
          totalPrice: (orderJson['total_price'] as num).toDouble(),
          currency: orderJson['currency'] as String? ?? 'TRY',
          status: OrderStatus.fromString(orderJson['status'] as String),
          buyerNote: orderJson['buyer_note'] as String?,
          sellerNote: orderJson['seller_note'] as String?,
          confirmedAt: orderJson['confirmed_at'] != null
              ? DateTime.parse(orderJson['confirmed_at'] as String)
              : null,
          cancelledAt: orderJson['cancelled_at'] != null
              ? DateTime.parse(orderJson['cancelled_at'] as String)
              : null,
          cancelledBy: orderJson['cancelled_by'] as String?,
          cancellationReason: orderJson['cancellation_reason'] as String?,
          completedAt: orderJson['completed_at'] != null
              ? DateTime.parse(orderJson['completed_at'] as String)
              : null,
          createdAt: DateTime.parse(orderJson['created_at'] as String),
          updatedAt: orderJson['updated_at'] != null
              ? DateTime.parse(orderJson['updated_at'] as String)
              : null,
          updatedBy: orderJson['updated_by'] as String?,
          updatedByName: updatedByJson != null
              ? '${updatedByJson['first_name'] ?? ''} ${updatedByJson['last_name'] ?? ''}'.trim()
              : null,
          updatedByAvatarUrl: updatedByJson?['avatar_url'] as String?,
          selectedSize: orderJson['selected_size'] as String?,
        );
      }).toList();
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
      return data.map((json) {
        final orderJson = json as Map<String, dynamic>;
        final buyerJson = orderJson['buyer'] as Map<String, dynamic>?;
        final sellerJson = orderJson['seller'] as Map<String, dynamic>?;
        final updatedByJson = orderJson['updated_by_user'] as Map<String, dynamic>?;

        return OrderModel(
          id: orderJson['id'] as String,
          listingId: orderJson['listing_id'] as String,
          buyerId: orderJson['buyer_id'] as String,
          buyerName: buyerJson != null
              ? '${buyerJson['first_name'] ?? ''} ${buyerJson['last_name'] ?? ''}'.trim()
              : null,
          buyerAvatarUrl: buyerJson?['avatar_url'] as String?,
          sellerId: orderJson['seller_id'] as String?,
          sellerName: sellerJson != null
              ? '${sellerJson['first_name'] ?? ''} ${sellerJson['last_name'] ?? ''}'.trim()
              : null,
          sellerAvatarUrl: sellerJson?['avatar_url'] as String?,
          quantity: orderJson['quantity'] as int? ?? 1,
          totalPrice: (orderJson['total_price'] as num).toDouble(),
          currency: orderJson['currency'] as String? ?? 'TRY',
          status: OrderStatus.fromString(orderJson['status'] as String),
          buyerNote: orderJson['buyer_note'] as String?,
          sellerNote: orderJson['seller_note'] as String?,
          confirmedAt: orderJson['confirmed_at'] != null
              ? DateTime.parse(orderJson['confirmed_at'] as String)
              : null,
          cancelledAt: orderJson['cancelled_at'] != null
              ? DateTime.parse(orderJson['cancelled_at'] as String)
              : null,
          cancelledBy: orderJson['cancelled_by'] as String?,
          cancellationReason: orderJson['cancellation_reason'] as String?,
          completedAt: orderJson['completed_at'] != null
              ? DateTime.parse(orderJson['completed_at'] as String)
              : null,
          createdAt: DateTime.parse(orderJson['created_at'] as String),
          updatedAt: orderJson['updated_at'] != null
              ? DateTime.parse(orderJson['updated_at'] as String)
              : null,
          updatedBy: orderJson['updated_by'] as String?,
          updatedByName: updatedByJson != null
              ? '${updatedByJson['first_name'] ?? ''} ${updatedByJson['last_name'] ?? ''}'.trim()
              : null,
          updatedByAvatarUrl: updatedByJson?['avatar_url'] as String?,
          selectedSize: orderJson['selected_size'] as String?,
        );
      }).toList();
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

      final Map<String, dynamic> orderJson = response;
      final buyerJson = orderJson['buyer'] as Map<String, dynamic>?;
      final sellerJson = orderJson['seller'] as Map<String, dynamic>?;
      final updatedByJson = orderJson['updated_by_user'] as Map<String, dynamic>?;

      return OrderModel(
        id: orderJson['id'] as String,
        listingId: orderJson['listing_id'] as String,
        buyerId: orderJson['buyer_id'] as String,
        buyerName: buyerJson != null
            ? '${buyerJson['first_name'] ?? ''} ${buyerJson['last_name'] ?? ''}'.trim()
            : null,
        buyerAvatarUrl: buyerJson?['avatar_url'] as String?,
        sellerId: orderJson['seller_id'] as String?,
        sellerName: sellerJson != null
            ? '${sellerJson['first_name'] ?? ''} ${sellerJson['last_name'] ?? ''}'.trim()
            : null,
        sellerAvatarUrl: sellerJson?['avatar_url'] as String?,
        quantity: orderJson['quantity'] as int? ?? 1,
        totalPrice: (orderJson['total_price'] as num).toDouble(),
        currency: orderJson['currency'] as String? ?? 'TRY',
        status: OrderStatus.fromString(orderJson['status'] as String),
        buyerNote: orderJson['buyer_note'] as String?,
        sellerNote: orderJson['seller_note'] as String?,
        confirmedAt: orderJson['confirmed_at'] != null
            ? DateTime.parse(orderJson['confirmed_at'] as String)
            : null,
        cancelledAt: orderJson['cancelled_at'] != null
            ? DateTime.parse(orderJson['cancelled_at'] as String)
            : null,
        cancelledBy: orderJson['cancelled_by'] as String?,
        cancellationReason: orderJson['cancellation_reason'] as String?,
        completedAt: orderJson['completed_at'] != null
            ? DateTime.parse(orderJson['completed_at'] as String)
            : null,
        createdAt: DateTime.parse(orderJson['created_at'] as String),
        updatedAt: orderJson['updated_at'] != null
            ? DateTime.parse(orderJson['updated_at'] as String)
            : null,
        updatedBy: orderJson['updated_by'] as String?,
        updatedByName: updatedByJson != null
            ? '${updatedByJson['first_name'] ?? ''} ${updatedByJson['last_name'] ?? ''}'.trim()
            : null,
        updatedByAvatarUrl: updatedByJson?['avatar_url'] as String?,
        selectedSize: orderJson['selected_size'] as String?,
      );
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
      return data.map((json) {
        final orderJson = json as Map<String, dynamic>;
        final buyerJson = orderJson['buyer'] as Map<String, dynamic>?;
        final sellerJson = orderJson['seller'] as Map<String, dynamic>?;
        final updatedByJson = orderJson['updated_by_user'] as Map<String, dynamic>?;

        return OrderModel(
          id: orderJson['id'] as String,
          listingId: orderJson['listing_id'] as String,
          buyerId: orderJson['buyer_id'] as String,
          buyerName: buyerJson != null
              ? '${buyerJson['first_name'] ?? ''} ${buyerJson['last_name'] ?? ''}'.trim()
              : null,
          buyerAvatarUrl: buyerJson?['avatar_url'] as String?,
          sellerId: orderJson['seller_id'] as String?,
          sellerName: sellerJson != null
              ? '${sellerJson['first_name'] ?? ''} ${sellerJson['last_name'] ?? ''}'.trim()
              : null,
          sellerAvatarUrl: sellerJson?['avatar_url'] as String?,
          quantity: orderJson['quantity'] as int? ?? 1,
          totalPrice: (orderJson['total_price'] as num).toDouble(),
          currency: orderJson['currency'] as String? ?? 'TRY',
          status: OrderStatus.fromString(orderJson['status'] as String),
          buyerNote: orderJson['buyer_note'] as String?,
          sellerNote: orderJson['seller_note'] as String?,
          confirmedAt: orderJson['confirmed_at'] != null
              ? DateTime.parse(orderJson['confirmed_at'] as String)
              : null,
          cancelledAt: orderJson['cancelled_at'] != null
              ? DateTime.parse(orderJson['cancelled_at'] as String)
              : null,
          cancelledBy: orderJson['cancelled_by'] as String?,
          cancellationReason: orderJson['cancellation_reason'] as String?,
          completedAt: orderJson['completed_at'] != null
              ? DateTime.parse(orderJson['completed_at'] as String)
              : null,
          createdAt: DateTime.parse(orderJson['created_at'] as String),
          updatedAt: orderJson['updated_at'] != null
              ? DateTime.parse(orderJson['updated_at'] as String)
              : null,
          updatedBy: orderJson['updated_by'] as String?,
          updatedByName: updatedByJson != null
              ? '${updatedByJson['first_name'] ?? ''} ${updatedByJson['last_name'] ?? ''}'.trim()
              : null,
          updatedByAvatarUrl: updatedByJson?['avatar_url'] as String?,
          selectedSize: orderJson['selected_size'] as String?,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Siparişler alınamadı: $e');
    }
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
      final response = await _supabase
          .from('listing_stock_by_size')
          .select('size, quantity')
          .eq('listing_id', listingId);

      final Map<String, int> stockBySize = {};
      for (final row in response) {
        stockBySize[row['size'] as String] = row['quantity'] as int;
      }
      return stockBySize;
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Beden bazlı stok alınamadı: $e');
    }
  }

  @override
  Future<void> updateStockBySize(String listingId, Map<String, int> stockBySize) async {
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
      if (stockBySize.isNotEmpty) {
        final inserts = stockBySize.entries.map((entry) => {
          'listing_id': listingId,
          'size': entry.key,
          'quantity': entry.value,
        }).toList();

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
}
