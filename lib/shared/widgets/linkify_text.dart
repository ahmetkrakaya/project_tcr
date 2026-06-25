import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';

/// Metindeki URL'leri otomatik algılar, tıklanabilir yapar ve metin seçimine izin verir.
class LinkifyText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final bool selectable;

  const LinkifyText({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
    this.selectable = true,
  });

  static final RegExp _urlRegex = RegExp(
    r'(https?:\/\/\S+|www\.\S+)',
    caseSensitive: false,
  );

  @override
  State<LinkifyText> createState() => _LinkifyTextState();
}

class _LinkifyTextState extends State<LinkifyText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final baseStyle = widget.style ?? const TextStyle();
    final linkStyle = widget.linkStyle ??
        baseStyle.copyWith(
          color: AppColors.primary,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.primary,
        );

    final matches = LinkifyText._urlRegex.allMatches(widget.text).toList();
    if (matches.isEmpty) {
      if (widget.selectable) {
        return SelectableText(widget.text, style: baseStyle);
      }
      return Text(widget.text, style: baseStyle);
    }

    final spans = <TextSpan>[];
    var cursor = 0;

    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }

      final rawUrl = match.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _openLink(context, rawUrl);
      _recognizers.add(recognizer);

      spans.add(
        TextSpan(
          text: rawUrl,
          style: linkStyle,
          recognizer: recognizer,
        ),
      );
      cursor = match.end;
    }

    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    final richSpan = TextSpan(style: baseStyle, children: spans);
    if (widget.selectable) {
      return SelectableText.rich(richSpan);
    }
    return Text.rich(richSpan);
  }

  Future<void> _openLink(BuildContext context, String rawUrl) async {
    final normalized = _normalizeUrl(rawUrl);
    final uri = Uri.tryParse(normalized);
    if (uri == null) return;

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link açılamadı')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link açılamadı')),
        );
      }
    }
  }

  String _normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }
}
