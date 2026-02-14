import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../events/domain/entities/event_entity.dart';
import '../../../events/presentation/providers/event_provider.dart';
import '../../../integrations/apple_watch/apple_watch_integration_settings.dart';
import '../../../integrations/apple_watch/apple_watch_provider.dart';
import '../../../integrations/apple_watch/apple_watch_workout_sync_service.dart';
import '../../../posts/domain/entities/post_entity.dart';
import '../../../posts/presentation/providers/post_provider.dart';
import '../../../notifications/presentation/providers/notification_provider.dart';

/// Home Page Scroll Controller Provider
final homePageScrollControllerProvider = StateNotifierProvider<HomePageScrollControllerNotifier, ScrollController?>((ref) {
  return HomePageScrollControllerNotifier();
});

/// Home Page Scroll Controller Notifier
class HomePageScrollControllerNotifier extends StateNotifier<ScrollController?> {
  HomePageScrollControllerNotifier() : super(null);
  
  void setController(ScrollController? controller) {
    state = controller;
  }
}

/// Home Page
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Türkçe timeago
    timeago.setLocaleMessages('tr', timeago.TrMessages());
    // Feed için postları yükle
    Future.microtask(() {
      ref.read(postsProvider.notifier).loadPosts();
    });

    // Apple Watch Auto Send: uygulama açılışında 7 günlük senkron
    Future.microtask(() async {
      try {
        final s = ref.read(appleWatchIntegrationProvider).settings;
        if (!s.enabled || s.mode != AppleWatchSendMode.autoSend) return;

        // Çok sık senkronu engelle (örn. 6 saatten sık olmasın)
        final last = s.lastSyncAt;
        if (last != null && DateTime.now().difference(last).inHours < 6) return;

        await ref.read(appleWatchWorkoutSyncServiceProvider).syncNext7Days();
        await ref.read(appleWatchIntegrationProvider.notifier).setLastSyncNow();
      } catch (_) {
        // Sessiz: bağlantı/yetki yoksa kullanıcı zaten Bağlantılar ekranından görecek
      }
    });
    // Infinite scroll için scroll listener
    _scrollController.addListener(_onScroll);
    // ScrollController'ı provider'a kaydet
    Future.microtask(() {
      ref.read(homePageScrollControllerProvider.notifier).setController(_scrollController);
    });
  }

  @override
  void deactivate() {
    // Widget ağaçtan çıkmadan önce provider'ı temizle (widget tree build'den sonra)
    Future.microtask(() {
      try {
        if (mounted) {
          ref.read(homePageScrollControllerProvider.notifier).setController(null);
        }
      } catch (e) {
        // Hata durumunda sessizce devam et
      }
    });
    super.deactivate();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      // %80'e ulaştığında daha fazla yükle
      ref.read(postsProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProfileProvider);
    final postsState = ref.watch(postsProvider);
    final thisWeekEvents = ref.watch(thisWeekEventsProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.read(postsProvider.notifier).refresh();
            ref.invalidate(thisWeekEventsProvider);
          },
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Header – kompakt, sayfa ile uyumlu
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Merhaba, ${user?.firstName ?? 'Koşucu'}! 👋',
                              style: AppTypography.titleLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bugün koşmaya hazır mısın?',
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.neutral500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const _NotificationIcon(),
                      const SizedBox(width: 8),
                      UserAvatar(
                        imageUrl: user?.avatarUrl,
                        name: user?.fullName,
                        size: 44,
                        onTap: () => context.goNamed(RouteNames.profile),
                      ),
                    ],
                  ),
                ),
              ),

              // Pinli + Bu Hafta Etkinlikleri - Real Data
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Başlık
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.push_pin,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Etkinlikler',
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.neutral700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => context.goNamed(
                              RouteNames.events,
                              queryParameters: {'tab': 'list'},
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Tümünü Gör',
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Etkinlikler
                    _buildThisWeekEvents(context, thisWeekEvents),
                  ],
                ),
              ),

              // Son Paylaşımlar (duyurular, postlar) - kompakt başlık
              SliverToBoxAdapter(
                child: _buildFeedSectionHeader(context),
              ),

              // Unified Feed - Activities and Posts
              _buildPostsFeed(context, postsState),

              // Bottom Spacing
              const SliverToBoxAdapter(
                child: SizedBox(height: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Feed bölümü için kompakt başlık: daha az alan, marka hissi yok
  Widget _buildFeedSectionHeader(BuildContext context) {
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(
        children: [
          Icon(
            Icons.article_outlined,
            size: 20,
            color: AppColors.neutral500,
          ),
          const SizedBox(width: 8),
          Text(
            'Son Paylaşımlar',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.neutral700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (isAdminOrCoach)
            IconButton(
              onPressed: () => context.pushNamed(RouteNames.createPost),
              icon: const Icon(Icons.add_circle_outline),
              color: AppColors.primary,
              iconSize: 22,
              tooltip: 'Duyuru ekle',
            ),
        ],
      ),
    );
  }

  Widget _buildThisWeekEvents(BuildContext context, AsyncValue<List<EventEntity>> eventsAsync) {
    return eventsAsync.when(
      data: (events) {
        // Datasource'tan zaten sıralı geliyor, gereksiz sıralama yapma
        if (events.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.neutral100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event_available,
                    color: AppColors.neutral400,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bu hafta için etkinlik bulunmuyor',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SizedBox(
          height: 168,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: events.length,
            cacheExtent: 500, // Daha fazla item cache'le
            itemBuilder: (context, index) {
              final event = events[index];
              return RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    width: 260,
                    child: _buildEventCard(context, event),
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => Builder(
        builder: (context) => _buildEventsShimmer(context),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.errorContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Etkinlikler yüklenemedi',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventsShimmer(BuildContext context) {
    return SizedBox(
      height: 168,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 3, // 3 shimmer card göster
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: 260,
              child: _buildEventCardShimmer(context),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEventCardShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (gradient alan)
            Container(
              height: 72,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Badge ve tarih
                  Row(
                    children: [
                      Container(
                        width: 45,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 55,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Başlık
                  Container(
                    width: double.infinity,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 160,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Lokasyon ve saat
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 80,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, EventEntity event) {
    return AppCard(
      padding: EdgeInsets.zero,
      elevation: 2,
      onTap: () => context.goNamed(
        RouteNames.eventDetail,
        pathParameters: {'eventId': event.id},
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _getEventTypeColor(event.eventType),
                  _getEventTypeColor(event.eventType).withValues(alpha: 0.75),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    _getEventTypeIcon(event.eventType),
                    size: 36,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                if (event.isPinned)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.push_pin,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (event.isToday)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'BUGÜN',
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getEventTypeColor(event.eventType).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        event.shortDayOfWeek,
                        style: AppTypography.labelSmall.copyWith(
                          color: _getEventTypeColor(event.eventType),
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    if (event.eventType == EventType.training) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getParticipationTypeColor(event).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _isIndividualParticipation(event) ? 'Bireysel' : 'Ekip',
                          style: AppTypography.labelSmall.copyWith(
                            color: _getParticipationTypeColor(event),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                    if (!_isIndividualParticipation(event)) ...[
                      const SizedBox(width: 6),
                      Text(
                        event.formattedTime,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.neutral500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (event.isUserParticipating)
                      Icon(
                        Icons.check_circle,
                        size: 14,
                        color: AppColors.success,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  event.title,
                  style: AppTypography.titleSmall.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!_isIndividualParticipation(event)) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.people_outline,
                        size: 12,
                        color: AppColors.neutral500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${event.participantCount} katılımcı',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.neutral500,
                          fontSize: 11,
                        ),
                      ),
                      if (event.locationName != null) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: AppColors.neutral500,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.locationName!,
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.neutral500,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getEventTypeIcon(EventType type) {
    switch (type) {
      case EventType.training:
        return Icons.directions_run;
      case EventType.race:
        return Icons.emoji_events;
      case EventType.social:
        return Icons.groups;
      case EventType.workshop:
        return Icons.school;
      case EventType.other:
        return Icons.event;
    }
  }

  Color _getEventTypeColor(EventType type) {
    switch (type) {
      case EventType.training:
        return AppColors.secondary;
      case EventType.race:
        return AppColors.error;
      case EventType.social:
        return AppColors.tertiary;
      case EventType.workshop:
        return AppColors.primary;
      case EventType.other:
        return AppColors.neutral600;
    }
  }

  bool _isIndividualParticipation(EventEntity event) =>
      event.participationType == 'individual';

  /// Bireysel/Ekip rozeti rengi (anasayfa, liste ve detayda aynı)
  Color _getParticipationTypeColor(EventEntity event) =>
      _isIndividualParticipation(event) ? AppColors.primary : AppColors.tertiary;

  /// Ana sayfa feed'i: sadece duyurular/postlar
  Widget _buildPostsFeed(BuildContext context, PostsState postsState) {
    final items = postsState.posts;
    
    final isLoading = postsState.isLoading;
    final hasError = postsState.error != null;
    final isEmpty = items.isEmpty && !isLoading;
    
    if (isLoading && items.isEmpty) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildPostCardShimmer(context),
          ),
          childCount: 3, // 3 shimmer post card göster
        ),
      );
    }
    
    if (hasError && items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ErrorStateWidget(
            title: 'Bir hata oluştu',
            message: postsState.error ?? 'Bilinmeyen hata',
            onRetry: () {
              ref.read(postsProvider.notifier).refresh();
            },
          ),
        ),
      );
    }
    
    if (isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: EmptyStateWidget(
            icon: Icons.directions_run,
            title: 'Henüz içerik yok',
            description: 'İlk koşunu paylaş veya bir post oku!',
          ),
        ),
      );
    }
    
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= items.length) {
            if (isLoading && postsState.hasMore) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildPostCardShimmer(context),
              );
            }
            return null;
          }
          
          final post = items[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildPostCard(context, post),
          );
        },
        childCount: items.length + (isLoading && postsState.hasMore ? 3 : 0), // 3 shimmer card göster
      ),
    );
  }

  // Eski aktivite feed implementasyonundan kalan helper fonksiyonlar kaldırıldı.

  Future<void> _onPostMenuSelected(BuildContext context, String value, PostEntity post) async {
    final messenger = ScaffoldMessenger.of(context);

    switch (value) {
      case 'edit':
        context.pushNamed(
          RouteNames.editPost,
          pathParameters: {'postId': post.id},
        ).then((_) {
          ref.read(postsProvider.notifier).refresh();
        });
        break;
      case 'delete':
        _showDeletePostConfirmation(context, post);
        break;
      case 'pin':
        try {
          final dataSource = ref.read(postDataSourceProvider);
          await dataSource.setPostPinned(post.id, !post.isPinned);
          await ref.read(postsProvider.notifier).refresh();
          messenger.showSnackBar(
            SnackBar(
              content: Text(post.isPinned ? 'Pin kaldırıldı' : 'Post sabitlendi'),
              backgroundColor: AppColors.success,
            ),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text('İşlem başarısız: $e')),
          );
        }
        break;
    }
  }

  void _showDeletePostConfirmation(BuildContext context, PostEntity post) {
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Postu Sil'),
        content: const Text(
          'Bu postu silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final dataSource = ref.read(postDataSourceProvider);
                await dataSource.deletePost(post.id);
                ref.read(postsProvider.notifier).removePost(post.id);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Post silindi'),
                    backgroundColor: AppColors.success,
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Post silinemedi: $e')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCardShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(
            bottom: BorderSide(
              color: AppColors.neutral300.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Kullanıcı adı
                        Container(
                          width: 120,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Zaman
                        Container(
                          width: 80,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Cover Image (opsiyonel - %50 şansla göster)
            if (DateTime.now().millisecond % 2 == 0)
              Container(
                width: double.infinity,
                height: 200,
                color: Colors.grey[300],
              ),
            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 200,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard(BuildContext context, PostEntity post) {
    return InkWell(
      onTap: () => context.pushNamed(
        RouteNames.postDetail,
        pathParameters: {'postId': post.id},
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(
            bottom: BorderSide(
              color: AppColors.neutral300.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserAvatar(
                    size: 48,
                    name: post.userName,
                    imageUrl: post.userAvatarUrl,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                post.userName,
                                style: AppTypography.titleSmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (post.isPinned)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.push_pin,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.article,
                              size: 14,
                              color: AppColors.neutral500,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              timeago.format(post.createdAt, locale: 'tr'),
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.neutral500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (ref.watch(isAdminProvider))
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.more_horiz,
                        size: 20,
                        color: AppColors.neutral500,
                      ),
                      onSelected: (value) => _onPostMenuSelected(context, value, post),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 20),
                              SizedBox(width: 8),
                              Text('Düzenle'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                              SizedBox(width: 8),
                              Text('Sil', style: TextStyle(color: AppColors.error)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'pin',
                          child: Row(
                            children: [
                              Icon(
                                post.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(post.isPinned ? 'Pini kaldır' : 'Pinle'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            
            // Cover Image
            if (post.coverImageUrl != null)
              Image.network(
                post.coverImageUrl!,
                width: double.infinity,
                height: 200,
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            
            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                post.title,
                style: AppTypography.headlineSmall.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationIcon extends ConsumerWidget {
  const _NotificationIcon();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadAsync = ref.watch(unreadNotificationCountProvider);
    final count = unreadAsync.valueOrNull ?? 0;

    return IconButton(
      onPressed: () => context.pushNamed(RouteNames.notifications),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined, size: 24),
          if (count > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count > 99 ? '99+' : count.toString(),
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      tooltip: 'Bildirimler',
    );
  }
}

// Eski birleşik feed yapısından kalan enum/sınıf kaldırıldı.
