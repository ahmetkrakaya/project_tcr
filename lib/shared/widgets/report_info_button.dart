import 'package:flutter/material.dart';

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
    this.dataSources = const [],
    this.calculations = const [],
    this.terms = const [],
    this.riskLogic = const [],
    this.takeaways = const [],
  });

  /// Baslik (rapor adi).
  final String title;

  /// Ne gosterir / amac - 1-2 kisa cumle.
  final String summary;

  /// Hangi veriler kullanilir.
  final List<String> dataSources;

  /// Metriklerin nasil hesaplandigi.
  final List<ReportInfoTerm> calculations;

  /// Terim sozlugu.
  final List<ReportInfoTerm> terms;

  /// Risk / durum renklerinin nasil belirlendigi.
  final List<String> riskLogic;

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
      icon: Icon(Icons.info_outline),
      onPressed: () => _showReportInfoSheet(context, info),
    );
  }
}

Future<void> _showReportInfoSheet(BuildContext context, ReportInfo info) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;

      return DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline,
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
                              color: cs.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.insights_rounded,
                              color: cs.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              info.title,
                              style: AppTypography.titleMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        info.summary,
                        style: AppTypography.bodyMedium.copyWith(
                          color: cs.onSurface,
                          height: 1.4,
                        ),
                      ),
                      if (info.dataSources.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _sectionTitle(
                          cs,
                          'Hangi veriler kullanılır?',
                          Icons.dataset_outlined,
                        ),
                        const SizedBox(height: 10),
                        ...info.dataSources.map((t) => _bulletRow(cs, t)),
                      ],
                      if (info.calculations.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _sectionTitle(
                          cs,
                          'Nasıl hesaplanır?',
                          Icons.calculate_outlined,
                        ),
                        const SizedBox(height: 10),
                        ...info.calculations.map((t) => _termRow(cs, t)),
                      ],
                      if (info.terms.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _sectionTitle(cs, 'Terimler', Icons.menu_book_outlined),
                        const SizedBox(height: 10),
                        ...info.terms.map((t) => _termRow(cs, t)),
                      ],
                      if (info.riskLogic.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _sectionTitle(
                          cs,
                          'Güvenli / Dikkat / Risk',
                          Icons.shield_outlined,
                        ),
                        const SizedBox(height: 10),
                        ...info.riskLogic.map((t) => _bulletRow(cs, t)),
                      ],
                      if (info.takeaways.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _sectionTitle(
                          cs,
                          'Nasıl okunur',
                          Icons.lightbulb_outline,
                        ),
                        const SizedBox(height: 10),
                        ...info.takeaways.map((t) => _takeawayRow(cs, t)),
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

Widget _sectionTitle(ColorScheme cs, String title, IconData icon) {
  return Row(
    children: [
      Icon(icon, size: 18, color: cs.onSurfaceVariant),
      const SizedBox(width: 8),
      Text(
        title,
        style: AppTypography.titleSmall.copyWith(
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      ),
    ],
  );
}

Widget _termRow(ColorScheme cs, ReportInfoTerm t) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.term,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          t.meaning,
          style: AppTypography.bodySmall.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ],
    ),
  );
}

Widget _bulletRow(ColorScheme cs, String text) {
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
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              color: cs.onSurface,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _takeawayRow(ColorScheme cs, String text) {
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
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              color: cs.onSurface,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}
