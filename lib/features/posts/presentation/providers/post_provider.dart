import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/post_remote_datasource.dart';
import '../../data/models/post_model.dart';
import '../../data/models/post_block_model.dart';
import '../../domain/entities/post_entity.dart';
import '../../domain/entities/post_block_entity.dart';

/// Supabase client provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Post datasource provider
final postDataSourceProvider = Provider<PostRemoteDataSource>((ref) {
  return PostRemoteDataSourceImpl(ref.watch(_supabaseProvider));
});

/// Posts State
class PostsState {
  final List<PostEntity> posts;
  final bool isLoading;
  final String? error;
  final bool hasMore;
  final int offset;

  const PostsState({
    this.posts = const [],
    this.isLoading = false,
    this.error,
    this.hasMore = true,
    this.offset = 0,
  });

  PostsState copyWith({
    List<PostEntity>? posts,
    bool? isLoading,
    String? error,
    bool? hasMore,
    int? offset,
  }) {
    return PostsState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
    );
  }
}

/// Posts Notifier
class PostsNotifier extends StateNotifier<PostsState> {
  final PostRemoteDataSource _dataSource;

  PostsNotifier(this._dataSource) : super(const PostsState());

  Future<void> loadPosts() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final models = await _dataSource.getPosts(limit: 20, offset: 0);
      final posts = models.map((m) => m.toEntity()).toList();

      state = state.copyWith(
        posts: posts,
        isLoading: false,
        hasMore: posts.length >= 20,
        offset: posts.length,
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
      final models = await _dataSource.getPosts(
        limit: 20,
        offset: state.offset,
      );
      final newPosts = models.map((m) => m.toEntity()).toList();

      state = state.copyWith(
        posts: [...state.posts, ...newPosts],
        isLoading: false,
        hasMore: newPosts.length >= 20,
        offset: state.offset + newPosts.length,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    state = const PostsState();
    await loadPosts();
  }

  /// Listeyi yeniden çekmeden yeni postu listenin başına ekler.
  void addPost(PostEntity post) {
    final list = [post, ...state.posts];
    state = state.copyWith(posts: list);
  }

  /// Listeyi yeniden çekmeden ilgili postu listeden kaldırır.
  void removePost(String postId) {
    final list = state.posts.where((p) => p.id != postId).toList();
    state = state.copyWith(
      posts: list,
      offset: list.isEmpty ? 0 : state.offset,
    );
  }

  /// Listeyi yeniden çekmeden ilgili postu güncellenmiş haliyle değiştirir.
  void replacePost(PostEntity post) {
    final list = state.posts
        .map((p) => p.id == post.id ? post : p)
        .toList();
    state = state.copyWith(posts: list);
  }
}

/// Posts Provider
final postsProvider = StateNotifierProvider<PostsNotifier, PostsState>((ref) {
  final dataSource = ref.watch(postDataSourceProvider);
  return PostsNotifier(dataSource);
});

/// Single Post Provider
final postByIdProvider = FutureProvider.family<PostEntity, String>((ref, postId) async {
  final dataSource = ref.watch(postDataSourceProvider);
  final model = await dataSource.getPostById(postId);
  return model.toEntity();
});

/// Post Blocks Provider
final postBlocksProvider = FutureProvider.family<List<PostBlockEntity>, String>((ref, postId) async {
  final dataSource = ref.watch(postDataSourceProvider);
  final models = await dataSource.getPostBlocks(postId);
  return models.map((m) => m.toEntity()).toList();
});

/// Create Post Notifier
class CreatePostNotifier extends StateNotifier<AsyncValue<PostEntity?>> {
  final PostRemoteDataSource _dataSource;

  CreatePostNotifier(this._dataSource) : super(const AsyncValue.data(null));

  Future<void> createPost({
    required String title,
    String? coverImageUrl,
    List<PostBlockModel> blocks = const [],
  }) async {
    state = const AsyncValue.loading();

    try {
      final postModel = PostModel(
        id: '',
        userId: '',
        title: title,
        coverImageUrl: coverImageUrl,
        isPublished: true,
        blocks: blocks,
        createdAt: DateTime.now(),
      );

      final created = await _dataSource.createPost(postModel);
      
      // Blokları oluştur
      for (int i = 0; i < blocks.length; i++) {
        final block = blocks[i].copyWith(
          postId: created.id,
          orderIndex: i,
        );
        await _dataSource.createPostBlock(block);
      }

      // Post'u tekrar getir (bloklarla birlikte)
      final fullPost = await _dataSource.getPostById(created.id);
      state = AsyncValue.data(fullPost.toEntity());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

/// Create Post Provider
final createPostProvider = StateNotifierProvider<CreatePostNotifier, AsyncValue<PostEntity?>>((ref) {
  final dataSource = ref.watch(postDataSourceProvider);
  return CreatePostNotifier(dataSource);
});

/// Post Block Model extension for copyWith
extension PostBlockModelCopyWith on PostBlockModel {
  PostBlockModel copyWith({
    String? id,
    String? postId,
    String? type,
    String? content,
    String? subContent,
    String? imageUrl,
    String? color,
    String? icon,
    int? orderIndex,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PostBlockModel(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      type: type ?? this.type,
      content: content ?? this.content,
      subContent: subContent ?? this.subContent,
      imageUrl: imageUrl ?? this.imageUrl,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      orderIndex: orderIndex ?? this.orderIndex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
