import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Logodan marka rengini çıkarır. Kenar pikselleri ve baskın renkleri
/// ağırlıklandırır; beyaza yakın renkleri (logo yazıları) filtreler.
Future<Color?> extractBrandColorFromImageBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 64,
    targetHeight: 64,
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;

  try {
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return null;

    final width = image.width;
    final height = image.height;
    final scores = <int, double>{};

    void samplePixel(int x, int y, {double weight = 1}) {
      final i = (y * width + x) * 4;
      final r = byteData.getUint8(i);
      final g = byteData.getUint8(i + 1);
      final b = byteData.getUint8(i + 2);
      final a = byteData.getUint8(i + 3);
      if (a < 100) return;

      final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
      // Beyaz/açık yazıları atla
      if (luminance > 0.88) return;
      // Çok soluk gri tonları atla
      final maxC = [r, g, b].reduce((a, b) => a > b ? a : b);
      final minC = [r, g, b].reduce((a, b) => a < b ? a : b);
      final saturation = maxC == 0 ? 0.0 : (maxC - minC) / maxC;
      if (saturation < 0.08 && luminance > 0.25) return;

      final qr = (r ~/ 16) * 16;
      final qg = (g ~/ 16) * 16;
      final qb = (b ~/ 16) * 16;
      final key = (qr << 16) | (qg << 8) | qb;

      // Doygun renklere bonus ver (arka plan genelde belirgin renktir)
      final score = weight * (1 + saturation * 2);
      scores[key] = (scores[key] ?? 0) + score;
    }

    // Kenar pikselleri — arka plan rengi genelde kenarlarda görünür
    for (var x = 0; x < width; x++) {
      samplePixel(x, 0, weight: 4);
      samplePixel(x, height - 1, weight: 4);
    }
    for (var y = 0; y < height; y++) {
      samplePixel(0, y, weight: 4);
      samplePixel(width - 1, y, weight: 4);
    }

    // Tüm pikseller
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        samplePixel(x, y);
      }
    }

    if (scores.isEmpty) return null;

    final best = scores.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    return Color(0xFF000000 | best.key);
  } finally {
    image.dispose();
  }
}

String colorToHex(Color color) {
  final r = color.red.toRadixString(16).padLeft(2, '0');
  final g = color.green.toRadixString(16).padLeft(2, '0');
  final b = color.blue.toRadixString(16).padLeft(2, '0');
  return '#${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
}

Color parseHexColor(String hex, {Color fallback = const Color(0xFF1B4332)}) {
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length == 6) {
    final value = int.tryParse(cleaned, radix: 16);
    if (value != null) return Color(0xFF000000 | value);
  }
  return fallback;
}
