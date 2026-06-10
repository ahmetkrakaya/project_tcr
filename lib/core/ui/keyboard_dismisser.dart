import 'package:flutter/material.dart';

/// Klavye açıkken ekranın boş alanına dokunulduğunda odak kaldırılarak klavyeyi kapatır.
class KeyboardDismisser extends StatelessWidget {
  const KeyboardDismisser({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}
