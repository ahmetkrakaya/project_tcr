double _toDouble(dynamic value) => (value as num?)?.toDouble() ?? 0;

int _toInt(dynamic value) => (value as num?)?.toInt() ?? 0;

/// Kasa raporundaki gelir kaynağı
enum FinanceSource {
  market('market', 'Market'),
  event('event', 'Etkinlik');

  final String value;
  final String label;
  const FinanceSource(this.value, this.label);

  static FinanceSource fromString(String? value) {
    return FinanceSource.values.firstWhere(
      (e) => e.value == value,
      orElse: () => FinanceSource.market,
    );
  }
}

/// Genel kasa raporundaki tek satır (bir ürün veya bir etkinlik)
class FinanceOverviewRow {
  final FinanceSource source;
  final String refId;
  final String title;
  final DateTime? refDate;
  final int quantity;

  /// Brüt ciro
  final double gross;

  /// Market: satılan malın maliyeti, Etkinlik: ortak (mekan) payı
  final double cost;
  final double net;
  final double collected;
  final double outstanding;

  const FinanceOverviewRow({
    required this.source,
    required this.refId,
    required this.title,
    this.refDate,
    required this.quantity,
    required this.gross,
    required this.cost,
    required this.net,
    required this.collected,
    required this.outstanding,
  });

  factory FinanceOverviewRow.fromJson(Map<String, dynamic> json) {
    final date = json['ref_date'] as String?;
    return FinanceOverviewRow(
      source: FinanceSource.fromString(json['source'] as String?),
      refId: json['ref_id'] as String,
      title: json['title'] as String? ?? '',
      refDate: date != null ? DateTime.tryParse(date) : null,
      quantity: _toInt(json['quantity']),
      gross: _toDouble(json['gross']),
      cost: _toDouble(json['cost']),
      net: _toDouble(json['net']),
      collected: _toDouble(json['collected']),
      outstanding: _toDouble(json['outstanding']),
    );
  }
}

/// Kasa raporu toplamları
class FinanceTotals {
  final double gross;
  final double cost;
  final double net;
  final double collected;
  final double outstanding;

  const FinanceTotals({
    required this.gross,
    required this.cost,
    required this.net,
    required this.collected,
    required this.outstanding,
  });

  factory FinanceTotals.of(Iterable<FinanceOverviewRow> rows) {
    double gross = 0, cost = 0, net = 0, collected = 0, outstanding = 0;
    for (final r in rows) {
      gross += r.gross;
      cost += r.cost;
      net += r.net;
      collected += r.collected;
      outstanding += r.outstanding;
    }
    return FinanceTotals(
      gross: gross,
      cost: cost,
      net: net,
      collected: collected,
      outstanding: outstanding,
    );
  }
}
