import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import 'user_activity_report_page.dart';
import '../../data/models/event_report_model.dart';
import '../../data/models/user_report_model.dart';
import '../../domain/entities/event_entity.dart';
import '../providers/event_provider.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';
import '../../../../core/constants/app_constants.dart';

enum GroupReportSortType { distance, duration, pace }

/// Etkinlik Raporu Sayfası
class EventReportPage extends ConsumerStatefulWidget {
  const EventReportPage({super.key});

  @override
  ConsumerState<EventReportPage> createState() => _EventReportPageState();
}

class _EventReportPageState extends ConsumerState<EventReportPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DateTime _startDate;
  late DateTime _endDate;
  String? _selectedEventType;
  String? _selectedGroupId;
  
  // Grup raporu için
  String? _selectedGroupReportGroupId;
  GroupReportSortType _groupReportSortType = GroupReportSortType.distance;
  String _groupReportUserSearchQuery = '';
  // Kullanıcı raporu için
  String? _selectedUserReportGroupId;
  GroupReportSortType _userReportSortType = GroupReportSortType.distance;
  String _userReportSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeCurrentWeekRange();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _initializeCurrentWeekRange() {
    final now = DateTime.now();
    // Haftanın pazartesi günü (hafta pazartesi başlasın)
    final monday = now.subtract(Duration(days: now.weekday - DateTime.monday));
    _startDate = DateTime(monday.year, monday.month, monday.day);
    // Bitiş: bugün (ör. salı ise pazartesi-salı, pazar ise pazartesi-pazar)
    _endDate = DateTime(now.year, now.month, now.day);
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _startDate) {
      setState(() {
        _startDate = picked;
        if (_startDate.isAfter(_endDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _endDate) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raporlar'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Etkinlik Raporu'),
            Tab(text: 'Grup Raporu'),
            Tab(text: 'Kullanıcı Raporu'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEventReportTab(),
          _buildGroupReportTab(),
          _buildUserReportTab(),
        ],
      ),
    );
  }

  Widget _buildEventReportTab() {
    final isTrainingSelected = _selectedEventType == 'training';
    
    final reportAsync = ref.watch(
      eventReportProvider((
        startDate: _startDate,
        endDate: _endDate,
        eventType: _selectedEventType,
        groupId: isTrainingSelected ? _selectedGroupId : null,
      )),
    );

    return Column(
        children: [
          // Tarih Seçimi ve Filtreler
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              border: Border(
                bottom: BorderSide(
                  color: AppColors.neutral200,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                // Tarih Seçimi
                Row(
                  children: [
                    Expanded(
                      child: _buildDateSelector(
                        context,
                        label: 'Başlangıç',
                        date: _startDate,
                        onTap: () => _selectStartDate(context),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDateSelector(
                        context,
                        label: 'Bitiş',
                        date: _endDate,
                        onTap: () => _selectEndDate(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Etkinlik Türü ve Grup Filtreleri
                Row(
                  children: [
                    Text(
                      'Etkinlik:',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildEventTypeFilter(),
                    if (isTrainingSelected) ...[
                      const SizedBox(width: 16),
                      Text(
                        'Grup:',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildGroupFilter(),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // İçerik
          Expanded(
            child: reportAsync.when(
              data: (report) {
                if (report.totalEvents == 0) {
                  final eventTypeText = _selectedEventType != null
                      ? EventType.values
                          .firstWhere((e) => e.name == _selectedEventType)
                          .displayName
                      : null;
                  
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bar_chart_outlined,
                          size: 64,
                          color: AppColors.neutral400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          eventTypeText != null
                              ? 'Seçilen tarih aralığında $eventTypeText etkinliği bulunamadı'
                              : 'Seçilen tarih aralığında etkinlik bulunamadı',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.neutral500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // İstatistik Kartları
                      _buildStatsCards(report),
                      const SizedBox(height: 24),

                      // Grafik
                      Text(
                        'Etkinlik Bazında Katılımcı Sayısı',
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildChart(report),
                      const SizedBox(height: 24),

                      // Etkinlik listesi (en yeniden en eskiye)
                      Text(
                        'Etkinlikler',
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildEventList(report),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: LoadingWidget()),
              error: (error, stackTrace) => Center(
                child: ErrorStateWidget(
                  title: 'Rapor yüklenemedi',
                  message: error.toString(),
                  onRetry: () {
                    ref.invalidate(
                      eventReportProvider((
                        startDate: _startDate,
                        endDate: _endDate,
                        eventType: _selectedEventType,
                        groupId: isTrainingSelected ? _selectedGroupId : null,
                      )),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      );
    
  }

  Widget _buildDateSelector(
    BuildContext context, {
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.neutral300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.neutral500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('dd.MM.yyyy').format(date),
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventTypeFilter() {
    final selectedType = _selectedEventType != null
        ? EventType.values.firstWhere((e) => e.name == _selectedEventType)
        : null;

    return PopupMenuButton<String?>(
      initialValue: _selectedEventType,
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.neutral300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selectedType?.displayName ?? 'Tümü',
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: AppColors.neutral600,
            ),
          ],
        ),
      ),
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.neutral200),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<String?>(
          value: null,
          child: Row(
            children: [
              Icon(
                _selectedEventType == null ? Icons.check : null,
                size: 18,
                color: AppColors.primary,
              ),
              if (_selectedEventType == null) const SizedBox(width: 8),
              Text('Tümü'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        ...EventType.values.map((type) {
          final typeString = type.name;
          final isSelected = _selectedEventType == typeString;
          return PopupMenuItem<String?>(
            value: typeString,
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.check : null,
                  size: 18,
                  color: AppColors.primary,
                ),
                if (isSelected) const SizedBox(width: 8),
                Text(type.displayName),
              ],
            ),
          );
        }),
      ],
      onSelected: (value) {
        setState(() {
          _selectedEventType = value;
          // Antrenman seçilmediyse grup filtresini temizle
          if (value != 'training') {
            _selectedGroupId = null;
          }
        });
      },
    );
  }

  Widget _buildGroupFilter() {
    final groupsAsync = ref.watch(allGroupsProvider);
    
    return groupsAsync.when(
      data: (groups) {
        final selectedGroup = _selectedGroupId != null
            ? groups.firstWhere((g) => g.id == _selectedGroupId, orElse: () => groups.first)
            : null;

        return PopupMenuButton<String?>(
          initialValue: _selectedGroupId,
          icon: SizedBox(
            width: double.infinity,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.neutral300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      selectedGroup?.name ?? 'Tüm Gruplar',
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: AppColors.neutral600,
                  ),
                ],
              ),
            ),
          ),
          offset: const Offset(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: AppColors.neutral200),
          ),
          itemBuilder: (context) => [
            PopupMenuItem<String?>(
              value: null,
              child: Row(
                children: [
                  Icon(
                    _selectedGroupId == null ? Icons.check : null,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  if (_selectedGroupId == null) const SizedBox(width: 8),
                  const Text('Tüm Gruplar'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            ...groups.map((group) {
              final isSelected = _selectedGroupId == group.id;
              return PopupMenuItem<String?>(
                value: group.id,
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.check : null,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    if (isSelected) const SizedBox(width: 8),
                    Text(group.name),
                  ],
                ),
              );
            }),
          ],
          onSelected: (value) {
            setState(() {
              _selectedGroupId = value;
            });
          },
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.neutral300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.neutral300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.error_outline, size: 16),
      ),
    );
  }

  Widget _buildStatsCards(EventReportSummaryModel report) {
    // Sadece Antrenman ve Yarış etkinlikleri
    final filteredEvents = report.events
        .where((e) => e.eventType == 'training' || e.eventType == 'race')
        .toList();

    final totalEvents = filteredEvents.length;
    final totalParticipants = filteredEvents.fold<int>(
      0,
      (sum, e) => sum + e.participantCount,
    );
    final averageParticipants =
        totalEvents > 0 ? totalParticipants / totalEvents : 0.0;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.event,
            title: 'Toplam Etkinlik',
            value: totalEvents.toString(),
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.people,
            title: 'Toplam Katılan',
            value: totalParticipants.toString(),
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.trending_up,
            title: 'Ortalama',
            value: averageParticipants.toStringAsFixed(1),
            color: AppColors.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildUserReportTab() {
    final userReportAsync = ref.watch(
      userReportProvider((
        startDate: _startDate,
        endDate: _endDate,
        groupId: _selectedUserReportGroupId,
      )),
    );

    return Column(
      children: [
        // Tarih Seçimi ve Grup Filtresi
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            border: Border(
              bottom: BorderSide(
                color: AppColors.neutral200,
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              // Tarih Seçimi
              Row(
                children: [
                  Expanded(
                    child: _buildDateSelector(
                      context,
                      label: 'Başlangıç',
                      date: _startDate,
                      onTap: () => _selectStartDate(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDateSelector(
                      context,
                      label: 'Bitiş',
                      date: _endDate,
                      onTap: () => _selectEndDate(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Grup Filtresi (opsiyonel)
              Row(
                children: [
                  Text(
                    'Grup:',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.neutral500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildUserReportGroupFilter(),
                  ),
                ],
              ),
            ],
          ),
        ),
        // İçerik
        Expanded(
          child: userReportAsync.when(
            data: (report) {
              if (report.totalUsers == 0) {
                return const Center(
                  child: EmptyStateWidget(
                    icon: Icons.directions_run,
                    title: 'Aktivite bulunamadı',
                    description:
                        'Seçilen tarih aralığında kullanıcı aktivitesi bulunamadı.',
                  ),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildUserReportSummaryCards(report),
                    const SizedBox(height: 24),
                    Text(
                      'Kullanıcı Bazında Mesafe',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildUserLeaderBoardChart(report),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Kullanıcı Listesi',
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _buildUserReportSortMenu(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'İsim veya soyisime göre ara',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                      style: AppTypography.bodySmall,
                      onChanged: (value) {
                        setState(() {
                          _userReportSearchQuery =
                              value.trim().toLowerCase();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildUserReportList(report.users),
                  ],
                ),
              );
            },
            loading: () => const Center(child: LoadingWidget()),
            error: (error, stackTrace) => Center(
              child: ErrorStateWidget(
                title: 'Rapor yüklenemedi',
                message: error.toString(),
                onRetry: () {
                  ref.invalidate(
                    userReportProvider((
                      startDate: _startDate,
                      endDate: _endDate,
                      groupId: _selectedUserReportGroupId,
                    )),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.neutral500,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// Grafiğin altında gösterilen etkinlik listesi (en yeniden en eskiye)
  Widget _buildEventList(EventReportSummaryModel report) {
    // Sadece Antrenman (training) ve Yarış (race) etkinlikleri ve Yeni → Eski sıralama
    final sortedEvents = report.events
        .where((e) => e.eventType == 'training' || e.eventType == 'race')
        .toList()
      ..sort((a, b) => b.eventDate.compareTo(a.eventDate));

    if (sortedEvents.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        ...sortedEvents.map((event) {
          // Liste satırı için tip/renk
          Color typeColor;
          String typeLabel;
          if (event.eventType == 'race') {
            typeColor = AppColors.error;
            typeLabel = 'Yarış';
          } else {
            // training
            final isIndividual = event.participationType == 'individual';
            typeColor = isIndividual ? AppColors.primary : AppColors.success;
            typeLabel = isIndividual ? 'Bireysel Antrenman' : 'Grup Antrenman';
          }

          return InkWell(
            onTap: () {
              context.pushNamed(
                RouteNames.eventReportDetail,
                pathParameters: {'eventId': event.eventId},
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Renkli tip ikonu
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      event.eventType == 'race'
                          ? Icons.emoji_events
                          : Icons.directions_run,
                      size: 16,
                      color: typeColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Başlık + tarih
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.eventTitle,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.neutral800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('dd.MM.yyyy EEEE – HH:mm', 'tr_TR')
                              .format(event.eventDate),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.neutral500,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Katılımcı sayısı + tip etiketi
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.people,
                            size: 14,
                            color: AppColors.neutral500,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            event.participantCount.toString(),
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.neutral700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          typeLabel,
                          style: AppTypography.bodySmall.copyWith(
                            fontSize: 10,
                            color: typeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildChart(EventReportSummaryModel report) {
    // Sadece Antrenman (training) ve Yarış (race) etkinlikleri
    final chartEvents = report.events
        .where((e) => e.eventType == 'training' || e.eventType == 'race')
        .toList();

    if (chartEvents.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxParticipants = chartEvents
        .map((e) => e.participantCount)
        .reduce((a, b) => a > b ? a : b);

    final barCount = chartEvents.length;
    final double barWidth;
    if (barCount <= 5) {
      barWidth = 24;
    } else if (barCount <= 10) {
      barWidth = 18;
    } else {
      barWidth = 12;
    }

    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxParticipants > 0 ? (maxParticipants * 1.2).ceilToDouble() : 10,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.primary,
              tooltipRoundedRadius: 8,
              tooltipPadding: const EdgeInsets.all(8),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final event = chartEvents[groupIndex];
                return BarTooltipItem(
                  '${event.eventTitle}\n${rod.toY.toInt()} katılımcı',
                  AppTypography.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= chartEvents.length) {
                    return const Text('');
                  }
                  // Etkinlik numarasını göster (1'den başlayarak)
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${index + 1}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.neutral600,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
                reservedSize: 30,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.neutral600,
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxParticipants > 0 ? (maxParticipants / 5).ceilToDouble() : 2,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: AppColors.neutral200,
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: AppColors.neutral300),
              left: BorderSide(color: AppColors.neutral300),
            ),
          ),
          barGroups: chartEvents.asMap().entries.map((entry) {
            final index = entry.key;
            final event = entry.value;

            // Renk belirleme: etkinlik türüne ve participation_type'a göre
            Color barColor;
            if (event.eventType == 'race') {
              // Yarışlar: kırmızı
              barColor = AppColors.error;
            } else if (event.eventType == 'training') {
              // Antrenmanlar: participation_type'a göre
              if (event.participationType == 'individual') {
                // Bireysel antrenmanlar: lacivert (primary)
                barColor = AppColors.primary;
              } else {
                // Grup antrenmanları: yeşil
                barColor = AppColors.success;
              }
            } else {
              // Diğer türler (teorik olarak filtreye girmemeli): varsayılan renk
              barColor = AppColors.neutral400;
            }

            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: event.participantCount.toDouble(),
                  color: barColor,
                  width: barWidth,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildUserReportSummaryCards(UserReportSummaryModel report) {
    final totalKm = report.totalDistanceKm;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.person,
            title: 'Toplam Koşan Kişi',
            value: report.totalUsers.toString(),
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.directions_run,
            title: 'Toplam Koşu',
            value: report.totalRuns.toString(),
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.route,
            title: 'Toplam KM',
            value: '${totalKm.toStringAsFixed(1)} km',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.speed,
            title: 'Ort. Pace',
            value: report.averagePaceSecondsPerKm != null
                ? _formatPace(report.averagePaceSecondsPerKm!)
                : '-',
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildUserReportList(List<UserAggregateStatModel> users) {
    if (users.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.directions_run,
        title: 'Kullanıcı bulunamadı',
        description: 'Seçilen tarih aralığında aktivitesi olan kullanıcı yok.',
      );
    }

    final sorted = [...users];

    sorted.sort((a, b) {
      switch (_userReportSortType) {
        case GroupReportSortType.distance:
          return b.totalDistanceMeters.compareTo(a.totalDistanceMeters);
        case GroupReportSortType.duration:
          return b.totalDurationSeconds.compareTo(a.totalDurationSeconds);
        case GroupReportSortType.pace:
          final ap = a.averagePaceSecondsPerKm ?? double.infinity;
          final bp = b.averagePaceSecondsPerKm ?? double.infinity;
          return ap.compareTo(bp); // daha hızlı önce
      }
    });

    List<UserAggregateStatModel> filtered = sorted;
    if (_userReportSearchQuery.isNotEmpty) {
      filtered = sorted.where((u) {
        final name = u.userName.toLowerCase();
        return name.contains(_userReportSearchQuery);
      }).toList();
    }

    if (filtered.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.person_search,
        title: 'Kullanıcı bulunamadı',
        description: 'Bu arama kriterleriyle kullanıcı bulunamadı.',
      );
    }

    // İlk 3 kullanıcıyı rozetle vurgula
    return Column(
      children: filtered.asMap().entries.map((entry) {
        final index = entry.key;
        final user = entry.value;
        final distanceKm = user.totalDistanceMeters / 1000.0;

        String formatDuration(int seconds) {
          final d = Duration(seconds: seconds);
          final h = d.inHours.toString().padLeft(2, '0');
          final m = (d.inMinutes % 60).toString().padLeft(2, '0');
          final s = (d.inSeconds % 60).toString().padLeft(2, '0');
          return '$h:$m:$s';
        }

        String paceStr;
        if (user.averagePaceSecondsPerKm != null &&
            user.averagePaceSecondsPerKm!.isFinite) {
          paceStr = _formatPace(user.averagePaceSecondsPerKm!);
        } else {
          paceStr = '-';
        }

        String? rankLabel;
        if (index == 0) rankLabel = 'Top 1';
        if (index == 1) rankLabel = 'Top 2';
        if (index == 2) rankLabel = 'Top 3';

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: UserAvatar(
            size: 40,
            name: user.userName,
            imageUrl: user.avatarUrl,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  user.userName,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (rankLabel != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    rankLabel,
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 10,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Row(
            children: [
              Icon(Icons.route, size: 14, color: AppColors.neutral500),
              const SizedBox(width: 4),
              Text(
                '${distanceKm.toStringAsFixed(2)} km',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.neutral600),
              ),
              const SizedBox(width: 12),
              Icon(Icons.timer_outlined, size: 14, color: AppColors.neutral500),
              const SizedBox(width: 4),
              Text(
                formatDuration(user.totalDurationSeconds),
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.neutral600),
              ),
              const SizedBox(width: 12),
              Icon(Icons.speed, size: 14, color: AppColors.neutral500),
              const SizedBox(width: 4),
              Text(
                '$paceStr dk/km',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.neutral600),
              ),
              const SizedBox(width: 12),
              Icon(Icons.directions_run,
                  size: 14, color: AppColors.neutral500),
              const SizedBox(width: 4),
              Text(
                '${user.totalRuns} koşu',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.neutral600),
              ),
            ],
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserActivityReportPage(
                  userId: user.userId,
                  userName: user.userName,
                  avatarUrl: user.avatarUrl,
                  startDate: _startDate,
                  endDate: _endDate,
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }

  Widget _buildUserLeaderBoardChart(UserReportSummaryModel report) {
    if (report.users.isEmpty) {
      return const SizedBox.shrink();
    }

    // Mesafeye göre ilk 10 kullanıcı
    final topUsers = [...report.users]
      ..sort(
        (a, b) => b.totalDistanceMeters.compareTo(a.totalDistanceMeters),
      );
    final maxCount = topUsers.length > 10 ? 10 : topUsers.length;
    final chartUsers = topUsers.take(maxCount).toList();

    final maxKm = chartUsers
        .map((u) => u.totalDistanceMeters / 1000.0)
        .fold<double>(0, (prev, v) => v > prev ? v : prev);

    if (maxKm <= 0) {
      return const SizedBox.shrink();
    }

    final barWidth = maxCount <= 5
        ? 24.0
        : maxCount <= 10
            ? 18.0
            : 12.0;

    return Container(
      height: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxKm * 1.2,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.primary,
              tooltipRoundedRadius: 8,
              tooltipPadding: const EdgeInsets.all(8),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final user = chartUsers[groupIndex];
                final km = (user.totalDistanceMeters / 1000.0)
                    .toStringAsFixed(2);
                return BarTooltipItem(
                  '${user.userName}\n$km km • ${user.totalRuns} koşu',
                  AppTypography.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= chartUsers.length) {
                    return const Text('');
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${index + 1}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.neutral600,
                        fontSize: 11,
                      ),
                    ),
                  );
                },
                reservedSize: 28,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toStringAsFixed(0),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.neutral600,
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxKm > 0 ? (maxKm / 4).ceilToDouble() : 2,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: AppColors.neutral200,
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: AppColors.neutral300),
              left: BorderSide(color: AppColors.neutral300),
            ),
          ),
          barGroups: List.generate(chartUsers.length, (index) {
            final user = chartUsers[index];
            final km = user.totalDistanceMeters / 1000.0;

            Color barColor;
            if (index == 0) {
              barColor = AppColors.primary;
            } else if (index == 1) {
              barColor = AppColors.primary.withValues(alpha: 0.8);
            } else if (index == 2) {
              barColor = AppColors.primary.withValues(alpha: 0.6);
            } else {
              barColor = AppColors.neutral400;
            }

            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: km,
                  color: barColor,
                  width: barWidth,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildGroupReportTab() {
    final groupReportAsync = _selectedGroupReportGroupId != null
        ? ref.watch(
            groupReportProvider((
              groupId: _selectedGroupReportGroupId!,
              startDate: _startDate,
              endDate: _endDate,
            )),
          )
        : null;

    return Column(
      children: [
        // Tarih Seçimi ve Grup Filtresi
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            border: Border(
              bottom: BorderSide(
                color: AppColors.neutral200,
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              // Tarih Seçimi
              Row(
                children: [
                  Expanded(
                    child: _buildDateSelector(
                      context,
                      label: 'Başlangıç',
                      date: _startDate,
                      onTap: () => _selectStartDate(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDateSelector(
                      context,
                      label: 'Bitiş',
                      date: _endDate,
                      onTap: () => _selectEndDate(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Grup Seçimi
              Row(
                children: [
                  const Text('Grup:'),
                  const SizedBox(width: 8),
                  Expanded(child: _buildGroupReportGroupFilter()),
                ],
              ),
            ],
          ),
        ),
        // İçerik
        Expanded(
          child: groupReportAsync == null
              ? Center(
                  child: Text(
                    'Grup seçiniz',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.neutral500,
                    ),
                  ),
                )
              : groupReportAsync.when(
                  data: (report) {
                    final totalKm = (report['total_distance_meters'] as num).toDouble() / 1000.0;
                    final averagePaceSecondsPerKm = report['average_pace_seconds_per_km'] as num?;
                    final userStats = report['user_stats'] as List<dynamic>;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // İstatistik Kartları (Grup raporu: sadece toplam KM ve ortalama pace)
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  icon: Icons.route,
                                  title: 'Toplam KM',
                                  value: '${totalKm.toStringAsFixed(2)} km',
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  icon: Icons.speed,
                                  title: 'Ort Pace',
                                  value: averagePaceSecondsPerKm != null
                                      ? _formatPace(averagePaceSecondsPerKm.toDouble())
                                      : '-',
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Kullanıcı Listesi başlık + arama + sıralama
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Kullanıcı İstatistikleri',
                                  style: AppTypography.titleMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              _buildGroupReportSortMenu(),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'İsim veya soyisime göre ara',
                              prefixIcon: const Icon(Icons.search, size: 18),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                            ),
                            style: AppTypography.bodySmall,
                            onChanged: (value) {
                              setState(() {
                                _groupReportUserSearchQuery = value.trim().toLowerCase();
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          if (userStats.isEmpty)
                            const EmptyStateWidget(
                              icon: Icons.directions_run,
                              title: 'Aktivite bulunamadı',
                              description: 'Seçilen tarih aralığında aktivite kaydı yok.',
                            )
                          else
                            _buildGroupReportUserList(userStats),
                        ],
                      ),
                    );
                  },
                  loading: () => const Center(child: LoadingWidget()),
                  error: (error, stackTrace) => Center(
                    child: ErrorStateWidget(
                      title: 'Rapor yüklenemedi',
                      message: error.toString(),
                      onRetry: () {
                        ref.invalidate(
                          groupReportProvider((
                            groupId: _selectedGroupReportGroupId!,
                            startDate: _startDate,
                            endDate: _endDate,
                          )),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildGroupReportGroupFilter() {
    final groupsAsync = ref.watch(allGroupsProvider);

    return groupsAsync.when(
      data: (groups) {
        final selectedGroup = _selectedGroupReportGroupId != null
            ? groups.firstWhere(
                (g) => g.id == _selectedGroupReportGroupId,
                orElse: () => groups.first,
              )
            : null;

        return PopupMenuButton<String>(
          initialValue: _selectedGroupReportGroupId,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.neutral100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.neutral300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    selectedGroup?.name ?? 'Grup Seçiniz',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w500,
                      color: AppColors.neutral700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 20, color: AppColors.neutral600),
              ],
            ),
          ),
          onSelected: (groupId) {
            setState(() {
              _selectedGroupReportGroupId = groupId;
            });
          },
          itemBuilder: (context) {
            return groups.map((group) {
              return PopupMenuItem<String>(
                value: group.id,
                child: Text(group.name),
              );
            }).toList();
          },
        );
      },
      loading: () => const SizedBox(
        height: 40,
        child: Center(child: LoadingWidget(size: 20)),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  String _formatPace(double secondsPerKm) {
    final totalSeconds = secondsPerKm.round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildGroupReportSortMenu() {
    String getSortLabel() {
      switch (_groupReportSortType) {
        case GroupReportSortType.distance:
          return 'Mesafe (km)';
        case GroupReportSortType.duration:
          return 'Süre';
        case GroupReportSortType.pace:
          return 'Pace';
      }
    }

    return PopupMenuButton<GroupReportSortType>(
      initialValue: _groupReportSortType,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.neutral100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.neutral300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              getSortLabel(),
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.neutral700,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 20, color: AppColors.neutral600),
          ],
        ),
      ),
      onSelected: (type) {
        setState(() {
          _groupReportSortType = type;
        });
      },
      itemBuilder: (context) {
        return [
          const PopupMenuItem<GroupReportSortType>(
            value: GroupReportSortType.distance,
            child: Text('Mesafe (km)'),
          ),
          const PopupMenuItem<GroupReportSortType>(
            value: GroupReportSortType.duration,
            child: Text('Süre'),
          ),
          const PopupMenuItem<GroupReportSortType>(
            value: GroupReportSortType.pace,
            child: Text('Pace'),
          ),
        ];
      },
    );
  }

  Widget _buildGroupReportUserList(List<dynamic> userStats) {
    final sorted = [...userStats];
    
    sorted.sort((a, b) {
      switch (_groupReportSortType) {
        case GroupReportSortType.distance:
          final aDist = (a['total_distance_meters'] as num).toDouble();
          final bDist = (b['total_distance_meters'] as num).toDouble();
          return bDist.compareTo(aDist); // En çok → en az
        case GroupReportSortType.duration:
          final aDur = a['total_duration_seconds'] as int;
          final bDur = b['total_duration_seconds'] as int;
          return bDur.compareTo(aDur); // En uzun → en kısa
        case GroupReportSortType.pace:
          final aPace = a['average_pace_seconds_per_km'] as num?;
          final bPace = b['average_pace_seconds_per_km'] as num?;
          if (aPace == null && bPace == null) return 0;
          if (aPace == null) return 1;
          if (bPace == null) return -1;
          return aPace.compareTo(bPace); // En hızlı → en yavaş
      }
    });

    // İsim/soyisim LIKE filtresi
    List<dynamic> filtered = sorted;
    if (_groupReportUserSearchQuery.isNotEmpty) {
      filtered = sorted.where((stat) {
        final userName = (stat['user_name'] as String?) ?? '';
        return userName.toLowerCase().contains(_groupReportUserSearchQuery);
      }).toList();
    }

    return Column(
      children: filtered.map((stat) {
        final userId = stat['user_id'] as String;
        final userName = stat['user_name'] as String;
        final avatarUrl = stat['avatar_url'] as String?;
        final distanceKm = (stat['total_distance_meters'] as num).toDouble() / 1000.0;
        final durationSeconds = stat['total_duration_seconds'] as int;
        final paceSecondsPerKm = stat['average_pace_seconds_per_km'] as num?;

        String formatDuration(int seconds) {
          final duration = Duration(seconds: seconds);
          return '${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
        }

        String formatPace(double secondsPerKm) {
          final totalSeconds = secondsPerKm.round();
          final minutes = totalSeconds ~/ 60;
          final seconds = totalSeconds % 60;
          return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        }

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: UserAvatar(
            size: 40,
            name: userName,
            imageUrl: avatarUrl,
          ),
          title: Text(
            userName,
            style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Row(
            children: [
              Icon(Icons.route, size: 14, color: AppColors.neutral500),
              const SizedBox(width: 4),
              Text(
                '${distanceKm.toStringAsFixed(2)} km',
                style: AppTypography.bodySmall.copyWith(color: AppColors.neutral600),
              ),
              const SizedBox(width: 12),
              Icon(Icons.timer_outlined, size: 14, color: AppColors.neutral500),
              const SizedBox(width: 4),
              Text(
                formatDuration(durationSeconds),
                style: AppTypography.bodySmall.copyWith(color: AppColors.neutral600),
              ),
              const SizedBox(width: 12),
              Icon(Icons.speed, size: 14, color: AppColors.neutral500),
              const SizedBox(width: 4),
              Text(
                paceSecondsPerKm != null
                    ? '${formatPace(paceSecondsPerKm.toDouble())} dk/km'
                    : '-',
                style: AppTypography.bodySmall.copyWith(color: AppColors.neutral600),
              ),
            ],
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserActivityReportPage(
                  userId: userId,
                  userName: userName,
                  avatarUrl: avatarUrl,
                  startDate: _startDate,
                  endDate: _endDate,
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }

  Widget _buildUserReportSortMenu() {
    return PopupMenuButton<GroupReportSortType>(
      initialValue: _userReportSortType,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.neutral100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.neutral300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _userReportSortType == GroupReportSortType.distance
                  ? 'Mesafe (km)'
                  : _userReportSortType == GroupReportSortType.duration
                      ? 'Süre'
                      : 'Pace',
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.neutral700,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down,
                size: 20, color: AppColors.neutral600),
          ],
        ),
      ),
      onSelected: (value) {
        setState(() {
          _userReportSortType = value;
        });
      },
      itemBuilder: (context) {
        return [
          const PopupMenuItem<GroupReportSortType>(
            value: GroupReportSortType.distance,
            child: Text('Mesafe (km)'),
          ),
          const PopupMenuItem<GroupReportSortType>(
            value: GroupReportSortType.duration,
            child: Text('Süre'),
          ),
          const PopupMenuItem<GroupReportSortType>(
            value: GroupReportSortType.pace,
            child: Text('Pace'),
          ),
        ];
      },
    );
  }

  Widget _buildUserReportGroupFilter() {
    final groupsAsync = ref.watch(allGroupsProvider);

    return groupsAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          return Text(
            'Tüm Gruplar',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.neutral500,
            ),
          );
        }

        final selectedGroup = _selectedUserReportGroupId != null
            ? groups.firstWhere(
                (g) => g.id == _selectedUserReportGroupId,
                orElse: () => groups.first,
              )
            : null;

        return PopupMenuButton<String?>(
          initialValue: _selectedUserReportGroupId,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.neutral100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.neutral300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selectedGroup?.name ?? 'Tüm Gruplar',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w500,
                    color: AppColors.neutral700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down,
                    size: 20, color: AppColors.neutral600),
              ],
            ),
          ),
          onSelected: (value) {
            setState(() {
              _selectedUserReportGroupId = value;
            });
          },
          itemBuilder: (context) {
            return [
              const PopupMenuItem<String?>(
                value: null,
                child: Text('Tüm Gruplar'),
              ),
              ...groups.map((g) {
                return PopupMenuItem<String?>(
                  value: g.id,
                  child: Text(g.name),
                );
              }),
            ];
          },
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.neutral300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.neutral300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.error_outline, size: 16),
      ),
    );
  }
}
