import 'dart:typed_data';

import '../../../core/utils/xlsx_writer.dart';
import '../../marketplace/data/models/order_model.dart';
import '../../marketplace/utils/market_excel_export.dart';
import '../../marketplace/utils/market_report_utils.dart';
import '../data/models/event_finance_model.dart';
import '../data/models/finance_report_model.dart';

/// Genel kasa raporunu çok sayfalı .xlsx dosyasına dönüştürür.
///
/// İlk sekme toplam özet, sonraki sekmeler her ürün ve her etkinlik için
/// market raporuyla aynı düzendedir: solda satış satırları, sağda özet blokları.
///
/// Toplam sekmesindeki kar/zarar, market ürünlerinde brüt satıştan tüm
/// üretim maliyetini düşer. Elde kalan stok bu yüzden kârı şişirmez.
Uint8List buildFinanceOverviewXlsx({
  required List<FinanceOverviewRow> rows,
  Map<String, MarketProductExportData> products = const {},
  Map<String, EventFinanceDetail> events = const {},
  DateTime? from,
  DateTime? to,
  FinanceSource? sourceFilter,
}) {
  final workbook = XlsxWorkbook();
  _writeTotalsSheet(
    workbook,
    rows,
    products: products,
    events: events,
    from: from,
    to: to,
    sourceFilter: sourceFilter,
  );

  for (final row in rows) {
    if (row.source == FinanceSource.market) {
      final product = products[row.refId];
      if (product != null) writeMarketProductSheet(workbook, product);
    } else {
      final event = events[row.refId];
      if (event != null) writeEventFinanceSheet(workbook, event);
    }
  }

  return workbook.encode();
}

