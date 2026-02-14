import 'platform_utils_stub.dart' if (dart.library.io) 'platform_utils_io.dart' as impl;

/// Android platformunda mı çalışıyor (Web'de false).
bool get isAndroid => impl.isAndroid;
