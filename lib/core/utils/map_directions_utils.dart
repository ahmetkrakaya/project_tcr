import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Harita uygulamasında yol tarifi açar.
/// iOS: Apple Maps, Android/diğer: Google Maps.
Future<void> openMapsForDirections({
  double? lat,
  double? lng,
  String? locationName,
  String? locationAddress,
}) async {
  final hasCoordinates = lat != null && lng != null;
  final fullAddress = _resolveAddress(locationName, locationAddress);

  if (!hasCoordinates && (fullAddress == null || fullAddress.isEmpty)) {
    return;
  }

  late final String url;

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    if (hasCoordinates) {
      url = 'http://maps.apple.com/?daddr=$lat,$lng';
    } else {
      url =
          'http://maps.apple.com/?q=${Uri.encodeComponent(fullAddress!)}';
    }
  } else if (hasCoordinates) {
    url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
  } else {
    url =
        'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(fullAddress!)}';
  }

  final uri = Uri.parse(url);

  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    final fallbackUrl = hasCoordinates
        ? 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'
        : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(fullAddress!)}';
    final fallbackUri = Uri.parse(fallbackUrl);
    if (await canLaunchUrl(fallbackUri)) {
      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    // Harita açılamazsa sessizce başarısız ol
  }
}

String? _resolveAddress(String? locationName, String? locationAddress) {
  final name = locationName?.trim();
  final address = locationAddress?.trim();

  if (name != null &&
      name.isNotEmpty &&
      address != null &&
      address.isNotEmpty) {
    return '$name, $address';
  }
  if (address != null && address.isNotEmpty) return address;
  if (name != null && name.isNotEmpty) return name;
  return null;
}

bool hasNavigableLocation({
  String? locationName,
  String? locationAddress,
  double? lat,
  double? lng,
}) {
  if (lat != null && lng != null) return true;
  final address = _resolveAddress(locationName, locationAddress);
  return address != null && address.isNotEmpty;
}
