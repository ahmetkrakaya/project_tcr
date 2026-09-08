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
import '../../data/models/market_report_model.dart';
import '../../utils/market_excel_export.dart';
import '../../utils/market_report_utils.dart';
import '../providers/marketplace_provider.dart';

/// Market genel satış ve kar-zarar raporu (admin).
class MarketReportsPage extends ConsumerStatefulWidget {
  const MarketReportsPage({super.key});

  @override
  ConsumerState<MarketReportsPage> createState() => _MarketReportsPageState();
}

class _MarketReportsPageState extends ConsumerState<MarketReportsPage> {
  ReportDateRange _range = ReportDateRange.all;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(marketOverviewProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Satış Raporları')),
        body: const Center(child: Text('Bu sayfaya erişim yetkiniz yok')),
      );
    }

    final overviewAsync = ref.watch(marketOverviewProvider(_range));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Satış Raporları'),
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
            onPressed: () => ref.invalidate(marketOverviewProvider(_range)),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildRangeFilter(context),
          Expanded(
            child: overviewAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Rapor alınamadı: $e', textAlign: TextAlign.center),
                ),
              ),
              data: (rows) => _buildBody(context, rows),
            ),
          ),
        ],
      ),
    );
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
    List<MarketOverviewRow>? overview,
  ) async {
    if (overview == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rapor henüz yüklenmedi')),
      );
      return;
    }
    if (overview.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dışa aktarılacak ürün yok')),
      );
      return;
    }

    final shareOrigin = _shareOriginFor(buttonContext);
    setState(() => _exporting = true);

    try {
      final dataSource = ref.read(marketplaceDataSourceProvider);
      final products = await Future.wait(
        overview.map((row) async {
          final reportFuture = dataSource.getProductReport(row.listingId);
          final salesFuture = dataSource.getProductSalesRows(row.listingId);
          final batchesFuture = dataSource.getProductionBatches(row.listingId);
          return MarketProductExportData(
            report: await reportFuture,
            sales: await salesFuture,
            batches: await batchesFuture,
          );
        }),
      );

      final bytes = buildMarketReportXlsx(
        overview: overview,
        products: products,
        from: _range.from,
        to: _range.to,
      );

      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '')
          .substring(0, 15);
      final file = File('${dir.path}/market_satis_raporu_$stamp.xlsx');
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

  Widget _buildRangeFilter(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasRange = _range.from != null || _range.to != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasRange
                  ? '${formatReportDate(_range.from)} - ${formatReportDate(_range.to)}'
                  : 'Tüm zamanlar',
              style: AppTypography.bodyMedium,
            ),
          ),
          if (hasRange)
            TextButton(
              onPressed: () => setState(() => _range = ReportDateRange.all),
              child: const Text('Temizle'),
            ),
          TextButton(
            onPressed: _pickRange,
            child: const Text('Tarih seç'),
          ),
        ],
      ),
    );
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

  Widget _buildBody(BuildContext context, List<MarketOverviewRow> rows) {
    if (rows.isEmpty) {
      return const Center(child: Text('Raporlanacak ürün bulunamadı'));
    }

    final totalProductionCost =
        rows.fold<double>(0, (sum, r) => sum + r.totalProductionCost);
    final totalSales = rows.fold<double>(0, (sum, r) => sum + r.totalSales);
    final totalOutstanding =
        rows.fold<double>(0, (sum, r) => sum + r.outstanding);
    final netProfit = totalSales - totalProductionCost;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(marketOverviewProvider(_range)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  context,
                  label: 'Toplam Üretim Maliyeti',
                  value: formatMoneyCompact(totalProductionCost),
                  icon: Icons.factory_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryCard(
                  context,
                  label: 'Satış Toplamı',
                  value: formatMoneyCompact(totalSales),
                  icon: Icons.sell_outlined,
                  color: AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  context,
                  label: 'Kar - Zarar',
                  value: formatMoneyCompact(netProfit),
                  icon: netProfit >= 0
                      ? Icons.trending_up
                      : Icons.trending_down,
                  color: netProfit >= 0 ? AppColors.success : AppColors.error,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryCard(
                  context,
                  label: 'Tahsil Edilmeyen',
                  value: formatMoneyCompact(totalOutstanding),
                  icon: Icons.pending_actions,
                  color: totalOutstanding > 0 ? AppColors.warning : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Ürünler',
            style: AppTypography.titleSmall
                .copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ProductRowCard(
                row: row,
                onTap: () => context.pushNamed(
                  RouteNames.marketProductReport,
                  pathParameters: {'listingId': row.listingId},
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = color ?? cs.primary;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: effectiveColor),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: effectiveColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductRowCard extends StatelessWidget {
  final MarketOverviewRow row;
  final VoidCallback onTap;

  const _ProductRowCard({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final profit = row.profitVsProduction;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (row.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    row.imageUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 44),
                  ),
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2_outlined, size: 20),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  row.title,
                  style: AppTypography.titleSmall
                      .copyWith(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _metric('Üretim', '${row.producedQuantity}'),
              _metric('Satılan', '${row.soldQuantity}'),
              _metric('Hediye', '${row.giftQuantity}'),
              _metric('Kalan', '${row.remainingQuantity}'),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: _metric('Ciro', formatMoneyCompact(row.totalSales)),
              ),
              Expanded(
                child: _metric(
                  'Maliyet',
                  formatMoneyCompact(row.totalProductionCost),
                ),
              ),
              Expanded(
                child: _metric(
                  'Kar-Zarar',
                  formatMoneyCompact(profit),
                  color: profit >= 0 ? AppColors.success : AppColors.error,
                ),
              ),
            ],
          ),
          if (row.outstanding > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: AppColors.warning),
                const SizedBox(width: 6),
                Text(
                  'Tahsil edilmeyen: ${formatMoneyCompact(row.outstanding)}',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.warning),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.labelSmall),
        Text(
          value,
          style: AppTypography.bodyMedium
              .copyWith(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}
