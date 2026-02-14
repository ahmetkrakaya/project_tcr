import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../data/models/chat_model.dart';
import '../providers/chat_provider.dart';

/// Event Chat Room Page - Etkinlik sohbet odası
class EventChatRoomPage extends ConsumerStatefulWidget {
  final String eventId;

  const EventChatRoomPage({super.key, required this.eventId});

  @override
  ConsumerState<EventChatRoomPage> createState() => _EventChatRoomPageState();
}

class _EventChatRoomPageState extends ConsumerState<EventChatRoomPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _replyToId;
  ChatMessageModel? _replyToMessage;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatRoomAsync = ref.watch(eventChatRoomProvider(widget.eventId));

    return Scaffold(
      appBar: _buildAppBar(chatRoomAsync),
      body: chatRoomAsync.when(
        data: (chatRoom) {
          if (chatRoom == null) {
            return _buildNoChatRoom();
          }
          return _buildChatContent(context, chatRoom);
        },
        loading: () => _buildLoadingSkeleton(),
        error: (error, _) => _buildError(context, error),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AsyncValue<ChatRoomModel?> chatRoomAsync) {
    return AppBar(
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.event, color: AppColors.secondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chatRoomAsync.valueOrNull?.name ?? 'Etkinlik Sohbeti',
                  style: AppTypography.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  chatRoomAsync.isLoading
                      ? 'Yükleniyor...'
                      : '${chatRoomAsync.valueOrNull?.memberCount ?? 0} katılımcı',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.neutral500),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (chatRoomAsync.hasValue && chatRoomAsync.value != null)
          IconButton(
            icon: const Icon(Icons.people_outline),
            onPressed: () => _showMembersSheet(context, chatRoomAsync.value!.id),
          ),
      ],
    );
  }

  Widget _buildNoChatRoom() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: AppColors.neutral400),
          const SizedBox(height: 16),
          Text(
            'Sohbet odası bulunamadı',
            style: AppTypography.titleMedium.copyWith(color: AppColors.neutral600),
          ),
          const SizedBox(height: 8),
          Text(
            'Bu etkinlik için henüz sohbet odası oluşturulmamış.',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.neutral500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    if (isContentNotFoundError(error)) {
      return ContentNotFoundWidget(
        onGoToNotifications: () => context.goNamed(RouteNames.notifications),
        onBack: () => context.pop(),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Bir hata oluştu', style: AppTypography.titleMedium),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () =>
                  ref.invalidate(eventChatRoomProvider(widget.eventId)),
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 6,
            itemBuilder: (context, index) {
              final isMe = index % 3 == 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                  children: [
                    if (!isMe) ...[
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.neutral200,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      width: 150 + (index * 20 % 80),
                      height: 50,
                      decoration: BoxDecoration(
                        color: isMe ? AppColors.primary.withValues(alpha: 0.3) : AppColors.neutral200,
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.neutral200,
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatContent(BuildContext context, ChatRoomModel chatRoom) {
    final messagesState = ref.watch(chatMessagesProvider(chatRoom.id));
    final canWriteAsync = ref.watch(canWriteInEventChatProvider(widget.eventId));
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    ref.listen(chatMessagesProvider(chatRoom.id), (previous, next) {
      if (previous?.messages.length != next.messages.length) {
        _scrollToBottom();
      }
    });

    final canWrite = canWriteAsync.valueOrNull ?? true;

    return Column(
      children: [
        if (chatRoom.isReadOnly)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.warningContainer,
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bu sohbet odası artık salt okunur.',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: messagesState.messages.isEmpty && !messagesState.isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: AppColors.neutral300),
                      const SizedBox(height: 16),
                      Text('Henüz mesaj yok', style: AppTypography.titleMedium.copyWith(color: AppColors.neutral500)),
                      const SizedBox(height: 8),
                      Text('İlk mesajı gönderen siz olun!', style: AppTypography.bodyMedium.copyWith(color: AppColors.neutral400)),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messagesState.messages.length,
                  itemBuilder: (context, index) {
                    final message = messagesState.messages[index];
                    final isMe = message.senderId == currentUserId;
                    final showAvatar = !isMe && (index == 0 || messagesState.messages[index - 1].senderId != message.senderId);

                    return _buildMessageBubble(
                      message: message,
                      isMe: isMe,
                      showAvatar: showAvatar,
                      onReply: canWrite ? () => _setReplyTo(message) : null,
                      onDelete: isMe && canWrite ? () => _deleteMessage(message.id, chatRoom.id) : null,
                    );
                  },
                ),
        ),
        if (_replyToMessage != null) _buildReplyIndicator(),
        if (!chatRoom.isReadOnly && canWrite) _buildMessageInput(chatRoom.id),
      ],
    );
  }

  Widget _buildReplyIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariantLight,
        border: Border(top: BorderSide(color: AppColors.neutral200)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_replyToMessage!.senderName ?? 'Anonim', style: AppTypography.labelMedium.copyWith(color: AppColors.primary)),
                Text(_replyToMessage!.content, style: AppTypography.bodySmall.copyWith(color: AppColors.neutral600), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: _clearReply),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required ChatMessageModel message,
    required bool isMe,
    bool showAvatar = false,
    VoidCallback? onReply,
    VoidCallback? onDelete,
  }) {
    final isTempMessage = message.id.startsWith('temp_');
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onLongPress: () {
          if (onReply != null || onDelete != null) {
            _showMessageOptions(message, onReply, onDelete);
          }
        },
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe && showAvatar) ...[
              UserAvatar(size: 32, name: message.senderName ?? 'A', imageUrl: message.senderAvatarUrl),
              const SizedBox(width: 8),
            ] else if (!isMe) ...[
              const SizedBox(width: 40),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe && showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, left: 12),
                      child: Text(
                        message.senderName ?? 'Anonim',
                        style: AppTypography.labelSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  Opacity(
                    opacity: isTempMessage ? 0.7 : 1.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isMe ? AppColors.primary : AppColors.surfaceVariantLight,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(isMe ? 18 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            message.isMessageDeleted ? 'Bu mesaj silindi' : message.content,
                            style: AppTypography.bodyMedium.copyWith(
                              color: isMe ? Colors.white : AppColors.neutral800,
                              fontStyle: message.isMessageDeleted ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isTempMessage ? 'Gönderiliyor...' : message.formattedTime,
                                style: AppTypography.labelSmall.copyWith(
                                  color: isMe ? Colors.white.withValues(alpha: 0.7) : AppColors.neutral400,
                                  fontSize: 10,
                                ),
                              ),
                              if (message.isEdited) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '(düzenlendi)',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: isMe ? Colors.white.withValues(alpha: 0.7) : AppColors.neutral400,
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput(String roomId) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Mesaj yaz...',
                filled: true,
                fillColor: AppColors.surfaceVariantLight,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              minLines: 1,
              onSubmitted: (_) => _sendMessage(roomId),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _sendMessage(roomId),
            child: CircleAvatar(
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  void _setReplyTo(ChatMessageModel message) {
    setState(() {
      _replyToId = message.id;
      _replyToMessage = message;
    });
  }

  void _clearReply() {
    setState(() {
      _replyToId = null;
      _replyToMessage = null;
    });
  }

  void _sendMessage(String roomId) {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final currentUser = Supabase.instance.client.auth.currentUser;

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMessage = ChatMessageModel(
      id: tempId,
      roomId: roomId,
      senderId: currentUserId,
      senderName: currentUser?.userMetadata?['first_name'] ?? 'Ben',
      messageType: 'text',
      content: content,
      replyToId: _replyToId,
      createdAt: DateTime.now(),
    );

    ref.read(chatMessagesProvider(roomId).notifier).addTempMessage(tempMessage);
    _messageController.clear();
    _clearReply();
    _scrollToBottom();

    ref.read(sendMessageProvider.notifier).sendMessageOptimistic(
      roomId: roomId,
      content: content,
      replyToId: _replyToId,
      tempId: tempId,
    ).then((success) {
      if (!success && mounted) {
        ref.read(chatMessagesProvider(roomId).notifier).removeMessage(tempId);
        final error = ref.read(sendMessageProvider).error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error ?? 'Mesaj gönderilemedi'), backgroundColor: AppColors.error),
        );
      }
    });
  }

  Future<void> _deleteMessage(String messageId, String roomId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mesajı Sil'),
        content: const Text('Bu mesajı silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Sil', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(sendMessageProvider.notifier).deleteMessage(messageId, roomId);
    }
  }

  void _showMessageOptions(ChatMessageModel message, VoidCallback? onReply, VoidCallback? onDelete) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onReply != null)
                ListTile(
                  leading: const Icon(Icons.reply),
                  title: const Text('Yanıtla'),
                  onTap: () {
                    Navigator.pop(context);
                    onReply();
                  },
                ),
              if (onDelete != null)
                ListTile(
                  leading: Icon(Icons.delete, color: AppColors.error),
                  title: Text('Sil', style: TextStyle(color: AppColors.error)),
                  onTap: () {
                    Navigator.pop(context);
                    onDelete();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMembersSheet(BuildContext context, String roomId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) {
          return Consumer(
            builder: (context, ref, child) {
              final membersAsync = ref.watch(chatRoomMembersProvider(roomId));

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Katılımcılar', style: AppTypography.titleLarge),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: membersAsync.when(
                      data: (members) => ListView.builder(
                        controller: scrollController,
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final member = members[index];
                          return ListTile(
                            leading: UserAvatar(size: 44, name: member.userName ?? 'A', imageUrl: member.userAvatarUrl),
                            title: Text(member.userName ?? 'Anonim'),
                          );
                        },
                      ),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (_, __) => const Center(child: Text('Üyeler yüklenemedi')),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
