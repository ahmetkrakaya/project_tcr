import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../marketplace/data/models/market_report_model.dart';
import '../../../marketplace/presentation/providers/marketplace_provider.dart'
    show
        ReportDateRange,
        marketOverviewProvider,
        marketplaceDataSourceProvider;
import '../../../marketplace/utils/market_excel_export.dart';
import '../../../marketplace/utils/market_report_utils.dart';
import '../../data/models/event_finance_model.dart';
import '../../data/models/finance_report_model.dart';
import '../../utils/finance_excel_export.dart';
import '../models/finance_cash_line.dart';
import '../providers/finance_provider.dart';

/// Market ve etkinlik gelirlerini birleştiren kasa raporu (yalnızca admin).
class FinanceReportsPage extends ConsumerStatefulWidget {
  const FinanceReportsPage({super.key});

  @override
  ConsumerState<FinanceReportsPage> createState() => _FinanceReportsPageState();
}

class _FinanceReportsPageState extends ConsumerState<FinanceReportsPage> {
  ReportDateRange _range = ReportDateRange.all;
  FinanceSource? _sourceFilter;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(financeOverviewProvider);
    });
  }

  Rect _shareOriginFor(BuildContext originContext) {
    final box = originContext.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final rect = Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      );
      if (rect.width > 0 && rect.height > 0) return rect;
    }
    final size = MediaQuery.of(originContext).size;
    return Rect.fromLTWH(size.width / 2 - 1, size.height / 2 - 1, 2, 2);
  }

  Future<void> _exportExcel(
    BuildContext buttonContext,
    List<FinanceOverviewRow>? rows,
  ) async {
    if (rows == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rapor henüz yüklenmedi')),
      );
      return;
    }
    final filtered = _filtered(rows);
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dışa aktarılacak kayıt yok')),
      );
      return;
    }

    final shareOrigin = _shareOriginFor(buttonContext);
    setState(() => _exporting = true);
    try {
      final marketData = ref.read(marketplaceDataSourceProvider);
      final financeData = ref.read(financeDataSourceProvider);
      final products = <String, MarketProductExportData>{};
      final events = <String, EventFinanceDetail>{};

      await Future.wait(filtered.map((row) async {
        if (row.source == FinanceSource.market) {
          final reportFuture = marketData.getProductReport(row.refId);
          final salesFuture = marketData.getProductSalesRows(row.refId);
          final batchesFuture = marketData.getProductionBatches(row.refId);
          products[row.refId] = MarketProductExportData(
            report: await reportFuture,
            sales: await salesFuture,
            batches: await batchesFuture,
          );
        } else {
          events[row.refId] =
              await financeData.getEventFinanceDetail(row.refId);
        }
      }));

      final bytes = buildFinanceOverviewXlsx(
        rows: filtered,
        products: products,
        events: events,
        from: _range.from,
        to: _range.to,
        sourceFilter: _sourceFilter,
      );
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '')
          .substring(0, 15);
      final file = File('${dir.path}/kasa_raporu_$stamp.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        sharePositionOrigin: shareOrigin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel oluşturulamadı: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<FinanceOverviewRow> _filtered(List<FinanceOverviewRow> rows) {
    if (_sourceFilter == null) return rows;
    return rows.where((r) => r.source == _sourceFilter).toList();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('tr', 'TR'),
      initialDateRange: _range.from != null && _range.to != null
          ? DateTimeRange(start: _range.from!, end: _range.to!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _range = ReportDateRange(from: picked.start, to: picked.end);
      });
    }
  }

  void _openRow(FinanceOverviewRow row) {
    if (row.source == FinanceSource.market) {
      context.pushNamed(
        RouteNames.marketProductReport,
        pathParameters: {'listingId': row.refId},
      );
    } else {
      context.pushNamed(
        RouteNames.eventFinance,
        pathParameters: {'eventId': row.refId},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kasa Raporu')),
        body: const Center(child: Text('Bu sayfaya erişim yetkiniz yok')),
      );
    }

    final overviewAsync = ref.watch(financeOverviewProvider(_range));
    final marketAsync = ref.watch(marketOverviewProvider(_range));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kasa Raporu'),
        actions: [
          Builder(
            builder: (buttonContext) => IconButton(
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              tooltip: 'Excel olarak paylaş',
              onPressed: _exporting
                  ? null
                  : () => _exportExcel(
                        buttonContext,
                        overviewAsync.valueOrNull,
                      ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(financeOverviewProvider(_range));
              ref.invalidate(marketOverviewProvider(_range));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(context),
          Expanded(
            child: overviewAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Rapor alınamadı: $e', textAlign: TextAlign.center),
                ),
              ),
              data: (rows) {
                final filtered = _filtered(rows);
                final needsMarket = filtered.any(
                  (row) => row.source == FinanceSource.market,
                );
                if (needsMarket &&
                    marketAsync.isLoading &&
                    !marketAsync.hasValue) {
                  return const Center(child: CircularProgressIndicator());
                }
                final marketById = {
                  for (final row
                      in marketAsync.valueOrNull ?? const <MarketOverviewRow>[])
                    row.listingId: row,
                };
                return _buildBody(
                  context,
                  filtered,
                  marketById: marketById,
                  stockUnavailable: needsMarket && marketAsync.hasError,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasRange = _range.from != null || _range.to != null;
    final rangeLabel = hasRange
        ? '${formatReportDate(_range.from)} – ${formatReportDate(_range.to)}'
        : 'Tüm zamanlar';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: InkWell(
                    onTap: _pickRange,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.date_range,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              rangeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (hasRange)
                  IconButton(
                    onPressed: () => setState(() => _range = ReportDateRange.all),
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    tooltip: 'Tarihi temizle',
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SourceSegments(
            selected: _sourceFilter,
            onSelected: (value) => setState(() => _sourceFilter = value),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<FinanceOverviewRow> rows, {
    required Map<String, MarketOverviewRow> marketById,
    required bool stockUnavailable,
  }) {
    if (rows.isEmpty) {
      return const Center(child: Text('Bu dönemde kayıt bulunamadı'));
    }

    final lines = [
      for (final row in rows) FinanceCashLine.from(row, marketById[row.refId]),
    ];
    final totals = FinanceCashTotals.of(lines);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(financeOverviewProvider(_range));
        ref.invalidate(marketOverviewProvider(_range));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (stockUnavailable) ...[
            Text(
              'Stok bilgisi alınamadı. Market satırları satılan kârı gösteriyor.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
            ),
            const SizedBox(height: 12),
          ],
          _CashSummary(totals: totals),
          const SizedBox(height: 22),
          Text(
            'Kaynaklar',
            style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CashSourceCard(
                line: line,
                onTap: () => _openRow(line.row),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceSegments extends StatelessWidget {
  final FinanceSource? selected;
  final ValueChanged<FinanceSource?> onSelected;

  const _SourceSegments({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _item(context, 'Tümü', selected == null, () => onSelected(null)),
          _item(
            context,
            'Market',
            selected == FinanceSource.market,
            () => onSelected(FinanceSource.market),
          ),
          _item(
            context,
            'Etkinlik',
            selected == FinanceSource.event,
            () => onSelected(FinanceSource.event),
          ),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _CashSummary extends StatelessWidget {
  final FinanceCashTotals totals;

  const _CashSummary({required this.totals});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final profitColor = _profitColor(totals.position);
    final muted = cs.onSurfaceVariant;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kar / Zarar',
            style: AppTypography.labelMedium.copyWith(color: muted),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _signedMoney(totals.position),
              style: AppTypography.headlineMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: profitColor,
                letterSpacing: -0.6,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            totals.hasMarket && totals.hasEvents
                ? 'Satıştan üretim maliyeti ve etkinlik gideri düşülür. Kalan stok bu sonucun içindedir.'
                : totals.hasMarket
                    ? 'Satıştan üretim maliyeti düşülür. Kalan stok bu sonucun içindedir.'
                    : 'Satıştan etkinlik gideri düşülür.',
            style: AppTypography.bodySmall.copyWith(color: muted, height: 1.35),
          ),
          if (totals.hasMarket && totals.hasEvents) ...[
            const SizedBox(height: 8),
            Text(
              'Market ${_signedMoney(totals.marketPosition)}  ·  Etkinlik ${_signedMoney(totals.eventNet)}',
              style: AppTypography.labelMedium.copyWith(color: muted),
            ),
          ],
          if (totals.hasMarket) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _CountPill(label: 'Üretilen', value: '${totals.produced}'),
                const SizedBox(width: 8),
                _CountPill(label: 'Giden', value: '${totals.gone}'),
                const SizedBox(width: 8),
                _CountPill(label: 'Kalan', value: '${totals.remaining}'),
              ],
            ),
            if (totals.produced > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (totals.gone / totals.produced).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: cs.primary,
                ),
              ),
            ],
            if (totals.bundleSales > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${totals.bundleSales} paket satıldı. Paket maliyeti bileşen ürünlerdedir.',
                style: AppTypography.labelSmall.copyWith(color: muted),
              ),
            ],
          ],
          const SizedBox(height: 16),
          _SummaryLine(label: 'Brüt ciro', value: formatMoneyCompact(totals.gross)),
          if (totals.hasMarket)
            _SummaryLine(
              label: 'Üretim maliyeti',
              value: formatMoneyCompact(totals.productionCost),
            ),
          if (totals.hasMarket)
            _SummaryLine(
              label: 'Kalan stok maliyeti',
              value: formatMoneyCompact(totals.remainingCost),
            ),
          if (totals.hasMarket)
            _SummaryLine(
              label: 'Satılan kâr',
              value: _signedMoney(totals.marketRealized),
              valueColor: _profitColor(totals.marketRealized),
            ),
          if (totals.hasEvents)
            _SummaryLine(
              label: 'Etkinlik gideri',
              value: formatMoneyCompact(totals.eventCost),
            ),
          if (totals.hasEvents && totals.hasMarket)
            _SummaryLine(
              label: 'Etkinlik net',
              value: _signedMoney(totals.eventNet),
              valueColor: _profitColor(totals.eventNet),
            ),
          if (totals.outstanding > 0.5)
            _SummaryLine(
              label: 'Tahsil edilmeyen',
              value: formatMoneyCompact(totals.outstanding),
              valueColor: AppColors.warning,
            ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final String label;
  final String value;

  const _CountPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(color: muted),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _CashSourceCard extends StatelessWidget {
  final FinanceCashLine line;
  final VoidCallback onTap;

  const _CashSourceCard({required this.line, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final profitColor = _profitColor(line.position);
    final muted = cs.onSurfaceVariant;
    final accent = line.isMarket ? AppColors.success : AppColors.info;
    final mix = _saleMix(line);

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  line.isBundle
                      ? Icons.inventory_2_outlined
                      : line.isMarket
                          ? Icons.storefront_outlined
                          : Icons.event_available_outlined,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.row.title,
                      style: AppTypography.titleSmall
                          .copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        line.isBundle ? 'Paket' : line.row.source.label,
                        if (line.row.refDate != null)
                          formatReportDate(line.row.refDate),
                      ].join(' · '),
                      style: AppTypography.labelSmall.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _signedMoney(line.position),
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w800,
                      color: profitColor,
                    ),
                  ),
                  Text(
                    line.isMarket ? 'Kar / Zarar' : 'Net',
                    style: AppTypography.labelSmall.copyWith(color: muted),
                  ),
                ],
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, color: muted, size: 20),
            ],
          ),
          if (line.hasInventory) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _InlineCount(label: 'Üretilen', value: '${line.produced ?? 0}'),
                _InlineCount(label: 'Giden', value: '${line.gone}'),
                _InlineCount(label: 'Kalan', value: '${line.remaining ?? 0}'),
              ],
            ),
            if ((line.produced ?? 0) > 0) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (line.gone / line.produced!).clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: cs.primary,
                ),
              ),
            ],
          ] else if (line.isBundle) ...[
            const SizedBox(height: 12),
            Text(
              '${line.gone} satıldı · ${line.remaining ?? 0} paket stoğu',
              style: AppTypography.bodySmall,
            ),
            Text(
              'Maliyet bileşen ürünlerde',
              style: AppTypography.labelSmall.copyWith(color: muted),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              '${line.gone} katılımcı',
              style: AppTypography.bodySmall.copyWith(color: muted),
            ),
          ],
          if (mix != null) ...[
            const SizedBox(height: 6),
            Text(mix, style: AppTypography.labelSmall.copyWith(color: muted)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniMetric(
                  label: 'Brüt',
                  value: formatMoneyCompact(line.gross),
                ),
              ),
              Expanded(
                child: _MiniMetric(
                  label: line.isMarket
                      ? (line.remainingCost != null ? 'Stok maliyeti' : 'Satılan maliyet')
                      : 'Gider',
                  value: formatMoneyCompact(
                    line.isMarket
                        ? (line.remainingCost ?? line.soldCost ?? 0)
                        : (line.eventCost ?? 0),
                  ),
                ),
              ),
              if (line.isMarket && line.hasInventory)
                Expanded(
                  child: _MiniMetric(
                    label: 'Satılan kâr',
                    value: _signedMoney(line.realized),
                    valueColor: _profitColor(line.realized),
                  ),
                ),
            ],
          ),
          if (line.outstanding > 0.5) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Text(
                  'Tahsil edilmeyen ${formatMoneyCompact(line.outstanding)}',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineCount extends StatelessWidget {
  final String label;
  final String value;

  const _InlineCount({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MiniMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

String? _saleMix(FinanceCashLine line) {
  if (!line.isMarket) return null;
  if (line.discounted == 0 && line.gift == 0 && line.bundleGone == 0) {
    return null;
  }
  final parts = <String>[
    if (line.regular > 0) '${line.regular} normal',
    if (line.discounted > 0) '${line.discounted} indirimli',
    if (line.gift > 0) '${line.gift} hediye',
    if (line.bundleGone > 0) '${line.bundleGone} paketle',
  ];
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

Color _profitColor(double value) {
  if (value > 0.5) return AppColors.success;
  if (value < -0.5) return AppColors.error;
  return AppColors.primary;
}

String _signedMoney(double value) {
  final text = formatMoneyCompact(value.abs());
  if (value < -0.5) return '-$text';
  if (value > 0.5) return '+$text';
  return text;
}