void _writeTotalsSheet(
  XlsxWorkbook workbook,
  List<FinanceOverviewRow> rows, {
  required Map<String, MarketProductExportData> products,
  required Map<String, EventFinanceDetail> events,
  DateTime? from,
  DateTime? to,
  FinanceSource? sourceFilter,
}) {
  final sheet = workbook.addSheet('Toplam');
  sheet.setColumnWidths({
    0: 28,
    1: 28,
    2: 14,
    3: 12,
    4: 11,
    5: 12,
    6: 11,
    7: 14,
    8: 14,
    9: 11,
    10: 14,
    11: 16,
    12: 18,
    13: 16,
    14: 16,
    15: 14,
    16: 16,
    17: 16,
    18: 16,
    19: 18,
  });
  sheet.freeze(cols: 2);

  final lines = [
    for (final row in rows) _CashLine.fromOverview(row, products, events),
  ];
  final market = lines.where((line) => line.isMarket).toList();
  final eventLines = lines.where((line) => !line.isMarket).toList();

  sheet.setText(0, 0, 'Kasa Raporu', style: XlsxStyle.title);
  sheet.merge(0, 0, colSpan: 4);

  final rangeLabel = from == null && to == null
      ? 'Tüm zamanlar'
      : '${formatReportDate(from)} - ${formatReportDate(to)}';
  final sourceLabel = sourceFilter?.label ?? 'Tümü';
  sheet.setText(
    1,
    0,
    'Dönem: $rangeLabel  ·  Kaynak: $sourceLabel',
    style: XlsxStyle.subtitle,
  );
  sheet.setText(
    2,
    0,
    'Kar / Zarar = brüt satış − üretim maliyeti − etkinlik gideri. '
    'Elde kalan ürünün maliyeti satışla kapanmadıysa sonuç zarardır. '
    'Gerçekleşen kâr yalnız giden birimlerin satışından onların maliyetini düşer.',
    style: XlsxStyle.subtitle,
  );
  sheet.merge(2, 0, colSpan: 12);

  final physical = market.where((line) => !line.isBundle);
  final produced = _sumInt(physical, (line) => line.produced);
  final gone = _sumInt(physical, (line) => line.gone);
  final bundleUnits = _sumInt(
    market.where((line) => line.isBundle),
    (line) => line.gone,
  );
  final remaining = _sumInt(physical, (line) => line.remaining);
  final productionCost = _sumOrNull(market, (line) => line.productionCost) ?? 0;
  final remainingCost = _sumOrNull(market, (line) => line.remainingCost) ?? 0;
  final soldCost = _sumOrNull(market, (line) => line.soldCost) ?? 0;
  final marketGross = _sum(market, (line) => line.gross);
  final marketRealized = _sum(market, (line) => line.realized);
  final marketPosition = _sum(market, (line) => line.position);
  final eventCost = _sumOrNull(eventLines, (line) => line.eventCost) ?? 0;
  final eventNet = _sum(eventLines, (line) => line.position);
  final gross = _sum(lines, (line) => line.gross);
  final collected = _sum(lines, (line) => line.collected);
  final outstanding = _sum(lines, (line) => line.outstanding);
  final realized = marketRealized + eventNet;
  final position = marketPosition + eventNet;

  const summaryStart = 4;
  final summary = <(String, num, bool)>[
    ('GENEL', 0, false),
    ('Brüt ciro', gross, true),
    ('Tahsil edilen', collected, true),
    ('Tahsil edilmeyen', outstanding, true),
    ('MARKET', 0, false),
    ('Üretilen adet', produced, false),
    ('Giden ürün adedi', gone, false),
    ('Paket satış adedi', bundleUnits, false),
    ('Kalan adet', remaining, false),
    ('Üretim maliyeti', productionCost, true),
    ('Satılan maliyet', soldCost, true),
    ('Kalan stok maliyeti', remainingCost, true),
    ('Market brüt', marketGross, true),
    ('Market gerçekleşen kâr', marketRealized, true),
    ('Market kar / zarar', marketPosition, true),
    ('ETKİNLİK', 0, false),
    ('Etkinlik gideri', eventCost, true),
    ('Etkinlik net', eventNet, true),
    ('SONUÇ', 0, false),
    ('Gerçekleşen kâr', realized, true),
    ('Kar / Zarar', position, true),
  ];

  var cursor = summaryStart;
  for (final (label, value, isMoney) in summary) {
    if (const {'GENEL', 'MARKET', 'ETKİNLİK', 'SONUÇ'}.contains(label)) {
      sheet.setText(cursor, 0, label, style: XlsxStyle.sectionHeader);
      sheet.merge(cursor, 0, colSpan: 2);
      cursor++;
      continue;
    }
    final highlight = label == 'Kar / Zarar' || label == 'Market kar / zarar';
    sheet.setText(cursor, 0, label, style: XlsxStyle.label);
    if (isMoney) {
      sheet.setNumber(
        cursor,
        1,
        value,
        style: highlight ? XlsxStyle.moneyHighlight : XlsxStyle.moneyBold,
      );
    } else {
      sheet.setNumber(cursor, 1, value, style: XlsxStyle.integerBold);
    }
    cursor++;
  }

  final tableHeaderRow = cursor + 2;
  sheet.setText(
    tableHeaderRow - 1,
    0,
    'KAYNAK BAZLI ÖZET',
    style: XlsxStyle.sectionHeader,
  );
  sheet.merge(tableHeaderRow - 1, 0, colSpan: 4);

  const headers = [
    'Kaynak',
    'Başlık',
    'Tarih',
    'Üretilen',
    'Normal',
    'İndirimli',
    'Hediye',
    'Paketle giden',
    'Toplam giden',
    'Kalan',
    'Birim maliyet',
    'Üretim maliyeti',
    'Kalan stok maliyeti',
    'Satılan maliyet',
    'Etkinlik gideri',
    'Brüt satış',
    'Gerçekleşen kâr',
    'Kar / Zarar',
    'Tahsil edilen',
    'Tahsil edilmeyen',
  ];
  for (var c = 0; c < headers.length; c++) {
    sheet.setText(tableHeaderRow, c, headers[c], style: XlsxStyle.columnHeader);
  }

  for (var i = 0; i < lines.length; i++) {
    lines[i].write(sheet, tableHeaderRow + 1 + i);
  }

  var footer = tableHeaderRow + 1 + lines.length;
  if (market.isNotEmpty) {
    _writeCashFooter(sheet, footer, 'Market toplam', market, kind: _FooterKind.market);
    footer++;
  }
  if (eventLines.isNotEmpty) {
    _writeCashFooter(
      sheet,
      footer,
      'Etkinlik toplam',
      eventLines,
      kind: _FooterKind.event,
    );
    footer++;
  }
  _writeCashFooter(sheet, footer, 'Genel toplam', lines, kind: _FooterKind.all);
}

