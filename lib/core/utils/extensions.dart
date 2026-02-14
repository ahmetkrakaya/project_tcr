import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// String Extensions
extension StringExtensions on String {
  /// Capitalize first letter
  String get capitalize {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// Capitalize each word
  String get capitalizeWords {
    if (isEmpty) return this;
    return split(' ').map((word) => word.capitalize).join(' ');
  }

  /// Check if string is valid email
  bool get isValidEmail {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(this);
  }

  /// Check if string is valid phone number
  bool get isValidPhone {
    return RegExp(r'^[0-9]{10,11}$').hasMatch(replaceAll(RegExp(r'[\s\-\(\)]'), ''));
  }

  /// Truncate string with ellipsis
  String truncate(int maxLength) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength)}...';
  }

  /// Parse as double or return null
  double? toDoubleOrNull() => double.tryParse(this);

  /// Parse as int or return null
  int? toIntOrNull() => int.tryParse(this);
}

/// DateTime Extensions
extension DateTimeExtensions on DateTime {
  /// Format as "dd MMMM yyyy"
  String get formattedDate {
    return DateFormat('dd MMMM yyyy', 'tr_TR').format(this);
  }

  /// Format as "dd MMM"
  String get shortDate {
    return DateFormat('dd MMM', 'tr_TR').format(this);
  }

  /// Format as "HH:mm"
  String get formattedTime {
    return DateFormat('HH:mm').format(this);
  }

  /// Format as "dd MMMM yyyy, HH:mm"
  String get formattedDateTime {
    return DateFormat('dd MMMM yyyy, HH:mm', 'tr_TR').format(this);
  }

  /// Format as "EEEE" (day name)
  String get dayName {
    return DateFormat('EEEE', 'tr_TR').format(this);
  }

  /// Format as relative time (e.g., "2 saat önce")
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(this);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} yıl önce';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} ay önce';
    } else if (difference.inDays > 7) {
      return '${(difference.inDays / 7).floor()} hafta önce';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} gün önce';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} saat önce';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} dakika önce';
    } else {
      return 'Az önce';
    }
  }

  /// Check if same day
  bool isSameDay(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }

  /// Check if today
  bool get isToday {
    final now = DateTime.now();
    return isSameDay(now);
  }

  /// Check if tomorrow
  bool get isTomorrow {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return isSameDay(tomorrow);
  }

  /// Check if this week
  bool get isThisWeek {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    return isAfter(startOfWeek) && isBefore(endOfWeek.add(const Duration(days: 1)));
  }
}

/// Duration Extensions
extension DurationExtensions on Duration {
  /// Format as "HH:mm:ss"
  String get formatted {
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    final seconds = inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format as pace (mm:ss per km)
  String get asPace {
    final minutes = inMinutes.remainder(60);
    final seconds = inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format as human readable
  String get humanReadable {
    if (inDays > 0) {
      return '$inDays gün ${inHours.remainder(24)} saat';
    } else if (inHours > 0) {
      return '$inHours saat ${inMinutes.remainder(60)} dakika';
    } else if (inMinutes > 0) {
      return '$inMinutes dakika';
    } else {
      return '$inSeconds saniye';
    }
  }
}

/// Number Extensions
extension NumberExtensions on num {
  /// Format as distance (e.g., "5.2 km" or "850 m")
  String get asDistance {
    if (this >= 1000) {
      return '${(this / 1000).toStringAsFixed(1)} km';
    }
    return '${toStringAsFixed(0)} m';
  }

  /// Format as kilometers
  String get asKilometers {
    return '${(this / 1000).toStringAsFixed(2)} km';
  }

  /// Format with thousands separator
  String get formatted {
    return NumberFormat('#,###', 'tr_TR').format(this);
  }

  /// Format as currency
  String get asCurrency {
    return NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(this);
  }

  /// Format as percentage
  String get asPercentage {
    return '${toStringAsFixed(1)}%';
  }

  /// Format as elevation
  String get asElevation {
    return '${toStringAsFixed(0)} m';
  }

  /// Format as calories
  String get asCalories {
    return '${toStringAsFixed(0)} kcal';
  }

  /// Format as heart rate
  String get asHeartRate {
    return '${toStringAsFixed(0)} bpm';
  }
}

/// BuildContext Extensions
extension BuildContextExtensions on BuildContext {
  /// Get theme
  ThemeData get theme => Theme.of(this);

  /// Get text theme
  TextTheme get textTheme => theme.textTheme;

  /// Get color scheme
  ColorScheme get colorScheme => theme.colorScheme;

  /// Get media query
  MediaQueryData get mediaQuery => MediaQuery.of(this);

  /// Get screen size
  Size get screenSize => mediaQuery.size;

  /// Get screen width
  double get screenWidth => screenSize.width;

  /// Get screen height
  double get screenHeight => screenSize.height;

  /// Check if dark mode
  bool get isDarkMode => theme.brightness == Brightness.dark;

  /// Get padding
  EdgeInsets get padding => mediaQuery.padding;

  /// Get view padding
  EdgeInsets get viewPadding => mediaQuery.viewPadding;

  /// Get view insets
  EdgeInsets get viewInsets => mediaQuery.viewInsets;

  /// Show snackbar
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? colorScheme.error : null,
      ),
    );
  }

  /// Show success snackbar
  void showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Show error snackbar
  void showErrorSnackBar(String message) {
    showSnackBar(message, isError: true);
  }
}

/// List Extensions
extension ListExtensions<T> on List<T> {
  /// Safe get element at index
  T? safeGet(int index) {
    if (index < 0 || index >= length) return null;
    return this[index];
  }

  /// Group by key
  Map<K, List<T>> groupBy<K>(K Function(T) keyFunction) {
    return fold<Map<K, List<T>>>(
      {},
      (map, element) {
        final key = keyFunction(element);
        map.putIfAbsent(key, () => []).add(element);
        return map;
      },
    );
  }
}

/// Map Extensions
extension MapExtensions<K, V> on Map<K, V> {
  /// Safe get value
  V? safeGet(K key) => containsKey(key) ? this[key] : null;
}
