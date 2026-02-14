import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/auth/presentation/pages/verify_email_page.dart';
import '../../features/auth/presentation/pages/complete_profile_page.dart';
import '../../features/auth/presentation/pages/onboarding_page.dart';
import '../../features/auth/presentation/pages/reset_password_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/events/presentation/pages/events_page.dart';
import '../../features/events/presentation/pages/event_detail_page.dart';
import '../../features/events/presentation/pages/create_event_page.dart';
import '../../features/events/presentation/pages/event_report_page.dart';
import '../../features/events/presentation/pages/event_report_detail_page.dart';
import '../../features/chat/presentation/pages/chat_page.dart';
import '../../features/chat/presentation/pages/chat_room_page.dart';
import '../../features/chat/presentation/pages/event_chat_room_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/profile/presentation/pages/profile_edit_page.dart';
import '../../features/profile/presentation/pages/ice_card_page.dart';
import '../../features/profile/presentation/pages/settings_page.dart';
import '../../features/profile/presentation/pages/statistics_page.dart';
import '../../features/activity/presentation/pages/activity_detail_page.dart';
import '../../features/activity/presentation/pages/activity_history_page.dart';
import '../../features/activity/presentation/pages/leaderboard_page.dart';
import '../../features/routes/presentation/pages/routes_page.dart';
import '../../features/routes/presentation/pages/route_detail_page.dart' as route_pages;
import '../../features/routes/presentation/pages/create_route_page.dart';
import '../../features/members_groups/presentation/pages/groups_page.dart';
import '../../features/members_groups/presentation/pages/group_detail_page.dart';
import '../../features/members_groups/presentation/pages/create_group_page.dart';
import '../../features/gallery/presentation/pages/event_gallery_page.dart';
import '../../features/marketplace/presentation/pages/marketplace_page.dart';
import '../../features/marketplace/presentation/pages/listing_detail_page.dart';
import '../../features/marketplace/presentation/pages/create_listing_page.dart';
import '../../features/marketplace/presentation/pages/favorites_page.dart';
import '../../features/marketplace/presentation/pages/orders_management_page.dart';
import '../../features/marketplace/presentation/pages/my_orders_page.dart';
import '../../features/tools/presentation/pages/pace_calculator_page.dart';
import '../../features/integrations/presentation/pages/integrations_page.dart';
import '../../features/integrations/presentation/pages/strava_activity_list_page.dart';
import '../../features/auth/presentation/providers/auth_notifier.dart';
import '../../features/notifications/presentation/providers/notification_provider.dart';
import '../../features/posts/presentation/pages/create_post_page.dart';
import '../../features/posts/presentation/pages/post_detail_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';

