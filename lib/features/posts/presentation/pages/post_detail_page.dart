import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/content_block_theme.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../domain/entities/post_block_entity.dart';
import '../../domain/entities/post_entity.dart';
import '../providers/post_provider.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        actions: [
          postAsync.when(
            data: (post) {
              final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
              final isAdmin = ref.watch(isAdminProvider);
              
              if (isAdminOrCoach) {
                return PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        context.pushNamed(
                          RouteNames.editPost,
                          pathParameters: {'postId': post.id},
                        ).then((_) {
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
                    if (isAdmin)
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
                Icon(Icons.error_outline, size: 48, color: AppColors.error),
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
                          Icon(
                            Icons.article,
                            size: 14,
                            color: ThemeBrightnessHolder.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeago.format(post.createdAt, locale: 'tr'),
                            style: AppTypography.bodySmall.copyWith(
                              color: ThemeBrightnessHolder.onSurfaceVariant,
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
              child: Builder(
                builder: (context) {
                  final cs = Theme.of(context).colorScheme;
                  return Material(
                    color: cs.primary.withValues(alpha: 0.12),
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
                              color: cs.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Bu etkinliğin programıdır',
                                style: AppTypography.labelMedium.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 12,
                              color: cs.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
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
        return _buildHeaderBlock(context, block);
      case PostBlockType.subheader:
        return _buildSubheaderBlock(context, block);
      case PostBlockType.scheduleItem:
        return _buildScheduleItemBlock(context, block);
      case PostBlockType.warning:
        return _buildWarningBlock(context, block);
      case PostBlockType.info:
        return _buildInfoBlock(context, block);
      case PostBlockType.tip:
        return _buildTipBlock(context, block);
      case PostBlockType.text:
        return _buildTextBlock(block);
      case PostBlockType.quote:
        return _buildQuoteBlock(context, block);
      case PostBlockType.listItem:
        return _buildListItemBlock(block);
      case PostBlockType.checklistItem:
        return _buildChecklistItemBlock(block);
      case PostBlockType.divider:
        return _buildDividerBlock();
      case PostBlockType.image:
        return _buildImageBlock(block);
      case PostBlockType.link:
        return _buildLinkBlock(context, block);
      case PostBlockType.raceResults:
        return _buildRaceResultsBlock(block);
    }
  }

  Future<void> _openExternalLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link açılamadı')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link açılamadı')),
        );
      }
    }
  }

  Widget _buildLinkBlock(BuildContext context, PostBlockEntity block) {
    final url = block.content.trim();
    final label = block.subContent?.trim().isNotEmpty == true
        ? block.subContent!.trim()
        : url;
    final infoAccent = ContentBlockTheme.title(
      context,
      AppColors.info,
      darkAccent: AppColors.infoLight,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: ContentBlockTheme.surface(
          context,
          lightContainer: AppColors.infoContainer.withValues(alpha: 0.45),
          semantic: AppColors.info,
        ),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _openExternalLink(context, url),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ContentBlockTheme.border(context, AppColors.info),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ContentBlockTheme.isDark(context)
                        ? AppColors.info.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.link,
                    color: infoAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTypography.bodyMedium.copyWith(
                          color: infoAccent,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: infoAccent,
                        ),
                      ),
                      if (label != url) ...[
                        const SizedBox(height: 4),
                        Text(
                          url,
                          style: AppTypography.bodySmall.copyWith(
                            color: ContentBlockTheme.onSurfaceVariant(context),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new,
                  size: 18,
                  color: infoAccent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBlock(BuildContext context, PostBlockEntity block) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ContentBlockTheme.isDark(context)
            ? cs.primaryContainer
            : AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: ContentBlockTheme.isDark(context)
            ? Border.all(color: cs.primary.withValues(alpha: 0.35))
            : null,
      ),
      child: Text(
        block.content,
        style: AppTypography.titleLarge.copyWith(
          fontWeight: FontWeight.bold,
          color: ContentBlockTheme.isDark(context)
              ? cs.onPrimaryContainer
              : AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildSubheaderBlock(BuildContext context, PostBlockEntity block) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        block.content,
        style: AppTypography.titleMedium.copyWith(
          fontWeight: FontWeight.w600,
          color: ContentBlockTheme.onSurface(context),
        ),
      ),
    );
  }

  Widget _buildScheduleItemBlock(BuildContext context, PostBlockEntity block) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ContentBlockTheme.surface(
          context,
          lightContainer: AppColors.secondaryContainer,
          semantic: AppColors.secondary,
        ),
        borderRadius: BorderRadius.circular(8),
        border: ContentBlockTheme.isDark(context)
            ? Border.all(
                color: ContentBlockTheme.border(context, AppColors.secondary),
              )
            : null,
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
              style: AppTypography.bodyMedium.copyWith(
                color: ContentBlockTheme.onSurface(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBlock(BuildContext context, PostBlockEntity block) {
    final titleColor = ContentBlockTheme.title(
      context,
      AppColors.error,
      darkAccent: AppColors.errorLight,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ContentBlockTheme.surface(
          context,
          lightContainer: AppColors.errorContainer,
          semantic: AppColors.error,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ContentBlockTheme.border(context, AppColors.error)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning, color: titleColor),
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
                      color: titleColor,
                    ),
                  ),
                if (block.subContent != null && block.subContent!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    block.subContent!,
                    style: AppTypography.bodyMedium.copyWith(
                      color: ContentBlockTheme.onSurface(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBlock(BuildContext context, PostBlockEntity block) {
    final titleColor = ContentBlockTheme.title(
      context,
      AppColors.info,
      darkAccent: AppColors.infoLight,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ContentBlockTheme.surface(
          context,
          lightContainer: AppColors.infoContainer,
          semantic: AppColors.info,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ContentBlockTheme.border(context, AppColors.info)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: titleColor),
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
                      color: titleColor,
                    ),
                  ),
                if (block.subContent != null && block.subContent!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    block.subContent!,
                    style: AppTypography.bodyMedium.copyWith(
                      color: ContentBlockTheme.onSurface(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipBlock(BuildContext context, PostBlockEntity block) {
    final titleColor = ContentBlockTheme.title(
      context,
      AppColors.success,
      darkAccent: AppColors.successLight,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ContentBlockTheme.surface(
          context,
          lightContainer: AppColors.successContainer,
          semantic: AppColors.success,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ContentBlockTheme.border(context, AppColors.success)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, color: titleColor),
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
                      color: titleColor,
                    ),
                  ),
                if (block.subContent != null && block.subContent!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    block.subContent!,
                    style: AppTypography.bodyMedium.copyWith(
                      color: ContentBlockTheme.onSurface(context),
                    ),
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

  Widget _buildQuoteBlock(BuildContext context, PostBlockEntity block) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ContentBlockTheme.isDark(context)
            ? cs.surfaceContainerHighest
            : AppColors.neutral100,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: cs.primary, width: 4),
        ),
      ),
      child: Text(
        block.content,
        style: AppTypography.bodyLarge.copyWith(
          fontStyle: FontStyle.italic,
          color: ContentBlockTheme.onSurface(context),
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
          Icon(Icons.check_box_outline_blank, size: 20),
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
      color: ThemeBrightnessHolder.outlineVariant,
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
  /// null => Belirsiz (kategorisi olmayan sonuçlar)
  String? _selectedRaceVariantLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    try {
      // JSON'u parse et
      final resultsData = jsonDecode(widget.block.content) as List<dynamic>;
      
      if (resultsData.isEmpty) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Center(
            child: Text(
              'Sonuç bulunamadı',
              style: AppTypography.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        );
      }

      bool hasRaceVariantLabelField = resultsData.any((r) {
        final map = r as Map<String, dynamic>;
        return map.containsKey('raceVariantLabel') ||
            map.containsKey('race_variant_label');
      });

      String? raceLabelFor(dynamic r) {
        final map = r as Map<String, dynamic>;

        final v1 = map['raceVariantLabel'];
        if (v1 is String) return v1;

        final v2 = map['race_variant_label'];
        if (v2 is String) return v2;

        return null;
      }

      final raceCategories = hasRaceVariantLabelField
          ? resultsData.map(raceLabelFor).toSet().toList()
          : const <String?>[];

      final dropdownValue = hasRaceVariantLabelField && raceCategories.isNotEmpty
          ? (raceCategories.contains(_selectedRaceVariantLabel)
              ? _selectedRaceVariantLabel
              : raceCategories.first)
          : null;

      // Filtreleme: önce kategori, sonra cinsiyet
      List<dynamic> filteredResults = resultsData;

      if (hasRaceVariantLabelField && raceCategories.isNotEmpty) {
        filteredResults = filteredResults
            .where((r) => raceLabelFor(r) == dropdownValue)
            .toList();
      }

      if (_selectedRankingType == 'female') {
        filteredResults = filteredResults.where((r) {
          final gender = (r as Map<String, dynamic>)['gender'] as String?;
          if (gender == null) return false;
          final g = gender.toLowerCase();
          return g == 'f' || g == 'female' || g == 'kadın' || g == 'k';
        }).toList();
      } else if (_selectedRankingType == 'male') {
        filteredResults = filteredResults.where((r) {
          final gender = (r as Map<String, dynamic>)['gender'] as String?;
          if (gender == null) return false;
          final g = gender.toLowerCase();
          return g == 'm' || g == 'male' || g == 'erkek' || g == 'e';
        }).toList();
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
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.emoji_events,
                      color: cs.onPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Yarış Sonuçları',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasRaceVariantLabelField) ...[
              // Kategori (mesafe) seçimi
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: dropdownValue,
                    isExpanded: true,
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: cs.onSurfaceVariant,
                    ),
                    style: AppTypography.bodyMedium.copyWith(
                      color: cs.onSurface,
                    ),
                    dropdownColor: cs.surfaceContainerHighest,
                    items: raceCategories.map((cat) {
                      return DropdownMenuItem<String?>(
                        value: cat,
                        child: Text(cat ?? 'Belirsiz'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedRaceVariantLabel = value;
                      });
                    },
                  ),
                ),
              ),
            ],
            // Dropdown ile sıralama tipi seçimi
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedRankingType,
                  isExpanded: true,
                  icon: Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
                  style: AppTypography.bodyMedium.copyWith(
                    color: cs.onSurface,
                  ),
                  dropdownColor: cs.surfaceContainerHighest,
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
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Center(
                  child: Text(
                    'Bu kategoride sonuç bulunamadı',
                    style: AppTypography.bodyMedium.copyWith(
                      color: cs.onSurfaceVariant,
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
                  Color rankColor = cs.outline;
                  Color rankBgColor = cs.surfaceContainerHighest;
                  Color cardColor = cs.surfaceContainerHigh;
                  if (rank == 1) {
                    rankColor = const Color(0xFFFFD700); // Altın
                    rankBgColor = isDark
                        ? const Color(0xFFFFD700).withValues(alpha: 0.18)
                        : const Color(0xFFFFF8DC);
                  } else if (rank == 2) {
                    rankColor = const Color(0xFFC0C0C0); // Gümüş
                    rankBgColor = isDark
                        ? const Color(0xFFC0C0C0).withValues(alpha: 0.18)
                        : const Color(0xFFF5F5F5);
                  } else if (rank == 3) {
                    rankColor = const Color(0xFFCD7F32); // Bronz
                    rankBgColor = isDark
                        ? const Color(0xFFCD7F32).withValues(alpha: 0.18)
                        : const Color(0xFFFFF4E6);
                  }

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: rank <= 3
                            ? rankColor.withValues(alpha: isDark ? 0.5 : 0.3)
                            : cs.outlineVariant,
                        width: rank <= 3 ? 2 : 1,
                      ),
                      boxShadow: isDark
                          ? null
                          : [
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
                            color: rank <= 3 ? rankBgColor : cs.surfaceContainerHighest,
                            shape: BoxShape.circle,
                            border: rank <= 3
                                ? Border.all(color: rankColor, width: 2)
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              rank.toString(),
                              style: AppTypography.titleMedium.copyWith(
                                color: rank <= 3 ? rankColor : cs.onSurfaceVariant,
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
                                    color: cs.onSurface,
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
                                color: cs.onSurface,
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
      final cs = Theme.of(context).colorScheme;
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
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
