import 'package:flutter/material.dart';

/// TCR App Colors
/// Twenty City Runners - Lacivert/Navy Blue temalı renk paleti

class AppColors {
  AppColors._();

  // Primary - TCR Lacivert/Navy Blue (Logo rengi)
  static const Color primary = Color(0xFF1E3A5F); // TCR Navy Blue
  static const Color primaryLight = Color(0xFF3D5A80);
  static const Color primaryDark = Color(0xFF0D1B2A);
  static const Color primaryContainer = Color(0xFFD1E3F8);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF0D1B2A);

  // Secondary - Dinamik yeşil tonları (performans, doğa, koşu)
  static const Color secondary = Color(0xFF2E7D32);
  static const Color secondaryLight = Color(0xFF4CAF50);
  static const Color secondaryDark = Color(0xFF1B5E20);
  static const Color secondaryContainer = Color(0xFFC8E6C9);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF1B5E20);

  // Tertiary - Açık mavi tonları (enerji, hareket)
  static const Color tertiary = Color(0xFF0288D1);
  static const Color tertiaryLight = Color(0xFF03A9F4);
  static const Color tertiaryDark = Color(0xFF01579B);
  static const Color tertiaryContainer = Color(0xFFB3E5FC);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color onTertiaryContainer = Color(0xFF01579B);

  // Background - Light Theme (Açık gri tonları - logo arka planı gibi)
  static const Color backgroundLight = Color(0xFFF5F7FA);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFE8ECF0);
  static const Color onBackgroundLight = Color(0xFF1E3A5F);
  static const Color onSurfaceLight = Color(0xFF1E3A5F);
  static const Color onSurfaceVariantLight = Color(0xFF5C6B7A);

  // Background - Dark Theme (Koyu lacivert tonları)
  static const Color backgroundDark = Color(0xFF0D1B2A);
  static const Color surfaceDark = Color(0xFF1B2838);
  static const Color surfaceVariantDark = Color(0xFF243447);
  static const Color onBackgroundDark = Color(0xFFE8ECF0);
  static const Color onSurfaceDark = Color(0xFFE8ECF0);
  static const Color onSurfaceVariantDark = Color(0xFFA0AEC0);

  // Error
  static const Color error = Color(0xFFD32F2F);
  static const Color errorLight = Color(0xFFEF5350);
  static const Color errorContainer = Color(0xFFFFCDD2);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color onErrorContainer = Color(0xFFB71C1C);

  // Success
  static const Color success = Color(0xFF388E3C);
  static const Color successLight = Color(0xFF66BB6A);
  static const Color successContainer = Color(0xFFC8E6C9);

  // Warning
  static const Color warning = Color(0xFFF57C00);
  static const Color warningLight = Color(0xFFFFB74D);
  static const Color warningContainer = Color(0xFFFFE0B2);

  // Info
  static const Color info = Color(0xFF1976D2);
  static const Color infoLight = Color(0xFF64B5F6);
  static const Color infoContainer = Color(0xFFBBDEFB);

  // Neutral
  static const Color neutral100 = Color(0xFFFFFFFF);
  static const Color neutral200 = Color(0xFFF5F5F5);
  static const Color neutral300 = Color(0xFFE0E0E0);
  static const Color neutral400 = Color(0xFFBDBDBD);
  static const Color neutral500 = Color(0xFF9E9E9E);
  static const Color neutral600 = Color(0xFF757575);
  static const Color neutral700 = Color(0xFF616161);
  static const Color neutral800 = Color(0xFF424242);
  static const Color neutral900 = Color(0xFF212121);

  // Elevation Gradient Colors (3D Harita için)
  static const Color elevationLow = Color(0xFF4CAF50); // Düz - Yeşil
  static const Color elevationMedium = Color(0xFFFFC107); // Orta - Sarı
  static const Color elevationHigh = Color(0xFFFF5722); // Yokuş - Turuncu
  static const Color elevationExtreme = Color(0xFFD32F2F); // Çok Dik - Kırmızı

  // Pace Colors
  static const Color paceEasy = Color(0xFF81C784);
  static const Color paceModerate = Color(0xFFFFB74D);
  static const Color paceHard = Color(0xFFEF5350);

  // Activity Colors
  static const Color running = Color(0xFF1E3A5F); // TCR Navy
  static const Color walking = Color(0xFF2E7D32);
  static const Color cycling = Color(0xFF0288D1);
  static const Color swimming = Color(0xFF00ACC1);

  // Role Colors
  static const Color superAdmin = Color(0xFFB71C1C);
  static const Color coach = Color(0xFF1565C0);
  static const Color member = Color(0xFF1E3A5F); // TCR Navy

  // RSVP Colors
  static const Color rsvpGoing = Color(0xFF4CAF50);
  static const Color rsvpNotGoing = Color(0xFFEF5350);
  static const Color rsvpMaybe = Color(0xFFFFC107);

  // Carpooling
  static const Color driver = Color(0xFF1976D2);
  static const Color passenger = Color(0xFF4CAF50);
  static const Color seatAvailable = Color(0xFF4CAF50);
  static const Color seatTaken = Color(0xFFBDBDBD);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryLight, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient tcrGradient = LinearGradient(
    colors: [Color(0xFF3D5A80), Color(0xFF1E3A5F), Color(0xFF0D1B2A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient energyGradient = LinearGradient(
    colors: [Color(0xFF1E3A5F), Color(0xFF3D5A80)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient performanceGradient = LinearGradient(
    colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkOverlay = LinearGradient(
    colors: [Colors.transparent, Color(0xCC0D1B2A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient elevationGradient = LinearGradient(
    colors: [elevationLow, elevationMedium, elevationHigh, elevationExtreme],
    stops: [0.0, 0.33, 0.66, 1.0],
  );

  // TCR Brand Colors (Logo'dan)
  static const Color tcrNavy = Color(0xFF1E3A5F);
  static const Color tcrNavyLight = Color(0xFF3D5A80);
  static const Color tcrNavyDark = Color(0xFF0D1B2A);
}
