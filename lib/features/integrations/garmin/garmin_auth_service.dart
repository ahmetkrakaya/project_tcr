import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';

class GarminAuthService {
  GarminAuthService._();
  static final instance = GarminAuthService._();

  /// PKCE code_verifier oluşturur (43-128 karakter, URL-safe)
  String _generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rng = Random.secure();
    return List.generate(64, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// code_verifier'dan code_challenge oluşturur (SHA-256 + base64url)
  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Garmin OAuth2 PKCE akışını başlatır, başarılı ise Edge Function'a gönderir.
  /// Başarılı bağlantıda true döner.
  Future<bool> connectGarmin() async {
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);
    final state = base64Url
        .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');

    final authUrl = Uri.parse(AppConstants.garminOAuthUrl).replace(
      queryParameters: {
        'client_id': AppConstants.garminClientId,
        'response_type': 'code',
        'redirect_uri': AppConstants.garminRedirectUri,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'state': state,
      },
    );

    final resultUrl = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: 'tcr',
    );

    final uri = Uri.parse(resultUrl);
    final code = uri.queryParameters['code'];
    final returnedState = uri.queryParameters['state'];
    final error = uri.queryParameters['error'];

    if (error != null) {
      throw Exception('Garmin OAuth hatası: $error');
    }

    if (code == null) {
      throw Exception('Garmin\'den yetkilendirme kodu alınamadı');
    }

    if (returnedState != state) {
      throw Exception('OAuth state doğrulaması başarısız');
    }

    // Edge Function'a gönder
    final response = await Supabase.instance.client.functions.invoke(
      'garmin-auth',
      body: {
        'code': code,
        'code_verifier': codeVerifier,
        'redirect_uri': AppConstants.garminRedirectUri,
      },
    );

    if (response.status != 200) {
      final data = response.data;
      final errorMsg = data is Map ? data['error'] ?? 'Bilinmeyen hata' : 'Bağlantı başarısız';
      throw Exception('Garmin bağlantısı başarısız: $errorMsg');
    }

    return true;
  }

  /// Garmin bağlantısını kaldırır
  Future<bool> disconnectGarmin() async {
    final response = await Supabase.instance.client.functions.invoke(
      'garmin-disconnect',
    );

    return response.status == 200;
  }
}

final garminAuthServiceProvider = Provider<GarminAuthService>((ref) {
  return GarminAuthService.instance;
});
