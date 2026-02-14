import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;

import 'package:permission_handler/permission_handler.dart';

/// Uygulama ilk açılışında (bildirim izni gibi) kamera ve galeri izinlerini ister.
/// Market gönderimlerinde bu izinlerin kullanım gerekçesinin açık olması ve
/// mümkünse başlangıçta izin istenmesi önerilir.
class AppPermissions {
  AppPermissions._();

  /// Kamera ve fotoğraf galerisi izinlerini ister.
  /// Sadece henüz karar verilmemiş (denied) olanlar için sistem dialogu gösterilir.
  /// Web'de izin mekanizması farklı olduğundan çalışmaz, skip edilir.
  static Future<void> requestMediaPermissions() async {
    if (kIsWeb) return;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final cameraStatus = await Permission.camera.status;
      if (cameraStatus.isDenied) {
        await Permission.camera.request();
      }
      final photosStatus = await Permission.photos.status;
      if (photosStatus.isDenied) {
        await Permission.photos.request();
      }
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final cameraStatus = await Permission.camera.status;
      if (cameraStatus.isDenied) {
        await Permission.camera.request();
      }
      // Android 13+ READ_MEDIA_IMAGES, daha eski sürümler storage
      final photosStatus = await Permission.photos.status;
      if (photosStatus.isDenied) {
        await Permission.photos.request();
      }
    }
  }
}
