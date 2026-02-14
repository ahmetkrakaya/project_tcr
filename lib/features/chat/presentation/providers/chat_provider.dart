import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/chat_remote_datasource.dart';
import '../../data/models/chat_model.dart';

/// Supabase client provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Chat datasource provider
final chatDataSourceProvider = Provider<ChatRemoteDataSource>((ref) {
  return ChatRemoteDataSourceImpl(ref.watch(_supabaseProvider));
});

/// Kullanıcının chat odaları (cached)
final userChatRoomsProvider = FutureProvider<List<ChatRoomModel>>((ref) async {
  ref.keepAlive(); // Bellekte tut
  final dataSource = ref.watch(chatDataSourceProvider);
  return dataSource.getUserChatRooms();
});

/// Event chat odası provider (cached)
final eventChatRoomProvider = FutureProvider.family<ChatRoomModel?, String>((ref, eventId) async {
  ref.keepAlive(); // Bellekte tut - sayfa geçişlerinde yeniden yükleme yapma
  final dataSource = ref.watch(chatDataSourceProvider);
  return dataSource.getEventChatRoom(eventId);
});

/// Kullanıcının belirli bir odaya üye olup olmadığını kontrol et (cached)
final isUserMemberProvider = FutureProvider.family<bool, String>((ref, roomId) async {
  ref.keepAlive();
  final dataSource = ref.watch(chatDataSourceProvider);
  return dataSource.isUserMember(roomId);
});

/// Oda üyeleri provider (cached)
final chatRoomMembersProvider = FutureProvider.family<List<ChatRoomMemberModel>, String>((ref, roomId) async {
  ref.keepAlive();
  final dataSource = ref.watch(chatDataSourceProvider);
  return dataSource.getRoomMembers(roomId);
});

/// Event chat prefetch - event detail sayfasında çağrılır
void prefetchEventChat(WidgetRef ref, String eventId) {
  // Chat odası ve yazma yetkisini önceden yükle
  ref.read(eventChatRoomProvider(eventId).future).then((room) {
    if (room != null) {
      // Mesajları da önceden yükle
      ref.read(chatMessagesProvider(room.id));
    }
  }).catchError((_) {}); // Hata olursa sessizce geç
}

