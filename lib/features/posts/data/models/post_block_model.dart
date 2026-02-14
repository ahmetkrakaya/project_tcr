import '../../domain/entities/post_block_entity.dart';

/// Post Block Model - Supabase JSON mapping
class PostBlockModel {
  final String id;
  final String postId;
  final String type;
  final String content;
  final String? subContent;
  final String? imageUrl;
  final String? color;
  final String? icon;
  final int orderIndex;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const PostBlockModel({
    required this.id,
    required this.postId,
    required this.type,
    required this.content,
    this.subContent,
    this.imageUrl,
    this.color,
    this.icon,
    required this.orderIndex,
    required this.createdAt,
    this.updatedAt,
  });

  factory PostBlockModel.fromJson(Map<String, dynamic> json) {
    return PostBlockModel(
      id: json['id'] as String,
      postId: json['post_id'] as String,
      type: json['type'] as String? ?? 'text',
      content: json['content'] as String? ?? '',
      subContent: json['sub_content'] as String?,
      imageUrl: json['image_url'] as String?,
      color: json['color'] as String?,
      icon: json['icon'] as String?,
      orderIndex: json['order_index'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'post_id': postId,
      'type': type,
      'content': content,
      'sub_content': subContent,
      'image_url': imageUrl,
      'color': color,
      'icon': icon,
      'order_index': orderIndex,
    };
  }

  Map<String, dynamic> toJsonWithId() {
    return {
      'id': id,
      ...toJson(),
    };
  }

  PostBlockEntity toEntity() {
    return PostBlockEntity(
      id: id,
      postId: postId,
      type: PostBlockType.fromString(type),
      content: content,
      subContent: subContent,
      imageUrl: imageUrl,
      color: color,
      icon: icon,
      orderIndex: orderIndex,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory PostBlockModel.fromEntity(PostBlockEntity entity) {
    return PostBlockModel(
      id: entity.id,
      postId: entity.postId,
      type: entity.type.toDbString(),
      content: entity.content,
      subContent: entity.subContent,
      imageUrl: entity.imageUrl,
      color: entity.color,
      icon: entity.icon,
      orderIndex: entity.orderIndex,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

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
