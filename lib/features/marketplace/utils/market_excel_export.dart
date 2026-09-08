import 'dart:typed_data';

import '../../../core/utils/xlsx_writer.dart';
import '../data/models/market_report_model.dart';
import '../data/models/production_batch_model.dart';
import 'market_report_utils.dart';

/// Tek ürünün Excel sekmesine yazılacak veri paketi.
class MarketProductExportData {
  final ProductReportSummary report;
  final List<ProductSalesRow> sales;
  final List<ProductionBatch> batches;

  const MarketProductExportData({
    required this.report,
    required this.sales,
    this.batches = const [],
  });
}

/// Market raporlarını çok sayfalı .xlsx dosyasına dönüştürür.
///
/// İlk sekme tüm ürünlerin özeti, sonraki sekmeler ürün başına satış
/// geçmişi + özet bloklarıdır. Harici Excel paketleri kullanılmaz;
/// projedeki [XlsxWorkbook] üretilir.
Uint8List buildMarketReportXlsx({
  required List<MarketOverviewRow> overview,
  required List<MarketProductExportData> products,
  DateTime? from,
  DateTime? to,
}) {
  final workbook = XlsxWorkbook();
  _writeOverviewSheet(workbook, overview, from: from, to: to);

  for (final product in products) {
    _writeProductSheet(workbook, product);
  }

  return workbook.encode();
}

/// Tek ürün raporu için tek sayfalı .xlsx.
Uint8List buildProductReportXlsx({
  required ProductReportSummary report,
  required List<ProductSalesRow> sales,
  List<ProductionBatch> batches = const [],
}) {
  final workbook = XlsxWorkbook();
  _writeProductSheet(
    workbook,
    MarketProductExportData(
      report: report,
      sales: sales,
      batches: batches,
    ),
  );
  return workbook.encode();
}

void _writeOverviewSheet(
  XlsxWorkbook workbook,
  List<MarketOverviewRow> overview, {
  DateTime? from,
  DateTime? to,
}) {
  final sheet = workbook.addSheet('Özet');
  sheet.setColumnWidths({
    0: 28,
    1: 10,
    2: 12,
    3: 10,
    4: 10,
    5: 10,
    6: 10,
    7: 14,
    8: 14,
    9: 12,
    10: 14,
    11: 14,
  });

  sheet.setText(0, 0, 'Market Satış Raporu', style: XlsxStyle.title);
  sheet.merge(0, 0, colSpan: 4);

  final rangeLabel = from == null && to == null
      ? 'Tüm zamanlar'
      : '${formatReportDate(from)} - ${formatReportDate(to)}';
  sheet.setText(1, 0, 'Dönem: $rangeLabel', style: XlsxStyle.subtitle);

  final totalProduction =
      overview.fold<double>(0, (s, r) => s + r.totalProductionCost);
  final totalSales = overview.fold<double>(0, (s, r) => s + r.totalSales);
  final totalPaid = overview.fold<double>(0, (s, r) => s + r.totalPaid);
  final totalOutstanding =
      overview.fold<double>(0, (s, r) => s + r.outstanding);
  final netProfit = totalSales - totalProduction;
  final totalProduced =
      overview.fold<int>(0, (s, r) => s + r.producedQuantity);
  final totalSold = overview.fold<int>(0, (s, r) => s + r.soldQuantity);
  final totalGift = overview.fold<int>(0, (s, r) => s + r.giftQuantity);
  final totalRemaining =
      overview.fold<int>(0, (s, r) => s + r.remainingQuantity);

  const summaryStart = 3;
  sheet.setText(summaryStart, 0, 'GENEL ÖZET', style: XlsxStyle.sectionHeader);
  sheet.merge(summaryStart, 0, colSpan: 2);

  final summaryRows = <(String, Object?)>[
    ('Toplam üretim adedi', totalProduced),
    ('Toplam üretim maliyeti', totalProduction),
    ('Satılan adet', totalSold),
    ('Hediye adet', totalGift),
    ('Kalan adet', totalRemaining),
    ('Satış toplamı', totalSales),
    ('Tahsil edilen', totalPaid),
    ('Tahsil edilmeyen', totalOutstanding),
    ('Kar - Zarar', netProfit),
  ];

  for (var i = 0; i < summaryRows.length; i++) {
    final (label, value) = summaryRows[i];
    final row = summaryStart + 1 + i;
    sheet.setText(row, 0, label, style: XlsxStyle.label);
    if (value is int) {
      sheet.setNumber(row, 1, value, style: XlsxStyle.integerBold);
    } else {
      sheet.setNumber(
        row,
        1,
        value as num,
        style: label == 'Kar - Zarar' || label.contains('maliyet') ||
                label.contains('Satış') || label.contains('Tahsil')
            ? XlsxStyle.moneyBold
            : XlsxStyle.money,
      );
    }
  }

  final tableHeaderRow = summaryStart + summaryRows.length + 3;
  sheet.setText(
    tableHeaderRow - 1,
    0,
    'ÜRÜN BAZLI ÖZET',
    style: XlsxStyle.sectionHeader,
  );

  const headers = [
    'Ürün',
    'Üretim',
    'Birim maliyet',
    'Satılan',
    'İndirimli',
    'Hediye',
    'Kalan',
    'Ciro',
    'Üretim maliyeti',
    'Kar-Zarar',
    'Tahsil edilen',
    'Tahsil edilmeyen',
  ];
  for (var c = 0; c < headers.length; c++) {
    sheet.setText(tableHeaderRow, c, headers[c], style: XlsxStyle.columnHeader);
  }

  for (var i = 0; i < overview.length; i++) {
    final row = overview[i];
    final r = tableHeaderRow + 1 + i;
    sheet.setText(r, 0, row.title, style: XlsxStyle.text);
    sheet.setNumber(r, 1, row.producedQuantity, style: XlsxStyle.integer);
    if (row.avgUnitCost != null) {
      sheet.setNumber(r, 2, row.avgUnitCost, style: XlsxStyle.money);
    } else {
      sheet.setBlank(r, 2);
    }
    sheet.setNumber(r, 3, row.soldQuantity, style: XlsxStyle.integer);
    sheet.setNumber(r, 4, row.discountedQuantity, style: XlsxStyle.integer);
    sheet.setNumber(r, 5, row.giftQuantity, style: XlsxStyle.integer);
    sheet.setNumber(r, 6, row.remainingQuantity, style: XlsxStyle.integer);
    sheet.setNumber(r, 7, row.totalSales, style: XlsxStyle.money);
    sheet.setNumber(r, 8, row.totalProductionCost, style: XlsxStyle.money);
    sheet.setNumber(r, 9, row.profitVsProduction, style: XlsxStyle.moneyBold);
    sheet.setNumber(r, 10, row.totalPaid, style: XlsxStyle.money);
    sheet.setNumber(r, 11, row.outstanding, style: XlsxStyle.money);
  }
}