/// App Router Provider - Auth state'den bağımsız, sadece başlangıçta kontrol eder
final appRouterProvider = Provider<GoRouter>((ref) {
  // NOT: ref.watch KULLANMA! Router yeniden oluşturulmasın
  // Auth kontrolü sadece redirect içinde ref.read ile yapılıyor
  
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    // refreshListenable KALDIRILDI - router otomatik yenilenmesin
    // Yönlendirmeler sayfalardan manuel yapılacak
    redirect: (context, state) {
      // Her navigation'da güncel auth durumunu oku (watch değil read!)
      final container = ProviderScope.containerOf(context);
      final authState = container.read(authNotifierProvider);
      
      final isAuthenticated = authState is AuthAuthenticated;
      final isNeedsPasswordReset = authState is AuthNeedsPasswordReset;
      final isAuthLoading = authState is AuthLoading;
      final isAuthInitial = authState is AuthInitial;
      final isAuthRoute = state.matchedLocation == '/login' ||
                          state.matchedLocation == '/register' ||
                          state.matchedLocation == '/verify-email';
      final isResetPasswordRoute = state.matchedLocation == '/reset-password';
      final isSplash = state.matchedLocation == '/';

      // Splash ekranında ise bekle (splash kendi kontrolünü yapacak)
      if (isSplash) return null;

      // Şifre sıfırlama linkinden gelindiyse sadece /reset-password sayfasına izin ver
      if (isNeedsPasswordReset && !isResetPasswordRoute) {
        return '/reset-password';
      }
      if (isResetPasswordRoute && !isNeedsPasswordReset && isAuthenticated) {
        return '/home';
      }

      // Auth sayfasındaysa (login, register, verify-email) - her zaman izin ver
      if (isAuthRoute) return null;

      // Reset password sayfasındaysa ve needsPasswordReset ise izin ver
      if (isResetPasswordRoute) return null;

      // Auth loading veya initial durumunda ve korumalı sayfaya erişmeye çalışıyorsa
      if ((isAuthLoading || isAuthInitial) && !isAuthRoute) {
        return '/login';
      }

      // Giriş yapmamışsa ve korumalı sayfaya erişmeye çalışıyorsa login'e yönlendir
      if (!isAuthenticated && !isAuthRoute) {
        return '/login';
      }

      return null;
    },
    routes: [
      // Splash
      GoRoute(
        path: '/',
        name: RouteNames.splash,
        builder: (context, state) => const SplashPage(),
      ),
      
      // Auth Routes
      GoRoute(
        path: '/login',
        name: RouteNames.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        name: RouteNames.register,
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/verify-email',
        name: RouteNames.verifyEmail,
        builder: (context, state) {
          final email = state.uri.queryParameters['email'] ?? 
                       (state.extra as Map<String, dynamic>?)?['email'] ?? 
                       '';
          return VerifyEmailPage(email: email);
        },
      ),
      GoRoute(
        path: '/complete-profile',
        name: RouteNames.completeProfile,
        builder: (context, state) => const CompleteProfilePage(),
      ),
      GoRoute(
        path: '/reset-password',
        name: RouteNames.resetPassword,
        builder: (context, state) => const ResetPasswordPage(),
      ),
      GoRoute(
        path: '/onboarding',
        name: RouteNames.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      
      // Main Shell Route with Bottom Navigation
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          // Home / Feed
          GoRoute(
            path: '/home',
            name: RouteNames.home,
            builder: (context, state) => const HomePage(),
            routes: [
              GoRoute(
                path: 'activity/:activityId',
                name: RouteNames.activityDetail,
                builder: (context, state) {
                  final activityId = state.pathParameters['activityId']!;
                  return ActivityDetailPage(activityId: activityId);
                },
              ),
              GoRoute(
                path: 'create-post',
                name: RouteNames.createPost,
                builder: (context, state) => const CreatePostPage(),
              ),
              GoRoute(
                path: 'edit-post/:postId',
                name: RouteNames.editPost,
                builder: (context, state) {
                  final postId = state.pathParameters['postId']!;
                  return CreatePostPage(postId: postId);
                },
              ),
              GoRoute(
                path: 'post/:postId',
                name: RouteNames.postDetail,
                builder: (context, state) {
                  final postId = state.pathParameters['postId']!;
                  return PostDetailPage(postId: postId);
                },
              ),
              GoRoute(
                path: 'leaderboard',
                name: RouteNames.leaderboard,
                builder: (context, state) => const LeaderboardPage(),
              ),
              GoRoute(
                path: 'notifications',
                name: RouteNames.notifications,
                builder: (context, state) => const NotificationsPage(),
              ),
            ],
          ),
          
          // Events
          GoRoute(
            path: '/events',
            name: RouteNames.events,
            builder: (context, state) {
              return EventsPage();
            },
            routes: [
              GoRoute(
                path: 'create',
                name: RouteNames.createEvent,
                builder: (context, state) => const CreateEventPage(),
              ),
              GoRoute(
                path: 'report',
                name: RouteNames.eventReport,
                builder: (context, state) => const EventReportPage(),
              ),
              GoRoute(
                path: 'report/:eventId',
                name: RouteNames.eventReportDetail,
                builder: (context, state) {
                  final eventId = state.pathParameters['eventId']!;
                  return EventReportDetailPage(eventId: eventId);
                },
              ),
              GoRoute(
                path: ':eventId',
                name: RouteNames.eventDetail,
                builder: (context, state) {
                  final eventId = state.pathParameters['eventId']!;
                  return EventDetailPage(eventId: eventId);
                },
                routes: [
                  GoRoute(
                    path: 'edit',
                    name: RouteNames.editEvent,
                    builder: (context, state) {
                      final eventId = state.pathParameters['eventId']!;
                      final scope = state.uri.queryParameters['scope'];
                      return CreateEventPage(
                        eventId: eventId,
                        editRecurrenceScope: scope,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'gallery',
                    name: RouteNames.eventGallery,
                    builder: (context, state) {
                      final eventId = state.pathParameters['eventId']!;
                      return EventGalleryPage(eventId: eventId);
                    },
                  ),
                  GoRoute(
                    path: 'chat',
                    name: RouteNames.eventChat,
                    builder: (context, state) {
                      final eventId = state.pathParameters['eventId']!;
                      return EventChatRoomPage(eventId: eventId);
                    },
                  ),
                  // Route detail için events altındaki nested route kaldırıldı
                  // /routes/:routeId kullanılmalı
                ],
              ),
            ],
          ),
          
          // Marketplace - Shell içinde bottom nav ile
          GoRoute(
            path: '/marketplace',
            name: RouteNames.marketplace,
            builder: (context, state) => const MarketplacePage(),
            routes: [
              GoRoute(
                path: 'create',
                name: RouteNames.listingCreate,
                builder: (context, state) => const CreateListingPage(),
              ),
              GoRoute(
                path: 'edit/:listingId',
                name: RouteNames.listingEdit,
                builder: (context, state) {
                  final listingId = state.pathParameters['listingId']!;
                  return CreateListingPage(listingId: listingId);
                },
              ),
              GoRoute(
                path: 'favorites',
                name: RouteNames.favorites,
                builder: (context, state) => const FavoritesPage(),
              ),
              GoRoute(
                path: 'orders-management',
                name: RouteNames.ordersManagement,
                builder: (context, state) => const OrdersManagementPage(),
              ),
              GoRoute(
                path: 'my-orders',
                name: RouteNames.myOrders,
                builder: (context, state) => const MyOrdersPage(),
              ),
              GoRoute(
                path: ':listingId',
                name: RouteNames.listingDetail,
                builder: (context, state) {
                  final listingId = state.pathParameters['listingId']!;
                  return ListingDetailPage(listingId: listingId);
                },
              ),
            ],
          ),
          
          // Routes (GPX rotaları) - Shell içinde bottom nav ile
          GoRoute(
            path: '/routes',
            name: RouteNames.routes,
            builder: (context, state) => const RoutesPage(),
            routes: [
              GoRoute(
                path: 'create',
                name: RouteNames.routeCreate,
                builder: (context, state) => const CreateRoutePage(),
              ),
              GoRoute(
                path: ':routeId',
                name: RouteNames.routeDetail,
                builder: (context, state) {
                  final routeId = state.pathParameters['routeId']!;
                  return route_pages.RouteDetailPage(routeId: routeId);
                },
                routes: [
                  GoRoute(
                    path: 'edit',
                    name: RouteNames.routeEdit,
                    builder: (context, state) {
                      final routeId = state.pathParameters['routeId']!;
                      return CreateRoutePage(routeId: routeId);
                    },
                  ),
                ],
              ),
            ],
          ),
          
          // Groups (Antrenman Grupları) - Shell içinde bottom nav ile
          GoRoute(
            path: '/groups',
            name: RouteNames.groups,
            builder: (context, state) => const GroupsPage(),
            routes: [
              GoRoute(
                path: 'create',
                name: RouteNames.createGroup,
                builder: (context, state) => const CreateGroupPage(),
              ),
              GoRoute(
                path: ':groupId',
                name: RouteNames.groupDetail,
                builder: (context, state) {
                  final groupId = state.pathParameters['groupId']!;
                  return GroupDetailPage(groupId: groupId);
                },
                routes: [
                  GoRoute(
                    path: 'edit',
                    name: RouteNames.editGroup,
                    builder: (context, state) {
                      final groupId = state.pathParameters['groupId']!;
                      return CreateGroupPage(groupId: groupId);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      
      // Profile (Outside shell - üst menüden erişilebilir)
      GoRoute(
        path: '/profile',
        name: RouteNames.profile,
        builder: (context, state) => const ProfilePage(),
        routes: [
          // Static route'ları önce koy (path parameter'dan önce)
          GoRoute(
            path: 'edit',
            name: RouteNames.profileEdit,
            builder: (context, state) => const ProfileEditPage(),
          ),
          GoRoute(
            path: 'ice-card',
            name: RouteNames.iceCard,
            builder: (context, state) {
              final userId = state.uri.queryParameters['userId'];
              return IceCardPage(userId: userId);
            },
          ),
          GoRoute(
            path: 'settings',
            name: RouteNames.settings,
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: 'integrations',
            name: RouteNames.integrations,
            builder: (context, state) => const IntegrationsPage(),
          ),
          GoRoute(
            path: 'integrations/strava-activities',
            name: RouteNames.stravaActivityList,
            builder: (context, state) => const StravaActivityListPage(),
          ),
          GoRoute(
            path: 'activity-history',
            name: RouteNames.activityHistory,
            builder: (context, state) {
              final userId = state.uri.queryParameters['userId'];
              return ActivityHistoryPage(userId: userId);
            },
          ),
          GoRoute(
            path: 'statistics',
            name: RouteNames.statistics,
            builder: (context, state) {
              final userId = state.uri.queryParameters['userId'];
              return StatisticsPage(userId: userId);
            },
          ),
          // Path parameter route'u en sonda (static route'lardan sonra)
          GoRoute(
            path: ':userId',
            name: RouteNames.userProfile,
            builder: (context, state) {
              final userId = state.pathParameters['userId']!;
              return ProfilePage(userId: userId);
            },
          ),
        ],
      ),
      
      // Chat (Outside shell - artık bottom nav'da yok)
      GoRoute(
        path: '/chat',
        name: RouteNames.chat,
        builder: (context, state) => const ChatPage(),
        routes: [
          GoRoute(
            path: ':roomId',
            name: RouteNames.chatRoom,
            builder: (context, state) {
              final roomId = state.pathParameters['roomId']!;
              return ChatRoomPage(roomId: roomId);
            },
          ),
        ],
      ),
      
      // Tools
      GoRoute(
        path: '/tools/pace-calculator',
        name: RouteNames.paceCalculator,
        builder: (context, state) => const PaceCalculatorPage(),
      ),

      // ── Universal Links / App Links yönlendirmeleri ──
      // rivlus.com/e/:id → /events/:id (etkinlik detay)
      GoRoute(
        path: '/e/:id',
        redirect: (context, state) {
          final id = state.pathParameters['id'];
          return '/events/$id';
        },
      ),
      // rivlus.com/m/:id → /marketplace/:id (ürün detay)
      GoRoute(
        path: '/m/:id',
        redirect: (context, state) {
          final id = state.pathParameters['id'];
          return '/marketplace/$id';
        },
      ),
    ],
    errorBuilder: (context, state) => ErrorPage(error: state.error),
  );
});

/// Main Shell with Bottom Navigation
class MainShell extends ConsumerWidget {
  final Widget child;
  
  const MainShell({super.key, required this.child});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(notificationRealtimeProvider.notifier).start();
    return Scaffold(
      body: child,
      bottomNavigationBar: const MainBottomNavigation(),
    );
  }
}

/// Bottom Navigation Bar - Floating Rounded Design
class MainBottomNavigation extends ConsumerStatefulWidget {
  const MainBottomNavigation({super.key});
  
  @override
  ConsumerState<MainBottomNavigation> createState() => _MainBottomNavigationState();
}

class _MainBottomNavigationState extends ConsumerState<MainBottomNavigation>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _triggerAnimation() {
    _animController.reset();
    _animController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final currentLocation = GoRouterState.of(context).matchedLocation;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    int currentIndex = 0;
    if (currentLocation.startsWith('/events')) {
      currentIndex = 1;
    } else if (currentLocation.startsWith('/marketplace')) {
      currentIndex = 2;
    } else if (currentLocation.startsWith('/groups')) {
      currentIndex = 3;
    } else if (currentLocation.startsWith('/routes')) {
      currentIndex = 4;
    }

    // Index değiştiğinde animasyonu tetikle
    if (_previousIndex != currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerAnimation();
      });
      _previousIndex = currentIndex;
    }

    final navItems = [
      (icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Ana Sayfa'),
      (icon: Icons.event_outlined, selectedIcon: Icons.event_rounded, label: 'Etkinlikler'),
      (icon: Icons.shopping_bag_outlined, selectedIcon: Icons.shopping_bag_rounded, label: 'Market'),
      (icon: Icons.groups_outlined, selectedIcon: Icons.groups_rounded, label: 'Gruplar'),
      (icon: Icons.route_outlined, selectedIcon: Icons.route_rounded, label: 'Rotalar'),
    ];

    final barColor = isDark ? AppColors.surfaceDark : Colors.white;
    final selectedColor = AppColors.primary;
    final unselectedColor = isDark ? AppColors.onSurfaceVariantDark : AppColors.neutral800;
    final selectedBgColor = isDark 
        ? AppColors.primary.withValues(alpha: 0.15) 
        : AppColors.primary.withValues(alpha: 0.08);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(36),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                blurRadius: 24,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
                blurRadius: 8,
                spreadRadius: 0,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(navItems.length, (index) {
                final isSelected = index == currentIndex;
                final item = navItems[index];
                
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      switch (index) {
                        case 0:
                          if (currentLocation == '/home' || currentLocation.startsWith('/home')) {
                            final scrollController = ref.read(homePageScrollControllerProvider);
                            if (scrollController != null && 
                                scrollController.hasClients &&
                                scrollController.position.pixels > 0) {
                              scrollController.animateTo(
                                0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                              return;
                            }
                          }
                          context.goNamed(RouteNames.home);
                          break;
                        case 1:
                          context.goNamed(RouteNames.events);
                          break;
                        case 2:
                          context.goNamed(RouteNames.marketplace);
                          break;
                        case 3:
                          context.goNamed(RouteNames.groups);
                          break;
                        case 4:
                          context.goNamed(RouteNames.routes);
                          break;
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedBuilder(
                      animation: _scaleAnimation,
                      builder: (context, child) {
                        final scale = isSelected ? _scaleAnimation.value : 1.0;
                        return Transform.scale(
                          scale: scale,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            padding: EdgeInsets.symmetric(
                              horizontal: isSelected ? 8 : 4,
                              vertical: isSelected ? 8 : 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected ? selectedBgColor : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  transitionBuilder: (child, animation) {
                                    return ScaleTransition(scale: animation, child: child);
                                  },
                                  child: Icon(
                                    isSelected ? item.selectedIcon : item.icon,
                                    key: ValueKey(isSelected ? 'selected_$index' : 'unselected_$index'),
                                    color: isSelected ? selectedColor : unselectedColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    color: isSelected ? selectedColor : unselectedColor,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                    fontSize: 10,
                                    height: 1.2,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// Error Page
class ErrorPage extends StatelessWidget {
  final Exception? error;
  
  const ErrorPage({super.key, this.error});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Bir hata oluştu',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              error?.toString() ?? 'Sayfa bulunamadı',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('Ana Sayfaya Dön'),
            ),
          ],
        ),
      ),
    );
  }
}

// RouterRefreshNotifier KALDIRILDI
// Router artık otomatik yenilenmiyor, yönlendirmeler sayfalardan manuel yapılıyor
// Bu sayede login/register sırasında splash ekranına gidilmiyor
