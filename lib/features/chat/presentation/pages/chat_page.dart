import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/user_avatar.dart';

/// Chat Page - Chat Room List
class ChatPage extends ConsumerWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sohbet'),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                // Search chats
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Gruplar'),
              Tab(text: 'Etkinlikler'),
              Tab(text: 'Soru-Cevap'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildGroupChats(context),
            _buildEventChats(context),
            _buildQASection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupChats(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Lobby - Always on top
        _buildChatRoomCard(
          context,
          roomId: 'lobby',
          name: 'TCR Lobby',
          subtitle: 'Herkesin katılabildiği genel sohbet',
          icon: Icons.public,
          iconColor: AppColors.primary,
          unreadCount: 5,
          lastMessage: 'Ahmet: Yarınki antrenman için hazır mısınız?',
          lastMessageTime: '14:32',
          isLobby: true,
        ),
        const SizedBox(height: 8),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Antrenman Grupları',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.neutral500,
            ),
          ),
        ),
        _buildChatRoomCard(
          context,
          roomId: '10k-group',
          name: '10K Grubu',
          subtitle: '45 üye',
          icon: Icons.directions_run,
          iconColor: AppColors.secondary,
          unreadCount: 0,
          lastMessage: 'Koç Ali: Bu hafta tempo artırıyoruz',
          lastMessageTime: 'Dün',
        ),
        const SizedBox(height: 8),
        _buildChatRoomCard(
          context,
          roomId: '21k-group',
          name: '21K Hazırlık',
          subtitle: '32 üye',
          icon: Icons.emoji_events,
          iconColor: AppColors.warning,
          unreadCount: 12,
          lastMessage: 'Program güncellendi, kontrol edin',
          lastMessageTime: '10:15',
        ),
        const SizedBox(height: 8),
        _buildChatRoomCard(
          context,
          roomId: 'beginners',
          name: 'Yeni Başlayanlar',
          subtitle: '78 üye',
          icon: Icons.school,
          iconColor: AppColors.tertiary,
          unreadCount: 0,
          lastMessage: 'Hoş geldiniz! Sorularınızı çekinmeden sorun',
          lastMessageTime: 'Paz',
        ),
      ],
    );
  }

  Widget _buildEventChats(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Aktif Etkinlik Sohbetleri',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.neutral500,
            ),
          ),
        ),
        _buildEventChatCard(
          context,
          roomId: 'event-1',
          eventName: 'Hafta Sonu Tempo Koşusu',
          date: 'Cumartesi, 25 Ocak',
          participantCount: 24,
          unreadCount: 3,
          lastMessage: 'Hava durumu güzel görünüyor!',
        ),
        const SizedBox(height: 8),
        _buildEventChatCard(
          context,
          roomId: 'event-2',
          eventName: 'Pazar Uzun Koşu',
          date: 'Pazar, 26 Ocak',
          participantCount: 18,
          unreadCount: 0,
          lastMessage: 'Parkur haritasını paylaştım',
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Arşiv (Salt Okunur)',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.neutral500,
            ),
          ),
        ),
        Opacity(
          opacity: 0.6,
          child: _buildEventChatCard(
            context,
            roomId: 'event-old',
            eventName: 'Geçen Hafta Antrenmanı',
            date: '18 Ocak',
            participantCount: 22,
            unreadCount: 0,
            lastMessage: 'Harika bir antrenmandı!',
            isArchived: true,
          ),
        ),
      ],
    );
  }

  Widget _buildQASection(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Ask Anonymous Question
        AppCard(
          gradient: AppColors.primaryGradient,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.help_outline,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Anonim Soru Sor',
                          style: AppTypography.titleSmall.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Koçlara anonim olarak soru sor',
                          style: AppTypography.bodySmall.copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white,
                  ),
                ],
              ),
            ],
          ),
          onTap: () {
            _showAskQuestionDialog(context);
          },
        ),
        const SizedBox(height: 20),
        
        // Featured Questions
        Text(
          'Haftanın Köşesi',
          style: AppTypography.titleMedium,
        ),
        const SizedBox(height: 12),
        _buildQACard(
          question: 'Tempo koşusu yaparken kalp atış hızım ne kadar olmalı?',
          answer: 'Tempo koşularında maksimum kalp atış hızınızın %85-90\'ı...',
          answeredBy: 'Koç Ali',
        ),
        const SizedBox(height: 12),
        _buildQACard(
          question: 'Koşu öncesi ve sonrası beslenme nasıl olmalı?',
          answer: 'Koşudan 2-3 saat önce hafif karbonhidrat ağırlıklı bir öğün...',
          answeredBy: 'Koç Ayşe',
        ),
      ],
    );
  }

  Widget _buildChatRoomCard(
    BuildContext context, {
    required String roomId,
    required String name,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required int unreadCount,
    required String lastMessage,
    required String lastMessageTime,
    bool isLobby = false,
  }) {
    return AppCard(
      onTap: () => context.goNamed(
        RouteNames.chatRoom,
        pathParameters: {'roomId': roomId},
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: AppTypography.titleSmall),
                    if (isLobby) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'GENEL',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.primary,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  lastMessage,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.neutral500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                lastMessageTime,
                style: AppTypography.labelSmall.copyWith(
                  color: unreadCount > 0 ? AppColors.primary : AppColors.neutral400,
                ),
              ),
              const SizedBox(height: 4),
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unreadCount.toString(),
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventChatCard(
    BuildContext context, {
    required String roomId,
    required String eventName,
    required String date,
    required int participantCount,
    required int unreadCount,
    required String lastMessage,
    bool isArchived = false,
  }) {
    return AppCard(
      onTap: () => context.goNamed(
        RouteNames.chatRoom,
        pathParameters: {'roomId': roomId},
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isArchived
                      ? AppColors.neutral200
                      : AppColors.secondaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  date,
                  style: AppTypography.labelSmall.copyWith(
                    color: isArchived ? AppColors.neutral500 : AppColors.secondary,
                  ),
                ),
              ),
              const Spacer(),
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unreadCount.toString(),
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              if (isArchived)
                const Icon(Icons.lock_outline, size: 16, color: AppColors.neutral400),
            ],
          ),
          const SizedBox(height: 8),
          Text(eventName, style: AppTypography.titleSmall),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.people_outline, size: 14, color: AppColors.neutral500),
              const SizedBox(width: 4),
              Text(
                '$participantCount katılımcı',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.neutral500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            lastMessage,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.neutral500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildQACard({
    required String question,
    required String answer,
    required String answeredBy,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  question,
                  style: AppTypography.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            answer,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.neutral600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const UserAvatar(size: 24, name: 'K'),
              const SizedBox(width: 8),
              Text(
                answeredBy,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.coach,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {},
                child: const Text('Devamını Oku'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAskQuestionDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Anonim Soru Sor',
                  style: AppTypography.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sorunuz anonim olarak koçlara iletilecek.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Sorunuzu yazın...',
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Gönder'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
