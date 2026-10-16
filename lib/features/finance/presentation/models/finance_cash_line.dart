import '../../../marketplace/data/models/market_report_model.dart';
import '../../../marketplace/utils/market_report_utils.dart';
import '../../data/models/finance_report_model.dart';

/// Kasa ekranındaki tek kaynak. Market satırı ürün raporundaki stok hesabını kullanır.
class FinanceCashLine {
  final FinanceOverviewRow row;
  final bool isBundle;
  final bool hasInventory;
  final int? produced;
  final int? remaining;
  final int regular;
  final int discounted;
  final int gift;
  final int bundleGone;
  final int gone;
  final double? productionCost;
  final double? remainingCost;
  final double? soldCost;
  final double? eventCost;
  final double gross;
  final double realized;
  final double position;
  final double collected;
  final double outstanding;

  const FinanceCashLine({
    required this.row,
    required this.isBundle,
    required this.hasInventory,
    required this.produced,
    required this.remaining,
    required this.regular,
    required this.discounted,
    required this.gift,
    required this.bundleGone,
    required this.gone,
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

  bool get isMarket => row.source == FinanceSource.market;

  factory FinanceCashLine.from(
    FinanceOverviewRow row,
    MarketOverviewRow? market,
  ) {
    if (row.source == FinanceSource.market && market != null) {
      final stockCost = market.isBundle
          ? null
          : remainingInventoryCost(
              isBundle: false,
              remainingQuantity: market.remainingQuantity,
              producedQuantity: market.producedQuantity,
              productionCost: market.totalProductionCost,
              avgUnitCost: market.avgUnitCost,
            );
      return FinanceCashLine(
        row: row,
        isBundle: market.isBundle,
        hasInventory: !market.isBundle,
        produced: market.isBundle ? null : market.producedQuantity,
        remaining: market.remainingQuantity,
        regular: market.regularQuantity,
        discounted: market.discountedQuantity,
        gift: market.giftQuantity,
        bundleGone: market.bundleSoldQuantity,
        gone: market.regularQuantity +
            market.discountedQuantity +
            market.giftQuantity +
            market.bundleSoldQuantity,
        productionCost: market.isBundle ? null : market.totalProductionCost,
        remainingCost: stockCost,
        soldCost: market.totalCogs,
        eventCost: null,
        gross: market.totalSales,
        realized: market.profitVsCogs,
        position: market.profitVsProduction,
        collected: market.totalPaid,
        outstanding: market.outstanding,
      );
    }

    if (row.source == FinanceSource.market) {
      return FinanceCashLine(
        row: row,
        isBundle: false,
        hasInventory: false,
        produced: null,
        remaining: null,
        regular: 0,
        discounted: 0,
        gift: 0,
        bundleGone: 0,
        gone: row.quantity,
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

    return FinanceCashLine(
      row: row,
      isBundle: false,
      hasInventory: false,
      produced: null,
      remaining: null,
      regular: 0,
      discounted: 0,
      gift: 0,
      bundleGone: 0,
      gone: row.quantity,
      productionCost: null,
      remainingCost: null,
      soldCost: null,
      eventCost: row.cost,
      gross: row.gross,
      realized: row.net,
      position: row.net,
      collected: row.collected,
      outstanding: row.outstanding,
    );
  }
}

/// Ekrandaki genel toplam. Kar/zarar üretim maliyeti ve etkinlik giderini düşer.
class FinanceCashTotals {
  final double gross;
  final double position;
  final double realized;
  final double outstanding;
  final double productionCost;
  final double remainingCost;
  final double eventCost;
  final double marketPosition;
  final double marketRealized;
  final double eventNet;
  final int produced;
  final int gone;
  final int remaining;
  final int bundleSales;
  final bool hasMarket;
  final bool hasEvents;

  const FinanceCashTotals({
    required this.gross,
    required this.position,
    required this.realized,
    required this.outstanding,
    required this.productionCost,
    required this.remainingCost,
    required this.eventCost,
    required this.marketPosition,
    required this.marketRealized,
    required this.eventNet,
    required this.produced,
    required this.gone,
    required this.remaining,
    required this.bundleSales,
    required this.hasMarket,
    required this.hasEvents,
  });

  factory FinanceCashTotals.of(List<FinanceCashLine> lines) {
    final market = lines.where((line) => line.isMarket);
    final physical = market.where((line) => line.hasInventory);
    final events = lines.where((line) => !line.isMarket);
    final bundles = market.where((line) => line.isBundle);

    double sum(Iterable<FinanceCashLine> source, double Function(FinanceCashLine) pick) {
      return source.fold<double>(0, (total, line) => total + pick(line));
    }

    int sumInt(Iterable<FinanceCashLine> source, int? Function(FinanceCashLine) pick) {
      return source.fold<int>(0, (total, line) => total + (pick(line) ?? 0));
    }

    return FinanceCashTotals(
      gross: sum(lines, (line) => line.gross),
      position: sum(lines, (line) => line.position),
      realized: sum(lines, (line) => line.realized),
      outstanding: sum(lines, (line) => line.outstanding),
      productionCost: sum(physical, (line) => line.productionCost ?? 0),
      remainingCost: sum(physical, (line) => line.remainingCost ?? 0),
      eventCost: sum(events, (line) => line.eventCost ?? 0),
      marketPosition: sum(market, (line) => line.position),
      marketRealized: sum(market, (line) => line.realized),
      eventNet: sum(events, (line) => line.position),
      produced: sumInt(physical, (line) => line.produced),
      gone: sumInt(physical, (line) => line.gone),
      remaining: sumInt(physical, (line) => line.remaining),
      bundleSales: sumInt(bundles, (line) => line.gone),
      hasMarket: market.isNotEmpty,
      hasEvents: events.isNotEmpty,
    );
  }
}
