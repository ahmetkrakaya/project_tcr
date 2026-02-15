import 'package:flutter/foundation.dart' show kIsWeb;

class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'TCR';
  static const String appFullName = 'Twenty City Runners';
  static const String appVersion = '1.0.0';

  // App Store URLs (for force update)
  static const String appStoreUrl = String.fromEnvironment(
    'APP_STORE_URL',
    defaultValue: 'https://apps.apple.com/app/id123456789', // Placeholder - replace with actual App ID
  );
  static const String playStoreUrl = String.fromEnvironment(
    'PLAY_STORE_URL',
    defaultValue: 'https://play.google.com/store/apps/details?id=com.rivlus.project_tcr',
  );

  // Supabase
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://lnodjfivycpyoytmwpcn.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imxub2RqZml2eWNweW95dG13cGNuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkwMjM3NDMsImV4cCI6MjA4NDU5OTc0M30.Huaq1EC6wM2zzVTKbflG1XIeINvVtYU6mRIAUTvzm5s',
  );

  // Strava
  static const String stravaClientId = String.fromEnvironment(
    'STRAVA_CLIENT_ID',
    defaultValue: '198092',
  );
  static const String stravaClientSecret = String.fromEnvironment(
    'STRAVA_CLIENT_SECRET',
    defaultValue: '0822fb63353132c51caaaf9051301427a01f98d3',
  );
  /// Strava OAuth redirect URI - web'de https, mobilde custom scheme
  static String get stravaRedirectUri =>
      kIsWeb ? 'https://app.rivlus.com/auth/callback' : 'tcr://redirect';

  /// Şifre sıfırlama e-postasındaki linkin yönlendirmesi
  /// Web'de https URL, mobilde custom scheme deep link
  static String get authResetPasswordRedirectUrl =>
      kIsWeb ? 'https://app.rivlus.com/reset-password' : 'tcr://reset-password';

  /// Etkinlik detay deep link (uygulamada aç – landing sayfasındaki buton bu linki kullanır)
  static String eventDetailDeepLink(String eventId) =>
      'tcr:///events/$eventId';

  /// Etkinlik paylaşım landing sayfası base URL (zengin önizleme için).
  /// NOT: www.rivlus.com kullanılmalı; rivlus.com → www redirect yapıyor,
  /// Android App Links redirect'i kabul etmez.
  static const String eventShareBaseUrl = String.fromEnvironment(
    'EVENT_SHARE_BASE_URL',
    defaultValue: 'https://www.rivlus.com',
  );

  /// Kısa paylaşım URL’i: /e/:id – Landing sayfası Supabase’den başlık/açıklama/görsel alır.
  static String eventShareUrlShort(String eventId) =>
      '$eventShareBaseUrl/e/${Uri.encodeComponent(eventId)}';

  /// Uzun paylaşım URL’i (geriye dönük uyumluluk). Query ile title, desc, img gönderir.
  static String eventShareUrl(
    String eventId,
    String title,
    String description, {
    String? imageUrl,
  }) {
    final base = '$eventShareBaseUrl/e';
    final params = <String>[
      'id=${Uri.encodeComponent(eventId)}',
      'title=${Uri.encodeComponent(title)}',
      'desc=${Uri.encodeComponent(description)}',
    ];
    if (imageUrl != null && imageUrl.isNotEmpty && imageUrl.startsWith('http')) {
      params.add('img=${Uri.encodeComponent(imageUrl)}');
    }
    return '$base?${params.join('&')}';
  }

  /// Marketplace paylaşım landing sayfası base URL (zengin önizleme için).
  /// NOT: www.rivlus.com kullanılmalı; rivlus.com → www redirect yapıyor,
  /// Android App Links redirect'i kabul etmez.
  static const String marketplaceShareBaseUrl = String.fromEnvironment(
    'MARKETPLACE_SHARE_BASE_URL',
    defaultValue: 'https://www.rivlus.com',
  );

  /// Marketplace detay deep link (uygulamada aç)
  static String listingDetailDeepLink(String listingId) =>
      'tcr:///marketplace/$listingId';

  /// Marketplace paylaşım URL'i: /m/:id – Landing sayfası Supabase'den başlık/fiyat/görsel alır.
  static String listingShareUrlShort(String listingId) =>
      '$marketplaceShareBaseUrl/m/${Uri.encodeComponent(listingId)}';

  /// Marketplace uzun paylaşım URL'i. Query ile title, price, img gönderir.
  static String listingShareUrl(
    String listingId,
    String title, {
    double? price,
    String currency = 'TRY',
    String? imageUrl,
  }) {
    final base = '$marketplaceShareBaseUrl/m';
    final params = <String>[
      'id=${Uri.encodeComponent(listingId)}',
      'title=${Uri.encodeComponent(title)}',
    ];
    if (price != null) {
      params.add('price=${Uri.encodeComponent(price.toStringAsFixed(0))}');
      params.add('currency=${Uri.encodeComponent(currency)}');
    }
    if (imageUrl != null && imageUrl.isNotEmpty && imageUrl.startsWith('http')) {
      params.add('img=${Uri.encodeComponent(imageUrl)}');
    }
    return '$base?${params.join('&')}';
  }

  static const String stravaAuthUrl = 'https://www.strava.com/oauth/authorize';
  static const String stravaTokenUrl = 'https://www.strava.com/oauth/token';
  static const String stravaApiUrl = 'https://www.strava.com/api/v3';
  static const String stravaScopes = 'activity:read,activity:read_all,profile:read_all';

  // Pagination
  static const int defaultPageSize = 20;
  static const int chatPageSize = 50;

  // Cache Duration
  static const Duration cacheDuration = Duration(hours: 1);
  static const Duration shortCacheDuration = Duration(minutes: 15);

  // Animation Duration
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const Duration shortAnimationDuration = Duration(milliseconds: 150);

  // Image
  static const int maxImageWidth = 1920;
  static const int maxImageHeight = 1080;
  static const int thumbnailSize = 300;
  static const int avatarSize = 200;


  // Event Chat
  static const Duration eventChatReadOnlyAfter = Duration(hours: 24);

  // Leaderboard
  static const int leaderboardTopCount = 50;

  // Marketplace
  static const Duration listingExpiryDays = Duration(days: 30);
}

