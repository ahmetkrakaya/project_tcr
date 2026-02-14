import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Android'de Strava OAuth akışını in-app WebView içinde açar.
/// Redirect (tcr://...) yakalanınca sayfa kapanır ve URL sonucu döner.
/// Böylece Chrome Custom Tabs nedeniyle uygulamanın yeniden başlaması engellenir.
class StravaOAuthWebViewPage extends StatefulWidget {
  const StravaOAuthWebViewPage({
    super.key,
    required this.initialUrl,
    required this.callbackScheme,
  });

  final String initialUrl;
  final String callbackScheme;

  @override
  State<StravaOAuthWebViewPage> createState() => _StravaOAuthWebViewPageState();
}

class _StravaOAuthWebViewPageState extends State<StravaOAuthWebViewPage> {
  bool _isLoading = true;

  void _complete(String? redirectUrl) {
    if (!mounted) return;
    Navigator.of(context).pop(redirectUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Strava ile Bağlan'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _complete(null),
        ),
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              useHybridComposition: true,
            ),
            onLoadStart: (controller, url) {
              setState(() => _isLoading = true);
            },
            onLoadStop: (controller, url) {
              setState(() => _isLoading = false);
            },
            onReceivedError: (controller, request, error) {
              setState(() => _isLoading = false);
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url.toString();
              if (url.toLowerCase().startsWith('${widget.callbackScheme.toLowerCase()}://')) {
                _complete(url);
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