void _writeProductSheet(
  XlsxWorkbook workbook,
  MarketProductExportData data,
) {
  final report = data.report;
  final sales = data.sales;
  final sheet = workbook.addSheet(report.title);

  // Sol: satış geçmişi (A-L), sağ: özet blokları (N-R)
  sheet.setColumnWidths({
    0: 6,
    1: 22,
    2: 12,
    3: 7,
    4: 13,
    5: 13,
    6: 13,
    7: 12,
    8: 12,
    9: 13,
    10: 12,
    11: 13,
    12: 11,
    13: 12,
    14: 12,
    15: 8,
    16: 12,
    17: 12,
    18: 28,
  });

  sheet.setText(0, 0, report.title, style: XlsxStyle.title);
  sheet.merge(0, 0, colSpan: 4);
  if (report.price != null) {
    sheet.setText(0, 4, 'Market fiyatı', style: XlsxStyle.label);
    sheet.setNumber(0, 5, report.price, style: XlsxStyle.moneyBold);
  }

  // --- Satış tablosu başlıkları (hemen 2. satırda; boş satır bırakma) ---
  const salesHeaderRow = 1;
  const salesHeaders = [
    'SAYI',
    'AD-SOYAD',
    'BEDEN',
    'ADET',
    'SİPARİŞ TARİHİ',
    'TESLİM TARİHİ',
    'ÖDEME TARİHİ',
    'MALİYET',
    'SATIŞ',
    'TOPLAM ÖDEME',
    'TOPLAM KAR',
    'ÖDEME ŞEKLİ',
    'TİP',
    'DURUM',
  ];
  for (var c = 0; c < salesHeaders.length; c++) {
    sheet.setText(
      salesHeaderRow,
      c,
      salesHeaders[c],
      style: XlsxStyle.columnHeader,
    );
  }

  for (var i = 0; i < sales.length; i++) {
    final row = sales[i];
    final r = salesHeaderRow + 1 + i;
    sheet.setNumber(r, 0, row.rowNo, style: XlsxStyle.integer);
    sheet.setText(r, 1, row.buyerName, style: XlsxStyle.text);
    sheet.setText(
      r,
      2,
      sizeWithGenderLabel(row.size, row.gender),
      style: XlsxStyle.center,
    );
    sheet.setNumber(r, 3, row.quantity, style: XlsxStyle.integer);
    sheet.setDate(r, 4, row.orderDate);
    sheet.setDate(r, 5, row.deliveryDate);
    sheet.setDate(r, 6, row.paymentDate);
    sheet.setNumber(r, 7, row.totalCost, style: XlsxStyle.money);
    sheet.setNumber(r, 8, row.totalPrice, style: XlsxStyle.money);
    sheet.setNumber(r, 9, row.paidAmount, style: XlsxStyle.money);
    sheet.setNumber(r, 10, row.profit, style: XlsxStyle.money);
    sheet.setText(r, 11, row.paymentMethod?.label, style: XlsxStyle.text);
    sheet.setText(r, 12, row.saleType.label, style: XlsxStyle.center);
    sheet.setText(r, 13, row.status.label, style: XlsxStyle.center);
  }

  // --- Sağ özet blokları ---
  const summaryCol = 14;
  var sr = 0;

  sheet.setText(
    sr,
    summaryCol,
    'ÜRETİM PARTİLERİ',
    style: XlsxStyle.sectionHeader,
  );
  sheet.merge(sr, summaryCol, colSpan: 5);
  sr++;
  sheet.setText(sr, summaryCol, 'Tarih', style: XlsxStyle.columnHeader);
  sheet.setText(sr, summaryCol + 1, 'Adet', style: XlsxStyle.columnHeader);
  sheet.setText(
    sr,
    summaryCol + 2,
    'Birim maliyet',
    style: XlsxStyle.columnHeader,
  );
  sheet.setText(sr, summaryCol + 3, 'Toplam', style: XlsxStyle.columnHeader);
  sheet.setText(sr, summaryCol + 4, 'Açıklama', style: XlsxStyle.columnHeader);
  sr++;

  final batches = List<ProductionBatch>.from(data.batches)
    ..sort((a, b) => a.producedAt.compareTo(b.producedAt));

  if (batches.isEmpty) {
    // Parti yoksa tek satırda toplam üretim özeti göster
    sheet.setText(sr, summaryCol, 'Kayıt yok', style: XlsxStyle.text);
    sheet.setNumber(
      sr,
      summaryCol + 1,
      report.producedQuantity,
      style: XlsxStyle.integer,
    );
    if (report.avgUnitCost != null) {
      sheet.setNumber(
        sr,
        summaryCol + 2,
        report.avgUnitCost,
        style: XlsxStyle.money,
      );
    } else {
      sheet.setBlank(sr, summaryCol + 2);
    }
    sheet.setNumber(
      sr,
      summaryCol + 3,
      report.productionCost,
      style: XlsxStyle.moneyHighlight,
    );
    sheet.setBlank(sr, summaryCol + 4);
    sr++;
  } else {
    for (final batch in batches) {
      sheet.setDate(sr, summaryCol, batch.producedAt);
      sheet.setNumber(
        sr,
        summaryCol + 1,
        batch.totalQuantity,
        style: XlsxStyle.integer,
      );
      sheet.setNumber(sr, summaryCol + 2, batch.unitCost, style: XlsxStyle.money);
      sheet.setNumber(sr, summaryCol + 3, batch.totalCost, style: XlsxStyle.money);
      sheet.setText(sr, summaryCol + 4, batch.note, style: XlsxStyle.text);
      sr++;
    }
  }

  sheet.setText(sr, summaryCol, 'TOPLAM', style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 1,
    report.producedQuantity,
    style: XlsxStyle.integerBold,
  );
  if (report.avgUnitCost != null) {
    sheet.setNumber(
      sr,
      summaryCol + 2,
      report.avgUnitCost,
      style: XlsxStyle.moneyBold,
    );
  } else {
    sheet.setBlank(sr, summaryCol + 2, style: XlsxStyle.label);
  }
  sheet.setNumber(
    sr,
    summaryCol + 3,
    report.productionCost,
    style: XlsxStyle.moneyHighlight,
  );
  sheet.setText(
    sr,
    summaryCol + 4,
    batches.length > 1 ? 'Ort. birim maliyet' : null,
    style: XlsxStyle.subtitle,
  );
  sr += 2;

  sheet.setText(sr, summaryCol, 'SATIŞ ÖZETİ', style: XlsxStyle.sectionHeader);
  sheet.merge(sr, summaryCol, colSpan: 3);
  sr++;
  sheet.setText(sr, summaryCol, '', style: XlsxStyle.columnHeader);
  sheet.setText(sr, summaryCol + 1, 'Adet', style: XlsxStyle.columnHeader);
  sheet.setText(sr, summaryCol + 2, 'Tutar', style: XlsxStyle.columnHeader);
  sr++;

  void salesSummaryLine(String label, int qty, double? amount) {
    sheet.setText(sr, summaryCol, label, style: XlsxStyle.label);
    sheet.setNumber(sr, summaryCol + 1, qty, style: XlsxStyle.integer);
    if (amount != null) {
      sheet.setNumber(sr, summaryCol + 2, amount, style: XlsxStyle.money);
    } else {
      sheet.setBlank(sr, summaryCol + 2);
    }
    sr++;
  }

  final regularQty = report.regularQuantity;
  salesSummaryLine('Satılan (normal)', regularQty, report.regularTotal);
  salesSummaryLine(
    'İndirimli',
    report.discountedQuantity,
    report.discountedTotal,
  );
  salesSummaryLine('Hediye', report.giftQuantity, null);
  sheet.setText(sr, summaryCol, 'Satış toplamı', style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 1,
    report.totalSoldQuantity,
    style: XlsxStyle.integerBold,
  );
  sheet.setNumber(
    sr,
    summaryCol + 2,
    report.totalSales,
    style: XlsxStyle.moneyHighlight,
  );
  sr += 2;

  sheet.setText(sr, summaryCol, 'KAR - ZARAR', style: XlsxStyle.sectionHeader);
  sheet.merge(sr, summaryCol, colSpan: 3);
  sr++;
  sheet.setText(sr, summaryCol, 'Üretim maliyetine göre', style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 2,
    report.profitVsProduction,
    style: XlsxStyle.moneyHighlight,
  );
  sr++;
  sheet.setText(sr, summaryCol, 'Satılan maliyetine göre', style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 2,
    report.profitVsCogs,
    style: XlsxStyle.moneyBold,
  );
  sr++;
  sheet.setText(sr, summaryCol, 'Tahsil edilen', style: XlsxStyle.label);
  sheet.setNumber(sr, summaryCol + 2, report.totalPaid, style: XlsxStyle.money);
  sr++;
  sheet.setText(sr, summaryCol, 'Tahsil edilmeyen', style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 2,
    report.outstanding,
    style: XlsxStyle.moneyBold,
  );
  sr++;
  sheet.setText(sr, summaryCol, 'Kalan adet', style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 2,
    report.remainingQuantity,
    style: XlsxStyle.integerBold,
  );
  sr += 2;

  if (report.sizeBreakdown.isNotEmpty) {
    sheet.setText(
      sr,
      summaryCol,
      'BEDEN KIRILIMI',
      style: XlsxStyle.sectionHeader,
    );
    sheet.merge(sr, summaryCol, colSpan: 5);
    sr++;
    sheet.setText(sr, summaryCol, 'Beden', style: XlsxStyle.columnHeader);
    sheet.setText(sr, summaryCol + 1, 'Üretim', style: XlsxStyle.columnHeader);
    sheet.setText(sr, summaryCol + 2, 'Satılan', style: XlsxStyle.columnHeader);
    sheet.setText(sr, summaryCol + 3, 'Kalan', style: XlsxStyle.columnHeader);
    sheet.setText(sr, summaryCol + 4, 'Stok', style: XlsxStyle.columnHeader);
    sr++;
    for (final size in report.sizeBreakdown) {
      sheet.setText(
        sr,
        summaryCol,
        sizeWithGenderLabel(size.size, size.gender),
        style: XlsxStyle.text,
      );
      sheet.setNumber(sr, summaryCol + 1, size.produced, style: XlsxStyle.integer);
      sheet.setNumber(sr, summaryCol + 2, size.sold, style: XlsxStyle.integer);
      sheet.setNumber(
        sr,
        summaryCol + 3,
        size.remaining,
        style: XlsxStyle.integer,
      );
      sheet.setNumber(sr, summaryCol + 4, size.stock, style: XlsxStyle.integer);
      sr++;
    }
  }
}
