import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Terim - anlam cifti (kucuk sozluk).
class ReportInfoTerm {
  const ReportInfoTerm(this.term, this.meaning);
  final String term;
  final String meaning;
}

/// Bir rapor sayfasinin bilgi icerigi.
class ReportInfo {
  const ReportInfo({
    required this.title,
    required this.summary,
    this.terms = const [],
    this.takeaways = const [],
  });

  /// Baslik (rapor adi).
  final String title;

  /// Ne gosterir / amac - 1-2 kisa cumle.
  final String summary;

  /// Terim sozlugu.
  final List<ReportInfoTerm> terms;

  /// Cikarimlar / nasil okunur (kisa maddeler).
  final List<String> takeaways;
}

/// AppBar'a konan bilgi butonu; dokununca sik bir alt sayfa acar.
class ReportInfoButton extends StatelessWidget {
  const ReportInfoButton({super.key, required this.info});

  final ReportInfo info;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Bilgi',
      icon: const Icon(Icons.info_outline),
      onPressed: () => _showReportInfoSheet(context, info),
    );
  }
}

Future<void> _showReportInfoSheet(BuildContext context, ReportInfo info) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.neutral400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.insights_rounded,
                                color: AppColors.primary, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              info.title,
                              style: AppTypography.titleMedium
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        info.summary,
                        style: AppTypography.bodyMedium
                            .copyWith(color: AppColors.neutral700, height: 1.4),
                      ),
                      if (info.terms.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _sectionTitle('Terimler', Icons.menu_book_outlined),
                        const SizedBox(height: 10),
                        ...info.terms.map(_termRow),
                      ],
                      if (info.takeaways.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _sectionTitle('Nasıl okunur', Icons.lightbulb_outline),
                        const SizedBox(height: 10),
                        ...info.takeaways.map(_takeawayRow),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _sectionTitle(String title, IconData icon) {
  return Row(
    children: [
      Icon(icon, size: 18, color: AppColors.neutral600),
      const SizedBox(width: 8),
      Text(
        title,
        style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
}

Widget _termRow(ReportInfoTerm t) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.term,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          t.meaning,
          style: AppTypography.bodySmall
              .copyWith(color: AppColors.neutral600, height: 1.35),
        ),
      ],
    ),
  );
}

Widget _takeawayRow(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.neutral700, height: 1.35),
          ),
        ),
      ],
    ),
  );
}
