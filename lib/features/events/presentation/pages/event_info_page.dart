import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../domain/entities/event_info_block_entity.dart';
import '../providers/event_provider.dart';

/// Etkinlik Bilgileri Sayfası - Tam ekran görüntüleme
class EventInfoPage extends ConsumerWidget {
  final String eventId;
  final String eventTitle;

  const EventInfoPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocksAsync = ref.watch(eventInfoBlocksProvider(eventId));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'Etkinlik Bilgileri',
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary,
                      AppColors.primaryDark,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Event Title Header
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.1),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.event,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eventTitle,
                          style: AppTypography.titleLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Program ve Detaylar',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Info Blocks Content
          blocksAsync.when(
            data: (blocks) {
              if (blocks.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 64,
                          color: AppColors.neutral300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Henüz bilgi eklenmemiş',
                          style: AppTypography.titleMedium.copyWith(
                            color: AppColors.neutral400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildBlock(context, blocks[index]),
                    childCount: blocks.length,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: LoadingWidget()),
            ),
            error: (error, _) => SliverFillRemaining(
              child: Center(
                child: Text('Hata: $error'),
              ),
            ),
          ),

          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildBlock(BuildContext context, EventInfoBlockEntity block) {
    switch (block.type) {
      case EventInfoBlockType.header:
        return _buildHeaderBlock(block);
      case EventInfoBlockType.subheader:
        return _buildSubheaderBlock(block);
      case EventInfoBlockType.scheduleItem:
        return _buildScheduleItemBlock(block);
      case EventInfoBlockType.warning:
        return _buildWarningBlock(block);
      case EventInfoBlockType.info:
        return _buildInfoBlock(block);
      case EventInfoBlockType.tip:
        return _buildTipBlock(block);
      case EventInfoBlockType.text:
        return _buildTextBlock(block);
      case EventInfoBlockType.quote:
        return _buildQuoteBlock(block);
      case EventInfoBlockType.listItem:
        return _buildListItemBlock(block);
      case EventInfoBlockType.checklistItem:
        return _buildChecklistItemBlock(block);
      case EventInfoBlockType.divider:
        return _buildDividerBlock();
    }
  }

  /// Ana başlık - Tarih bloğu
  Widget _buildHeaderBlock(EventInfoBlockEntity block) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.secondary,
            AppColors.secondary.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              block.content,
              style: AppTypography.titleLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Alt başlık
  Widget _buildSubheaderBlock(EventInfoBlockEntity block) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.tertiary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: AppColors.tertiary, width: 4),
        ),
      ),
      child: Row(
        children: [
          Text(
            block.icon ?? '🔴',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              block.content,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.tertiary,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.tertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Program öğesi - Saat + Açıklama
  Widget _buildScheduleItemBlock(EventInfoBlockEntity block) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Saat badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.secondary,
                  AppColors.secondaryLight,
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              block.content,
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Açıklama
          Expanded(
            child: Text(
              block.subContent ?? '',
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Uyarı bloğu - Kırmızı
  Widget _buildWarningBlock(EventInfoBlockEntity block) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  block.content,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (block.subContent != null && block.subContent!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              block.subContent!,
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.error.withValues(alpha: 0.9),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Bilgi bloğu - Mavi
  Widget _buildInfoBlock(EventInfoBlockEntity block) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('ℹ️', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  block.content,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.info,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (block.subContent != null && block.subContent!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              block.subContent!,
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.info.withValues(alpha: 0.9),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// İpucu bloğu - Yeşil
  Widget _buildTipBlock(EventInfoBlockEntity block) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💡', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  block.content,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (block.subContent != null && block.subContent!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              block.subContent!,
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.success.withValues(alpha: 0.9),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Normal metin
  Widget _buildTextBlock(EventInfoBlockEntity block) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        block.content,
        style: AppTypography.bodyLarge.copyWith(
          color: AppColors.neutral700,
          height: 1.6,
        ),
      ),
    );
  }

  /// Alıntı bloğu
  Widget _buildQuoteBlock(EventInfoBlockEntity block) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: Colors.purple, width: 5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('💯', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '"${block.content}"',
                  style: AppTypography.titleMedium.copyWith(
                    fontStyle: FontStyle.italic,
                    color: AppColors.neutral700,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (block.subContent != null && block.subContent!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '— ${block.subContent}',
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.purple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Liste öğesi
  Widget _buildListItemBlock(EventInfoBlockEntity block) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.tertiary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
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

  /// Kontrol listesi öğesi
  Widget _buildChecklistItemBlock(EventInfoBlockEntity block) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_box_outline_blank_rounded,
            size: 26,
            color: AppColors.secondary,
          ),
          const SizedBox(width: 12),
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

  /// Ayırıcı çizgi
  Widget _buildDividerBlock() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.neutral300, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Icon(
              Icons.more_horiz,
              color: AppColors.neutral400,
              size: 24,
            ),
          ),
          Expanded(child: Divider(color: AppColors.neutral300, thickness: 1)),
        ],
      ),
    );
  }
}
