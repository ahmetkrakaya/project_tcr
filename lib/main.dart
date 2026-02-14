import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/notifications/fcm_service.dart';
import 'core/notifications/notification_handler.dart';
import 'core/permissions/app_permissions.dart';
import 'shared/providers/auth_provider.dart';

import 'firebase_options.dart';

Future<void> main() async {
  // Şifre sıfırlama deep link hatalarını (otp_expired vb.) yakala; ensureInitialized ve runApp aynı zone'da olmalı
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Firebase
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // Bildirim ve izinler sadece mobilde (web'de desteklenmiyor)
    if (!kIsWeb) {
      await FcmService.requestPermission();
      await AppPermissions.requestMediaPermissions();
      await initNotificationHandler(invokeNotificationNavigation);
    }

    // Initialize date formatting for Turkish locale
    await initializeDateFormatting('tr_TR', null);

    // Initialize Supabase
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );

    // FCM token: giriş yapmış kullanıcı varsa hemen yaz, token değişince güncelle (sadece mobil)
    if (!kIsWeb) {
      if (Supabase.instance.client.auth.currentUser != null) {
        await FcmService.refreshAndSaveToken();
      }
      FcmService.onTokenRefresh.listen((token) => FcmService.saveTokenToSupabase(token));
      Supabase.instance.client.auth.onAuthStateChange.listen((event) {
        if (event.session != null) FcmService.refreshAndSaveToken();
      });
    }

    // Sadece dikey (portrait) yönlendirme - mobilde App Store yayını için
    if (!kIsWeb) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }

    // Set system UI overlay style (sadece mobil)
    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      );
    }

    runApp(
      const ProviderScope(
        child: TCRApp(),
      ),
    );
  }, (error, stack) {
    if (error is supabase.AuthException &&
        (error.message.toLowerCase().contains('expired') ||
            error.message.toLowerCase().contains('invalid') ||
            error.code == 'access_denied')) {
      passwordResetLinkErrorNotifier.value =
          'Linkin süresi dolmuş veya zaten kullanılmış. Lütfen giriş ekranından "Şifremi Unuttum" ile tekrar talep edin.';
    }
  });
}

/// Şifre sıfırlama linki hatası (otp_expired vb.) gelince notifier set eder.
/// Dialog, Navigator altındaki LoginPage'de gösterilir.
class _AuthLinkErrorListener extends StatefulWidget {
  const _AuthLinkErrorListener({required this.child});

  final Widget child;

  @override
  State<_AuthLinkErrorListener> createState() => _AuthLinkErrorListenerState();
}

class _AuthLinkErrorListenerState extends State<_AuthLinkErrorListener> {
  StreamSubscription<supabase.AuthState>? _authSubscription;

  static const _resetLinkErrorMessage =
      'Linkin süresi dolmuş veya zaten kullanılmış. Lütfen giriş ekranından "Şifremi Unuttum" ile tekrar talep edin.';

  @override
  void initState() {
    super.initState();
    // Auth stream'deki hataları dinle (Supabase notifyException ile emit ediyor)
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) {},
      onError: (error, _) {
        if (error is supabase.AuthException &&
            (error.message.toLowerCase().contains('expired') ||
                error.message.toLowerCase().contains('invalid') ||
                error.code == 'access_denied')) {
          passwordResetLinkErrorNotifier.value = _resetLinkErrorMessage;
        }
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// TCR App Widget
class TCRApp extends ConsumerWidget {
  const TCRApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    // Bildirim tıklanınca yönlendirme callback'i (sadece mobil)
    if (!kIsWeb) {
      setNotificationNavigationCallback((message) {
        navigateFromNotification(router, message);
      });
      // Uygulama kapalıyken bildirimle açıldıysa ilk mesajı işle
      WidgetsBinding.instance.addPostFrameCallback((_) {
        handleInitialMessage();
      });
    }

    return MaterialApp.router(
      title: AppConstants.appFullName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      routerConfig: router,
      // Localization settings for Turkish
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [
        Locale('tr', 'TR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        const baseWidth = 430.0; // iPhone Pro Max benzeri referans genişlik
        final width = mq.size.width;
        // Küçük ekranlarda metni biraz küçült, büyük ekranda 1.0 bırak
        final rawScale = width / baseWidth;
        final textScale = rawScale.clamp(0.8, 1.0);

        return _AuthLinkErrorListener(
          child: MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
