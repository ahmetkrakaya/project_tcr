import 'post_block_entity.dart';

/// Post Entity
class PostEntity {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String title;
  final String? coverImageUrl;
  final bool isPublished;
  final List<PostBlockEntity> blocks;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isPinned;
  final DateTime? pinnedAt;
  final String? eventId;

  const PostEntity({
    required this.id,
    required this.userId,
    required this.userName,
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

  PostEntity copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userAvatarUrl,
    String? title,
    String? coverImageUrl,
    bool? isPublished,
    List<PostBlockEntity>? blocks,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
    DateTime? pinnedAt,
    String? eventId,
  }) {
    return PostEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
      title: title ?? this.title,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      isPublished: isPublished ?? this.isPublished,
      blocks: blocks ?? this.blocks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      eventId: eventId ?? this.eventId,
    );
  }
}
