import '../../domain/entities/post_entity.dart';
import 'post_block_model.dart';

/// Post Model - Supabase JSON mapping
class PostModel {
  final String id;
  final String userId;
  final String? userName;
  final String? userAvatarUrl;
  final String title;
  final String? coverImageUrl;
  final bool isPublished;
  final List<PostBlockModel> blocks;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isPinned;
  final DateTime? pinnedAt;
  final String? eventId;

  const PostModel({
    required this.id,
    required this.userId,
    this.userName,
    this.userAvatarUrl,
    required this.title,
    this.coverImageUrl,
    this.isPublished = true,
    this.blocks = const [],
    required this.createdAt,
    this.updatedAt,
    this.isPinned = false,
    this.pinnedAt,
    this.eventId,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) {
    final blocksJson = json['post_blocks'] as List<dynamic>?;
    final blocks = blocksJson != null
        ? blocksJson
            .map((b) => PostBlockModel.fromJson(b as Map<String, dynamic>))
            .toList()
        : <PostBlockModel>[];

    return PostModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String?,
      userAvatarUrl: json['avatar_url'] as String?,
      title: json['title'] as String,
      coverImageUrl: json['cover_image_url'] as String?,
      isPublished: json['is_published'] as bool? ?? true,
      blocks: blocks,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      isPinned: json['is_pinned'] as bool? ?? false,
      pinnedAt: json['pinned_at'] != null
          ? DateTime.parse(json['pinned_at'] as String)
          : null,
      eventId: json['event_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'title': title,
      'cover_image_url': coverImageUrl,
      'is_published': isPublished,
      'is_pinned': isPinned,
      'pinned_at': pinnedAt?.toIso8601String(),
      'event_id': eventId,
    };
  }

  /// Update için kullanılacak JSON (userId hariç)
  Map<String, dynamic> toUpdateJson() {
    return {
      'title': title,
      'cover_image_url': coverImageUrl,
      'is_published': isPublished,
      'is_pinned': isPinned,
      'pinned_at': pinnedAt?.toIso8601String(),
      'event_id': eventId,
    };
  }

  PostEntity toEntity() {
    return PostEntity(
      id: id,
      userId: userId,
      userName: userName ?? 'Anonim',
      userAvatarUrl: userAvatarUrl,
      title: title,
      coverImageUrl: coverImageUrl,
      isPublished: isPublished,
      blocks: blocks.map((b) => b.toEntity()).toList(),
      createdAt: createdAt,
      updatedAt: updatedAt,
      isPinned: isPinned,
      pinnedAt: pinnedAt,
      eventId: eventId,
    );
  }

  factory PostModel.fromEntity(PostEntity entity) {
    return PostModel(
      id: entity.id,
      userId: entity.userId,
      userName: entity.userName,
      userAvatarUrl: entity.userAvatarUrl,
      title: entity.title,
      coverImageUrl: entity.coverImageUrl,
      isPublished: entity.isPublished,
      blocks: entity.blocks.map((b) => PostBlockModel.fromEntity(b)).toList(),
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      isPinned: entity.isPinned,
      pinnedAt: entity.pinnedAt,
      eventId: entity.eventId,
    );
  }
}
