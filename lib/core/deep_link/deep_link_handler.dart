import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;

import 'package:app_links/app_links.dart';

/// Deep link (App Links / Universal Links) ile gelen URI'yi uygulama path'ine çevirir.
/// - https://rivlus.com/e/:id → /events/:id
/// - https://rivlus.com/m/:id → /marketplace/:id
/// - tcr:///events/:id, tcr://events/:id → /events/:id
/// - tcr:///marketplace/:id, tcr://marketplace/:id → /marketplace/:id
String? parseUriToAppPath(Uri? uri) {
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final path = uri.path;
  // rivlus.com veya www.rivlus.com
  if (host == 'rivlus.com' || host == 'www.rivlus.com') {
    final eMatch = RegExp(r'^/e/([^/]+)').firstMatch(path);
    if (eMatch != null) return '/events/${Uri.decodeComponent(eMatch.group(1)!)}';
    final mMatch = RegExp(r'^/m/([^/]+)').firstMatch(path);
    if (mMatch != null) return '/marketplace/${Uri.decodeComponent(mMatch.group(1)!)}';
    return null;
  }
  // tcr scheme (tcr:///events/123 veya tcr://events/123)
  if (uri.scheme == 'tcr') {
    if (path.startsWith('/events/')) return path;
    if (path.startsWith('/marketplace/')) return path;
    final pathNorm = path.startsWith('/') ? path : '/$path';
    if (pathNorm.startsWith('/events/') || pathNorm.startsWith('/marketplace/')) {
      return pathNorm;
    }
    // tcr://events/123 → host=events, path=/123
    if (host == 'events' && path.isNotEmpty) return '/events$path';
    if (host == 'marketplace' && path.isNotEmpty) return '/marketplace$path';
    return null;
  }
  return null;
}

/// Cold start veya login sonrası yönlendirilecek deep link path.
/// Splash/link ile açıldığında set edilir; auth sonrası veya login sonrası bu path'e gidilir.
String? get pendingDeepLinkPath => _pendingDeepLinkPath;
String? _pendingDeepLinkPath;

void setPendingDeepLinkPath(String? path) {
  _pendingDeepLinkPath = path;
}

String? takePendingDeepLinkPath() {
  final p = _pendingDeepLinkPath;
  _pendingDeepLinkPath = null;
  return p;
}

/// Uygulama deep link ile (cold start) açıldıysa ilk URI'yi döndürür.
/// Web'de çağrılmamalı.
Future<Uri?> getInitialUri() async {
  if (kIsWeb) return null;
  try {
    final appLinks = AppLinks();
    final uri = await appLinks.getInitialLink();
    if (kDebugMode) {
      // Logcat / Xcode console'da görmek için: "TCR_DEEPLINK" ile filtrele
      debugPrint('TCR_DEEPLINK getInitialUri: ${uri?.toString() ?? "null"}');
    }
    return uri;
  } catch (e, st) {
    if (kDebugMode) debugPrint('TCR_DEEPLINK getInitialUri error: $e $st');
    return null;
  }
}

/// Uygulama açıkken veya arka plandayken gelen linkleri dinler.
/// Örn. kullanıcı WhatsApp'tan linke tıklar, uygulama açılır veya öne gelir.
Stream<Uri> get uriLinkStream {
  if (kIsWeb) return Stream.empty();
  try {
    final appLinks = AppLinks();
    return appLinks.uriLinkStream;
  } catch (_) {
    return Stream.empty();
  }
}
