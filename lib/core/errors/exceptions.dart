/// Base Exception class for app-specific exceptions
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalException;

  const AppException({
    required this.message,
    this.code,
    this.originalException,
  });

  @override
  String toString() => 'AppException: $message (code: $code)';
}

/// Authentication Exception - renamed to avoid conflict with Supabase
class AppAuthException extends AppException {
  const AppAuthException({
    required super.message,
    super.code,
    super.originalException,
  });

  @override
  String toString() => 'AppAuthException: $message (code: $code)';
}

/// Server Exception
class ServerException extends AppException {
  const ServerException({
    required super.message,
    super.code,
    super.originalException,
  });

  /// Factory constructor from HTTP response
  factory ServerException.fromResponse(int statusCode, String? message) {
    String errorMessage;
    String errorCode;

    switch (statusCode) {
      case 400:
        errorMessage = message ?? 'Geçersiz istek';
        errorCode = 'BAD_REQUEST';
        break;
      case 401:
        errorMessage = message ?? 'Oturum süresi dolmuş, lütfen tekrar giriş yapın';
        errorCode = 'UNAUTHORIZED';
        break;
      case 403:
        errorMessage = message ?? 'Bu işlem için yetkiniz yok';
        errorCode = 'FORBIDDEN';
        break;
      case 404:
        errorMessage = message ?? 'Kaynak bulunamadı';
        errorCode = 'NOT_FOUND';
        break;
      case 422:
        errorMessage = message ?? 'İşlem yapılamadı';
        errorCode = 'UNPROCESSABLE_ENTITY';
        break;
      case 429:
        errorMessage = message ?? 'Çok fazla istek gönderildi, lütfen bekleyin';
        errorCode = 'TOO_MANY_REQUESTS';
        break;
      case 500:
        errorMessage = message ?? 'Sunucu hatası';
        errorCode = 'INTERNAL_SERVER_ERROR';
        break;
      case 502:
        errorMessage = message ?? 'Sunucu geçici olarak kullanılamıyor';
        errorCode = 'BAD_GATEWAY';
        break;
      case 503:
        errorMessage = message ?? 'Sunucu bakımda';
        errorCode = 'SERVICE_UNAVAILABLE';
        break;
      default:
        errorMessage = message ?? 'Bilinmeyen sunucu hatası';
        errorCode = 'UNKNOWN_ERROR';
    }

    return ServerException(message: errorMessage, code: errorCode);
  }

  @override
  String toString() => 'ServerException: $message (code: $code)';
}

/// Cache Exception
class CacheException extends AppException {
  const CacheException({
    required super.message,
    super.code,
    super.originalException,
  });

  @override
  String toString() => 'CacheException: $message (code: $code)';
}

/// Network Exception
class NetworkException extends AppException {
  const NetworkException({
    super.message = 'İnternet bağlantısı yok',
    super.code = 'NO_INTERNET',
    super.originalException,
  });

  @override
  String toString() => 'NetworkException: $message (code: $code)';
}

/// Validation Exception
class ValidationException extends AppException {
  final Map<String, List<String>>? errors;

  const ValidationException({
    required super.message,
    super.code,
    super.originalException,
    this.errors,
  });

  @override
  String toString() => 'ValidationException: $message (code: $code)';
}

/// Storage Exception
class StorageException extends AppException {
  const StorageException({
    required super.message,
    super.code,
    super.originalException,
  });

  @override
  String toString() => 'StorageException: $message (code: $code)';
}

/// Permission Exception
class PermissionException extends AppException {
  const PermissionException({
    required super.message,
    super.code,
    super.originalException,
  });

  @override
  String toString() => 'PermissionException: $message (code: $code)';
}

/// Kullanıcı zaten başka bir gruba üye; başka gruba geçmek için önce mevcut gruptan ayrılması gerekir.
class UserAlreadyInGroupException extends AppException {
  final String? currentGroupId;
  final String? currentGroupName;

  const UserAlreadyInGroupException({
    required super.message,
    super.code = 'USER_ALREADY_IN_GROUP',
    super.originalException,
    this.currentGroupId,
    this.currentGroupName,
  });

  @override
  String toString() =>
      'UserAlreadyInGroupException: $message (group: $currentGroupName)';
}

/// Verilen hata, içeriğin bulunamadığı/silinmiş olduğu durumuna karşılık geliyor mu?
/// (Örn. PostgREST PGRST116 - "Cannot coerce the result to a single JSON object")
bool isContentNotFoundError(Object error) {
  if (error is ServerException) {
    if (error.code == 'PGRST116' || error.code == 'NOT_FOUND') {
      return true;
    }
    final msg = error.message.toLowerCase();
    if (msg.contains('pgrst116') ||
        msg.contains('single json') ||
        msg.contains('cannot coerce') ||
        msg.contains('bulunamadı')) {
      return true;
    }
  }
  final str = error.toString().toLowerCase();
  return str.contains('pgrst116') ||
      str.contains('single json') ||
      str.contains('cannot coerce');
}
