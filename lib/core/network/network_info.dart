import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Network Info Provider
final networkInfoProvider = Provider<NetworkInfo>((ref) {
  return NetworkInfoImpl(
    connectivity: Connectivity(),
    internetChecker: InternetConnection(),
  );
});

/// Network connection status provider
final networkStatusProvider = StreamProvider<bool>((ref) {
  final networkInfo = ref.watch(networkInfoProvider);
  return networkInfo.onConnectivityChanged;
});

/// Network Info Interface
abstract class NetworkInfo {
  Future<bool> get isConnected;
  Stream<bool> get onConnectivityChanged;
}

/// Network Info Implementation
class NetworkInfoImpl implements NetworkInfo {
  final Connectivity connectivity;
  final InternetConnection internetChecker;

  NetworkInfoImpl({
    required this.connectivity,
    required this.internetChecker,
  });

  @override
  Future<bool> get isConnected async {
    final connectivityResult = await connectivity.checkConnectivity();
    
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return false;
    }
    
    // Gerçek internet bağlantısını kontrol et
    return await internetChecker.hasInternetAccess;
  }

  @override
  Stream<bool> get onConnectivityChanged {
    return connectivity.onConnectivityChanged.asyncMap((results) async {
      if (results.contains(ConnectivityResult.none)) {
        return false;
      }
      return await internetChecker.hasInternetAccess;
    });
  }
}
