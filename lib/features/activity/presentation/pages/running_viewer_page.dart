import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../domain/entities/activity_entity.dart';
import '../providers/activity_provider.dart';

// İzin verilen kullanıcı ID'leri (Ömer, Ahmet, Ayça)
const _allowedUserIds = StravaWatchConstants.allowedUserIds;

// Koşucu kimlik bilgileri
const _ahmetId = StravaWatchConstants.ahmetId;
const _aycaId = StravaWatchConstants.aycaId;
const _omerId = StravaWatchConstants.omerId;

/// Espirili metinler — Ömer'e laf, Ahmet & Ayça'ya övgü
class _RunningViewerCopy {
  _RunningViewerCopy._();

  static String headerTitle(bool isOmer, String? viewerId) {
    if (isOmer) return 'Ömer, utanmadan bak şunlara!';
    if (viewerId == _ahmetId) return 'Efsane koşucu: Sen';
    if (viewerId == _aycaId) return 'Kraliçe Ayça\'nın koşuları';
    return 'Koşu Takip';
  }

  static String headerSubtitle(bool isOmer) {
    if (isOmer) {
      return 'Ahmet ve Ayça sahada; sen bildirime 1 saat geç bakıyorsun. '
          'Şampiyonlar koşuyor, sen izliyorsun — tam senlik.';
    }
    return 'TCR\'nin gerçek motorları burada.';
  }

  static String headerFootnote(bool isOmer) {
    if (!isOmer) return '';
    return 'Ömer: Koşmak için Strava bağlamak yetmez, ayakkabı da lazım. '
        'Ahmet ve Ayça ise her gün ders veriyor.';
  }

  static String pinnedTitle(bool isOmer) =>
      isOmer ? 'Ömer\'e Koşu Dersi' : 'Koşu Takip';

  static String tabLabel(String runnerName, bool isAhmet) {
    if (isAhmet) return 'Ahmet ⭐';
    return 'Ayça 👑';
  }

  static String runnerBannerTitle(String runnerName, bool isAhmet) {
    if (isAhmet) return 'Ahmet Karakaya — TCR\'nin Ferrari\'si';
    return 'Ayça Şen — Pace\'in kraliçesi';
  }

  static String runnerBannerBody(bool isOmer, bool isAhmet) {
    if (isAhmet) {
      return isOmer
          ? 'Her km\'si Ömer\'in hayalindeki antrenman. Sen hâlâ "yarın başlarım" '
              'diyorsan, Ahmet çoktan 14 km\'yi bitirmiş.'
          : 'Tempo, mesafe, disiplin… Hepsi sende. Ömer izlerken sen koşarsın.';
    }
    return isOmer
        ? 'Ayça koşarken Ömer muhtemelen bildirimi erteliyor. '
            'Senin koşuların ise herkesin moral deposu.'
        : 'Güçlü, istikrarlı, ilham verici. Ömer\'e her koşunda ders veriyorsun.';
  }

  static String emptyTitle(String runnerName, bool isOmer) {
    if (isOmer) return '$runnerName dinleniyor, Ömer rahatla';
    return '$runnerName henüz koşmamış';
  }

  static String emptyDescription(String runnerName, bool isOmer) {
    if (isOmer) {
      return '$runnerName koşmayınca sen de üzülme — zaten sen de '
          'koşmuyorsun, aranızda bağ var.';
    }
    return 'Yeni koşular burada görünecek.';
  }

  static String cardQuip(String runnerName, double distanceKm, bool isOmer, int index) {
    if (!isOmer) return '';
    final km = distanceKm.toStringAsFixed(1);
    final roasts = distanceKm >= 10
        ? [
            'Ömer, bu tek koşu senin aylık hedefini utandırıyor.',
            '$km km — Ömer\'in "çok uzun" dediği mesafe, $runnerName için ısınma.',
          ]
        : distanceKm >= 5
            ? [
                'Ömer bu tempoda ancak markete koşar.',
                '$km km: $runnerName koştu, Ömer hâlâ "bakacağım" diyor.',
              ]
            : [
                'Kısa da olsa $runnerName\'ten Ömer\'e ders.',
                'Ömer: "Ben de koşarım" — $runnerName: "Kanıtla."',
              ];
    final praises = [
      'Efsane performans. Ömer izlemekle yetiniyor.',
      'Bu pace\'e Ömer ancak hayalinde yetişir.',
      'TCR\'nin gururu $runnerName, Ömer\'in koltuğu.',
    ];
    return index.isEven ? praises[index % praises.length] : roasts[index % roasts.length];
  }

