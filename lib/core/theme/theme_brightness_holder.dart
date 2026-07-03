import 'package:flutter/material.dart';

import 'app_colors.dart';

/// MaterialApp builder içinde güncellenir; context olmayan helper'larda tema renkleri için.
class ThemeBrightnessHolder {
  ThemeBrightnessHolder._();

  static Brightness _brightness = Brightness.light;

  static void update(Brightness brightness) {
    _brightness = brightness;
  }

  static bool get isDark => _brightness == Brightness.dark;

  static Color get primary =>
      isDark ? AppColors.primaryDarkAccent : AppColors.primary;

  static Color get onPrimary =>
      isDark ? AppColors.primaryDark : AppColors.onPrimary;

  static Color get primaryContainer =>
      isDark ? AppColors.primaryDarkContainer : AppColors.primaryContainer;

  static Color get onPrimaryContainer =>
      isDark ? AppColors.onPrimaryDarkContainer : AppColors.onPrimaryContainer;

  static Color get surface =>
      isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

  static Color get onSurface =>
      isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;

  static Color get onSurfaceVariant => isDark
      ? AppColors.onSurfaceVariantDark
      : AppColors.onSurfaceVariantLight;

  static Color get surfaceContainerHighest => isDark
      ? AppColors.surfaceVariantDark
      : AppColors.surfaceVariantLight;

  static Color get scaffoldBackground =>
      isDark ? AppColors.backgroundDark : AppColors.backgroundLight;

  static Color get outline =>
      isDark ? const Color(0xFF475569) : AppColors.neutral400;

  static Color get outlineVariant =>
      isDark ? const Color(0xFF334155) : AppColors.neutral300;
}
