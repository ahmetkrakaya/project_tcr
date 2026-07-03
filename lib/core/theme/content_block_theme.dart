import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Post ve etkinlik bilgi blokları için light/dark uyumlu renkler.
class ContentBlockTheme {
  ContentBlockTheme._();

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color onSurface(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color onSurfaceVariant(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  /// Açık temada pastel konteyner, koyu temada semantik renk tonu.
  static Color surface(
    BuildContext context, {
    required Color lightContainer,
    required Color semantic,
    double darkAlpha = 0.16,
  }) {
    if (isDark(context)) {
      return semantic.withValues(alpha: darkAlpha);
    }
    return lightContainer;
  }

  static Color border(BuildContext context, Color semantic) {
    if (isDark(context)) {
      return semantic.withValues(alpha: 0.45);
    }
    return semantic.withValues(alpha: 0.35);
  }

  /// Başlık/vurgu rengi — koyu temada daha açık ton.
  static Color title(
    BuildContext context,
    Color semantic, {
    Color? darkAccent,
  }) {
    if (isDark(context)) {
      return darkAccent ?? semantic;
    }
    return semantic;
  }

  /// Gövde metni — koyu zeminde her zaman okunabilir.
  static Color body(
    BuildContext context,
    Color semantic, {
    Color? darkAccent,
  }) {
    if (isDark(context)) {
      return onSurface(context);
    }
    return semantic.withValues(alpha: 0.9);
  }
}
