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
import '../../data/models/order_model.dart';
import '../../data/models/production_batch_model.dart';
import '../../utils/market_excel_export.dart';
import '../../utils/market_report_utils.dart';
import '../providers/marketplace_provider.dart';

/// Tek ürünün Excel benzeri satış ve kar-zarar raporu (admin).
class ProductReportPage extends ConsumerStatefulWidget {
  final String listingId;

  const ProductReportPage({super.key, required this.listingId});

  @override
  ConsumerState<ProductReportPage> createState() => _ProductReportPageState();
}

class _ProductReportPageState extends ConsumerState<ProductReportPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      invalidateMarketplaceCachesForWidget(
        ref,
        listingId: widget.listingId,
        refreshListingsGrid: false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final listingId = widget.listingId;
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ürün Raporu')),
        body: const Center(child: Text('Bu sayfaya erişim yetkiniz yok')),
      );
    }

    final reportAsync = ref.watch(productReportProvider(listingId));
    final salesAsync = ref.watch(productSalesRowsProvider(listingId));
    final batchesAsync = ref.watch(productionBatchesProvider(listingId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ürün Raporu'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_shopping_cart_outlined),
            tooltip: 'Satış Ekle',
            onPressed: () => _openManualSale(context),
          ),
          IconButton(
            icon: const Icon(Icons.factory_outlined),
            tooltip: 'Parti Ekle',
            onPressed: () => context.pushNamed(
              RouteNames.productionBatches,
              pathParameters: {'listingId': listingId},
            ),
          ),
          Builder(
            // Paylaşım popover'ı butonun konumundan açılsın
            builder: (buttonContext) => IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Excel olarak paylaş',
              onPressed: () => _exportExcel(
                buttonContext,
                reportAsync.valueOrNull,
                salesAsync.valueOrNull,
                batchesAsync.valueOrNull,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: () => _refresh(),
          ),
        ],
      ),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Rapor alınamadı: $e', textAlign: TextAlign.center),
          ),
        ),
        data: (report) => RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _ProductHeader(report: report),
              const SizedBox(height: 16),
              _ProductionSummaryCard(
                report: report,
                batchCount: batchesAsync.valueOrNull?.length ?? 0,
                onOpenBatches: () => context.pushNamed(
                  RouteNames.productionBatches,
                  pathParameters: {'listingId': listingId},
                ),
              ),
              const SizedBox(height: 12),
              _SalesSummaryCard(report: report),
              const SizedBox(height: 12),
              _ProfitCard(report: report),
              if (report.sizeBreakdown.isNotEmpty) ...[
                const SizedBox(height: 20),
                _sectionTitle('Beden Kırılımı'),
                _SizeBreakdownTable(rows: report.sizeBreakdown),
              ],
              const SizedBox(height: 20),
              _sectionTitle('Satış Geçmişi'),
              salesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Satış geçmişi alınamadı: $e'),
                data: (rows) => rows.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('Henüz satış kaydı yok')),
                      )
                    : _SalesTable(
                        rows: rows,
                        onRowTap: (row) => _openRowActions(context, row),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _refresh() {
    invalidateMarketplaceCachesForWidget(
      ref,
      listingId: widget.listingId,
      refreshListingsGrid: false,
    );
  }

  Future<void> _openManualSale(BuildContext context) async {
    final saved = await context.pushNamed<bool>(
      RouteNames.manualSale,
      queryParameters: {'listingId': widget.listingId},
    );
    if (saved == true) _refresh();
  }

  Future<void> _openRowActions(
    BuildContext context,
    ProductSalesRow row,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                row.buyerName,
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Düzenle'),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.error),
              title: Text('Sil', style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted || action == null) return;

    if (action == 'edit') {
      final saved = await context.pushNamed<bool>(
        RouteNames.manualSale,
        queryParameters: {'listingId': widget.listingId, 'orderId': row.orderId},
      );
      if (saved == true) _refresh();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Satışı sil'),
        content: Text(
          '${row.buyerName} adına kayıtlı satış silinecek. '
          'Stoktan düşülmüşse stok geri eklenir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await ref
        .read(manualSaleProvider.notifier)
        .deleteSale(row.orderId, widget.listingId);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Satış silindi' : 'Satış silinemedi'),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
    if (success) _refresh();
  }

  /// iOS paylaşım sayfası, popover'ı konumlandırmak için sıfırdan farklı bir
  /// kaynak dikdörtgeni ister; verilmezse paylaşım hata ile döner.
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
    BuildContext context,
    ProductReportSummary? report,
    List<ProductSalesRow>? rows,
    List<ProductionBatch>? batches,
  ) async {
    if (report == null || rows == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rapor henüz yüklenmedi')),
      );
      return;
    }

    final shareOrigin = _shareOriginFor(context);

    try {
      final bytes = buildProductReportXlsx(
        report: report,
        sales: rows,
        batches: batches ?? const [],
      );
      final dir = await getTemporaryDirectory();
      final safeTitle =
          report.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').toLowerCase();
      final file = File('${dir.path}/market_rapor_$safeTitle.xlsx');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        sharePositionOrigin: shareOrigin,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel oluşturulamadı: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ProductHeader extends StatelessWidget {
  final ProductReportSummary report;

  const _ProductHeader({required this.report});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        if (report.imageUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              report.imageUrl!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(width: 56),
            ),
          )
        else
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.inventory_2_outlined),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                report.title,
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              if (report.price != null)
                Text(
                  'Market fiyatı: ${formatMoneyCompact(report.price)}',
                  style: AppTypography.bodySmall
                      .copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductionSummaryCard extends StatelessWidget {
  final ProductReportSummary report;
  final int batchCount;
  final VoidCallback onOpenBatches;

  const _ProductionSummaryCard({
    required this.report,
    required this.batchCount,
    required this.onOpenBatches,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        children: [
          _reportRow('Üretim adedi', '${report.producedQuantity}'),
          const Divider(height: 20),
          _reportRow(
            batchCount > 1 ? 'Ort. birim maliyet' : 'Birim maliyet',
            formatMoney(report.avgUnitCost),
          ),
          const Divider(height: 20),
          _reportRow(
            'Toplam üretim maliyeti',
            formatMoney(report.productionCost),
            emphasize: true,
          ),
          const Divider(height: 20),
          _reportRow('Kalan adet', '${report.remainingQuantity}'),
          const Divider(height: 20),
          _reportRow('Güncel stok', '${report.currentStock}'),
          if (batchCount > 0) ...[
            const Divider(height: 20),
            InkWell(
              onTap: onOpenBatches,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$batchCount üretim partisi',
                        style: AppTypography.bodyMedium
                            .copyWith(color: cs.primary),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: cs.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SalesSummaryCard extends StatelessWidget {
  final ProductReportSummary report;

  const _SalesSummaryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          _reportRow(
            'Satılan',
            '${report.regularQuantity} adet',
            trailing: formatMoneyCompact(report.regularTotal),
          ),
          const Divider(height: 20),
          _reportRow(
            'İndirimli',
            '${report.discountedQuantity} adet',
            trailing: formatMoneyCompact(report.discountedTotal),
          ),
          const Divider(height: 20),
          _reportRow('Hediye', '${report.giftQuantity} adet'),
          const Divider(height: 20),
          _reportRow(
            'Satış toplamı',
            formatMoney(report.totalSales),
            emphasize: true,
          ),
          const Divider(height: 20),
          _reportRow('Tahsil edilen', formatMoney(report.totalPaid)),
          const Divider(height: 20),
          _reportRow(
            'Kalan alacak',
            formatMoney(report.outstanding),
            valueColor:
                report.outstanding > 0 ? AppColors.warning : AppColors.success,
          ),
        ],
      ),
    );
  }
}

class _ProfitCard extends StatelessWidget {
  final ProductReportSummary report;

  const _ProfitCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final profit = report.profitVsProduction;
    final color = profit >= 0 ? AppColors.success : AppColors.error;

    return AppCard(
      backgroundColor: color.withValues(alpha: 0.08),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                profit >= 0 ? Icons.trending_up : Icons.trending_down,
                color: color,
              ),
              const SizedBox(width: 10),
              Text(
                'Kar - Zarar',
                style: AppTypography.titleSmall
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                formatMoney(profit),
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Satılan ürünlerin maliyetine göre kar: ${formatMoney(report.profitVsCogs)}',
                  style: AppTypography.bodySmall
                      .copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SizeBreakdownTable extends StatelessWidget {
  final List<ProductSizeBreakdown> rows;

  const _SizeBreakdownTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          headingRowHeight: 40,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 48,
          columns: const [
            DataColumn(label: Text('Beden')),
            DataColumn(label: Text('Üretim'), numeric: true),
            DataColumn(label: Text('Satılan'), numeric: true),
            DataColumn(label: Text('Kalan'), numeric: true),
            DataColumn(label: Text('Stok'), numeric: true),
          ],
          rows: rows
              .map(
                (row) => DataRow(cells: [
                  DataCell(Text(sizeWithGenderLabel(row.size, row.gender))),
                  DataCell(Text('${row.produced}')),
                  DataCell(Text('${row.sold}')),
                  DataCell(Text('${row.remaining}')),
                  DataCell(Text('${row.stock}')),
                ]),
              )
              .toList(),
        ),
      ),
    );
  }
}

/// Excel tablosunun karşılığı: yatay kaydırmalı satış geçmişi.
class _SalesTable extends StatelessWidget {
  final List<ProductSalesRow> rows;
  final ValueChanged<ProductSalesRow> onRowTap;

  const _SalesTable({required this.rows, required this.onRowTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          headingRowHeight: 44,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 56,
          columns: const [
            DataColumn(label: Text('#'), numeric: true),
            DataColumn(label: Text('Ad-Soyad')),
            DataColumn(label: Text('Beden')),
            DataColumn(label: Text('Adet'), numeric: true),
            DataColumn(label: Text('Sipariş')),
            DataColumn(label: Text('Teslim')),
            DataColumn(label: Text('Ödeme')),
            DataColumn(label: Text('Maliyet'), numeric: true),
            DataColumn(label: Text('Satış'), numeric: true),
            DataColumn(label: Text('Tahsilat'), numeric: true),
            DataColumn(label: Text('Kar'), numeric: true),
            DataColumn(label: Text('Ödeme Şekli')),
            DataColumn(label: Text('Tip')),
            DataColumn(label: Text('Durum')),
          ],
          rows: rows.map((row) {
            final isCancelled = row.status == OrderStatus.cancelled;
            final baseStyle = isCancelled
                ? AppTypography.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                    decoration: TextDecoration.lineThrough,
                  )
                : AppTypography.bodySmall;

            return DataRow(
              onSelectChanged: (_) => onRowTap(row),
              color: row.saleType == SaleType.gift
                  ? WidgetStatePropertyAll(
                      AppColors.info.withValues(alpha: 0.08))
                  : row.outstanding > 0
                      ? WidgetStatePropertyAll(
                          AppColors.warning.withValues(alpha: 0.08))
                      : null,
              cells: [
                DataCell(Text('${row.rowNo}', style: baseStyle)),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(row.buyerName, style: baseStyle),
                      if (row.isManual) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.storefront,
                            size: 12, color: cs.onSurfaceVariant),
                      ],
                    ],
                  ),
                ),
                DataCell(Text(sizeWithGenderLabel(row.size, row.gender),
                    style: baseStyle)),
                DataCell(Text('${row.quantity}', style: baseStyle)),
                DataCell(Text(formatReportDate(row.orderDate), style: baseStyle)),
                DataCell(
                    Text(formatReportDate(row.deliveryDate), style: baseStyle)),
                DataCell(
                    Text(formatReportDate(row.paymentDate), style: baseStyle)),
                DataCell(
                    Text(formatMoneyCompact(row.totalCost), style: baseStyle)),
                DataCell(
                    Text(formatMoneyCompact(row.totalPrice), style: baseStyle)),
                DataCell(
                    Text(formatMoneyCompact(row.paidAmount), style: baseStyle)),
                DataCell(
                  Text(
                    formatMoneyCompact(row.profit),
                    style: baseStyle.copyWith(
                      fontWeight: FontWeight.w700,
                      color:
                          row.profit >= 0 ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
                DataCell(
                    Text(row.paymentMethod?.label ?? '-', style: baseStyle)),
                DataCell(Text(row.saleType.label, style: baseStyle)),
                DataCell(Text(row.status.label, style: baseStyle)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

Widget _reportRow(
  String label,
  String value, {
  String? trailing,
  bool emphasize = false,
  Color? valueColor,
}) {
  return Row(
    children: [
      Expanded(child: Text(label, style: AppTypography.bodyMedium)),
      Text(
        value,
        style: (emphasize
                ? AppTypography.titleMedium
                : AppTypography.bodyLarge)
            .copyWith(fontWeight: FontWeight.w600, color: valueColor),
      ),
      if (trailing != null) ...[
        const SizedBox(width: 12),
        SizedBox(
          width: 90,
          child: Text(
            trailing,
            textAlign: TextAlign.right,
            style: AppTypography.bodyMedium,
          ),
        ),
      ],
    ],
  );
}
