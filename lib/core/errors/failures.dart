abstract class Failure {
  final String message;
  final String? code;
  final dynamic originalError;

  const Failure({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  String toString() => 'Failure(message: $message, code: $code)';
}

/// Server/API hataları
class ServerFailure extends Failure {
  const ServerFailure({
    required super.message,
    super.code,
    super.originalError,
  });

  factory ServerFailure.fromStatusCode(int statusCode, [String? message]) {
    switch (statusCode) {
      case 400:
        return ServerFailure(
          message: message ?? 'Geçersiz istek',
          code: 'BAD_REQUEST',
        );
      case 401:
        return ServerFailure(
          message: message ?? 'Yetkilendirme gerekli',
          code: 'UNAUTHORIZED',
        );
      case 403:
        return ServerFailure(
          message: message ?? 'Erişim reddedildi',
          code: 'FORBIDDEN',
        );
      case 404:
        return ServerFailure(
          message: message ?? 'Kaynak bulunamadı',
          code: 'NOT_FOUND',
        );
      case 409:
        return ServerFailure(
          message: message ?? 'Çakışma hatası',
          code: 'CONFLICT',
        );
      case 422:
        return ServerFailure(
          message: message ?? 'İşlem yapılamadı',
          code: 'UNPROCESSABLE_ENTITY',
        );
      case 429:
        return ServerFailure(
          message: message ?? 'Çok fazla istek, lütfen bekleyin',
          code: 'TOO_MANY_REQUESTS',
        );
      case 500:
        return ServerFailure(
          message: message ?? 'Sunucu hatası',
          code: 'INTERNAL_SERVER_ERROR',
        );
      case 502:
        return ServerFailure(
          message: message ?? 'Sunucuya ulaşılamıyor',
          code: 'BAD_GATEWAY',
        );
      case 503:
        return ServerFailure(
          message: message ?? 'Servis kullanılamıyor',
          code: 'SERVICE_UNAVAILABLE',
        );
      default:
        return ServerFailure(
          message: message ?? 'Bilinmeyen sunucu hatası',
          code: 'UNKNOWN',
        );
    }
  }
}

/// Ağ/Bağlantı hataları
class NetworkFailure extends Failure {
  const NetworkFailure({
    super.message = 'İnternet bağlantısı yok',
    super.code = 'NO_INTERNET',
    super.originalError,
  });
}

/// Önbellek hataları
class CacheFailure extends Failure {
  const CacheFailure({
    super.message = 'Önbellek hatası',
    super.code = 'CACHE_ERROR',
    super.originalError,
  });
}

/// Yetkilendirme hataları
class AuthFailure extends Failure {
  const AuthFailure({
    required super.message,
    super.code,
    super.originalError,
  });

  factory AuthFailure.invalidCredentials() => const AuthFailure(
        message: 'Geçersiz kimlik bilgileri',
        code: 'INVALID_CREDENTIALS',
      );

  factory AuthFailure.userNotFound() => const AuthFailure(
        message: 'Kullanıcı bulunamadı',
        code: 'USER_NOT_FOUND',
      );

  factory AuthFailure.emailAlreadyInUse() => const AuthFailure(
        message: 'Bu e-posta adresi zaten kullanımda',
        code: 'EMAIL_ALREADY_IN_USE',
      );

  factory AuthFailure.weakPassword() => const AuthFailure(
        message: 'Şifre çok zayıf',
        code: 'WEAK_PASSWORD',
      );

  factory AuthFailure.sessionExpired() => const AuthFailure(
        message: 'Oturum süresi doldu, lütfen tekrar giriş yapın',
        code: 'SESSION_EXPIRED',
      );

  factory AuthFailure.socialLoginCancelled() => const AuthFailure(
        message: 'Giriş işlemi iptal edildi',
        code: 'SOCIAL_LOGIN_CANCELLED',
      );

  factory AuthFailure.socialLoginFailed(String provider) => AuthFailure(
        message: '$provider ile giriş başarısız',
        code: 'SOCIAL_LOGIN_FAILED',
      );
}

/// Doğrulama hataları
class ValidationFailure extends Failure {
  final Map<String, String>? fieldErrors;

  const ValidationFailure({
    required super.message,
    super.code = 'VALIDATION_ERROR',
    this.fieldErrors,
    super.originalError,
  });

  factory ValidationFailure.required(String fieldName) => ValidationFailure(
        message: '$fieldName zorunludur',
        fieldErrors: {fieldName: 'Bu alan zorunludur'},
      );

  factory ValidationFailure.invalidFormat(String fieldName) => ValidationFailure(
        message: '$fieldName geçersiz formatta',
        fieldErrors: {fieldName: 'Geçersiz format'},
      );

  factory ValidationFailure.tooShort(String fieldName, int minLength) =>
      ValidationFailure(
        message: '$fieldName en az $minLength karakter olmalıdır',
        fieldErrors: {fieldName: 'En az $minLength karakter'},
      );

  factory ValidationFailure.tooLong(String fieldName, int maxLength) =>
      ValidationFailure(
        message: '$fieldName en fazla $maxLength karakter olabilir',
        fieldErrors: {fieldName: 'En fazla $maxLength karakter'},
      );
}

/// Dosya işlem hataları
class FileFailure extends Failure {
  const FileFailure({
    required super.message,
    super.code,
    super.originalError,
  });

  factory FileFailure.notFound() => const FileFailure(
        message: 'Dosya bulunamadı',
        code: 'FILE_NOT_FOUND',
      );

  factory FileFailure.tooLarge(int maxSizeMB) => FileFailure(
        message: 'Dosya boyutu ${maxSizeMB}MB\'dan büyük olamaz',
        code: 'FILE_TOO_LARGE',
      );

  factory FileFailure.invalidFormat(List<String> allowedFormats) => FileFailure(
        message: 'Geçersiz dosya formatı. İzin verilen: ${allowedFormats.join(', ')}',
        code: 'INVALID_FORMAT',
      );

  factory FileFailure.uploadFailed() => const FileFailure(
        message: 'Dosya yüklenemedi',
        code: 'UPLOAD_FAILED',
      );
}

/// İzin hataları
class PermissionFailure extends Failure {
  const PermissionFailure({
    required super.message,
    super.code = 'PERMISSION_DENIED',
    super.originalError,
  });

  factory PermissionFailure.location() => const PermissionFailure(
        message: 'Konum izni gerekli',
        code: 'LOCATION_PERMISSION',
      );

  factory PermissionFailure.camera() => const PermissionFailure(
        message: 'Kamera izni gerekli',
        code: 'CAMERA_PERMISSION',
      );

  factory PermissionFailure.storage() => const PermissionFailure(
        message: 'Depolama izni gerekli',
        code: 'STORAGE_PERMISSION',
      );

  factory PermissionFailure.health() => const PermissionFailure(
        message: 'Sağlık verisi izni gerekli',
        code: 'HEALTH_PERMISSION',
      );

  factory PermissionFailure.notification() => const PermissionFailure(
        message: 'Bildirim izni gerekli',
        code: 'NOTIFICATION_PERMISSION',
      );
}

/// Bilinmeyen hatalar
class UnknownFailure extends Failure {
  const UnknownFailure({
    super.message = 'Bilinmeyen bir hata oluştu',
    super.code = 'UNKNOWN',
    super.originalError,
  });
}
