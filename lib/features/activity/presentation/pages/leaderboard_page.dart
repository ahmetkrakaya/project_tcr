import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/user_avatar.dart';

/// Leaderboard Page
class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key});

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lider Tablosu'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Bu Hafta'),
            Tab(text: 'Bu Ay'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLeaderboardList('weekly'),
          _buildLeaderboardList('monthly'),
        ],
      ),
    );
  }

  Widget _buildLeaderboardList(String period) {
    return CustomScrollView(
      slivers: [
        // Top 3 Podium
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _buildPodium(),
          ),
        ),

        // Rest of the list
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final rank = index + 4;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: _buildLeaderboardItem(rank),
              );
            },
            childCount: 47,
          ),
        ),

        const SliverToBoxAdapter(
          child: SizedBox(height: 20),
        ),
      ],
    );
  }

  Widget _buildPodium() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 2nd Place
        _buildPodiumItem(
          rank: 2,
          name: 'Ayşe K.',
          distance: '78.5 km',
          height: 100,
          color: Colors.grey.shade400,
        ),
        const SizedBox(width: 8),
        // 1st Place
        _buildPodiumItem(
          rank: 1,
          name: 'Mehmet Y.',
          distance: '92.3 km',
          height: 130,
          color: AppColors.warning,
        ),
        const SizedBox(width: 8),
        // 3rd Place
        _buildPodiumItem(
          rank: 3,
          name: 'Ali D.',
          distance: '65.2 km',
          height: 80,
          color: Colors.orange.shade700,
        ),
      ],
    );
  }

  Widget _buildPodiumItem({
    required int rank,
    required String name,
    required String distance,
    required double height,
    required Color color,
  }) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            UserAvatar(
              size: rank == 1 ? 64 : 52,
              name: name,
              showBorder: true,
              borderColor: color,
              borderWidth: 3,
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: AppTypography.labelMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          distance,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.neutral500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 80,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.8),
                color,
              ],
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(8),
            ),
          ),
          child: Center(
            child: Icon(
              rank == 1 ? Icons.emoji_events : Icons.military_tech,
              color: Colors.white,
              size: rank == 1 ? 32 : 24,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardItem(int rank) {
    final isCurrentUser = rank == 12; // Example: current user at rank 12

    return AppCard(
      backgroundColor: isCurrentUser ? AppColors.primaryContainer : null,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '$rank',
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: isCurrentUser ? AppColors.primary : AppColors.neutral500,
              ),
            ),
          ),
          const UserAvatar(size: 40, name: 'User'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isCurrentUser ? 'Sen' : 'Kullanıcı $rank',
                      style: AppTypography.titleSmall.copyWith(
                        color: isCurrentUser ? AppColors.primary : null,
                      ),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'SEN',
                          style: AppTypography.labelSmall.copyWith(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${15 - rank % 10} koşu',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${60 - rank + (rank % 5)}.${rank % 10} km',
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isCurrentUser ? AppColors.primary : null,
                ),
              ),
              if (rank < 10)
                Row(
                  children: [
                    Icon(
                      Icons.arrow_upward,
                      size: 12,
                      color: AppColors.success,
                    ),
                    Text(
                      '${rank % 3 + 1}',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
