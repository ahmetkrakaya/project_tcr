import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/training_load_models.dart';

/// Antrenman yuku gosterimi icin ortak renk/metin yardimcilari.
class TrainingLoadFormat {
  TrainingLoadFormat._();

  static Color statusColor(TrainingLoadStatus status) {
    switch (status) {
      case TrainingLoadStatus.ok:
        return AppColors.success;
      case TrainingLoadStatus.warning:
        return AppColors.warning;
      case TrainingLoadStatus.risk:
        return AppColors.error;
      case TrainingLoadStatus.unknown:
        return AppColors.neutral500;
    }
  }

  static String statusLabel(TrainingLoadStatus status) {
    switch (status) {
      case TrainingLoadStatus.ok:
        return 'Güvenli';
      case TrainingLoadStatus.warning:
        return 'Dikkat';
      case TrainingLoadStatus.risk:
        return 'Risk';
      case TrainingLoadStatus.unknown:
        return 'Veri yok';
    }
  }

  /// TSB (form) degerine gore koc yorumu.
  static String tsbInterpretation(double tsb) {
    if (tsb >= 25) return 'Çok dinlenik (form düşebilir)';
    if (tsb >= 15) return 'Yarışa hazır, en iyi form';
    if (tsb >= 5) return 'İyi form, hafif dinlenik';
    if (tsb >= -10) return 'Dengeli yük';
    if (tsb >= -30) return 'Üretken antrenman bloğu';
    return 'Aşırı yüklenme riski';
  }

  /// ACWR degerine gore renk (0.8-1.3 tatli nokta).
  static Color acwrColor(double? acwr) {
    if (acwr == null) return AppColors.neutral500;
    if (acwr > 1.5 || acwr < 0.5) return AppColors.error;
    if (acwr > 1.3 || acwr < 0.8) return AppColors.warning;
    return AppColors.success;
  }

  static String formatSigned(double value) {
    final rounded = value.round();
    return rounded > 0 ? '+$rounded' : '$rounded';
  }
}
