/// Chat Room Model - Supabase JSON mapping
class ChatRoomModel {
  final String id;
  final String name;
  final String? description;
  final String roomType;
  final String? eventId;
  final String? trainingGroupId;
  final String? avatarUrl;
  final bool isActive;
  final bool isReadOnly;
  final DateTime? readOnlyAt;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int memberCount;
  final ChatMessageModel? lastMessage;

  const ChatRoomModel({
    required this.id,
    required this.name,
    this.description,
    required this.roomType,
    this.eventId,
    this.trainingGroupId,
    this.avatarUrl,
    this.isActive = true,
    this.isReadOnly = false,
    this.readOnlyAt,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.memberCount = 0,
    this.lastMessage,
  });

  factory ChatRoomModel.fromJson(Map<String, dynamic> json) {
    return ChatRoomModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      roomType: json['room_type'] as String? ?? 'group',
      eventId: json['event_id'] as String?,
      trainingGroupId: json['training_group_id'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      isReadOnly: json['is_read_only'] as bool? ?? false,
      readOnlyAt: json['read_only_at'] != null
          ? DateTime.parse(json['read_only_at'] as String)
          : null,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      memberCount: json['member_count'] as int? ?? 0,
      lastMessage: json['last_message'] != null
          ? ChatMessageModel.fromJson(json['last_message'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'room_type': roomType,
      'event_id': eventId,
      'training_group_id': trainingGroupId,
      'avatar_url': avatarUrl,
      'is_active': isActive,
      'is_read_only': isReadOnly,
      'created_by': createdBy,
    };
  }

  ChatRoomModel copyWith({
    String? id,
    String? name,
    String? description,
    String? roomType,
    String? eventId,
    String? trainingGroupId,
    String? avatarUrl,
    bool? isActive,
    bool? isReadOnly,
    DateTime? readOnlyAt,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? memberCount,
    ChatMessageModel? lastMessage,
  }) {
    return ChatRoomModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      roomType: roomType ?? this.roomType,
      eventId: eventId ?? this.eventId,
      trainingGroupId: trainingGroupId ?? this.trainingGroupId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isActive: isActive ?? this.isActive,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      readOnlyAt: readOnlyAt ?? this.readOnlyAt,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      memberCount: memberCount ?? this.memberCount,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}

/// Chat Message Model - Supabase JSON mapping
class ChatMessageModel {
  final String id;
  final String roomId;
  final String? senderId;
  final String? senderName;
  final String? senderAvatarUrl;
  final String messageType;
  final String content;
  final String? imageUrl;
  final String? replyToId;
  final ChatMessageModel? replyTo;
  final bool isEdited;
  final DateTime? editedAt;
  final bool isDeleted;
  final DateTime? deletedAt;
  final DateTime createdAt;

  const ChatMessageModel({
    required this.id,
    required this.roomId,
    this.senderId,
    this.senderName,
    this.senderAvatarUrl,
    this.messageType = 'text',
    required this.content,
    this.imageUrl,
    this.replyToId,
    this.replyTo,
    this.isEdited = false,
    this.editedAt,
    this.isDeleted = false,
    this.deletedAt,
    required this.createdAt,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    // Sender bilgilerini nested object'ten al
    final senderData = json['sender'] as Map<String, dynamic>?;
    final senderName = senderData != null
        ? '${senderData['first_name'] ?? ''} ${senderData['last_name'] ?? ''}'.trim()
        : null;

    return ChatMessageModel(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      senderId: json['sender_id'] as String?,
      senderName: senderName?.isEmpty == true ? 'Anonim' : senderName,
      senderAvatarUrl: senderData?['avatar_url'] as String?,
      messageType: json['message_type'] as String? ?? 'text',
      content: json['content'] as String,
      imageUrl: json['image_url'] as String?,
      replyToId: json['reply_to_id'] as String?,
      replyTo: json['reply_to'] != null
          ? ChatMessageModel.fromJson(json['reply_to'] as Map<String, dynamic>)
          : null,
      isEdited: json['is_edited'] as bool? ?? false,
      editedAt: json['edited_at'] != null
          ? DateTime.parse(json['edited_at'] as String)
          : null,
      isDeleted: json['is_deleted'] as bool? ?? false,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'room_id': roomId,
      'sender_id': senderId,
      'message_type': messageType,
      'content': content,
      'image_url': imageUrl,
      'reply_to_id': replyToId,
    };
  }

  /// Mesaj sistemden mi gelmiş (otomatik mesaj)
  bool get isSystemMessage => messageType == 'system';

  /// Mesaj duyuru mu
  bool get isAnnouncement => messageType == 'announcement';

  /// Mesaj resim içeriyor mu
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  /// Mesaj silinmiş mi
  bool get isMessageDeleted => isDeleted;

  /// Formatlı zaman
  String get formattedTime {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(createdAt.year, createdAt.month, createdAt.day);

    if (messageDate == today) {
      return '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Dün ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    } else {
      return '${createdAt.day}/${createdAt.month} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    }
  }
}

/// Chat Room Member Model
class ChatRoomMemberModel {
  final String id;
  final String roomId;
  final String userId;
  final String? userName;
  final String? userAvatarUrl;
  final bool isMuted;
  final DateTime lastReadAt;
  final DateTime joinedAt;

  const ChatRoomMemberModel({
    required this.id,
    required this.roomId,
    required this.userId,
    this.userName,
    this.userAvatarUrl,
    this.isMuted = false,
    required this.lastReadAt,
    required this.joinedAt,
  });

  factory ChatRoomMemberModel.fromJson(Map<String, dynamic> json) {
    // User bilgilerini nested object'ten al
    final userData = json['users'] as Map<String, dynamic>?;
    final userName = userData != null
        ? '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''}'.trim()
        : null;

    return ChatRoomMemberModel(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      userId: json['user_id'] as String,
      userName: userName?.isEmpty == true ? 'Anonim' : userName,
      userAvatarUrl: userData?['avatar_url'] as String?,
      isMuted: json['is_muted'] as bool? ?? false,
      lastReadAt: DateTime.parse(json['last_read_at'] as String),
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }
}

/// Enum for chat room types
enum ChatRoomType {
  lobby,
  group,
  event,
  direct,
  anonymousQa;

  String get value {
    switch (this) {
      case ChatRoomType.lobby:
        return 'lobby';
      case ChatRoomType.group:
        return 'group';
      case ChatRoomType.event:
        return 'event';
      case ChatRoomType.direct:
        return 'direct';
      case ChatRoomType.anonymousQa:
        return 'anonymous_qa';
    }
  }

  String get displayName {
    switch (this) {
      case ChatRoomType.lobby:
        return 'Lobi';
      case ChatRoomType.group:
        return 'Grup';
      case ChatRoomType.event:
        return 'Etkinlik';
      case ChatRoomType.direct:
        return 'Direkt Mesaj';
      case ChatRoomType.anonymousQa:
        return 'Anonim Soru-Cevap';
    }
  }

  static ChatRoomType fromString(String value) {
    switch (value) {
      case 'lobby':
        return ChatRoomType.lobby;
      case 'group':
        return ChatRoomType.group;
      case 'event':
        return ChatRoomType.event;
      case 'direct':
        return ChatRoomType.direct;
      case 'anonymous_qa':
        return ChatRoomType.anonymousQa;
      default:
        return ChatRoomType.group;
    }
  }
}

/// Enum for message types
enum MessageType {
  text,
  image,
  system,
  announcement;

  String get value {
    switch (this) {
      case MessageType.text:
        return 'text';
      case MessageType.image:
        return 'image';
      case MessageType.system:
        return 'system';
      case MessageType.announcement:
        return 'announcement';
    }
  }

  static MessageType fromString(String value) {
    switch (value) {
      case 'text':
        return MessageType.text;
      case 'image':
        return MessageType.image;
      case 'system':
        return MessageType.system;
      case 'announcement':
        return MessageType.announcement;
      default:
        return MessageType.text;
    }
  }
}