  static String detailsLabel(bool isOmer) =>
      isOmer ? 'Ömer, utanmadan detaylara bak' : 'Detaylar';
}

/// Strava Watch Bildirimi geldiğinde açılan özel koşu görüntüleme sayfası.
/// Sadece Ömer, Ahmet ve Ayça erişebilir.
/// Ömer, Ahmet ve Ayça'nın koşularını sekmeli olarak görür.
class RunningViewerPage extends ConsumerStatefulWidget {
  /// Bildirimden gelen aktivite ID'si (viewed_at güncelleme için)
  final String? notificationActivityId;

  const RunningViewerPage({
    super.key,
    this.notificationActivityId,
  });

  @override
  ConsumerState<RunningViewerPage> createState() => _RunningViewerPageState();
}

class _RunningViewerPageState extends ConsumerState<RunningViewerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _markedAsViewed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Bildirimden geldiyse viewed_at güncelle
    if (widget.notificationActivityId != null && !_markedAsViewed) {
      _markActivityAsViewed();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _markActivityAsViewed() async {
    if (_markedAsViewed) return;
    _markedAsViewed = true;

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;

      await Supabase.instance.client
          .from('strava_watch_notifications')
          .update({'viewed_at': DateTime.now().toIso8601String()})
          .eq('activity_id', widget.notificationActivityId!)
          .eq('watcher_user_id', currentUserId)
          .isFilter('viewed_at', null);
    } catch (e) {
      debugPrint('[RunningViewer] viewed_at güncelleme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    // Erişim kontrolü: sadece 3 kişi
    if (currentUserId == null || !_allowedUserIds.contains(currentUserId)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Erişim Yok')),
        body: const Center(
          child: Text('Bu sayfaya erişim yetkiniz bulunmuyor.'),
        ),
      );
    }

    final isOmer = currentUserId == _omerId;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildSliverHeader(context, currentUserId, isOmer),
        ],
        body: Column(
          children: [
            _buildTabBar(context, isOmer),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _RunnerActivitiesTab(
                    userId: _aycaId,
                    runnerName: 'Ayça Şen',
                    isAhmet: false,
                    isOmerViewer: isOmer,
                  ),
                  _RunnerActivitiesTab(
                    userId: _ahmetId,
                    runnerName: 'Ahmet Karakaya',
                    isAhmet: true,
                    isOmerViewer: isOmer,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildSliverHeader(
    BuildContext context,
    String currentUserId,
    bool isOmer,
  ) {
    final footnote = _RunningViewerCopy.headerFootnote(isOmer);

    return SliverAppBar(
      expandedHeight: footnote.isNotEmpty ? 220 : 190,
      floating: false,
      pinned: true,
      backgroundColor: AppColors.primary,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryDark, AppColors.primaryLight],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isOmer ? '😤' : '🏆',
                        style: const TextStyle(fontSize: 28),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _RunningViewerCopy.headerTitle(isOmer, currentUserId),
                          style: AppTypography.headlineSmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _RunningViewerCopy.headerSubtitle(isOmer),
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  if (footnote.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.amber.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        footnote,
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.amber.shade100,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      title: Text(
        _RunningViewerCopy.pinnedTitle(isOmer),
        style: AppTypography.titleLarge.copyWith(color: Colors.white),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => context.pop(),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context, bool isOmer) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.neutral500,
        indicatorColor: AppColors.secondary,
        indicatorWeight: 3,
        tabs: [
          Tab(
            icon: const Text('🏃‍♀️', style: TextStyle(fontSize: 18)),
            text: _RunningViewerCopy.tabLabel('Ayça Şen', false),
          ),
          Tab(
            icon: const Text('🏃‍♂️', style: TextStyle(fontSize: 18)),
            text: _RunningViewerCopy.tabLabel('Ahmet Karakaya', true),
          ),
        ],
      ),
    );
  }
}

/// Sekme üstü övgü / Ömer'e laf banner'ı
class _RunnerPraiseBanner extends StatelessWidget {
  final String runnerName;
  final bool isAhmet;
  final bool isOmerViewer;

  const _RunnerPraiseBanner({
    required this.runnerName,
    required this.isAhmet,
    required this.isOmerViewer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isAhmet
              ? [
                  AppColors.secondary.withOpacity(0.15),
                  AppColors.primary.withOpacity(0.08),
                ]
              : [
                  Colors.purple.withOpacity(0.12),
                  AppColors.tertiary.withOpacity(0.1),
                ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isAhmet ? AppColors.secondary : Colors.purple).withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(isAhmet ? '⭐' : '👑', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _RunningViewerCopy.runnerBannerTitle(runnerName, isAhmet),
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _RunningViewerCopy.runnerBannerBody(isOmerViewer, isAhmet),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.neutral500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tek bir koşucunun aktivite listesi sekmesi
class _RunnerActivitiesTab extends ConsumerStatefulWidget {
  final String userId;
  final String runnerName;
  final bool isAhmet;
  final bool isOmerViewer;

  const _RunnerActivitiesTab({
    required this.userId,
    required this.runnerName,
    required this.isAhmet,
    required this.isOmerViewer,
  });

  @override
  ConsumerState<_RunnerActivitiesTab> createState() => _RunnerActivitiesTabState();
}

class _RunnerActivitiesTabState extends ConsumerState<_RunnerActivitiesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      Future.microtask(() {
        if (mounted) {
          ref
              .read(userActivitiesNotifierProvider(widget.userId).notifier)
              .loadActivities();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(userActivitiesNotifierProvider(widget.userId));

    if (state.isLoading && state.activities.isEmpty) {
      return const Center(child: LoadingWidget());
    }

    if (state.error != null && state.activities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: 12),
            Text('Bir hata oluştu', style: AppTypography.titleMedium),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref
                  .read(userActivitiesNotifierProvider(widget.userId).notifier)
                  .refresh(),
              child: const Text('Yeniden Dene'),
            ),
          ],
        ),
      );
    }

    // Sadece running aktiviteleri filtrele
    final runActivities = state.activities
        .where((a) => a.activityType == ActivityType.running)
        .toList();

    final showPraiseBanner = !widget.isAhmet;

    if (runActivities.isEmpty) {
      return ListView(
        children: [
          if (showPraiseBanner)
            _RunnerPraiseBanner(
              runnerName: widget.runnerName,
              isAhmet: widget.isAhmet,
              isOmerViewer: widget.isOmerViewer,
            ),
          EmptyStateWidget(
            icon: Icons.directions_run,
            title: _RunningViewerCopy.emptyTitle(
              widget.runnerName,
              widget.isOmerViewer,
            ),
            description: _RunningViewerCopy.emptyDescription(
              widget.runnerName,
              widget.isOmerViewer,
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref
          .read(userActivitiesNotifierProvider(widget.userId).notifier)
          .refresh(),
      child: ListView.builder(
        padding: EdgeInsets.only(
          top: showPraiseBanner ? 0 : 12,
          bottom: 16,
        ),
        itemCount: runActivities.length +
            (state.hasMore ? 1 : 0) +
            (showPraiseBanner ? 1 : 0),
        itemBuilder: (context, index) {
          if (showPraiseBanner && index == 0) {
            return _RunnerPraiseBanner(
              runnerName: widget.runnerName,
              isAhmet: widget.isAhmet,
              isOmerViewer: widget.isOmerViewer,
            );
          }

          final activityIndex = showPraiseBanner ? index - 1 : index;

          if (activityIndex >= runActivities.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _RunActivityCard(
              activity: runActivities[activityIndex],
              runnerName: widget.runnerName,
              isOmerViewer: widget.isOmerViewer,
              listIndex: activityIndex,
            ),
          );
        },
      ),
    );
  }
}

/// Tek bir koşu aktivitesi kartı
class _RunActivityCard extends StatelessWidget {
  final ActivityEntity activity;
  final String runnerName;
  final bool isOmerViewer;
  final int listIndex;

  const _RunActivityCard({
    required this.activity,
    required this.runnerName,
    required this.isOmerViewer,
    required this.listIndex,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMMM y, HH:mm', 'tr_TR').format(activity.startTime);
    final quip = _RunningViewerCopy.cardQuip(
      runnerName,
      activity.distanceKm,
      isOmerViewer,
      listIndex,
    );

    return AppCard(
      onTap: () => context.pushNamed(
        RouteNames.activityDetail,
        pathParameters: {'activityId': activity.id},
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık ve tarih
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.directions_run,
                  color: AppColors.secondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title ?? 'Koşu',
                      style: AppTypography.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                  ],
                ),
              ),
              if (activity.source == ActivitySource.strava)
                _StravaSourceBadge(),
            ],
          ),
          const SizedBox(height: 14),

          // Metrik kartlar: Mesafe, Süre, Pace
          Row(
            children: [
              _MetricChip(
                icon: Icons.straighten,
                label: 'Mesafe',
                value: activity.distanceMeters != null
                    ? '${activity.distanceKm.toStringAsFixed(2)} km'
                    : '--',
                color: AppColors.secondary,
              ),
              const SizedBox(width: 8),
              _MetricChip(
                icon: Icons.timer_outlined,
                label: 'Süre',
                value: activity.formattedDuration,
                color: AppColors.tertiary,
              ),
              const SizedBox(width: 8),
              _MetricChip(
                icon: Icons.speed,
                label: 'Pace',
                value: activity.averagePaceSeconds != null
                    ? '${activity.formattedPace} /km'
                    : '--',
                color: AppColors.primary,
              ),
            ],
          ),

          // Kalp hızı ve kadans varsa göster
          if (activity.averageHeartRate != null || activity.averageCadence != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (activity.averageHeartRate != null) ...[
                  _MetricChip(
                    icon: Icons.favorite_outline,
                    label: 'Kalp Hızı',
                    value: '${activity.averageHeartRate} bpm',
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                ],
                if (activity.maxHeartRate != null)
                  _MetricChip(
                    icon: Icons.favorite,
                    label: 'Max KH',
                    value: '${activity.maxHeartRate} bpm',
                    color: Colors.red.shade700,
                  ),
                if (activity.averageCadence != null) ...[
                  const SizedBox(width: 8),
                  _MetricChip(
                    icon: Icons.swap_vert,
                    label: 'Kadans',
                    value: '${activity.averageCadence} spm',
                    color: Colors.deepPurple,
                  ),
                ],
              ],
            ),
          ],

          // Yükseklik farkı ve kalori
          if (activity.elevationGain != null || activity.caloriesBurned != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (activity.elevationGain != null && activity.elevationGain! > 0)
                  _MetricChip(
                    icon: Icons.terrain,
                    label: 'İrtifa',
                    value: '${activity.elevationGain!.toStringAsFixed(0)} m',
                    color: Colors.brown,
                  ),
                if (activity.caloriesBurned != null) ...[
                  const SizedBox(width: 8),
                  _MetricChip(
                    icon: Icons.local_fire_department_outlined,
                    label: 'Kalori',
                    value: '${activity.caloriesBurned} kcal',
                    color: Colors.orange,
                  ),
                ],
              ],
            ),
          ],

          if (quip.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                quip,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.primaryDark,
                  fontStyle: FontStyle.italic,
                  height: 1.3,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _RunningViewerCopy.detailsLabel(isOmerViewer),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18, color: AppColors.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 3),
                Text(
                  label,
                  style: AppTypography.labelSmall.copyWith(
                    color: color,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _StravaSourceBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFC4C02).withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFC4C02).withOpacity(0.4)),
      ),
      child: const Text(
        'Strava',
        style: TextStyle(
          color: Color(0xFFFC4C02),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
