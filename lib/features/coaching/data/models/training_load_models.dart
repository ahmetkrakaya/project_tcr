/// Antrenman yuku durum bayragi
enum TrainingLoadStatus { ok, warning, risk, unknown }

TrainingLoadStatus _statusFromString(String? value) {
  switch (value) {
    case 'ok':
      return TrainingLoadStatus.ok;
    case 'warning':
      return TrainingLoadStatus.warning;
    case 'risk':
      return TrainingLoadStatus.risk;
    default:
      return TrainingLoadStatus.unknown;
  }
}

double? _toDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

double _toDouble(dynamic value) => _toDoubleOrNull(value) ?? 0;

/// Koc panelinde tek bir sporcunun guncel yuk ozeti
class AthleteLoadOverviewModel {
  const AthleteLoadOverviewModel({
    required this.userId,
    required this.fullName,
    this.avatarUrl,
    required this.ctl,
    required this.atl,
    required this.tsb,
    required this.acute7d,
    required this.chronic28d,
    this.acwr,
    this.rampPct,
    required this.distance7dKm,
    required this.status,
  });

  final String userId;
  final String fullName;
  final String? avatarUrl;

  /// Fitness (Chronic Training Load)
  final double ctl;

  /// Yorgunluk (Acute Training Load)
  final double atl;

  /// Form (Training Stress Balance)
  final double tsb;

  /// Son 7 gun toplam TSS
  final double acute7d;

  /// Son 28 gun toplam TSS
  final double chronic28d;

  /// Akut:Kronik yuk orani (null = yetersiz veri)
  final double? acwr;

  /// Haftalik yuk degisim yuzdesi (null = onceki hafta verisi yok)
  final double? rampPct;

  /// Son 7 gun mesafe (km)
  final double distance7dKm;

  final TrainingLoadStatus status;

  factory AthleteLoadOverviewModel.fromJson(Map<String, dynamic> json) {
    return AthleteLoadOverviewModel(
      userId: json['user_id'] as String,
      fullName: (json['full_name'] as String?)?.trim().isNotEmpty == true
          ? (json['full_name'] as String).trim()
          : 'İsimsiz',
      avatarUrl: json['avatar_url'] as String?,
      ctl: _toDouble(json['ctl']),
      atl: _toDouble(json['atl']),
      tsb: _toDouble(json['tsb']),
      acute7d: _toDouble(json['acute_7d']),
      chronic28d: _toDouble(json['chronic_28d']),
      acwr: _toDoubleOrNull(json['acwr']),
      rampPct: _toDoubleOrNull(json['ramp_pct']),
      distance7dKm: _toDouble(json['distance_7d_km']),
      status: _statusFromString(json['status'] as String?),
    );
  }
}

/// PMC grafigi icin gunluk yuk noktasi
class TrainingLoadPointModel {
  const TrainingLoadPointModel({
    required this.date,
    required this.tss,
    required this.ctl,
    required this.atl,
    required this.tsb,
  });

  final DateTime date;
  final double tss;
  final double ctl;
  final double atl;
  final double tsb;

  factory TrainingLoadPointModel.fromJson(Map<String, dynamic> json) {
    return TrainingLoadPointModel(
      date: DateTime.parse(json['date'] as String),
      tss: _toDouble(json['tss']),
      ctl: _toDouble(json['ctl']),
      atl: _toDouble(json['atl']),
      tsb: _toDouble(json['tsb']),
    );
  }
}
