import '../../domain/entities/event_info_block_entity.dart';

/// Event Info Block Model - Supabase JSON mapping
class EventInfoBlockModel {
  final String id;
  final String eventId;
  final String type;
  final String content;
  final String? subContent;
  final String? color;
  final String? icon;
  final int orderIndex;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const EventInfoBlockModel({
    required this.id,
    required this.eventId,
    required this.type,
    required this.content,
    this.subContent,
    this.color,
    this.icon,
    required this.orderIndex,
    required this.createdAt,
    this.updatedAt,
  });

  factory EventInfoBlockModel.fromJson(Map<String, dynamic> json) {
    return EventInfoBlockModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      type: json['type'] as String? ?? 'text',
      content: json['content'] as String? ?? '',
      subContent: json['sub_content'] as String?,
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
      'event_id': eventId,
      'type': type,
      'content': content,
      'sub_content': subContent,
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

  EventInfoBlockEntity toEntity() {
    return EventInfoBlockEntity(
      id: id,
      eventId: eventId,
      type: EventInfoBlockType.fromString(type),
      content: content,
      subContent: subContent,
      color: color,
      icon: icon,
      orderIndex: orderIndex,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory EventInfoBlockModel.fromEntity(EventInfoBlockEntity entity) {
    return EventInfoBlockModel(
      id: entity.id,
      eventId: entity.eventId,
      type: entity.type.toDbString(),
      content: entity.content,
      subContent: entity.subContent,
      color: entity.color,
      icon: entity.icon,
      orderIndex: entity.orderIndex,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  EventInfoBlockModel copyWith({
    String? id,
    String? eventId,
    String? type,
    String? content,
    String? subContent,
    String? color,
    String? icon,
    int? orderIndex,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EventInfoBlockModel(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      type: type ?? this.type,
      content: content ?? this.content,
      subContent: subContent ?? this.subContent,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      orderIndex: orderIndex ?? this.orderIndex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
