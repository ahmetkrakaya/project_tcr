import 'package:flutter/widgets.dart';

/// Basit responsive yardımcıları ve [BuildContext] extension'ları.
///
/// Amaç: Farklı telefon boyutlarında orantılı boşluk ve görsel boyutlandırma
/// sağlayarak sabit piksel kullanımını azaltmak.
extension ResponsiveContext on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);

  double get screenWidth => screenSize.width;

  double get screenHeight => screenSize.height;

  /// Ekran yüksekliğinin [fraction] oranı kadar yükseklik.
  double heightPct(double fraction) => screenHeight * fraction;

  /// Ekran genişliğinin [fraction] oranı kadar genişlik.
  double widthPct(double fraction) => screenWidth * fraction;

  /// Dikey boşluk için yardımcı `SizedBox`.
  Widget vSpace(double fraction) => SizedBox(height: heightPct(fraction));

  /// Yatay boşluk için yardımcı `SizedBox`.
  Widget hSpace(double fraction) => SizedBox(width: widthPct(fraction));

  /// Ekran genişliğine göre min–max aralığında logo/görsel boyutu hesaplar.
  ///
  /// Örneğin:
  /// ```dart
  /// final size = context.imageSize(
  ///   min: 96,
  ///   max: 160,
  ///   fractionOfWidth: 0.35,
  /// );
  /// ```
  double imageSize({
    double min = 96,
    double max = 160,
    double fractionOfWidth = 0.35,
  }) {
    final base = screenWidth * fractionOfWidth;
    return base.clamp(min, max);
  }

  /// Ekran genişliğine göre küçük/orta/büyük cihazlar için değer seçer.
  ///
  /// Örn:
  /// ```dart
  /// final padding = context.responsiveValue(small: 16, medium: 20, large: 24);
  /// ```
  double responsiveValue({
    required double small,
    double? medium,
    double? large,
    double mediumBreakpoint = 360,
    double largeBreakpoint = 600,
  }) {
    if (screenWidth >= largeBreakpoint && large != null) {
      return large;
    }
    if (screenWidth >= mediumBreakpoint && medium != null) {
      return medium;
    }
    return small;
  }
}

/// Metin stilleri için basit responsive ölçekleme extension'ı.
///
/// Örn:
/// ```dart
/// style: AppTypography.titleLarge
///   .copyWith(fontWeight: FontWeight.w600)
///   .scaleForDeviceWidth(context);
/// ```
extension ResponsiveTextStyle on TextStyle {
  TextStyle scaleForDeviceWidth(
    BuildContext context, {
    double baseWidth = 430, // iPhone Pro Max benzeri referans genişlik
    double minScale = 0.9,
    double maxScale = 1.0,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final scale = (width / baseWidth).clamp(minScale, maxScale);
    final currentFontSize = fontSize;
    if (currentFontSize == null) return this;
    return copyWith(fontSize: currentFontSize * scale);
  }
}