/// Storage Keys
class StorageKeys {
  StorageKeys._();

  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String userId = 'user_id';
  static const String userRole = 'user_role';
  static const String onboardingCompleted = 'onboarding_completed';
  static const String themeMode = 'theme_mode';
  static const String notificationsEnabled = 'notifications_enabled';
  static const String selectedTrainingGroup = 'selected_training_group';
}

/// Route Names
class RouteNames {
  RouteNames._();

  // Auth
  static const String splash = 'splash';
  static const String onboarding = 'onboarding';
  static const String login = 'login';
  static const String register = 'register';
  static const String verifyEmail = 'verify-email';
  static const String completeProfile = 'complete-profile';
  static const String resetPassword = 'reset-password';

  // Main
  static const String home = 'home';
  static const String feed = 'feed';
  static const String events = 'events';
  static const String chat = 'chat';
  static const String profile = 'profile';
  static const String notifications = 'notifications';

  // Events
  static const String eventDetail = 'event-detail';
  static const String createEvent = 'create-event';
  static const String editEvent = 'edit-event';
  static const String eventReport = 'event-report';
  static const String eventReportDetail = 'event-report-detail';
  static const String carpoolOffers = 'carpool-offers';
  static const String carpoolCreate = 'carpool-create';

  // Routes & Maps
  static const String routes = 'routes';
  static const String routeDetail = 'route-detail';
  static const String routeEdit = 'route-edit';
  static const String route3DView = 'route-3d-view';
  static const String routeCreate = 'route-create';

  // Groups (Antrenman Grupları)
  static const String groups = 'groups';
  static const String groupDetail = 'group-detail';
  static const String createGroup = 'create-group';
  static const String editGroup = 'edit-group';
  static const String upcomingBirthdays = 'upcoming-birthdays';

  // Chat
  static const String chatRoom = 'chat-room';
  static const String chatRoomDetail = 'chat-room-detail';
  static const String eventChat = 'event-chat';
  static const String anonymousQA = 'anonymous-qa';

  // Profile
  static const String profileEdit = 'profile-edit';
  static const String userProfile = 'user-profile';
  static const String iceCard = 'ice-card';
  static const String iceCardEdit = 'ice-card-edit';
  static const String settings = 'settings';
  static const String integrations = 'integrations';
  static const String stravaActivityList = 'strava-activity-list';
  static const String statistics = 'statistics';

  // Activity
  static const String activityDetail = 'activity-detail';
  static const String activityCreate = 'activity-create';
  static const String activityHistory = 'activity-history';
  static const String leaderboard = 'leaderboard';

  // Posts
  static const String createPost = 'create-post';
  static const String editPost = 'edit-post';
  static const String postDetail = 'post-detail';

  // Gallery
  static const String eventGallery = 'event-gallery';
  static const String photoViewer = 'photo-viewer';

  // Marketplace
  static const String marketplace = 'marketplace';
  static const String listingDetail = 'listing-detail';
  static const String listingCreate = 'listing-create';
  static const String listingEdit = 'listing-edit';
  static const String myListings = 'my-listings';
  static const String favorites = 'favorites';
  static const String ordersManagement = 'orders-management';
  static const String myOrders = 'my-orders';

  // Tools
  static const String paceCalculator = 'pace-calculator';
  static const String laneCalculator = 'lane-calculator';
}

/// Asset Paths
class AssetPaths {
  AssetPaths._();

  // Images
  static const String imagesPath = 'assets/images';
  static const String logo = '$imagesPath/logo.png';
  /// Paylaşım önizlemesinde gösterilecek uygulama logosu (share sheet ikonu)
  static const String shareLogo = '$imagesPath/tcr_logo.jpg';
  static const String logoWhite = '$imagesPath/logo_white.png';
  static const String onboarding1 = '$imagesPath/onboarding_1.png';
  static const String onboarding2 = '$imagesPath/onboarding_2.png';
  static const String onboarding3 = '$imagesPath/onboarding_3.png';
  static const String placeholder = '$imagesPath/placeholder.png';
  static const String emptyState = '$imagesPath/empty_state.png';

  // Icons
  static const String iconsPath = 'assets/icons';
  static const String googleIcon = '$iconsPath/google.svg';
  static const String appleIcon = '$iconsPath/apple.svg';
  static const String stravaIcon = '$iconsPath/strava.svg';
  static const String connectWithStravaIcon = '$iconsPath/connect_with_strava.svg';
  static const String garminIcon = '$iconsPath/garmin.svg';
}
