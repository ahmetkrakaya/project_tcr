import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Post kapak ve içerik görsellerini yüklemeden önce standart boyuta getirir.
class PostImageProcessor {
  static const int coverWidth = 1200;
  static const int coverHeight = 675; // 16:9

  static const int blockMaxDimension = 1200;
  static const double blockMaxAspectRatio = 3.0;

  /// Kapak görseli: merkezden 16:9 kırp, yeniden boyutlandır, JPEG olarak döndür.
  static Uint8List processCoverImage(Uint8List input) {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw Exception('Görsel okunamadı');
    }

    final cropped = _centerCropToAspect(
      decoded,
      coverWidth / coverHeight,
    );
    final resized = img.copyResize(
      cropped,
      width: coverWidth,
      height: coverHeight,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  }

  /// İçerik görseli: aşırı en-boy oranlarını sınırla, max boyuta küçült.
  static Uint8List processBlockImage(Uint8List input) {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw Exception('Görsel okunamadı');
    }

    var image = decoded;
    final ratio = image.width / image.height;

    if (ratio > blockMaxAspectRatio) {
      image = _centerCropToAspect(image, blockMaxAspectRatio);
    } else if (ratio < 1 / blockMaxAspectRatio) {
      image = _centerCropToAspect(image, 1 / blockMaxAspectRatio);
    }

    final resized = _resizeToMaxDimension(image, blockMaxDimension);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  }

  static img.Image _centerCropToAspect(img.Image image, double targetAspect) {
    final currentAspect = image.width / image.height;

    final int cropWidth;
    final int cropHeight;
    final int x;
    final int y;

    if (currentAspect > targetAspect) {
      cropHeight = image.height;
      cropWidth = (cropHeight * targetAspect).round();
      x = (image.width - cropWidth) ~/ 2;
      y = 0;
    } else {
      cropWidth = image.width;
      cropHeight = (cropWidth / targetAspect).round();
      x = 0;
      y = (image.height - cropHeight) ~/ 2;
    }

    return img.copyCrop(
      image,
      x: x,
      y: y,
      width: cropWidth,
      height: cropHeight,
    );
  }

  static img.Image _resizeToMaxDimension(img.Image image, int maxDim) {
    if (image.width <= maxDim && image.height <= maxDim) {
      return image;
    }

    if (image.width >= image.height) {
      return img.copyResize(image, width: maxDim);
    }
    return img.copyResize(image, height: maxDim);
  }
}
