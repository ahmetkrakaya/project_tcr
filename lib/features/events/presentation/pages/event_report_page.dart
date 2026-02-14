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
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String? _selectedEventType;
  String? _selectedGroupId;
  
  // Grup raporu için
  String? _selectedGroupReportGroupId;
  GroupReportSortType _groupReportSortType = GroupReportSortType.distance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEventReportTab(),
          _buildGroupReportTab(),
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
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.event,
            title: 'Toplam Etkinlik',
            value: report.totalEvents.toString(),
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.people,
            title: 'Toplam Katılan',
            value: report.totalParticipants.toString(),
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.trending_up,
            title: 'Ortalama',
            value: report.averageParticipants.toStringAsFixed(1),
            color: AppColors.warning,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTypography.titleLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 4),
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
    // Yeni → Eski sıralama
    final sortedEvents = [...report.events]
      ..sort((a, b) => b.eventDate.compareTo(a.eventDate));

    return Column(
      children: sortedEvents.map((event) {
        return InkWell(
          onTap: () {
            context.pushNamed(
              RouteNames.eventReportDetail,
              pathParameters: {'eventId': event.eventId},
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.neutral500,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.eventTitle,
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppColors.neutral800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('dd.MM.yyyy EEEE – HH:mm', 'tr_TR').format(event.eventDate),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChart(EventReportSummaryModel report) {
    if (report.events.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxParticipants = report.events
        .map((e) => e.participantCount)
        .reduce((a, b) => a > b ? a : b);

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
                final event = report.events[groupIndex];
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
                  if (index < 0 || index >= report.events.length) {
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
          barGroups: report.events.asMap().entries.map((entry) {
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
                // Bireysel antrenmanlar: açık mavi
                barColor = AppColors.tertiaryLight;
              } else {
                // Ekip antrenmanları: yeşil
                barColor = AppColors.success;
              }
            } else {
              // Diğer türler: varsayılan renk
              barColor = AppColors.primary;
            }
            
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: event.participantCount.toDouble(),
                  color: barColor,
                  width: 20,
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
                    final totalDurationSeconds = report['total_duration_seconds'] as int;
                    final averagePaceSecondsPerKm = report['average_pace_seconds_per_km'] as num?;
                    final userStats = report['user_stats'] as List<dynamic>;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // İstatistik Kartları
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
                                  icon: Icons.timer_outlined,
                                  title: 'Toplam Süre',
                                  value: _formatDuration(totalDurationSeconds),
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
                          // Kullanıcı Listesi
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


  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    return '${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
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

    return Column(
      children: sorted.map((stat) {
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
}