enum _FooterKind { market, event, all }

void _writeCashFooter(
  XlsxSheet sheet,
  int row,
  String label,
  List<_CashLine> lines, {
  required _FooterKind kind,
}) {
  final physical = lines.where((line) => line.isMarket && !line.isBundle);
  final showInventory = kind == _FooterKind.market;
  final showSaleSplit = kind != _FooterKind.all;

  sheet.setText(row, 0, label, style: XlsxStyle.textBold);
  sheet.setBlank(row, 1, style: XlsxStyle.textBold);
  sheet.setBlank(row, 2, style: XlsxStyle.label);
  _qtyCell(
    sheet,
    row,
    3,
    showInventory ? _sumInt(physical, (line) => line.produced) : null,
    bold: true,
  );
  _qtyCell(
    sheet,
    row,
    4,
    showSaleSplit ? _sumInt(lines, (line) => line.regular) : null,
    bold: true,
  );
  _qtyCell(
    sheet,
    row,
    5,
    showSaleSplit ? _sumInt(lines, (line) => line.discounted) : null,
    bold: true,
  );
  _qtyCell(
    sheet,
    row,
    6,
    showSaleSplit ? _sumInt(lines, (line) => line.gift) : null,
    bold: true,
  );
  _qtyCell(
    sheet,
    row,
    7,
    showInventory ? _sumInt(lines, (line) => line.bundleGone) : null,
    bold: true,
  );
  _qtyCell(
    sheet,
    row,
    8,
    kind == _FooterKind.all ? null : _sumInt(lines, (line) => line.gone),
    bold: true,
  );
  _qtyCell(
    sheet,
    row,
    9,
    showInventory ? _sumInt(physical, (line) => line.remaining) : null,
    bold: true,
  );
  sheet.setBlank(row, 10, style: XlsxStyle.label);
  _moneyCell(sheet, row, 11, _sumOrNull(lines, (line) => line.productionCost), bold: true);
  _moneyCell(sheet, row, 12, _sumOrNull(lines, (line) => line.remainingCost), bold: true);
  _moneyCell(sheet, row, 13, _sumOrNull(lines, (line) => line.soldCost), bold: true);
  _moneyCell(sheet, row, 14, _sumOrNull(lines, (line) => line.eventCost), bold: true);
  _moneyCell(sheet, row, 15, _sum(lines, (line) => line.gross), bold: true);
  _moneyCell(
    sheet,
    row,
    16,
    _sum(lines, (line) => line.isMarket ? line.realized : line.position),
    bold: true,
  );
  _moneyCell(sheet, row, 17, _sum(lines, (line) => line.position), highlight: true);
  _moneyCell(sheet, row, 18, _sum(lines, (line) => line.collected), bold: true);
  _moneyCell(sheet, row, 19, _sum(lines, (line) => line.outstanding), bold: true);
}

double _sum(Iterable<_CashLine> lines, double Function(_CashLine line) pick) {
  return lines.fold<double>(0, (sum, line) => sum + pick(line));
}

double? _sumOrNull(
  Iterable<_CashLine> lines,
  double? Function(_CashLine line) pick,
) {
  final values = lines.map(pick).whereType<double>().toList();
  if (values.isEmpty) return null;
  return values.fold<double>(0, (sum, value) => sum + value);
}

int _sumInt(Iterable<_CashLine> lines, int? Function(_CashLine line) pick) {
  return lines.fold<int>(0, (sum, line) => sum + (pick(line) ?? 0));
}

void _qtyCell(
  XlsxSheet sheet,
  int row,
  int col,
  int? value, {
  bool bold = false,
}) {
  if (value == null) {
    sheet.setBlank(row, col, style: bold ? XlsxStyle.integerBold : XlsxStyle.integer);
    return;
  }
  sheet.setNumber(
    row,
    col,
    value,
    style: bold ? XlsxStyle.integerBold : XlsxStyle.integer,
  );
}

