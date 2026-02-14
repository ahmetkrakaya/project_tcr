import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/chat_model.dart';

/// Chat Remote Data Source
abstract class ChatRemoteDataSource {
  /// Kullanıcının chat odalarını getir
  Future<List<ChatRoomModel>> getUserChatRooms();

  /// Event chat odasını getir
  Future<ChatRoomModel?> getEventChatRoom(String eventId);

  /// Chat odasındaki mesajları getir
  Future<List<ChatMessageModel>> getMessages(String roomId, {int limit = 50, int offset = 0});

  /// Yeni mesaj gönder
  Future<ChatMessageModel> sendMessage({
    required String roomId,
    required String content,
    String? imageUrl,
    String? replyToId,
  });

  /// Mesaj sil
  Future<void> deleteMessage(String messageId);

  /// Mesaj düzenle
  Future<ChatMessageModel> editMessage(String messageId, String newContent);

  /// Oda üyelerini getir
  Future<List<ChatRoomMemberModel>> getRoomMembers(String roomId);

  /// Kullanıcı oda üyesi mi kontrol et
  Future<bool> isUserMember(String roomId);

  /// Mesajları okundu olarak işaretle
  Future<void> markMessagesAsRead(String roomId);

  /// Realtime mesaj dinleyici
  Stream<ChatMessageModel> subscribeToMessages(String roomId);

  /// Realtime subscription iptal
  void unsubscribeFromMessages();
}

/// Chat Remote Data Source Implementation
class ChatRemoteDataSourceImpl implements ChatRemoteDataSource {
  final SupabaseClient _supabase;
  RealtimeChannel? _messageChannel;

  ChatRemoteDataSourceImpl(this._supabase);

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  @override
  Future<List<ChatRoomModel>> getUserChatRooms() async {
    try {
      final userId = _currentUserId;
      if (userId == null) throw ServerException(message: 'Kullanıcı giriş yapmamış');

      // Kullanıcının üye olduğu odaları bul
      final memberResponse = await _supabase
          .from('chat_room_members')
          .select('room_id')
          .eq('user_id', userId);

      final roomIds = (memberResponse as List<dynamic>)
          .map((e) => e['room_id'] as String)
          .toList();

      if (roomIds.isEmpty) return [];

      // Odaları getir
      final roomsResponse = await _supabase
          .from('chat_rooms')
          .select()
          .inFilter('id', roomIds)
          .eq('is_active', true)
          .order('updated_at', ascending: false);

      final List<dynamic> roomsData = roomsResponse as List<dynamic>;

      // Her oda için üye sayısı ve son mesajı al
      return Future.wait(roomsData.map((json) async {
        final roomId = json['id'] as String;
        final memberCount = await _getMemberCount(roomId);
        final lastMessage = await _getLastMessage(roomId);

        return ChatRoomModel.fromJson({
          ...json as Map<String, dynamic>,
          'member_count': memberCount,
          'last_message': lastMessage,
        });
      }));
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Chat odaları alınamadı: $e');
    }
  }

  @override
  Future<ChatRoomModel?> getEventChatRoom(String eventId) async {
    try {
      // Önce mevcut chat odasını ara (birden fazla varsa ilkini al)
      final existingRooms = await _supabase
          .from('chat_rooms')
          .select()
          .eq('event_id', eventId)
          .eq('room_type', 'event')
          .order('created_at', ascending: true)
          .limit(1);

      Map<String, dynamic>? response;
      
      if (existingRooms.isNotEmpty) {
        response = existingRooms.first;
      } else {
        // Chat odası yoksa oluştur
        final userId = _currentUserId;
        if (userId == null) {
          throw ServerException(message: 'Kullanıcı giriş yapmamış');
        }

        // Event bilgilerini al
        final eventResponse = await _supabase
            .from('events')
            .select('title, status, created_by')
            .eq('id', eventId)
            .maybeSingle();

        if (eventResponse == null) {
          throw ServerException(message: 'Etkinlik bulunamadı');
        }

        // Sadece published event'ler için chat odası oluştur
        if (eventResponse['status'] != 'published') {
          return null;
        }

        // Chat odası oluştur
        final createResponse = await _supabase
            .from('chat_rooms')
            .insert({
              'name': '${eventResponse['title']} - Etkinlik Sohbeti',
              'room_type': 'event',
              'event_id': eventId,
              'created_by': eventResponse['created_by'],
            })
            .select()
            .maybeSingle();

        if (createResponse == null) {
          throw ServerException(message: 'Chat odası oluşturulamadı');
        }

        response = createResponse;
      }

      final roomId = response['id'] as String;
      
      // Kullanıcıyı odaya ekle (yoksa)
      final userId = _currentUserId;
      if (userId != null) {
        try {
          await _supabase
              .from('chat_room_members')
              .upsert({
                'room_id': roomId,
                'user_id': userId,
              }, onConflict: 'room_id,user_id');
        } catch (e) {
          throw ServerException(message: 'Chat room member ekleme hatası: $e');
        }
      }

      final memberCount = await _getMemberCount(roomId);

      return ChatRoomModel.fromJson({
        ...response,
        'member_count': memberCount,
      });
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException(message: 'Event chat odası alınamadı: $e');
    }
  }

