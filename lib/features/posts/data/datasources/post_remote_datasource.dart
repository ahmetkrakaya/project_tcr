import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/post_model.dart';
import '../models/post_block_model.dart';

/// Post Remote Data Source
abstract class PostRemoteDataSource {
  /// Tüm yayınlanmış postları getir
  Future<List<PostModel>> getPosts({int limit = 20, int offset = 0});

  /// Tek bir post getir
  Future<PostModel> getPostById(String id);

  /// event_id ile post getir (etkinlik programından üretilen post)
  Future<PostModel?> getPostByEventId(String eventId);

  /// Post oluştur
  Future<PostModel> createPost(PostModel post);

  /// Post güncelle
  Future<PostModel> updatePost(PostModel post);

  /// Post sil
  Future<void> deletePost(String id);

  /// Post pinle / pin kaldır (sadece admin)
  Future<void> setPostPinned(String postId, bool pinned);

  // ========== Post Blocks ==========

  /// Post bloklarını getir
  Future<List<PostBlockModel>> getPostBlocks(String postId);

  /// Post bloğu oluştur
  Future<PostBlockModel> createPostBlock(PostBlockModel block);

  /// Birden fazla post bloğunu tek istekte oluştur
  Future<List<PostBlockModel>> createPostBlocks(String postId, List<PostBlockModel> blocks);

  /// Post bloğu güncelle
  Future<PostBlockModel> updatePostBlock(PostBlockModel block);

  /// Post bloğu sil
  Future<void> deletePostBlock(String blockId);

  /// Tüm blokları toplu güncelle (sıralama için)
  Future<void> reorderPostBlocks(String postId, List<PostBlockModel> blocks);

  /// Tüm blokları sil
  Future<void> deleteAllPostBlocks(String postId);
}

/// Post Remote Data Source Implementation
class PostRemoteDataSourceImpl implements PostRemoteDataSource {
  final SupabaseClient _supabase;

