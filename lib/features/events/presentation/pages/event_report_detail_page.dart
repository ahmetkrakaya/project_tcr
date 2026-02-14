import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';
import '../../../members_groups/domain/entities/group_entity.dart';
import '../../presentation/providers/event_provider.dart';
import '../../data/models/event_activity_stat_model.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';

/// Etkinlik Raporu Detay Sayfası
/// - Grup bazında antrenman programı
/// - Kullanıcı listesi: mesafe / süre / pace sıralamaları
class EventReportDetailPage extends ConsumerStatefulWidget {
  final String eventId;

  const EventReportDetailPage({super.key, required this.eventId});

  @override
  ConsumerState<EventReportDetailPage> createState() => _EventReportDetailPageState();
}

enum _StatSortType { distance, duration, pace }

class _EventReportDetailPageState extends ConsumerState<EventReportDetailPage> {
  _StatSortType _sortType = _StatSortType.distance;
  String? _selectedGroupId;

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventByIdProvider(widget.eventId));
    final statsAsync = ref.watch(eventActivityStatsProvider(widget.eventId));
    final programsAsync = ref.watch(eventGroupProgramsProvider(widget.eventId));
    
    // Seçilen grubun üyelerini al (filtreleme için)
    final groupMembersAsync = _selectedGroupId != null
        ? ref.watch(groupMembersProvider(_selectedGroupId!))
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Etkinlik Detayı'),
      ),
      body: eventAsync.when(
        data: (event) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Etkinlik başlık ve tarih
                Text(
                  event.title,
                  style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('dd.MM.yyyy – HH:mm').format(event.startTime),
                  style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
                ),
                const SizedBox(height: 16),

                // Grup bazında antrenman programı
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Grup Bazında Antrenman Programı',
                        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    programsAsync.when(
                      data: (programs) {
                        if (programs.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return _buildGroupFilter(programs);
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                programsAsync.when(
                  data: (programs) {
                    if (programs.isEmpty) {
                      return const EmptyStateWidget(
                        icon: Icons.list_alt_outlined,
                        title: 'Program bulunamadı',
                        description: 'Bu etkinlik için grup bazında program eklenmemiş.',
                      );
                    }

                    // Grup filtresi varsa filtrele
                    final filteredPrograms = _selectedGroupId == null
                        ? programs
                        : programs.where((p) => p.trainingGroupId == _selectedGroupId).toList();

                    if (filteredPrograms.isEmpty) {
                      return const EmptyStateWidget(
                        icon: Icons.list_alt_outlined,
                        title: 'Program bulunamadı',
                        description: 'Seçilen grup için program bulunamadı.',
                      );
                    }

                    return Column(
                      children: filteredPrograms.map((p) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: _parseColor(p.groupColor) ?? AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        p.groupName ?? 'Grup',
                                        style: AppTypography.bodyMedium.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  p.programContent,
                                  style: AppTypography.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(8),
                    child: LoadingWidget(size: 24),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Programlar yüklenemedi: $e',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Sıralama menüsü
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Kullanıcı İstatistikleri',
                        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    _buildSortMenu(),
                  ],
                ),
                const SizedBox(height: 12),

                // Grup üyeleri ve istatistikleri birlikte kontrol et
                if (_selectedGroupId != null && groupMembersAsync != null)
                  groupMembersAsync.when(
                    data: (members) {
                      final memberUserIds = members.map((m) => m.userId).toSet();
                      return statsAsync.when(
                        data: (stats) {
                          if (stats.isEmpty) {
                            return const EmptyStateWidget(
                              icon: Icons.directions_run,
                              title: 'Aktivite bulunamadı',
                              description: 'Bu etkinliğe bağlı aktivite kaydı yok.',
                            );
                          }

                          // Sadece seçilen gruptaki kullanıcıların istatistiklerini göster
                          final filteredStats = stats.where((s) => memberUserIds.contains(s.userId)).toList();

                          if (filteredStats.isEmpty) {
                            return const EmptyStateWidget(
                              icon: Icons.directions_run,
                              title: 'Aktivite bulunamadı',
                              description: 'Seçilen grup için aktivite kaydı yok.',
                            );
                          }

                          return _buildStatsList(filteredStats);
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.all(8),
                          child: LoadingWidget(size: 24),
                        ),
                        error: (e, _) => Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            'İstatistikler yüklenemedi: $e',
                            style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                          ),
                        ),
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.all(8),
                      child: LoadingWidget(size: 24),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Grup üyeleri yüklenemedi: $e',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                      ),
                    ),
                  )
                else
                  // Grup seçilmemişse tüm istatistikleri göster
                  statsAsync.when(
                    data: (stats) {
                      if (stats.isEmpty) {
                        return const EmptyStateWidget(
                          icon: Icons.directions_run,
                          title: 'Aktivite bulunamadı',
                          description: 'Bu etkinliğe bağlı aktivite kaydı yok.',
                        );
                      }

                      return _buildStatsList(stats);
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.all(8),
                      child: LoadingWidget(size: 24),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'İstatistikler yüklenemedi: $e',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        loading: () => const Center(child: LoadingWidget()),
        error: (e, _) => Center(
          child: ErrorStateWidget(
            title: 'Etkinlik yüklenemedi',
            message: e.toString(),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsList(List<EventActivityStatModel> stats) {
    final sorted = [...stats];
    switch (_sortType) {
      case _StatSortType.distance:
        sorted.sort((a, b) => b.totalDistanceMeters.compareTo(a.totalDistanceMeters));
        break;
      case _StatSortType.duration:
        sorted.sort((a, b) => b.totalDurationSeconds.compareTo(a.totalDurationSeconds));
        break;
      case _StatSortType.pace:
        sorted.sort((a, b) {
          final ap = a.averagePaceSecondsPerKm ?? double.infinity;
          final bp = b.averagePaceSecondsPerKm ?? double.infinity;
          return ap.compareTo(bp); // küçük pace öne
        });
        break;
    }

    return Column(
      children: sorted.map((s) {
        final distanceKm = s.totalDistanceMeters / 1000.0;
        final duration = Duration(seconds: s.totalDurationSeconds);
        final paceSec = s.averagePaceSecondsPerKm;

        String durationStr =
            '${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
        String paceStr = paceSec != null && paceSec.isFinite
            ? _formatPace(paceSec)
            : '-';

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: UserAvatar(
            size: 40,
            name: s.userName,
            imageUrl: s.avatarUrl,
          ),
          title: Text(
            s.userName,
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
                durationStr,
                style: AppTypography.bodySmall.copyWith(color: AppColors.neutral600),
              ),
              const SizedBox(width: 12),
              Icon(Icons.speed, size: 14, color: AppColors.neutral500),
              const SizedBox(width: 4),
              Text(
                '$paceStr dk/km',
                style: AppTypography.bodySmall.copyWith(color: AppColors.neutral600),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGroupFilter(List<EventGroupProgramEntity> programs) {
    // Programlardan benzersiz grupları çıkar
    final groups = <String, String?>{};
    for (final program in programs) {
      if (!groups.containsKey(program.trainingGroupId)) {
        groups[program.trainingGroupId] = program.groupName;
      }
    }

    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedGroupName = _selectedGroupId == null
        ? 'Tümü'
        : groups[_selectedGroupId] ?? 'Grup';

    return PopupMenuButton<String?>(
      initialValue: _selectedGroupId,
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
                selectedGroupName,
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
          _selectedGroupId = groupId;
        });
      },
      itemBuilder: (context) {
        return [
          const PopupMenuItem<String?>(
            value: null,
            child: Text('Tümü'),
          ),
          ...groups.entries.map((entry) {
            return PopupMenuItem<String?>(
              value: entry.key,
              child: Text(entry.value ?? 'Grup'),
            );
          }),
        ];
      },
    );
  }

  Widget _buildSortMenu() {
    String getSortLabel() {
      switch (_sortType) {
        case _StatSortType.distance:
          return 'Mesafe (km)';
        case _StatSortType.duration:
          return 'Süre';
        case _StatSortType.pace:
          return 'Pace';
      }
    }

    return PopupMenuButton<_StatSortType>(
      initialValue: _sortType,
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
          _sortType = type;
        });
      },
      itemBuilder: (context) {
        return [
          const PopupMenuItem<_StatSortType>(
            value: _StatSortType.distance,
            child: Text('Mesafe (km)'),
          ),
          const PopupMenuItem<_StatSortType>(
            value: _StatSortType.duration,
            child: Text('Süre'),
          ),
          const PopupMenuItem<_StatSortType>(
            value: _StatSortType.pace,
            child: Text('Pace'),
          ),
        ];
      },
    );
  }

  String _formatPace(double secondsPerKm) {
    final totalSeconds = secondsPerKm.round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      var value = hex.replaceAll('#', '');
      if (value.length == 6) {
        value = 'FF$value';
      }
      return Color(int.parse(value, radix: 16));
    } catch (_) {
      return null;
    }
  }
}