/// Chat mesajları state
class ChatMessagesState {
  final List<ChatMessageModel> messages;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  const ChatMessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  ChatMessagesState copyWith({
    List<ChatMessageModel>? messages,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return ChatMessagesState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

/// Chat mesajları notifier
class ChatMessagesNotifier extends StateNotifier<ChatMessagesState> {
  final ChatRemoteDataSource _dataSource;
  // ignore: unused_field - will be used for future features
  final Ref _ref;
  final String roomId;
  StreamSubscription<ChatMessageModel>? _subscription;
  static const int _pageSize = 50;

  ChatMessagesNotifier(this._dataSource, this._ref, this.roomId)
      : super(const ChatMessagesState()) {
    _init();
  }

  Future<void> _init() async {
    await loadMessages();
    _subscribeToNewMessages();
  }

  Future<void> loadMessages() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final messages = await _dataSource.getMessages(roomId, limit: _pageSize);
      state = state.copyWith(
        messages: messages,
        isLoading: false,
        hasMore: messages.length >= _pageSize,
      );

      // Mesajları okundu olarak işaretle
      await _dataSource.markMessagesAsRead(roomId);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadMoreMessages() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final moreMessages = await _dataSource.getMessages(
        roomId,
        limit: _pageSize,
        offset: state.messages.length,
      );

      state = state.copyWith(
        messages: [...moreMessages.reversed, ...state.messages],
        isLoading: false,
        hasMore: moreMessages.length >= _pageSize,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void _subscribeToNewMessages() {
    final stream = _dataSource.subscribeToMessages(roomId);
    _subscription = stream.listen((message) {
      // Kendi gönderdiğimiz mesajları zaten eklediğimiz için kontrol et
      final exists = state.messages.any((m) => m.id == message.id);
      if (!exists) {
        state = state.copyWith(
          messages: [...state.messages, message],
        );
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _dataSource.unsubscribeFromMessages();
    super.dispose();
  }

  void refresh() {
    state = const ChatMessagesState();
    _init();
  }

  /// Geçici mesaj ekle (optimistic UI için)
  void addTempMessage(ChatMessageModel message) {
    state = state.copyWith(
      messages: [...state.messages, message],
    );
  }

  /// Geçici mesajı gerçek mesajla değiştir
  void replaceTempMessage(String tempId, ChatMessageModel realMessage) {
    state = state.copyWith(
      messages: state.messages.map((m) {
        if (m.id == tempId) return realMessage;
        return m;
      }).toList(),
    );
  }

  /// Mesajı kaldır (hata durumunda)
  void removeMessage(String messageId) {
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );
  }
}

/// Chat mesajları provider (cached - sayfa geçişlerinde korunur)
final chatMessagesProvider = StateNotifierProvider.family<ChatMessagesNotifier, ChatMessagesState, String>((ref, roomId) {
  ref.keepAlive(); // Mesajları bellekte tut
  final dataSource = ref.watch(chatDataSourceProvider);
  return ChatMessagesNotifier(dataSource, ref, roomId);
});

/// Mesaj gönderme state
class SendMessageState {
  final bool isSending;
  final String? error;

  const SendMessageState({
    this.isSending = false,
    this.error,
  });
}

/// Mesaj gönderme notifier
class SendMessageNotifier extends StateNotifier<SendMessageState> {
  final ChatRemoteDataSource _dataSource;
  final Ref _ref;

  SendMessageNotifier(this._dataSource, this._ref) : super(const SendMessageState());

  Future<bool> sendMessage({
    required String roomId,
    required String content,
    String? imageUrl,
    String? replyToId,
  }) async {
    if (content.trim().isEmpty && imageUrl == null) return false;

    state = const SendMessageState(isSending: true);

    try {
      final message = await _dataSource.sendMessage(
        roomId: roomId,
        content: content.trim(),
        imageUrl: imageUrl,
        replyToId: replyToId,
      );

      // Mesajı yerel state'e ekle
      final messagesNotifier = _ref.read(chatMessagesProvider(roomId).notifier);
      final currentState = _ref.read(chatMessagesProvider(roomId));
      
      // Mesaj zaten eklenmemişse ekle
      if (!currentState.messages.any((m) => m.id == message.id)) {
        messagesNotifier.state = currentState.copyWith(
          messages: [...currentState.messages, message],
        );
      }

      state = const SendMessageState(isSending: false);
      return true;
    } catch (e) {
      state = SendMessageState(isSending: false, error: e.toString());
      return false;
    }
  }

  /// Optimistic UI için mesaj gönderme - geçici mesaj zaten eklenmiş durumda
  Future<bool> sendMessageOptimistic({
    required String roomId,
    required String content,
    String? imageUrl,
    String? replyToId,
    required String tempId,
  }) async {
    if (content.trim().isEmpty && imageUrl == null) return false;

    try {
      final message = await _dataSource.sendMessage(
        roomId: roomId,
        content: content.trim(),
        imageUrl: imageUrl,
        replyToId: replyToId,
      );

      // Geçici mesajı gerçek mesajla değiştir
      _ref.read(chatMessagesProvider(roomId).notifier).replaceTempMessage(tempId, message);

      return true;
    } catch (e) {
      state = SendMessageState(error: e.toString());
      return false;
    }
  }

  Future<bool> deleteMessage(String messageId, String roomId) async {
    try {
      await _dataSource.deleteMessage(messageId);
      
      // Mesajı yerel state'den kaldır
      final messagesNotifier = _ref.read(chatMessagesProvider(roomId).notifier);
      final currentState = _ref.read(chatMessagesProvider(roomId));
      
      messagesNotifier.state = currentState.copyWith(
        messages: currentState.messages.where((m) => m.id != messageId).toList(),
      );

      return true;
    } catch (e) {
      state = SendMessageState(error: e.toString());
      return false;
    }
  }

  Future<bool> editMessage(String messageId, String newContent, String roomId) async {
    try {
      final updatedMessage = await _dataSource.editMessage(messageId, newContent);
      
      // Mesajı yerel state'de güncelle
      final messagesNotifier = _ref.read(chatMessagesProvider(roomId).notifier);
      final currentState = _ref.read(chatMessagesProvider(roomId));
      
      messagesNotifier.state = currentState.copyWith(
        messages: currentState.messages.map((m) {
          if (m.id == messageId) return updatedMessage;
          return m;
        }).toList(),
      );

      return true;
    } catch (e) {
      state = SendMessageState(error: e.toString());
      return false;
    }
  }

  void clearError() {
    state = const SendMessageState();
  }
}

/// Mesaj gönderme provider
final sendMessageProvider = StateNotifierProvider<SendMessageNotifier, SendMessageState>((ref) {
  final dataSource = ref.watch(chatDataSourceProvider);
  return SendMessageNotifier(dataSource, ref);
});

/// Chat odasının yazılabilir olup olmadığını kontrol eden provider
final canWriteInChatRoomProvider = FutureProvider.family<bool, String>((ref, roomId) async {
  final dataSource = ref.watch(chatDataSourceProvider);
  
  // Önce odayı al
  final rooms = await dataSource.getUserChatRooms();
  final room = rooms.where((r) => r.id == roomId).firstOrNull;
  
  if (room == null) return false;
  if (room.isReadOnly) return false;

  // Event odası ise tarih kontrolü yap
  if (room.eventId != null) {
    final supabase = ref.watch(_supabaseProvider);
    try {
      final event = await supabase
          .from('events')
          .select('end_time, start_time')
          .eq('id', room.eventId!)
          .single();

      final eventEndTime = event['end_time'] != null
          ? DateTime.parse(event['end_time'] as String)
          : DateTime.parse(event['start_time'] as String).add(const Duration(hours: 2));

      // Etkinlik bittikten 1 gün sonra yazılamaz
      if (DateTime.now().isAfter(eventEndTime.add(const Duration(days: 1)))) {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  // Kullanıcı üye mi kontrol et
  return dataSource.isUserMember(roomId);
});

/// Event chat odasının yazılabilir olup olmadığını kontrol eden provider (eventId ile) - cached
final canWriteInEventChatProvider = FutureProvider.family<bool, String>((ref, eventId) async {
  ref.keepAlive();
  final dataSource = ref.watch(chatDataSourceProvider);
  final room = await dataSource.getEventChatRoom(eventId);
  
  if (room == null) return false;
  if (room.isReadOnly) return false;

  // Tarih kontrolü
  final supabase = ref.watch(_supabaseProvider);
  try {
    final event = await supabase
        .from('events')
        .select('end_time, start_time')
        .eq('id', eventId)
        .single();

    final eventEndTime = event['end_time'] != null
        ? DateTime.parse(event['end_time'] as String)
        : DateTime.parse(event['start_time'] as String).add(const Duration(hours: 2));

    // Etkinlik bittikten 1 gün sonra yazılamaz
    if (DateTime.now().isAfter(eventEndTime.add(const Duration(days: 1)))) {
      return false;
    }
  } catch (_) {
    return false;
  }

  // Kullanıcı üye mi kontrol et
  return dataSource.isUserMember(room.id);
});
