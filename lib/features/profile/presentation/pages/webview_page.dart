import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sayfa içinde URL açmak için WebView sayfası
class WebViewPage extends StatefulWidget {
  const WebViewPage({
    super.key,
    required this.url,
    required this.title,
  });

  final String url;
  final String title;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  bool _isLoading = true;
  double _progress = 0;

  String get _fullUrl {
    final url = widget.url;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return 'https://$url';
  }

  /// Belirli URL'lerin dış tarayıcıda açılması gerekip gerekmediğini kontrol eder
  bool _shouldOpenExternally(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('whatsapp.com') ||
        lowerUrl.contains('chat.whatsapp.com') ||
        lowerUrl.contains('instagram.com') ||
        lowerUrl.contains('strava.com');
  }

  /// URL'i dış tarayıcıda açar
  Future<void> _openExternalUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('[WebViewPage] URL açılamadı: $url');
      }
    } catch (e) {
      debugPrint('[WebViewPage] URL açma hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_fullUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              useHybridComposition: true,
            ),
            onWebViewCreated: (controller) {
              debugPrint('[WebViewPage] WebView created');
            },
            onLoadStart: (controller, url) {
              debugPrint('[WebViewPage] Load started: $url');
              setState(() => _isLoading = true);
            },
            onLoadStop: (controller, url) {
              debugPrint('[WebViewPage] Load stopped: $url');
              setState(() => _isLoading = false);
            },
            onProgressChanged: (controller, progress) {
              debugPrint('[WebViewPage] Progress: $progress%');
              setState(() {
                _progress = progress / 100;
                if (progress == 100) {
                  _isLoading = false;
                }
              });
            },
            onReceivedError: (controller, request, error) {
              debugPrint('[WebViewPage] Error: ${error.description}');
              setState(() => _isLoading = false);
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url.toString();
              debugPrint('[WebViewPage] Navigation to: $url');
              
              // WhatsApp, Instagram ve Strava linklerini dış tarayıcıda aç
              if (_shouldOpenExternally(url)) {
                await _openExternalUrl(url);
                return NavigationActionPolicy.CANCEL;
              }
              
              // Diğer linkler WebView içinde açılsın
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (_isLoading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  if (_progress > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        '${(_progress * 100).toInt()}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