void _moneyCell(
  XlsxSheet sheet,
  int row,
  int col,
  double? value, {
  bool bold = false,
  bool highlight = false,
}) {
  if (value == null) {
    sheet.setBlank(row, col, style: bold ? XlsxStyle.moneyBold : XlsxStyle.money);
    return;
  }
  sheet.setNumber(
    row,
    col,
    value,
    style: highlight
        ? XlsxStyle.moneyHighlight
        : (bold ? XlsxStyle.moneyBold : XlsxStyle.money),
  );
}

/// Toplam sekmesindeki tek satır. Market rakamları ürün sekmesiyle aynı kaynaktır.
class _CashLine {
  final bool isMarket;
  final bool isBundle;
  final String sourceLabel;
  final String title;
  final DateTime? date;
  final int? produced;
  final int? regular;
  final int? discounted;
  final int? gift;
  final int? bundleGone;
  final int? gone;
  final int? remaining;
  final double? unitCost;
  final double? productionCost;
  final double? remainingCost;
  final double? soldCost;
  final double? eventCost;
  final double gross;
  final double realized;
  final double position;
  final double collected;
  final double outstanding;

  const _CashLine({
    required this.isMarket,
    required this.isBundle,
    required this.sourceLabel,
    required this.title,
    required this.date,
    required this.produced,
    required this.regular,
    required this.discounted,
    required this.gift,
    required this.bundleGone,
    required this.gone,
    required this.remaining,
    required this.unitCost,
    required this.productionCost,
    required this.remainingCost,
    required this.soldCost,
    required this.eventCost,
    required this.gross,
    required this.realized,
    required this.position,
    required this.collected,
    required this.outstanding,
  });

  factory _CashLine.fromOverview(
    FinanceOverviewRow row,
    Map<String, MarketProductExportData> products,
    Map<String, EventFinanceDetail> events,
  ) {
    if (row.source == FinanceSource.market) {
      final report = products[row.refId]?.report;
      if (report == null) {
        return _CashLine(
          isMarket: true,
          isBundle: false,
          sourceLabel: row.source.label,
          title: row.title,
          date: row.refDate,
          produced: null,
          regular: null,
          discounted: null,
          gift: null,
          bundleGone: null,
          gone: row.quantity,
          remaining: null,
          unitCost: null,
          productionCost: null,
          remainingCost: null,
          soldCost: row.cost,
          eventCost: null,
          gross: row.gross,
          realized: row.net,
          position: row.net,
          collected: row.collected,
          outstanding: row.outstanding,
        );
      }
      final remainingCost = remainingInventoryCost(
        isBundle: report.isBundle,
        remainingQuantity: report.remainingQuantity,
        producedQuantity: report.producedQuantity,
        productionCost: report.productionCost,
        avgUnitCost: report.avgUnitCost,
      );
      return _CashLine(
        isMarket: true,
        isBundle: report.isBundle,
        sourceLabel: report.isBundle ? 'Paket' : 'Market',
        title: report.title.isEmpty ? row.title : report.title,
        date: row.refDate,
        produced: report.isBundle ? null : report.producedQuantity,
        regular: report.regularQuantity,
        discounted: report.discountedQuantity,
        gift: report.giftQuantity,
        bundleGone: report.bundleSoldQuantity,
        gone: report.totalSoldQuantity + report.bundleSoldQuantity,
        remaining: report.remainingQuantity,
        unitCost: report.avgUnitCost,
        productionCost: report.isBundle ? null : report.productionCost,
        remainingCost: report.isBundle ? null : remainingCost,
        soldCost: report.totalCogs,
        eventCost: null,
        gross: report.totalSales,
        realized: report.profitVsCogs,
        position: report.profitVsProduction,
        collected: report.totalPaid,
        outstanding: report.outstanding,
      );
    }

    final detail = events[row.refId];
    final summary = detail?.summary;
    return _CashLine(
      isMarket: false,
      isBundle: false,
      sourceLabel: 'Etkinlik',
      title: detail?.title.isNotEmpty == true ? detail!.title : row.title,
      date: row.refDate ?? detail?.startTime,
      produced: null,
      regular: summary?.regularCount,
      discounted: summary?.discountedCount,
      gift: summary?.giftCount,
      bundleGone: null,
      gone: summary?.participantCount ?? row.quantity,
      remaining: null,
      unitCost: null,
      productionCost: null,
      remainingCost: null,
      soldCost: null,
      eventCost: summary?.totalPartnerShare ?? row.cost,
      gross: summary?.totalSales ?? row.gross,
      realized: summary?.netProfit ?? row.net,
      position: summary?.netProfit ?? row.net,
      collected: summary?.totalPaid ?? row.collected,
      outstanding: summary?.outstanding ?? row.outstanding,
    );
  }