  PostRemoteDataSourceImpl(this._supabase);

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  @override
  Future<List<PostModel>> getPosts({int limit = 20, int offset = 0}) async {
    try {
      final response = await _supabase
          .from('posts')
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .eq('is_published', true)
          .order('is_pinned', ascending: false)
          .order('pinned_at', ascending: false)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) {
        final postJson = json as Map<String, dynamic>;
        final userJson = postJson['users'] as Map<String, dynamic>;
        
        return PostModel(
          id: postJson['id'] as String,
          userId: postJson['user_id'] as String,
          userName: '${userJson['first_name'] ?? ''} ${userJson['last_name'] ?? ''}'.trim(),
          userAvatarUrl: userJson['avatar_url'] as String?,
          title: postJson['title'] as String,
          coverImageUrl: postJson['cover_image_url'] as String?,
          isPublished: postJson['is_published'] as bool? ?? true,
          blocks: const [],
          createdAt: DateTime.parse(postJson['created_at'] as String),
          updatedAt: postJson['updated_at'] != null
              ? DateTime.parse(postJson['updated_at'] as String)
              : null,
          isPinned: postJson['is_pinned'] as bool? ?? false,
          pinnedAt: postJson['pinned_at'] != null
              ? DateTime.parse(postJson['pinned_at'] as String)
              : null,
          eventId: postJson['event_id'] as String?,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Postlar alınamadı: $e');
    }
  }

  @override
  Future<PostModel> getPostById(String id) async {
    try {
      final response = await _supabase
          .from('posts')
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url),
            post_blocks(*)
          ''')
          .eq('id', id)
          .eq('is_published', true)
          .single();

      final Map<String, dynamic> postJson = response;
      final userJson = postJson['users'] as Map<String, dynamic>;
      final blocksJson = postJson['post_blocks'] as List<dynamic>?;
      
      final blocks = blocksJson != null
          ? blocksJson
              .map((b) => PostBlockModel.fromJson(b as Map<String, dynamic>))
              .toList()
          : <PostBlockModel>[];

      return PostModel(
        id: postJson['id'] as String,
        userId: postJson['user_id'] as String,
        userName: '${userJson['first_name'] ?? ''} ${userJson['last_name'] ?? ''}'.trim(),
        userAvatarUrl: userJson['avatar_url'] as String?,
        title: postJson['title'] as String,
        coverImageUrl: postJson['cover_image_url'] as String?,
        isPublished: postJson['is_published'] as bool? ?? true,
        blocks: blocks,
        createdAt: DateTime.parse(postJson['created_at'] as String),
        updatedAt: postJson['updated_at'] != null
            ? DateTime.parse(postJson['updated_at'] as String)
            : null,
        isPinned: postJson['is_pinned'] as bool? ?? false,
        pinnedAt: postJson['pinned_at'] != null
            ? DateTime.parse(postJson['pinned_at'] as String)
            : null,
        eventId: postJson['event_id'] as String?,
      );
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Post alınamadı: $e');
    }
  }

  @override
  Future<PostModel?> getPostByEventId(String eventId) async {
    try {
      final response = await _supabase
          .from('posts')
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .eq('event_id', eventId)
          .maybeSingle();
      if (response == null) return null;
      final Map<String, dynamic> postJson = response;
      final userJson = postJson['users'] as Map<String, dynamic>;
      return PostModel(
        id: postJson['id'] as String,
        userId: postJson['user_id'] as String,
        userName: '${userJson['first_name'] ?? ''} ${userJson['last_name'] ?? ''}'.trim(),
        userAvatarUrl: userJson['avatar_url'] as String?,
        title: postJson['title'] as String,
        coverImageUrl: postJson['cover_image_url'] as String?,
        isPublished: postJson['is_published'] as bool? ?? true,
        blocks: const [],
        createdAt: DateTime.parse(postJson['created_at'] as String),
        updatedAt: postJson['updated_at'] != null
            ? DateTime.parse(postJson['updated_at'] as String)
            : null,
        isPinned: postJson['is_pinned'] as bool? ?? false,
        pinnedAt: postJson['pinned_at'] != null
            ? DateTime.parse(postJson['pinned_at'] as String)
            : null,
        eventId: postJson['event_id'] as String?,
      );
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Post alınamadı: $e');
    }
  }

  @override
  Future<void> setPostPinned(String postId, bool pinned) async {
    try {
      await _supabase.from('posts').update({
        'is_pinned': pinned,
        'pinned_at': pinned ? DateTime.now().toUtc().toIso8601String() : null,
      }).eq('id', postId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Post pinlenemedi: $e');
    }
  }

  @override
  Future<PostModel> createPost(PostModel post) async {
    try {
      if (_currentUserId == null) {
        throw ServerException(message: 'Kullanıcı giriş yapmamış', code: 'UNAUTHORIZED');
      }

      final response = await _supabase
          .from('posts')
          .insert({
            ...post.toJson(),
            'user_id': _currentUserId,
          })
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .single();

      final Map<String, dynamic> postJson = response;
      final userJson = postJson['users'] as Map<String, dynamic>;

      return PostModel(
        id: postJson['id'] as String,
        userId: postJson['user_id'] as String,
        userName: '${userJson['first_name'] ?? ''} ${userJson['last_name'] ?? ''}'.trim(),
        userAvatarUrl: userJson['avatar_url'] as String?,
        title: postJson['title'] as String,
        coverImageUrl: postJson['cover_image_url'] as String?,
        isPublished: postJson['is_published'] as bool? ?? true,
        blocks: const [],
        createdAt: DateTime.parse(postJson['created_at'] as String),
        updatedAt: postJson['updated_at'] != null
            ? DateTime.parse(postJson['updated_at'] as String)
            : null,
        isPinned: postJson['is_pinned'] as bool? ?? false,
        pinnedAt: postJson['pinned_at'] != null
            ? DateTime.parse(postJson['pinned_at'] as String)
            : null,
        eventId: postJson['event_id'] as String?,
      );
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Post oluşturulamadı: $e');
    }
  }

  @override
  Future<PostModel> updatePost(PostModel post) async {
    try {
      final response = await _supabase
          .from('posts')
          .update(post.toUpdateJson())
          .eq('id', post.id)
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .single();

      final Map<String, dynamic> postJson = response;
      final userJson = postJson['users'] as Map<String, dynamic>;

      return PostModel(
        id: postJson['id'] as String,
        userId: postJson['user_id'] as String,
        userName: '${userJson['first_name'] ?? ''} ${userJson['last_name'] ?? ''}'.trim(),
        userAvatarUrl: userJson['avatar_url'] as String?,
        title: postJson['title'] as String,
        coverImageUrl: postJson['cover_image_url'] as String?,
        isPublished: postJson['is_published'] as bool? ?? true,
        blocks: post.blocks,
        createdAt: DateTime.parse(postJson['created_at'] as String),
        updatedAt: postJson['updated_at'] != null
            ? DateTime.parse(postJson['updated_at'] as String)
            : null,
        isPinned: postJson['is_pinned'] as bool? ?? false,
        pinnedAt: postJson['pinned_at'] != null
            ? DateTime.parse(postJson['pinned_at'] as String)
            : null,
        eventId: postJson['event_id'] as String?,
      );
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Post güncellenemedi: $e');
    }
  }

  @override
  Future<void> deletePost(String id) async {
    try {
      await _supabase
          .from('posts')
          .delete()
          .eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Post silinemedi: $e');
    }
  }

  // ========== Post Blocks Implementation ==========

  @override
  Future<List<PostBlockModel>> getPostBlocks(String postId) async {
    try {
      final response = await _supabase
          .from('post_blocks')
          .select()
          .eq('post_id', postId)
          .order('order_index', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => PostBlockModel.fromJson(json as Map<String, dynamic>)).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Post blokları alınamadı: $e');
    }
  }

  @override
  Future<PostBlockModel> createPostBlock(PostBlockModel block) async {
    try {
      final response = await _supabase
          .from('post_blocks')
          .insert(block.toJson())
          .select()
          .single();

      return PostBlockModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Post bloğu oluşturulamadı: $e');
    }
  }

  @override
  Future<List<PostBlockModel>> createPostBlocks(String postId, List<PostBlockModel> blocks) async {
    if (blocks.isEmpty) return [];
    try {
      final list = blocks.map((b) => b.toJson()).toList();
      final response = await _supabase
          .from('post_blocks')
          .insert(list)
          .select();

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => PostBlockModel.fromJson(json as Map<String, dynamic>)).toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Post blokları oluşturulamadı: $e');
    }
  }

  @override
  Future<PostBlockModel> updatePostBlock(PostBlockModel block) async {
    try {
      final response = await _supabase
          .from('post_blocks')
          .update(block.toJson())
          .eq('id', block.id)
          .select()
          .single();

      return PostBlockModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Post bloğu güncellenemedi: $e');
    }
  }

  @override
  Future<void> deletePostBlock(String blockId) async {
    try {
      await _supabase
          .from('post_blocks')
          .delete()
          .eq('id', blockId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Post bloğu silinemedi: $e');
    }
  }

  @override
  Future<void> reorderPostBlocks(String postId, List<PostBlockModel> blocks) async {
    try {
      // Her bloğu yeni sırasıyla güncelle
      for (int i = 0; i < blocks.length; i++) {
        await _supabase
            .from('post_blocks')
            .update({'order_index': i})
            .eq('id', blocks[i].id);
      }
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Post blokları sıralanamadı: $e');
    }
  }

  @override
  Future<void> deleteAllPostBlocks(String postId) async {
    try {
      await _supabase
          .from('post_blocks')
          .delete()
          .eq('post_id', postId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Post blokları silinemedi: $e');
    }
  }
}
