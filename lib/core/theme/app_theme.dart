import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// TCR App Theme
/// Light ve Dark tema yapılandırması

class AppTheme {
  AppTheme._();

  // Border Radius
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;
  static const double radiusFull = 999;

  // Spacing
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;
  static const double spacingXl = 32;
  static const double spacingXxl = 48;

  // Elevation
  static const double elevationNone = 0;
  static const double elevationSm = 2;
  static const double elevationMd = 4;
  static const double elevationLg = 8;
  static const double elevationXl = 16;

  // Light Theme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: _lightColorScheme,
      textTheme: AppTypography.textTheme.apply(
        bodyColor: _lightColorScheme.onSurface,
        displayColor: _lightColorScheme.onSurface,
      ),
      iconTheme: IconThemeData(color: _lightColorScheme.onSurface),
      scaffoldBackgroundColor: AppColors.backgroundLight,
      appBarTheme: _lightAppBarTheme,
      cardTheme: _lightCardTheme,
      elevatedButtonTheme: _elevatedButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme,
      textButtonTheme: _textButtonTheme,
      floatingActionButtonTheme: _lightFabTheme,
      inputDecorationTheme: _lightInputDecorationTheme,
      chipTheme: _lightChipTheme,
      bottomNavigationBarTheme: _lightBottomNavTheme,
      navigationBarTheme: _lightNavigationBarTheme,
      tabBarTheme: _lightTabBarTheme,
      dividerTheme: _lightDividerTheme,
      listTileTheme: _lightListTileTheme,
      dialogTheme: _dialogTheme,
      bottomSheetTheme: _bottomSheetTheme,
      snackBarTheme: _snackBarTheme,
    );
  }

  // Dark Theme
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: _darkColorScheme,
      textTheme: AppTypography.textTheme.apply(
        bodyColor: _darkColorScheme.onSurface,
        displayColor: _darkColorScheme.onSurface,
      ),
      iconTheme: IconThemeData(color: _darkColorScheme.onSurface),
      scaffoldBackgroundColor: AppColors.backgroundDark,
      appBarTheme: _darkAppBarTheme,
      cardTheme: _darkCardTheme,
      elevatedButtonTheme: _elevatedButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme,
      textButtonTheme: _textButtonTheme,
      floatingActionButtonTheme: _darkFabTheme,
      inputDecorationTheme: _darkInputDecorationTheme,
      chipTheme: _darkChipTheme,
      bottomNavigationBarTheme: _darkBottomNavTheme,
      navigationBarTheme: _darkNavigationBarTheme,
      tabBarTheme: _darkTabBarTheme,
      dividerTheme: _darkDividerTheme,
      listTileTheme: _darkListTileTheme,
      dialogTheme: _dialogTheme,
      bottomSheetTheme: _bottomSheetTheme,
      snackBarTheme: _snackBarTheme,
    );
  }

  // Color Schemes - TCR Navy Blue Theme
  static const ColorScheme _lightColorScheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.onPrimaryContainer,
    secondary: AppColors.secondary,
    onSecondary: AppColors.onSecondary,
    secondaryContainer: AppColors.secondaryContainer,
    onSecondaryContainer: AppColors.onSecondaryContainer,
    tertiary: AppColors.tertiary,
    onTertiary: AppColors.onTertiary,
    tertiaryContainer: AppColors.tertiaryContainer,
    onTertiaryContainer: AppColors.onTertiaryContainer,
    error: AppColors.error,
    onError: AppColors.onError,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: AppColors.onErrorContainer,
    surface: AppColors.surfaceLight,
    onSurface: AppColors.onSurfaceLight,
    surfaceContainerHighest: AppColors.surfaceVariantLight,
    onSurfaceVariant: AppColors.onSurfaceVariantLight,
    outline: AppColors.neutral400,
    outlineVariant: AppColors.neutral300,
    inverseSurface: AppColors.neutral800,
    onInverseSurface: AppColors.neutral100,
  );

  static const ColorScheme _darkColorScheme = ColorScheme.dark(
    primary: AppColors.primaryLight,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryDark,
    onPrimaryContainer: AppColors.primaryContainer,
    secondary: AppColors.secondaryLight,
    onSecondary: AppColors.onSecondary,
    secondaryContainer: AppColors.secondaryDark,
    onSecondaryContainer: AppColors.secondaryContainer,
    tertiary: AppColors.tertiaryLight,
    onTertiary: AppColors.onTertiary,
    tertiaryContainer: AppColors.tertiaryDark,
    onTertiaryContainer: AppColors.tertiaryContainer,
    error: AppColors.errorLight,
    onError: AppColors.onPrimary,
    errorContainer: AppColors.error,
    onErrorContainer: AppColors.errorContainer,
    surface: AppColors.surfaceDark,
    onSurface: AppColors.onSurfaceDark,
    surfaceContainerHighest: AppColors.surfaceVariantDark,
    onSurfaceVariant: AppColors.onSurfaceVariantDark,
    outline: AppColors.neutral500,
    outlineVariant: AppColors.neutral600,
    inverseSurface: AppColors.onSurfaceDark,
    onInverseSurface: AppColors.surfaceDark,
  );

  // AppBar Themes
  static const AppBarTheme _lightAppBarTheme = AppBarTheme(
    elevation: 0,
    centerTitle: true,
    backgroundColor: AppColors.surfaceLight,
    foregroundColor: AppColors.onSurfaceLight,
    surfaceTintColor: Colors.transparent,
    systemOverlayStyle: SystemUiOverlayStyle.dark,
    titleTextStyle: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: AppColors.onSurfaceLight,
    ),
  );

  static const AppBarTheme _darkAppBarTheme = AppBarTheme(
    elevation: 0,
    centerTitle: true,
    backgroundColor: AppColors.surfaceDark,
    foregroundColor: AppColors.onSurfaceDark,
    surfaceTintColor: Colors.transparent,
    systemOverlayStyle: SystemUiOverlayStyle.light,
    titleTextStyle: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: AppColors.onSurfaceDark,
    ),
  );

  // Card Themes
  static const CardThemeData _lightCardTheme = CardThemeData(
    elevation: elevationSm,
    color: AppColors.surfaceLight,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
    ),
    margin: EdgeInsets.zero,
  );

  static const CardThemeData _darkCardTheme = CardThemeData(
    elevation: elevationSm,
    color: AppColors.surfaceDark,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
    ),
    margin: EdgeInsets.zero,
  );

  // Button Themes
  static final ElevatedButtonThemeData _elevatedButtonTheme =
      ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: elevationNone,
      padding: const EdgeInsets.symmetric(horizontal: spacingLg, vertical: spacingMd),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      textStyle: AppTypography.buttonText,
    ),
  );

  static final OutlinedButtonThemeData _outlinedButtonTheme =
      OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: spacingLg, vertical: spacingMd),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      textStyle: AppTypography.buttonText,
    ),
  );

  static final TextButtonThemeData _textButtonTheme = TextButtonThemeData(
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: spacingMd, vertical: spacingSm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSm),
      ),
      textStyle: AppTypography.buttonText,
    ),
  );

  static const FloatingActionButtonThemeData _lightFabTheme =
      FloatingActionButtonThemeData(
    elevation: elevationMd,
    shape: CircleBorder(),
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.onPrimary,
  );

  static const FloatingActionButtonThemeData _darkFabTheme =
      FloatingActionButtonThemeData(
    elevation: elevationMd,
    shape: CircleBorder(),
    backgroundColor: AppColors.primaryLight,
    foregroundColor: AppColors.onPrimary,
  );

  // Input Decoration Themes
  static final InputDecorationTheme _lightInputDecorationTheme =
      InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surfaceVariantLight,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: spacingMd, vertical: spacingMd),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      borderSide: const BorderSide(color: AppColors.primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      borderSide: const BorderSide(color: AppColors.error, width: 1),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      borderSide: const BorderSide(color: AppColors.error, width: 2),
    ),
    labelStyle: AppTypography.bodyMedium.copyWith(color: AppColors.neutral600),
    hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.neutral500),
    errorStyle: AppTypography.bodySmall.copyWith(color: AppColors.error),
  );

  static final InputDecorationTheme _darkInputDecorationTheme =
      InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surfaceVariantDark,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: spacingMd, vertical: spacingMd),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      borderSide: const BorderSide(color: AppColors.errorLight, width: 1),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      borderSide: const BorderSide(color: AppColors.errorLight, width: 2),
    ),
    labelStyle:
        AppTypography.bodyMedium.copyWith(color: AppColors.onSurfaceVariantDark),
    hintStyle:
        AppTypography.bodyMedium.copyWith(color: AppColors.onSurfaceVariantDark),
    errorStyle: AppTypography.bodySmall.copyWith(color: AppColors.errorLight),
  );

  // Chip Themes - Daha iyi kontrast için güncellendi
  static const ChipThemeData _lightChipTheme = ChipThemeData(
    backgroundColor: AppColors.neutral200,
    selectedColor: AppColors.primary,
    disabledColor: AppColors.neutral300,
    padding: EdgeInsets.symmetric(horizontal: spacingSm, vertical: spacingXs),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radiusFull)),
    ),
    labelStyle: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: AppColors.neutral700, // Unselected text color
    ),
    secondaryLabelStyle: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.onPrimary, // Selected text color (white)
    ),
    brightness: Brightness.light,
  );

  static const ChipThemeData _darkChipTheme = ChipThemeData(
    backgroundColor: AppColors.surfaceVariantDark,
    selectedColor: AppColors.primaryLight,
    disabledColor: AppColors.neutral700,
    padding: EdgeInsets.symmetric(horizontal: spacingSm, vertical: spacingXs),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radiusFull)),
    ),
    labelStyle: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: AppColors.onSurfaceVariantDark, // Unselected text color
    ),
    secondaryLabelStyle: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.onPrimary, // Selected text color (white)
    ),
    brightness: Brightness.dark,
  );

  // Bottom Navigation Themes
  static const BottomNavigationBarThemeData _lightBottomNavTheme =
      BottomNavigationBarThemeData(
    backgroundColor: AppColors.surfaceLight,
    selectedItemColor: AppColors.primary,
    unselectedItemColor: AppColors.neutral500,
    type: BottomNavigationBarType.fixed,
    elevation: elevationMd,
    selectedLabelStyle: AppTypography.navLabel,
    unselectedLabelStyle: AppTypography.navLabel,
  );

  static const BottomNavigationBarThemeData _darkBottomNavTheme =
      BottomNavigationBarThemeData(
    backgroundColor: AppColors.surfaceDark,
    selectedItemColor: AppColors.primaryLight,
    unselectedItemColor: AppColors.onSurfaceVariantDark,
    type: BottomNavigationBarType.fixed,
    elevation: elevationMd,
    selectedLabelStyle: AppTypography.navLabel,
    unselectedLabelStyle: AppTypography.navLabel,
  );

  // Navigation Bar Themes (Material 3)
  static const NavigationBarThemeData _lightNavigationBarTheme =
      NavigationBarThemeData(
    backgroundColor: AppColors.surfaceLight,
    indicatorColor: AppColors.primaryContainer,
    surfaceTintColor: Colors.transparent,
    elevation: elevationSm,
    height: 64,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
  );

  static const NavigationBarThemeData _darkNavigationBarTheme =
      NavigationBarThemeData(
    backgroundColor: AppColors.surfaceDark,
    indicatorColor: AppColors.primaryLight,
    surfaceTintColor: Colors.transparent,
    elevation: elevationSm,
    height: 64,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
  );

  // Tab Bar Themes
  static const TabBarThemeData _lightTabBarTheme = TabBarThemeData(
    labelColor: AppColors.primary,
    unselectedLabelColor: AppColors.neutral600,
    indicatorColor: AppColors.primary,
    labelStyle: AppTypography.tabText,
    unselectedLabelStyle: AppTypography.tabText,
    indicatorSize: TabBarIndicatorSize.label,
  );

  static const TabBarThemeData _darkTabBarTheme = TabBarThemeData(
    labelColor: AppColors.primaryLight,
    unselectedLabelColor: AppColors.neutral400,
    indicatorColor: AppColors.primaryLight,
    labelStyle: AppTypography.tabText,
    unselectedLabelStyle: AppTypography.tabText,
    indicatorSize: TabBarIndicatorSize.label,
  );

  // Divider Themes
  static const DividerThemeData _lightDividerTheme = DividerThemeData(
    color: AppColors.neutral300,
    thickness: 1,
    space: 1,
  );

  static const DividerThemeData _darkDividerTheme = DividerThemeData(
    color: AppColors.neutral600,
    thickness: 1,
    space: 1,
  );

  // List Tile Themes
  static const ListTileThemeData _lightListTileTheme = ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(horizontal: spacingMd),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
    ),
  );

  static const ListTileThemeData _darkListTileTheme = ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(horizontal: spacingMd),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
    ),
  );

  // Dialog Theme
  static final DialogThemeData _dialogTheme = DialogThemeData(
    elevation: elevationLg,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusLg),
    ),
  );

  // Bottom Sheet Theme
  static final BottomSheetThemeData _bottomSheetTheme = BottomSheetThemeData(
    elevation: elevationLg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
    ),
    showDragHandle: true,
  );

  // Snack Bar Theme
  static final SnackBarThemeData _snackBarTheme = SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMd),
    ),
  );
}
