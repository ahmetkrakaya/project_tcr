import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../pages/event_info_page.dart';
import '../widgets/event_info_blocks_editor.dart';
import '../providers/event_provider.dart';

/// Etkinlik Bilgileri Önizleme Kartı
/// Sadece başlık ve öğe sayısı - tıklayınca tam sayfa açılır
class EventInfoBlocksViewer extends ConsumerWidget {
  final String eventId;
  final String eventTitle;
  final bool showEditButton; // Admin/Coach için düzenleme butonu
  /// Antrenman dışı etkinliklerde kart boş olsa bile gösterilir (içerik eklenebilsin)
  final bool showWhenEmpty;

  const EventInfoBlocksViewer({
    super.key,
    required this.eventId,
    required this.eventTitle,
    this.showEditButton = false,
    this.showWhenEmpty = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocksAsync = ref.watch(eventInfoBlocksProvider(eventId));

    return blocksAsync.when(
      data: (blocks) {
        if (blocks.isEmpty && !showWhenEmpty) {
          return const SizedBox.shrink();
        }
        return _buildPreviewCard(context, blocks.length);
      },
      loading: () => showWhenEmpty ? _buildPreviewCard(context, 0) : const SizedBox.shrink(),
      error: (_, __) => showWhenEmpty ? _buildPreviewCard(context, 0) : const SizedBox.shrink(),
    );
  }

  Widget _buildPreviewCard(BuildContext context, int itemCount) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12), // Sadece dikey margin (parent zaten 20px horizontal padding kullanıyor)
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Ana kart - Genişletilmiş ve daha belirgin
          Expanded(
            child: GestureDetector(
              onTap: () => _openFullPage(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), // Daha fazla padding
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16), // Daha yuvarlatılmış
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // İkon - Daha büyük
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.article_outlined,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Başlık ve öğe sayısı
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Etkinlik Programı & Bilgiler',
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$itemCount öğe',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.neutral500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Düzenleme butonu - Sadece ikon, arkasında renk yok
                    if (showEditButton) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _openEditor(context),
                        icon: const Icon(
                          Icons.edit_note,
                          color: AppColors.primary,
                          size: 24,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openFullPage(BuildContext context) {
    // Sayfa açılmadan önce provider'ı yenile
    final container = ProviderScope.containerOf(context);
    container.invalidate(eventInfoBlocksProvider(eventId));
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventInfoPage(
          eventId: eventId,
          eventTitle: eventTitle,
        ),
      ),
    );
  }

  void _openEditor(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventInfoBlocksEditor(eventId: eventId),
      ),
    );
  }
}
