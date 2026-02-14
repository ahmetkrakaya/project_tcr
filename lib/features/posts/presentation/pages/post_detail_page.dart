import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../domain/entities/post_block_entity.dart';
import '../../domain/entities/post_entity.dart';
import '../providers/post_provider.dart';

/// Post Detail Page
class PostDetailPage extends ConsumerWidget {
  final String postId;

  const PostDetailPage({
    super.key,
    required this.postId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(postByIdProvider(postId));
    final currentUser = ref.watch(currentUserProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        actions: [
          postAsync.when(
            data: (post) {
              final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
              final isOwner = currentUser?.id == post.userId;
              
              if (isOwner || isAdminOrCoach) {
                return PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        context.pushNamed(
                          RouteNames.editPost,
                          pathParameters: {'postId': post.id},
                        ).then((_) {
                          // Düzenleme sayfasından dönünce post'u yenile
                          ref.invalidate(postByIdProvider(post.id));
                          ref.invalidate(postBlocksProvider(post.id));
                        });
                        break;
                      case 'delete':
                        _showDeleteConfirmation(context, ref, post);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined),
                          SizedBox(width: 8),
                          Text('Düzenle'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: AppColors.error),
                          SizedBox(width: 8),
                          Text('Sil', style: TextStyle(color: AppColors.error)),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: postAsync.when(
        data: (post) => _buildPostContent(context, ref, post),
        loading: () => const Center(child: LoadingWidget()),
        error: (error, _) {
          if (isContentNotFoundError(error)) {
            return ContentNotFoundWidget(
              onGoToNotifications: () =>
                  context.goNamed(RouteNames.notifications),
              onBack: () => context.pop(),
            );
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                const SizedBox(height: 16),
                Text('Hata: $error'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(postByIdProvider(postId)),
                  child: const Text('Tekrar Dene'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPostContent(BuildContext context, WidgetRef ref, PostEntity post) {
    final blocksAsync = ref.watch(postBlocksProvider(post.id));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                UserAvatar(
                  size: 48,
                  name: post.userName,
                  imageUrl: post.userAvatarUrl,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.userName,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.article,
                            size: 14,
                            color: AppColors.neutral500,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeago.format(post.createdAt, locale: 'tr'),
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.neutral500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bu etkinliğin programıdır (event_id bağlantılı postlar için)
          if (post.eventId != null && post.eventId!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => context.pushNamed(
                    RouteNames.eventDetail,
                    pathParameters: {'eventId': post.eventId!},
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_note,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bu etkinliğin programıdır',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 12,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Title
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              post.title,
              style: AppTypography.headlineMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Blocks
          blocksAsync.when(
            data: (blocks) {
              if (blocks.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Henüz içerik bloğu yok'),
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: blocks.map((block) => _buildBlock(context, block)).toList(),
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: LoadingWidget()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Bloklar yüklenemedi: $error'),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildBlock(BuildContext context, PostBlockEntity block) {
    switch (block.type) {
      case PostBlockType.header:
        return _buildHeaderBlock(block);
      case PostBlockType.subheader:
        return _buildSubheaderBlock(block);
      case PostBlockType.scheduleItem:
        return _buildScheduleItemBlock(block);
      case PostBlockType.warning:
        return _buildWarningBlock(block);
      case PostBlockType.info:
        return _buildInfoBlock(block);
      case PostBlockType.tip:
        return _buildTipBlock(block);
      case PostBlockType.text:
        return _buildTextBlock(block);
      case PostBlockType.quote:
        return _buildQuoteBlock(block);
      case PostBlockType.listItem:
        return _buildListItemBlock(block);
      case PostBlockType.checklistItem:
        return _buildChecklistItemBlock(block);
      case PostBlockType.divider:
        return _buildDividerBlock();
      case PostBlockType.image:
        return _buildImageBlock(block);
      case PostBlockType.raceResults:
        return _buildRaceResultsBlock(block);
    }
  }

  Widget _buildHeaderBlock(PostBlockEntity block) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        block.content,
        style: AppTypography.titleLarge.copyWith(
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildSubheaderBlock(PostBlockEntity block) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        block.content,
        style: AppTypography.titleMedium.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildScheduleItemBlock(PostBlockEntity block) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              block.content,
              style: AppTypography.labelMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              block.subContent ?? '',
              style: AppTypography.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBlock(PostBlockEntity block) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (block.content.isNotEmpty)
                  Text(
                    block.content,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.error,
                    ),
                  ),
                if (block.subContent != null && block.subContent!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    block.subContent!,
                    style: AppTypography.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBlock(PostBlockEntity block) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.infoContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (block.content.isNotEmpty)
                  Text(
                    block.content,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.info,
                    ),
                  ),
                if (block.subContent != null && block.subContent!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    block.subContent!,
                    style: AppTypography.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipBlock(PostBlockEntity block) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.successContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, color: AppColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (block.content.isNotEmpty)
                  Text(
                    block.content,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                if (block.subContent != null && block.subContent!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    block.subContent!,
                    style: AppTypography.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextBlock(PostBlockEntity block) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        block.content,
        style: AppTypography.bodyLarge,
      ),
    );
  }

  Widget _buildQuoteBlock(PostBlockEntity block) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.neutral100,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: AppColors.primary, width: 4),
        ),
      ),
      child: Text(
        block.content,
        style: AppTypography.bodyLarge.copyWith(
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildListItemBlock(PostBlockEntity block) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: AppTypography.bodyLarge),
          Expanded(
            child: Text(
              block.content,
              style: AppTypography.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItemBlock(PostBlockEntity block) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_box_outline_blank, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              block.content,
              style: AppTypography.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDividerBlock() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      height: 1,
      color: AppColors.neutral300,
    );
  }

  Widget _buildImageBlock(PostBlockEntity block) {
    if (block.imageUrl == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          block.imageUrl!,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: 200,
            color: AppColors.neutral200,
            child: const Center(
              child: Icon(Icons.broken_image, size: 48),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRaceResultsBlock(PostBlockEntity block) {
    return _RaceResultsBlockWidget(block: block);
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref, PostEntity post) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Postu Sil'),
        content: const Text('Bu postu silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final dataSource = ref.read(postDataSourceProvider);
                await dataSource.deletePost(post.id);
                if (context.mounted) {
                  ref.read(postsProvider.notifier).removePost(post.id);
                  Navigator.pop(context); // Post detail sayfasından çık
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Post silindi'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Post silinemedi: $e')),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }
}

/// Yarış sonuçları bloğu için StatefulWidget (dropdown ile filtreleme için)
class _RaceResultsBlockWidget extends StatefulWidget {
  final PostBlockEntity block;

  const _RaceResultsBlockWidget({required this.block});

  @override
  State<_RaceResultsBlockWidget> createState() => _RaceResultsBlockWidgetState();
}

class _RaceResultsBlockWidgetState extends State<_RaceResultsBlockWidget> {
  String _selectedRankingType = 'overall'; // 'overall', 'male', 'female'

  @override
  Widget build(BuildContext context) {
    try {
      // JSON'u parse et
      final resultsData = jsonDecode(widget.block.content) as List<dynamic>;
      
      if (resultsData.isEmpty) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.neutral100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.neutral200),
          ),
          child: Center(
            child: Text(
              'Sonuç bulunamadı',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.neutral500,
              ),
            ),
          ),
        );
      }

      // Filtreleme: Seçilen sıralama tipine göre
      List<dynamic> filteredResults = resultsData;
      
      if (_selectedRankingType == 'female') {
        filteredResults = resultsData
            .where((r) {
              final gender = (r as Map<String, dynamic>)['gender'] as String?;
              if (gender == null) return false;
              final g = gender.toLowerCase();
              return g == 'f' || g == 'female' || g == 'kadın' || g == 'k';
            })
            .toList();
      } else if (_selectedRankingType == 'male') {
        filteredResults = resultsData
            .where((r) {
              final gender = (r as Map<String, dynamic>)['gender'] as String?;
              if (gender == null) return false;
              final g = gender.toLowerCase();
              return g == 'm' || g == 'male' || g == 'erkek' || g == 'e';
            })
            .toList();
      }

      // Sıralama: Her zaman süreye göre (en hızlıdan en yavaşa)
      filteredResults.sort((a, b) {
        final aTime = (a as Map<String, dynamic>)['finishTimeSeconds'] as int? ?? 999999;
        final bTime = (b as Map<String, dynamic>)['finishTimeSeconds'] as int? ?? 999999;
        return aTime.compareTo(bTime);
      });

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık ve Dropdown
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.emoji_events,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Yarış Sonuçları',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Dropdown ile sıralama tipi seçimi
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.neutral100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.neutral300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedRankingType,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down, color: AppColors.neutral600),
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.neutral900,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'overall',
                      child: Text('Genel Sıralama'),
                    ),
                    DropdownMenuItem(
                      value: 'male',
                      child: Text('Erkekler Sıralaması'),
                    ),
                    DropdownMenuItem(
                      value: 'female',
                      child: Text('Kadınlar Sıralaması'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedRankingType = value;
                      });
                    }
                  },
                ),
              ),
            ),
            // Sonuç listesi
            if (filteredResults.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.neutral100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.neutral200),
                ),
                child: Center(
                  child: Text(
                    'Bu kategoride sonuç bulunamadı',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.neutral500,
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredResults.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final result = filteredResults[index] as Map<String, dynamic>;
                  final rank = index + 1; // Filtrelenmiş listedeki sıra
                  final fullName = result['fullName'] as String? ?? 'Anonim';
                  final avatarUrl = result['avatarUrl'] as String?;
                  final formattedFinishTime = result['formattedFinishTime'] as String? ?? '-';

                  // İlk 3 için özel renkler
                  Color rankColor = AppColors.neutral400;
                  Color rankBgColor = AppColors.neutral100;
                  if (rank == 1) {
                    rankColor = const Color(0xFFFFD700); // Altın
                    rankBgColor = const Color(0xFFFFF8DC);
                  } else if (rank == 2) {
                    rankColor = const Color(0xFFC0C0C0); // Gümüş
                    rankBgColor = const Color(0xFFF5F5F5);
                  } else if (rank == 3) {
                    rankColor = const Color(0xFFCD7F32); // Bronz
                    rankBgColor = const Color(0xFFFFF4E6);
                  }

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: rank <= 3 ? rankColor.withValues(alpha: 0.3) : AppColors.neutral200,
                        width: rank <= 3 ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neutral200.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Sıralama numarası
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: rank <= 3 ? rankBgColor : AppColors.neutral100,
                            shape: BoxShape.circle,
                            border: rank <= 3
                                ? Border.all(color: rankColor, width: 2)
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              rank.toString(),
                              style: AppTypography.titleMedium.copyWith(
                                color: rank <= 3 ? rankColor : AppColors.neutral700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Avatar ve isim
                        Expanded(
                          child: Row(
                            children: [
                              if (avatarUrl != null && avatarUrl.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: UserAvatar(
                                    size: 40,
                                    name: fullName,
                                    imageUrl: avatarUrl,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  fullName,
                                  style: AppTypography.bodyLarge.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Süre
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formattedFinishTime,
                              style: AppTypography.titleMedium.copyWith(
                                fontFeatures: const [FontFeature.tabularFigures()],
                                fontWeight: FontWeight.bold,
                                color: AppColors.neutral900,
                              ),
                            ),
                            if (rank <= 3) ...[
                              const SizedBox(height: 4),
                              Icon(
                                rank == 1
                                    ? Icons.emoji_events
                                    : rank == 2
                                        ? Icons.workspace_premium
                                        : Icons.stars,
                                color: rankColor,
                                size: 16,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      );
    } catch (e) {
      // JSON parse hatası durumunda
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.neutral100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.neutral200),
        ),
        child: Center(
          child: Text(
            'Sonuçlar yüklenemedi',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.error,
            ),
          ),
        ),
      );
    }
  }
}
