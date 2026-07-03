import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../domain/entities/event_entity.dart';
import '../providers/event_provider.dart';
import '../widgets/admin_monthly_program_entry_card.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// Events Page
class EventsPage extends ConsumerStatefulWidget {
  const EventsPage({super.key, this.initialWorkoutView = false});

  /// Bildirimle açıldığında doğrudan antrenman görünümünü aç.
  final bool initialWorkoutView;

  @override
  ConsumerState<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends ConsumerState<EventsPage> {
  DateTime? _selectedDay;
  final ScrollController _scrollController = ScrollController();
  String _currentMonthTitle = '';
  bool _hasScrolledToCurrentDate = false;
  bool _initialScrollScheduled = false;
  DateTime? _topVisibleDate;
  bool _isInitialLoad = true;
  bool _skipNextScrollUpdate = false;
  // Pin durumlarını local state'te tut (optimistic update için)
  final Map<String, ({bool isPinned, DateTime? pinnedAt})> _pinnedStates = {};
  
  // Cache'lenmiş event listeleri (performans için)
  List<EventEntity>? _cachedSortedEvents;
  Map<DateTime, List<EventEntity>>? _cachedEventsByDate;
  String? _cachedEventsHash; // Events değişti mi kontrol etmek için
  
  // Scroll throttle için
  DateTime? _lastScrollUpdate;
  static const _scrollThrottleMs = 100; // 100ms throttle

  /// Etkinlikler ↔ Antrenmanlar görünümü
  /// - Admin'de: "Antrenmanlar" = aylık plan görünümü
  /// - Diğer kullanıcılarda: "Antrenmanlar" = sadece antrenman etkinlikleri filtreli liste
  bool _workoutView = false;

  @override
  void initState() {
    super.initState();
    _workoutView = widget.initialWorkoutView;
    final now = DateTime.now();
    _selectedDay = now; // İlk açılışta bugünün tarihi
    _currentMonthTitle = _getMonthTitle(now);
    final todayMonday = _getFirstMonday(now);
    _topVisibleDate =
        todayMonday; // İlk yüklemede bugünün haftasının Pazartesi'si
  }

  void _scrollToCurrentDate() {
    if (!_scrollController.hasClients || !mounted) return;

    // ScrollPosition henüz layout tamamlanmadan minScrollExtent null olabilir; jumpTo atılırsa hata verir.
    final position = _scrollController.position;
    double minExtent;
    double maxExtent;
    try {
      minExtent = position.minScrollExtent;
      maxExtent = position.maxScrollExtent;
    } catch (_) {
      // Position hazır değil, bir sonraki frame'de tekrar dene
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasScrolledToCurrentDate) _scrollToCurrentDate();
      });
      return;
    }

    final now = DateTime.now();
    final startDate = DateTime(2025, 7, 1);
    final firstMonday = _getFirstMonday(startDate);

    // Bugünün bulunduğu haftanın Pazartesi'sini bul
    final todayMonday = _getFirstMonday(now);

    // Kaç hafta geçmiş?
    final weeksPassed = (todayMonday.difference(firstMonday).inDays / 7)
        .floor();

    // Haftalık takvim yüksekliği
    final screenWidth = MediaQuery.of(context).size.width;
    final cellWidth = (screenWidth - 16) / 7;
    final cellHeight = cellWidth;
    final weekHeight = cellHeight + 8;

    // Scroll pozisyonunu ayarla (bugünün haftasını 1. satıra getir)
    final scrollPosition = weeksPassed * weekHeight;
    final clampedScroll = scrollPosition.clamp(minExtent, maxExtent);

    // İlk yüklemede seçili tarihi bugün olarak tut (scroll sırasında değişmesin)
    final todayDate = DateTime(now.year, now.month, now.day);

    // İlk yüklemede animasyon yapmadan direkt konumlan (görünür animasyon olmasın)
    if (_isInitialLoad) {
      // Scroll listener'ı geçici olarak kaldır (jumpTo sırasında tetiklenmesin)
      _scrollController.removeListener(_onScroll);

      // Scroll pozisyonunu ayarla (geçerli aralık içinde)
      _scrollController.jumpTo(clampedScroll);

      // Seçili tarihi bugün olarak ayarla ve ay başlığını güncelle
      final currentMonthDate = DateTime(todayDate.year, todayDate.month, 1);
      setState(() {
        _selectedDay = todayDate; // Bugün seçili kalacak
        _topVisibleDate = todayMonday;
        _currentMonthTitle = _getMonthTitle(currentMonthDate);
        _hasScrolledToCurrentDate = true;
        _isInitialLoad = false;
      });

      // Listener'ı tekrar ekle (artık scroll yapıldığında çalışacak)
      // Kısa bir gecikme ile ekle ki jumpTo tamamlanmış olsun
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _scrollController.addListener(_onScroll);
          // İlk birkaç scroll'u atla (jumpTo sonrası tetiklenen scroll'ları)
          _skipNextScrollUpdate = true;
          // Bir kez daha seçili tarihi bugün olarak ayarla (güvence için)
          setState(() {
            _selectedDay = todayDate;
          });
        }
      });
    } else {
      // Sonraki scroll'lar için animasyonlu
      _scrollController.animateTo(
        clampedScroll,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

      // Scroll sonrası başlığı güncelle
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && _scrollController.hasClients) {
          _onScroll();
          _hasScrolledToCurrentDate = true;
        }
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !mounted) return;

    // İlk yükleme sırasında veya skip flag'i aktifse seçili tarihi değiştirme
    if (_isInitialLoad || _skipNextScrollUpdate) {
      _skipNextScrollUpdate = false; // Flag'i sıfırla
      return;
    }

    // Throttle: Çok sık çağrılmasını önle
    final scrollNow = DateTime.now();
    if (_lastScrollUpdate != null) {
      final timeSinceLastUpdate = scrollNow.difference(_lastScrollUpdate!);
      if (timeSinceLastUpdate.inMilliseconds < _scrollThrottleMs) {
        return; // Çok yakın zamanda güncellendi, atla
      }
    }
    _lastScrollUpdate = scrollNow;

    final scrollOffset = _scrollController.offset;
    final startDate = DateTime(2025, 7, 1);
    final firstMonday = _getFirstMonday(startDate);

    // Haftalık takvim yüksekliği (MediaQuery'yi cache'le)
    final screenWidth = MediaQuery.maybeOf(context)?.size.width ?? 
                        MediaQuery.of(context).size.width;
    final cellWidth = (screenWidth - 16) / 7;
    final cellHeight = cellWidth;
    final weekHeight = cellHeight + 8; // hücre + event noktaları için boşluk

    // Görünür alanın en üstündeki (1. satır, 1. sütun) günü bul
    // scrollOffset direkt olarak görünür alanın en üstünü gösterir
    final weekIndex = (scrollOffset / weekHeight).floor();
    final weekStart = firstMonday.add(Duration(days: weekIndex * 7));

    // 1. satır 1. sütun = Pazartesi (weekStart zaten Pazartesi)
    final topLeftDate = weekStart;

    // Bugünün bulunduğu haftanın Pazartesi'sini bul
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final todayMonday = _getFirstMonday(now);

    // Bugünün haftasındaysak bugünü seç, değilse 1. satır 1. sütunu seç
    DateTime dateToSelect;
    if (isSameDay(weekStart, todayMonday)) {
      // Bugünün haftasındayız, bugünü seç
      dateToSelect = todayDate;
    } else {
      // Bugünün haftasında değiliz, 1. satır 1. sütunu seç
      dateToSelect = topLeftDate;
    }

    // Scroll sırasında seçili tarihi güncelle
    if (_selectedDay == null || !isSameDay(_selectedDay, dateToSelect)) {
      setState(() {
        _selectedDay = dateToSelect;
        _topVisibleDate = topLeftDate;
      });
    } else if (_topVisibleDate != topLeftDate) {
      setState(() {
        _topVisibleDate = topLeftDate;
      });
    }

    // Seçili tarihin hangi ay olduğunu bul
    final selectedDate = _selectedDay ?? dateToSelect;
    final currentMonthDate = DateTime(selectedDate.year, selectedDate.month, 1);
    final newMonthTitle = _getMonthTitle(currentMonthDate);

    if (_currentMonthTitle != newMonthTitle) {
      setState(() {
        _currentMonthTitle = newMonthTitle;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final showWorkoutView = _workoutView;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 112,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(showWorkoutView ? Icons.event : Icons.fitness_center),
              tooltip: showWorkoutView
                  ? 'Etkinlik görünümüne dön'
                  : (isAdmin
                      ? 'Aylık antrenman görünümü'
                      : 'Antrenman görünümü'),
              onPressed: () {
                setState(() {
                  _workoutView = !_workoutView;
                  // Görünüm değişince cache'i temizle (filtreleme/hash değişiyor)
                  _cachedSortedEvents = null;
                  _cachedEventsByDate = null;
                  _cachedEventsHash = null;
                });
              },
            ),
            IconButton(
              icon: Icon(Icons.calendar_today),
              onPressed: () {
                _hasScrolledToCurrentDate = false;
                _scrollToCurrentDate();
              },
              tooltip: 'Bugüne git',
            ),
          ],
        ),
        title: Text(showWorkoutView ? 'Antrenmanlar' : 'Etkinlikler'),
        actions: [
          IconButton(
            icon: Icon(Icons.emoji_events_outlined),
            tooltip: 'TCR Yarışları',
            onPressed: () => context.pushNamed(RouteNames.clubRaces),
          ),
          if (isAdmin)
            PopupMenuButton<String>(
              icon: Icon(Icons.add),
              onSelected: (value) {
                if (value == 'create') {
                  context.pushNamed(RouteNames.createEvent);
                  return;
                }
                if (value == 'weekly_editor') {
                  context.pushNamed(RouteNames.adminWeeklyProgramEditor);
                  return;
                }
                if (value == 'monthly_upload') {
                  context.pushNamed(RouteNames.adminMonthlyProgramUpload);
                  return;
                }
                if (value == 'recurring') {
                  context.pushNamed(RouteNames.recurringEvents);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: 'create',
                  child: Text('Etkinlik Oluştur'),
                ),
                PopupMenuItem<String>(
                  value: 'weekly_editor',
                  child: Text('Haftalık Program'),
                ),
                PopupMenuItem<String>(
                  value: 'recurring',
                  child: Text('Tekrar Eden Etkinlikler'),
                ),
                PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'monthly_upload',
                  child: Text('Excel ile yükle (gelişmiş)'),
                ),
              ],
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Web'de body yüksekliği sınırlı olmayabiliyor; açıkça sınır veriyoruz ki
          // takvim + etkinlik listesi Column içinde Expanded düzgün paylaşsın.
          final maxHeight = kIsWeb
              ? (MediaQuery.sizeOf(context).height -
                  (MediaQuery.paddingOf(context).top + kToolbarHeight))
              : constraints.maxHeight;
          return SizedBox(
            height: maxHeight,
            child: Column(
              children: [
                // Ay başlığı
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _currentMonthTitle,
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                // Takvim içeriği
                Expanded(child: _buildCalendarView()),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalendarView() {
    final showWorkoutView = _workoutView;
    if (showWorkoutView) {
      return _buildUserWorkoutCalendarView();
    }

    final isAdmin = ref.watch(isAdminProvider);
    final allEventsAsync = ref.watch(allEventsProvider);

    return allEventsAsync.when(
      data: (events) {
        final visibleEvents = showWorkoutView
            ? events.where((e) => e.eventType == EventType.training).toList()
            : events;

        // Events hash'i oluştur (cache kontrolü için)
        final eventsHash =
            '${showWorkoutView ? 'workouts' : 'events'}_${visibleEvents.length}_${visibleEvents.map((e) => '${e.id}_${e.isPinned}_${e.pinnedAt}').join('_')}';
        
        // Cache kontrolü: events veya pinned states değişmediyse cache'i kullan
        if (_cachedEventsHash == eventsHash && 
            _cachedSortedEvents != null && 
            _cachedEventsByDate != null) {
          // Cache'den kullan
        } else {
          // Veriler yüklendikten sonra mevcut tarihe scroll et (sadece ilk yüklemede, tek noktadan)
          // Eventleri tarihe göre hash map'e çevir (Hızlı erişim için)
          // Pinlenen etkinlikleri en başta göster
          // Local state'teki pin durumlarını uygula (optimistic update)
          final eventsWithLocalState = visibleEvents.map((event) {
            if (_pinnedStates.containsKey(event.id)) {
              final pinnedState = _pinnedStates[event.id]!;
              return EventEntity(
                id: event.id,
                title: event.title,
                description: event.description,
                eventType: event.eventType,
                status: event.status,
                startTime: event.startTime,
                endTime: event.endTime,
                locationName: event.locationName,
                locationAddress: event.locationAddress,
                locationLat: event.locationLat,
                locationLng: event.locationLng,
                routeId: event.routeId,
                trainingGroupId: event.trainingGroupId,
                trainingTypeId: event.trainingTypeId,
                trainingTypeName: event.trainingTypeName,
                trainingTypeDescription: event.trainingTypeDescription,
                trainingTypeColor: event.trainingTypeColor,
                weatherNote: event.weatherNote,
                coachNotes: event.coachNotes,
                bannerImageUrl: event.bannerImageUrl,
                createdBy: event.createdBy,
                createdAt: event.createdAt,
                participantCount: event.participantCount,
                isUserParticipating: event.isUserParticipating,
                laneConfig: event.laneConfig,
                isPinned: pinnedState.isPinned,
                pinnedAt: pinnedState.pinnedAt,
              );
            }
            return event;
          }).toList();

          final sortedEvents = List<EventEntity>.from(eventsWithLocalState);
          sortedEvents.sort((a, b) {
            if (a.isPinned && !b.isPinned) return -1;
            if (!a.isPinned && b.isPinned) return 1;
            if (a.isPinned && b.isPinned) {
              if (a.pinnedAt != null && b.pinnedAt != null) {
                return b.pinnedAt!.compareTo(a.pinnedAt!);
              }
              if (a.pinnedAt != null) return -1;
              if (b.pinnedAt != null) return 1;
            }
            return a.startTime.compareTo(b.startTime);
          });

          final eventsByDate = <DateTime, List<EventEntity>>{};
          for (final event in sortedEvents) {
            final date = DateTime(
              event.startTime.year,
              event.startTime.month,
              event.startTime.day,
            );
            eventsByDate.putIfAbsent(date, () => []).add(event);
          }
          
          // Cache'e kaydet
          _cachedSortedEvents = sortedEvents;
          _cachedEventsByDate = eventsByDate;
          _cachedEventsHash = eventsHash;
        }
        
        final eventsByDate = _cachedEventsByDate!;

        final startDate = DateTime(2025, 7, 1);
        final endDate = DateTime(2030, 12, 31);
        final firstMonday = _getFirstMonday(startDate);
        final lastMonday = _getLastMonday(endDate);
        final totalWeeks =
            ((lastMonday.difference(firstMonday).inDays) / 7).ceil() + 1;

        // İlk yüklemede mevcut tarihe scroll et (sadece bir kez planla; ListView yerleşene kadar geciktir)
        if (!_hasScrolledToCurrentDate && !_initialScrollScheduled) {
          _initialScrollScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted &&
                  !_hasScrolledToCurrentDate &&
                  _scrollController.hasClients) {
                _scrollToCurrentDate();
              }
            });
          });
        }

        return Column(
          children: [
            // Haftanın günleri başlığı
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']
                    .map(
                      (day) => Expanded(
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

            // 3 haftalık takvim görünümü (smooth scroll)
            SizedBox(
              height: _calculateThreeWeekHeight(),
              child: ClipRect(
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          // Her item 1 hafta gösterir
                          final startWeek = firstMonday.add(
                            Duration(days: index * 7),
                          );
                          return RepaintBoundary(
                            child: _buildWeekCalendar(
                              startWeek,
                              eventsByDate: eventsByDate,
                            ),
                          );
                        },
                        childCount: totalWeeks,
                        addAutomaticKeepAlives: false, // Performans için
                        addRepaintBoundaries: false, // Manuel ekledik
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Alt kısım: Etkinlik listesi
            Expanded(
              child:
                  _buildUpcomingEventsList(eventsByDate, isAdmin, showWorkoutView),
            ),
          ],
        );
      },
      loading: () => const Center(child: LoadingWidget()),
      error: (error, _) => Center(
        child: ErrorStateWidget(
          title: 'Etkinlikler yüklenemedi',
          message: error.toString(),
          onRetry: () => ref.invalidate(allEventsProvider),
        ),
      ),
    );
  }

  /// Kullanıcı (admin dahil): kişisel aylık plan satırları + takvim (günlerde plan noktası)
  Widget _buildUserWorkoutCalendarView() {
    final monthAnchor = DateTime(
      (_selectedDay ?? DateTime.now()).year,
      (_selectedDay ?? DateTime.now()).month,
      1,
    );
    final rowsAsync = ref.watch(userMonthlyProgramsForWindowProvider(monthAnchor));

    // Scroll view hep ekranda kalsın; veri yüklenirken widget sökülüp takvim kaymasın.
    final rows = rowsAsync.valueOrNull ?? const [];

    final byDate = <DateTime, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final pd = r['plan_date'] as String?;
      if (pd == null) continue;
      final d = DateTime.tryParse(pd);
      if (d == null) continue;
      final key = DateTime(d.year, d.month, d.day);
      byDate.putIfAbsent(key, () => []).add(r);
    }
    final daysWithItems = byDate.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => DateTime(e.key.year, e.key.month, e.key.day))
        .toSet();

    final startDate = DateTime(2025, 7, 1);
    final endDate = DateTime(2030, 12, 31);
    final firstMonday = _getFirstMonday(startDate);
    final lastMonday = _getLastMonday(endDate);
    final totalWeeks =
        ((lastMonday.difference(firstMonday).inDays) / 7).ceil() + 1;

    if (!_hasScrolledToCurrentDate && !_initialScrollScheduled) {
      _initialScrollScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && !_hasScrolledToCurrentDate && _scrollController.hasClients) {
            _scrollToCurrentDate();
          }
        });
      });
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']
                .map(
                  (day) => Expanded(
                    child: Text(
                      day,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        SizedBox(
          height: _calculateThreeWeekHeight(),
          child: ClipRect(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final startWeek =
                          firstMonday.add(Duration(days: index * 7));
                      return RepaintBoundary(
                        child: _buildWeekCalendar(
                          startWeek,
                          daysWithSimpleDots: daysWithItems,
                        ),
                      );
                    },
                    childCount: totalWeeks,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: rowsAsync.when(
            data: (rows) => _buildUserMonthlyWorkoutList(rows),
            loading: () => const Center(child: LoadingWidget()),
            error: (e, _) => Center(
              child: ErrorStateWidget(
                title: 'Antrenmanlar yüklenemedi',
                message: e.toString(),
                onRetry: () => ref.invalidate(
                  userMonthlyProgramsForWindowProvider(monthAnchor),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserMonthlyWorkoutList(List<Map<String, dynamic>> rows) {
    if (_selectedDay == null || _topVisibleDate == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Yükleniyor...'),
        ),
      );
    }

    final startDate = _selectedDay!;
    final startKey = DateTime(startDate.year, startDate.month, startDate.day);

    final byDate = <DateTime, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final pd = r['plan_date'] as String?;
      final d = pd == null ? null : DateTime.tryParse(pd);
      if (d == null) continue;
      final k = DateTime(d.year, d.month, d.day);
      if (!k.isBefore(startKey)) {
        byDate.putIfAbsent(k, () => []).add(r);
      }
    }

    final eventDays = byDate.keys.toList()..sort();

    if (eventDays.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.fitness_center,
                size: 48,
                color: ThemeBrightnessHolder.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Bu günden itibaren antrenman kaydı yok',
                style: AppTypography.bodyMedium.copyWith(
                  color: ThemeBrightnessHolder.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: eventDays.length,
      cacheExtent: 500,
      itemBuilder: (context, index) {
        final date = eventDays[index];
        final dayRows = byDate[date]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 8, top: index == 0 ? 0 : 16),
              child: Text(
                '${date.day} ${_getMonthName(date)} ${_getDayName(date)} ${date.year}',
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ThemeBrightnessHolder.onSurface,
                ),
              ),
            ),
            ...dayRows.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AdminMonthlyProgramEntryCard(
                  row: r,
                  enableLanePicker: true,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Ay başlığını Türkçe olarak büyük harflerle döndürür (Örn: "OCAK 2024")
  String _getMonthTitle(DateTime date) {
    const monthNames = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    return '${monthNames[date.month - 1].toUpperCase()} ${date.year}';
  }

  // İki tarihin aynı gün olup olmadığını kontrol eder
  bool isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // Verilen tarihten önceki Pazartesi'yi bulur
  DateTime _getFirstMonday(DateTime date) {
    final weekday = date.weekday; // 1 = Pazartesi, 7 = Pazar
    final daysToMonday = (weekday == 1) ? 0 : (weekday - 1);
    return DateTime(date.year, date.month, date.day - daysToMonday);
  }

  // Verilen tarihten sonraki Pazartesi'yi bulur
  DateTime _getLastMonday(DateTime date) {
    final weekday = date.weekday;
    final daysToMonday = (weekday == 1) ? 0 : (8 - weekday);
    return DateTime(date.year, date.month, date.day + daysToMonday);
  }

  // 3 haftalık takvim yüksekliğini hesaplar.
  // Web'de geniş ekranda hücreler çok büyük olmasın ve etkinlik listesine yer kalsın diye üst sınır uygulanır.
  double _calculateThreeWeekHeight() {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final cellWidth = (screenWidth - 16) / 7;
    final cellHeight = cellWidth;
    final weekHeight = cellHeight + 8; // hücre + event noktaları için boşluk
    final threeWeeks = weekHeight * 3;
    if (kIsWeb) {
      // Web: takvim daha az yer kaplasın; en fazla ekranın %28'i veya 260px
      final maxCalendarHeight = (screenHeight * 0.28).clamp(200.0, 260.0);
      return threeWeeks.clamp(0.0, maxCalendarHeight);
    }
    return threeWeeks;
  }

  // 1 haftalık takvim widget'ı oluşturur
  Widget _buildWeekCalendar(
    DateTime startWeek, {
    Map<DateTime, List<EventEntity>>? eventsByDate,
    Set<DateTime>? daysWithSimpleDots,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    // MediaQuery'yi optimize et (mümkünse cache'lenmiş değeri kullan)
    final screenWidth = MediaQuery.maybeOf(context)?.size.width ?? 
                        MediaQuery.of(context).size.width;
    final cellWidth = (screenWidth - 16) / 7;
    final cellHeight = cellWidth;

    return SizedBox(
      height: cellHeight + 8, // hücre yüksekliği + event noktaları için boşluk
      child: Row(
        children: List.generate(7, (index) {
          final currentDay = startWeek.add(Duration(days: index));
          final dayKey =
              DateTime(currentDay.year, currentDay.month, currentDay.day);
          final dayEvents = eventsByDate?[currentDay] ?? const <EventEntity>[];
          final hasSimpleDot =
              daysWithSimpleDots != null && daysWithSimpleDots.contains(dayKey);
          final isSelected = isSameDay(_selectedDay, currentDay);
          final isToday = isSameDay(DateTime.now(), currentDay);

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedDay = currentDay;
                });
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Gün Sayısı Karesi
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withValues(alpha: 0.18)
                          : (isToday
                                ? colorScheme.primaryContainer.withValues(
                                    alpha: 0.35,
                                  )
                                : null),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : (isToday
                                  ? colorScheme.primary.withValues(alpha: 0.7)
                                  : Colors.transparent),
                        width: 2,
                      ),
                    ),
                    child: Text(
                      '${currentDay.day}',
                      style: AppTypography.bodyMedium.copyWith(
                        color: isSelected || isToday
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                        fontWeight: isSelected || isToday
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (eventsByDate != null && dayEvents.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: dayEvents.take(3).map((e) {
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: _getEventTypeColor(e.eventType),
                              shape: BoxShape.circle,
                            ),
                          );
                        }).toList(),
                      ),
                    )
                  else if (hasSimpleDot)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: AppColors.secondary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox(height: 8), // Hizalamayı korumak için boşluk
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildEventCard(
    BuildContext context,
    WidgetRef ref,
    EventEntity event,
    bool isAdmin,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    // Local state'teki pin durumunu kontrol et
    final effectiveEvent = _pinnedStates.containsKey(event.id)
        ? EventEntity(
            id: event.id,
            title: event.title,
            description: event.description,
            eventType: event.eventType,
            status: event.status,
            startTime: event.startTime,
            endTime: event.endTime,
            locationName: event.locationName,
            locationAddress: event.locationAddress,
            locationLat: event.locationLat,
            locationLng: event.locationLng,
            routeId: event.routeId,
            trainingGroupId: event.trainingGroupId,
            trainingTypeId: event.trainingTypeId,
            trainingTypeName: event.trainingTypeName,
            trainingTypeDescription: event.trainingTypeDescription,
            trainingTypeColor: event.trainingTypeColor,
            weatherNote: event.weatherNote,
            coachNotes: event.coachNotes,
            bannerImageUrl: event.bannerImageUrl,
            createdBy: event.createdBy,
            createdAt: event.createdAt,
            participantCount: event.participantCount,
            isUserParticipating: event.isUserParticipating,
            laneConfig: event.laneConfig,
            isPinned: _pinnedStates[event.id]!.isPinned,
            pinnedAt: _pinnedStates[event.id]!.pinnedAt,
          )
        : event;

    final trainingRoutes = effectiveEvent.eventType == EventType.training
        ? ref.watch(eventRouteOptionsProvider(effectiveEvent.id)).valueOrNull
        : null;
    final locationText = (trainingRoutes != null && trainingRoutes.length >= 2)
        ? trainingRoutes.map((r) => r.displayName).join(' · ')
        : effectiveEvent.locationName;

    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.pushNamed(
        RouteNames.eventDetail,
        pathParameters: {'eventId': effectiveEvent.id},
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date Badge
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: effectiveEvent.isToday
                  ? AppColors.secondary
                  : colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  effectiveEvent.shortDayOfWeek.toUpperCase(),
                  style: AppTypography.labelSmall.copyWith(
                    color: effectiveEvent.isToday
                        ? Colors.white
                        : colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
                Text(
                  effectiveEvent.startTime.day.toString(),
                  style: AppTypography.headlineSmall.copyWith(
                    color: effectiveEvent.isToday
                        ? Colors.white
                        : colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Event Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getEventTypeColor(
                          effectiveEvent.eventType,
                        ).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        effectiveEvent.eventType.displayName,
                        style: AppTypography.labelSmall.copyWith(
                          color: _getEventTypeColor(effectiveEvent.eventType),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (effectiveEvent.isUserParticipating)
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: AppColors.success,
                      ),
                    if (effectiveEvent.isUserParticipating && isAdmin)
                      const SizedBox(width: 4),
                    if (isAdmin)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                          final newPinnedState = !effectiveEvent.isPinned;
                          final newPinnedAt = newPinnedState
                              ? DateTime.now()
                              : null;

                          // Optimistic update: UI'ı hemen güncelle
                          setState(() {
                            _pinnedStates[effectiveEvent.id] = (
                              isPinned: newPinnedState,
                              pinnedAt: newPinnedAt,
                            );
                            // Cache'i temizle (yeniden hesaplanacak)
                            _cachedSortedEvents = null;
                            _cachedEventsByDate = null;
                            _cachedEventsHash = null;
                          });

                          final messenger = ScaffoldMessenger.of(context);

                          try {
                            final dataSource = ref.read(
                              eventDataSourceProvider,
                            );
                            await dataSource.setEventPinned(
                              effectiveEvent.id,
                              newPinnedState,
                            );

                            // Başarılı olduğunda provider'ları yenile (arka planda)
                            ref.invalidate(upcomingEventsProvider);
                            ref.invalidate(thisWeekEventsProvider);
                            ref.invalidate(allEventsProvider);
                          } catch (e) {
                            // Hata durumunda geri al (rollback) - local state'i kaldır, provider'dan gelen değeri kullan
                            setState(() {
                              _pinnedStates.remove(effectiveEvent.id);
                              // Cache'i temizle (yeniden hesaplanacak)
                              _cachedSortedEvents = null;
                              _cachedEventsByDate = null;
                              _cachedEventsHash = null;
                            });

                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('İşlem başarısız: $e'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            effectiveEvent.isPinned
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            size: 16,
                            color: effectiveEvent.isPinned
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  effectiveEvent.title,
                  style: AppTypography.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: ThemeBrightnessHolder.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        effectiveEvent.formattedTime,
                        style: AppTypography.bodySmall.copyWith(
                          color: ThemeBrightnessHolder.onSurfaceVariant,
                        ),
                      ),
                      if (locationText != null) ...[
                        const SizedBox(width: 12),
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: ThemeBrightnessHolder.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            locationText,
                            style: AppTypography.bodySmall.copyWith(
                              color: ThemeBrightnessHolder.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 14,
                      color: ThemeBrightnessHolder.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${effectiveEvent.participantCount} katılımcı',
                      style: AppTypography.bodySmall.copyWith(
                        color: ThemeBrightnessHolder.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

  // Türkçe gün isimlerini döndürür
  String _getDayName(DateTime date) {
    const dayNames = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    return dayNames[date.weekday - 1];
  }

  // Türkçe ay isimlerini döndürür
  String _getMonthName(DateTime date) {
    const monthNames = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    return monthNames[date.month - 1];
  }

  // Yaklaşan etkinlikler listesini oluşturur
  Widget _buildUpcomingEventsList(
    Map<DateTime, List<EventEntity>> eventsByDate,
    bool isAdmin,
    bool showWorkoutView,
  ) {
    // Seçili tarih yoksa veya _topVisibleDate yoksa bekle
    if (_selectedDay == null || _topVisibleDate == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Yükleniyor...'),
        ),
      );
    }

    // Seçili tarihten başlayarak etkinlik olan günleri bul
    final startDate = _selectedDay!;
    final startDateKey = DateTime(startDate.year, startDate.month, startDate.day);

    // Etkinlik olan günleri topla (sadece eventsByDate'deki key'leri kontrol et, döngü yapma)
    final eventDays = <DateTime>[];
    for (final dateKey in eventsByDate.keys) {
      // Sadece seçili tarihten sonraki veya eşit olan tarihleri ekle
      if (!dateKey.isBefore(startDateKey)) {
        if (eventsByDate[dateKey]!.isNotEmpty) {
          eventDays.add(dateKey);
        }
      }
    }
    
    // Tarihe göre sırala
    eventDays.sort();

    if (eventDays.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                showWorkoutView ? Icons.fitness_center : Icons.event_available,
                size: 48,
                color: ThemeBrightnessHolder.outline,
              ),
              const SizedBox(height: 16),
              Text(
                showWorkoutView ? 'Yaklaşan antrenman yok' : 'Yaklaşan etkinlik yok',
                style: AppTypography.bodyMedium.copyWith(
                  color: ThemeBrightnessHolder.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: eventDays.length,
      cacheExtent: 500, // Daha fazla item cache'le
      itemBuilder: (context, index) {
        final date = eventDays[index];
        final dayEvents = eventsByDate[date]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tarih başlığı
            Padding(
              padding: EdgeInsets.only(bottom: 8, top: index == 0 ? 0 : 16),
              child: Text(
                '${date.day} ${_getMonthName(date)} ${_getDayName(date)} ${date.year}',
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ThemeBrightnessHolder.onSurface,
                ),
              ),
            ),
            // O güne ait etkinlikler
            ...dayEvents.map(
              (event) => RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildEventCard(
                    context,
                    ref,
                    event,
                    isAdmin,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