  void write(XlsxSheet sheet, int row) {
    sheet.setText(row, 0, sourceLabel, style: XlsxStyle.text);
    sheet.setText(row, 1, title, style: XlsxStyle.text);
    sheet.setDate(row, 2, date);
    _qtyCell(sheet, row, 3, produced);
    _qtyCell(sheet, row, 4, regular);
    _qtyCell(sheet, row, 5, discounted);
    _qtyCell(sheet, row, 6, gift);
    _qtyCell(sheet, row, 7, bundleGone);
    _qtyCell(sheet, row, 8, gone);
    _qtyCell(sheet, row, 9, remaining);
    _moneyCell(sheet, row, 10, unitCost);
    _moneyCell(sheet, row, 11, productionCost);
    _moneyCell(sheet, row, 12, remainingCost);
    _moneyCell(sheet, row, 13, soldCost);
    _moneyCell(sheet, row, 14, eventCost);
    _moneyCell(sheet, row, 15, gross);
    _moneyCell(sheet, row, 16, isMarket ? realized : position);
    _moneyCell(sheet, row, 17, position, highlight: true);
    _moneyCell(sheet, row, 18, collected);
    _moneyCell(sheet, row, 19, outstanding);
  }
}

/// Tek etkinliğin satış listesini market ürün sekmesiyle aynı düzende üretir.
Uint8List buildEventFinanceXlsx(EventFinanceDetail detail) {
  final workbook = XlsxWorkbook();
  writeEventFinanceSheet(workbook, detail);
  return workbook.encode();
}

