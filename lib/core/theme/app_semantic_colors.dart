import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Semantik renkler — ColorScheme'de olmayan UI tonları.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.iconBoxBackground,
    required this.subtleAccentBackground,
    required this.chevron,
    required this.placeholder,
  });

  final Color shimmerBase;
  final Color shimmerHighlight;
  final Color iconBoxBackground;
  final Color subtleAccentBackground;
  final Color chevron;
  final Color placeholder;

  static const light = AppSemanticColors(
    shimmerBase: AppColors.neutral200,
    shimmerHighlight: AppColors.neutral100,
    iconBoxBackground: AppColors.neutral200,
    subtleAccentBackground: Color(0x141E3A5F),
    chevron: AppColors.neutral400,
    placeholder: AppColors.neutral300,
  );

  static const dark = AppSemanticColors(
    shimmerBase: Color(0xFF1E262D),
    shimmerHighlight: Color(0xFF2A3440),
    iconBoxBackground: AppColors.surfaceVariantDark,
    subtleAccentBackground: Color(0x2626C6DA),
    chevron: Color(0xFF64748B),
    placeholder: Color(0xFF334155),
  );

  @override
  AppSemanticColors copyWith({
    Color? shimmerBase,
    Color? shimmerHighlight,
    Color? iconBoxBackground,
    Color? subtleAccentBackground,
    Color? chevron,
    Color? placeholder,
  }) {
    return AppSemanticColors(
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
      iconBoxBackground: iconBoxBackground ?? this.iconBoxBackground,
      subtleAccentBackground:
          subtleAccentBackground ?? this.subtleAccentBackground,
      chevron: chevron ?? this.chevron,
      placeholder: placeholder ?? this.placeholder,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t)!,
      shimmerHighlight:
          Color.lerp(shimmerHighlight, other.shimmerHighlight, t)!,
      iconBoxBackground:
          Color.lerp(iconBoxBackground, other.iconBoxBackground, t)!,
      subtleAccentBackground: Color.lerp(
        subtleAccentBackground,
        other.subtleAccentBackground,
        t,
      )!,
      chevron: Color.lerp(chevron, other.chevron, t)!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
    );
  }
}