  @override
  Future<List<ChatMessageModel>> getMessages(String roomId, {int limit = 50, int offset = 0}) async {
    try {
      final response = await _supabase
          .from('chat_messages')
          .select('''
            *,
            sender:users!chat_messages_sender_id_fkey(
              first_name,
              last_name,
              avatar_url
            )
          ''')
          .eq('room_id', roomId)
          .eq('is_deleted', false)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final List<dynamic> data = response as List<dynamic>;
      
      // Mesajları en eskiden en yeniye sırala (UI için)
      final messages = data
          .map((json) => ChatMessageModel.fromJson(json as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();

      return messages;
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Mesajlar alınamadı: $e');
    }
  }

  @override
  Future<ChatMessageModel> sendMessage({
    required String roomId,
    required String content,
    String? imageUrl,
    String? replyToId,
  }) async {
    try {
      final userId = _currentUserId;
      if (userId == null) throw ServerException(message: 'Kullanıcı giriş yapmamış');

      // Önce odanın salt okunur olup olmadığını kontrol et
      final room = await _supabase
          .from('chat_rooms')
          .select('is_read_only, event_id')
          .eq('id', roomId)
          .single();

      if (room['is_read_only'] == true) {
        throw ServerException(message: 'Bu sohbet odası artık salt okunur.');
      }

      // Event chat odası ise, etkinlik tarihini kontrol et
      if (room['event_id'] != null) {
        final event = await _supabase
            .from('events')
            .select('end_time, start_time')
            .eq('id', room['event_id'])
            .single();

        final eventEndTime = event['end_time'] != null
            ? DateTime.parse(event['end_time'] as String)
            : DateTime.parse(event['start_time'] as String).add(const Duration(hours: 2));

        // Etkinlik bittikten 1 gün sonra mesaj gönderilemez
        if (DateTime.now().isAfter(eventEndTime.add(const Duration(days: 1)))) {
          throw ServerException(message: 'Etkinlik sona erdikten 1 gün sonra mesaj gönderilemez.');
        }
      }

      // Kullanıcının odaya üye olduğunu kontrol et
      final isMember = await isUserMember(roomId);
      if (!isMember) {
        throw ServerException(message: 'Bu odaya mesaj gönderme yetkiniz yok.');
      }

      final response = await _supabase
          .from('chat_messages')
          .insert({
            'room_id': roomId,
            'sender_id': userId,
            'content': content,
            'message_type': imageUrl != null ? 'image' : 'text',
            'image_url': imageUrl,
            'reply_to_id': replyToId,
          })
          .select('''
            *,
            sender:users!chat_messages_sender_id_fkey(
              first_name,
              last_name,
              avatar_url
            )
          ''')
          .single();

      // Odanın updated_at'ini güncelle
      await _supabase
          .from('chat_rooms')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', roomId);

      return ChatMessageModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException(message: 'Mesaj gönderilemedi: $e');
    }
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    try {
      final userId = _currentUserId;
      if (userId == null) throw ServerException(message: 'Kullanıcı giriş yapmamış');

      // Mesajın sahibi mi kontrol et
      final message = await _supabase
          .from('chat_messages')
          .select('sender_id')
          .eq('id', messageId)
          .single();

      if (message['sender_id'] != userId) {
        throw ServerException(message: 'Sadece kendi mesajınızı silebilirsiniz.');
      }

      await _supabase
          .from('chat_messages')
          .update({
            'is_deleted': true,
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', messageId);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException(message: 'Mesaj silinemedi: $e');
    }
  }

  @override
  Future<ChatMessageModel> editMessage(String messageId, String newContent) async {
    try {
      final userId = _currentUserId;
      if (userId == null) throw ServerException(message: 'Kullanıcı giriş yapmamış');

      // Mesajın sahibi mi kontrol et
      final message = await _supabase
          .from('chat_messages')
          .select('sender_id')
          .eq('id', messageId)
          .single();

      if (message['sender_id'] != userId) {
        throw ServerException(message: 'Sadece kendi mesajınızı düzenleyebilirsiniz.');
      }

      final response = await _supabase
          .from('chat_messages')
          .update({
            'content': newContent,
            'is_edited': true,
            'edited_at': DateTime.now().toIso8601String(),
          })
          .eq('id', messageId)
          .select('''
            *,
            sender:users!chat_messages_sender_id_fkey(
              first_name,
              last_name,
              avatar_url
            )
          ''')
          .single();

      return ChatMessageModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException(message: 'Mesaj düzenlenemedi: $e');
    }
  }

  @override
  Future<List<ChatRoomMemberModel>> getRoomMembers(String roomId) async {
    try {
      final response = await _supabase
          .from('chat_room_members')
          .select('''
            *,
            users!inner(first_name, last_name, avatar_url)
          ''')
          .eq('room_id', roomId)
          .order('joined_at', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      return data
          .map((json) => ChatRoomMemberModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message, code: e.code);
    } catch (e) {
      throw ServerException(message: 'Oda üyeleri alınamadı: $e');
    }
  }

  @override
  Future<bool> isUserMember(String roomId) async {
    final userId = _currentUserId;
    if (userId == null) return false;

    try {
      final response = await _supabase
          .from('chat_room_members')
          .select()
          .eq('room_id', roomId)
          .eq('user_id', userId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> markMessagesAsRead(String roomId) async {
    try {
      final userId = _currentUserId;
      if (userId == null) return;

      await _supabase
          .from('chat_room_members')
          .update({'last_read_at': DateTime.now().toIso8601String()})
          .eq('room_id', roomId)
          .eq('user_id', userId);
    } catch (e) {
      // Sessizce hata yakala
    }
  }

  @override
  Stream<ChatMessageModel> subscribeToMessages(String roomId) {
    final controller = StreamController<ChatMessageModel>.broadcast();

    _messageChannel = _supabase
        .channel('chat_room_$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) async {
            try {
              // Yeni mesajın tam bilgilerini al
              final messageId = payload.newRecord['id'] as String;
              final response = await _supabase
                  .from('chat_messages')
                  .select('''
                    *,
                    sender:users!chat_messages_sender_id_fkey(
                      first_name,
                      last_name,
                      avatar_url
                    )
                  ''')
                  .eq('id', messageId)
                  .single();

              final message = ChatMessageModel.fromJson(response);
              controller.add(message);
            } catch (e) {
              // Hata durumunda sessizce geç
            }
          },
        )
        .subscribe();

    return controller.stream;
  }

  @override
  void unsubscribeFromMessages() {
    _messageChannel?.unsubscribe();
    _messageChannel = null;
  }

  // Helper methods
  Future<int> _getMemberCount(String roomId) async {
    try {
      final response = await _supabase
          .from('chat_room_members')
          .select()
          .eq('room_id', roomId);

      return (response as List<dynamic>).length;
    } catch (e) {
      return 0;
    }
  }

  Future<Map<String, dynamic>?> _getLastMessage(String roomId) async {
    try {
      final response = await _supabase
          .from('chat_messages')
          .select('''
            *,
            sender:users!chat_messages_sender_id_fkey(
              first_name,
              last_name,
              avatar_url
            )
          ''')
          .eq('room_id', roomId)
          .eq('is_deleted', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return response;
    } catch (e) {
      return null;
    }
  }
}