/// Etkinlik sekmesi: solda katılımcı satırları, sağda gider ve kâr blokları.
void writeEventFinanceSheet(XlsxWorkbook workbook, EventFinanceDetail detail) {
  final sheet = workbook.addSheet(detail.title);
  final summary = detail.summary;

  sheet.setColumnWidths({
    0: 6,
    1: 22,
    2: 7,
    3: 13,
    4: 13,
    5: 12,
    6: 12,
    7: 13,
    8: 12,
    9: 13,
    10: 11,
    11: 12,
    12: 18,
    13: 18,
    14: 12,
    15: 14,
    16: 14,
    17: 28,
  });

  sheet.setText(0, 0, detail.title, style: XlsxStyle.title);
  sheet.merge(0, 0, colSpan: 4);
  if (detail.ticketPrice != null) {
    sheet.setText(0, 4, 'Bilet fiyatı', style: XlsxStyle.label);
    sheet.setNumber(0, 5, detail.ticketPrice, style: XlsxStyle.moneyBold);
  }

  const salesHeaderRow = 1;
  final salesHeaders = [
    'SAYI',
    'AD-SOYAD',
    'ADET',
    'KAYIT TARİHİ',
    'ÖDEME TARİHİ',
    'MALİYET',
    'SATIŞ',
    'TOPLAM ÖDEME',
    'TOPLAM KAR',
    'ÖDEME ŞEKLİ',
    'TİP',
    'KATILIM',
    if (detail.menuOptions.isNotEmpty) 'MENÜ',
  ];
  for (var c = 0; c < salesHeaders.length; c++) {
    sheet.setText(
      salesHeaderRow,
      c,
      salesHeaders[c],
      style: XlsxStyle.columnHeader,
    );
  }

  final orderedSales = List<EventSaleRow>.from(detail.sales)
    ..sort(compareEventSales);
  for (var i = 0; i < orderedSales.length; i++) {
    final sale = orderedSales[i];
    final styles = SalesRowStyles.of(eventSalesRowTone(sale));
    final r = salesHeaderRow + 1 + i;
    sheet.setNumber(r, 0, i + 1, style: styles.integer);
    sheet.setText(r, 1, sale.buyerName, style: styles.text);
    sheet.setNumber(r, 2, sale.quantity, style: styles.integer);
    sheet.setDate(r, 3, sale.createdAt, style: styles.date);
    sheet.setDate(r, 4, sale.paymentDate, style: styles.date);
    sheet.setNumber(r, 5, sale.totalPartnerShare, style: styles.money);
    sheet.setNumber(r, 6, sale.totalPrice, style: styles.money);
    sheet.setNumber(r, 7, sale.paidAmount, style: styles.money);
    sheet.setNumber(r, 8, sale.net, style: styles.money);
    sheet.setText(r, 9, sale.paymentMethod?.label, style: styles.text);
    sheet.setText(r, 10, sale.saleType.label, style: styles.center);
    sheet.setText(
      r,
      11,
      sale.isCancelled ? '-' : (sale.checkedIn ? 'Katıldı' : 'Katılmadı'),
      style: styles.center,
    );
    if (detail.menuOptions.isNotEmpty) {
      sheet.setText(r, 12, sale.menuChoice, style: styles.text);
    }
  }

  const summaryCol = 13;
  var sr = 0;

  sheet.setText(sr, summaryCol, 'GİDERLER', style: XlsxStyle.sectionHeader);
  sheet.merge(sr, summaryCol, colSpan: 5);
  sr++;
  sheet.setText(sr, summaryCol, 'Ad', style: XlsxStyle.columnHeader);
  sheet.setText(sr, summaryCol + 1, 'Kapsam', style: XlsxStyle.columnHeader);
  sheet.setText(sr, summaryCol + 2, 'Birim', style: XlsxStyle.columnHeader);
  sheet.setText(sr, summaryCol + 3, 'Toplam', style: XlsxStyle.columnHeader);
  sheet.setText(sr, summaryCol + 4, 'Açıklama', style: XlsxStyle.columnHeader);
  sr++;

  final activeSales =
      detail.sales.where((sale) => !sale.isCancelled).toList();
  final participantCount = summary.participantCount;

  if (detail.costs.isEmpty) {
    sheet.setText(sr, summaryCol, 'Kayıt yok', style: XlsxStyle.text);
    sheet.setBlank(sr, summaryCol + 1);
    sheet.setBlank(sr, summaryCol + 2);
    sheet.setNumber(
      sr,
      summaryCol + 3,
      summary.totalPartnerShare,
      style: XlsxStyle.moneyHighlight,
    );
    sheet.setBlank(sr, summaryCol + 4);
    sr++;
  } else {
    for (final cost in detail.costs) {
      final lineTotal = cost.scope == EventCostScope.event
          ? cost.shareValue
          : cost.amountFor(detail.ticketPrice ?? 0) * participantCount;
      final isPercent = cost.shareType == PartnerShareType.percent &&
          cost.scope == EventCostScope.perPerson;
      sheet.setText(sr, summaryCol, cost.name, style: XlsxStyle.text);
      sheet.setText(sr, summaryCol + 1, cost.scope.label, style: XlsxStyle.center);
      if (isPercent) {
        sheet.setText(
          sr,
          summaryCol + 2,
          '%${_trimNumber(cost.shareValue)}',
          style: XlsxStyle.center,
        );
      } else {
        sheet.setNumber(sr, summaryCol + 2, cost.shareValue, style: XlsxStyle.money);
      }
      sheet.setNumber(sr, summaryCol + 3, lineTotal, style: XlsxStyle.money);
      sheet.setText(
        sr,
        summaryCol + 4,
        cost.scope == EventCostScope.perPerson ? 'Kişi başı' : 'Etkinlik geneli',
        style: XlsxStyle.text,
      );
      sr++;
    }
  }

  sheet.setText(sr, summaryCol, 'TOPLAM', style: XlsxStyle.label);
  sheet.setBlank(sr, summaryCol + 1, style: XlsxStyle.label);
  sheet.setBlank(sr, summaryCol + 2, style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 3,
    summary.totalPartnerShare,
    style: XlsxStyle.moneyHighlight,
  );
  sheet.setText(
    sr,
    summaryCol + 4,
    detail.locationName,
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

  double amountOf(SaleType type) {
    return activeSales
        .where((sale) => sale.saleType == type)
        .fold<double>(0, (sum, sale) => sum + sale.totalPrice);
  }

  salesSummaryLine('Satılan (normal)', summary.regularCount, amountOf(SaleType.regular));
  salesSummaryLine(
    'İndirimli',
    summary.discountedCount,
    amountOf(SaleType.discounted),
  );
  salesSummaryLine('Hediye', summary.giftCount, null);
  sheet.setText(sr, summaryCol, 'Satış toplamı', style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 1,
    summary.participantCount,
    style: XlsxStyle.integerBold,
  );
  sheet.setNumber(
    sr,
    summaryCol + 2,
    summary.totalSales,
    style: XlsxStyle.moneyHighlight,
  );
  sr += 2;

  sheet.setText(sr, summaryCol, 'KAR - ZARAR', style: XlsxStyle.sectionHeader);
  sheet.merge(sr, summaryCol, colSpan: 3);
  sr++;
  sheet.setText(sr, summaryCol, 'Kişi başı gider', style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 2,
    summary.perPersonCost,
    style: XlsxStyle.money,
  );
  sr++;
  sheet.setText(sr, summaryCol, 'Etkinlik gideri', style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 2,
    summary.eventFixedCost,
    style: XlsxStyle.money,
  );
  sr++;
  sheet.setText(sr, summaryCol, 'Net kâr', style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 2,
    summary.netProfit,
    style: XlsxStyle.moneyHighlight,
  );
  sr++;
  sheet.setText(sr, summaryCol, 'Tahsil edilen', style: XlsxStyle.label);
  sheet.setNumber(sr, summaryCol + 2, summary.totalPaid, style: XlsxStyle.money);
  sr++;
  sheet.setText(sr, summaryCol, 'Tahsil edilmeyen', style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 2,
    summary.outstanding,
    style: XlsxStyle.moneyBold,
  );
  sr++;
  sheet.setText(sr, summaryCol, 'Katılımcı', style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 2,
    summary.participantCount,
    style: XlsxStyle.integerBold,
  );
  sr++;
  sheet.setText(sr, summaryCol, 'Katılan', style: XlsxStyle.label);
  sheet.setNumber(
    sr,
    summaryCol + 2,
    activeSales
        .where((sale) => sale.checkedIn)
        .fold<int>(0, (sum, sale) => sum + sale.quantity),
    style: XlsxStyle.integerBold,
  );
}

String _trimNumber(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

bool _eventPaid(EventSaleRow sale) => sale.outstanding <= 0.009;

/// 0 ödenmemiş, 10 ödenmiş, 30 hediye, 40 iptal.
int _eventSortRank(EventSaleRow sale) {
  if (sale.isCancelled) return 40;
  if (sale.saleType == SaleType.gift) return 30;
  final type = sale.saleType == SaleType.discounted ? 1 : 0;
  if (!_eventPaid(sale)) return type;
  return 10 + type;
}

SalesRowTone eventSalesRowTone(EventSaleRow sale) {
  if (sale.isCancelled) return SalesRowTone.none;
  if (sale.saleType == SaleType.gift) return SalesRowTone.green;
  if (!_eventPaid(sale)) return SalesRowTone.red;
  return SalesRowTone.none;
}

int compareEventSales(EventSaleRow a, EventSaleRow b) {
  final rank = _eventSortRank(a).compareTo(_eventSortRank(b));
  if (rank != 0) return rank;
  return a.buyerName.toLowerCase().compareTo(b.buyerName.toLowerCase());
}
