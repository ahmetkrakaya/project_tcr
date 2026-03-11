import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../events/domain/entities/event_entity.dart';
import '../../domain/entities/club_race_entity.dart';
import '../providers/club_race_provider.dart';

/// TCR Yarışlar Sayfası
class ClubRacesPage extends ConsumerWidget {
  const ClubRacesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final racesAsync = ref.watch(allClubRacesProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TCR Yarışları'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Yeni Yarış Ekle',
              onPressed: () => context.pushNamed(RouteNames.clubRaceCreate),
            ),
        ],
      ),
      body: racesAsync.when(
        data: (races) {
          if (races.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.emoji_events_outlined,
              title: 'Henüz yarış eklenmemiş',
              description: 'TCR yarış takvimi burada görünecek',
            );
          }

          final upcomingRaces = races.where((r) => !r.isPast).toList();
          final pastRaces = races.where((r) => r.isPast).toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(allClubRacesProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (upcomingRaces.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.upcoming,
                    title: 'Yaklaşan Yarışlar',
                    iconColor: AppColors.primary,
                  ),
                  const SizedBox(height: 12),
                  ...upcomingRaces.map((race) => _RaceCard(
                        race: race,
                        isAdmin: isAdmin,
                      )),
                ],
                if (upcomingRaces.isNotEmpty && pastRaces.isNotEmpty)
                  const SizedBox(height: 24),
                if (pastRaces.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.history,
                    title: 'Geçmiş Yarışlar',
                    iconColor: AppColors.neutral500,
                  ),
                  const SizedBox(height: 12),
                  ...pastRaces.map((race) => _RaceCard(
                        race: race,
                        isAdmin: isAdmin,
                        isPast: true,
                      )),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: LoadingWidget()),
        error: (error, _) => Center(
          child: ErrorStateWidget(
            title: 'Yarışlar yüklenemedi',
            message: error.toString(),
            onRetry: () => ref.invalidate(allClubRacesProvider),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color iconColor;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _RaceCard extends ConsumerStatefulWidget {
  final ClubRaceEntity race;
  final bool isAdmin;
  final bool isPast;

  const _RaceCard({
    required this.race,
    required this.isAdmin,
    this.isPast = false,
  });

  @override
  ConsumerState<_RaceCard> createState() => _RaceCardState();
}

class _RaceCardState extends ConsumerState<_RaceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;
  bool _isActionsVisible = false;

  static const double _actionWidth = 68.0;

  double get _totalActionsWidth => _actionWidth * 3;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(-_totalActionsWidth, 0),
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _toggleActions() {
    if (_isActionsVisible) {
      _slideController.reverse();
    } else {
      _slideController.forward();
    }
    _isActionsVisible = !_isActionsVisible;
  }

  void _closeActions() {
    if (_isActionsVisible) {
      _slideController.reverse();
      _isActionsVisible = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final race = widget.race;
    final dateFormat = DateFormat('d MMMM yyyy, EEEE', 'tr_TR');
    final daysUntil = race.date.difference(DateTime.now()).inDays;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: null,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  // Arka plan: aksiyon butonları
                  if (widget.isAdmin)
                    Positioned.fill(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _ActionButton(
                            icon: Icons.event,
                            label: 'Etkinlik',
                            color: AppColors.primary,
                            onTap: () {
                              _closeActions();
                              _createEventFromRace(context, race);
                            },
                          ),
                          _ActionButton(
                            icon: Icons.edit,
                            label: 'Düzenle',
                            color: AppColors.warning,
                            onTap: () {
                              _closeActions();
                              context.pushNamed(
                                RouteNames.clubRaceEdit,
                                pathParameters: {'raceId': race.id},
                                extra: race,
                              );
                            },
                          ),
                          _ActionButton(
                            icon: Icons.delete,
                            label: 'Sil',
                            color: AppColors.error,
                            onTap: () {
                              _closeActions();
                              _showDeleteDialog(context, ref, race);
                            },
                          ),
                        ],
                      ),
                    ),

                  // Ön plan: kart içeriği
                  AnimatedBuilder(
                    animation: _slideAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: widget.isAdmin ? _slideAnimation.value : Offset.zero,
                        child: child,
                      );
                    },
                    child: GestureDetector(
                      onHorizontalDragEnd: widget.isAdmin
                          ? (details) {
                              if (details.primaryVelocity != null &&
                                  details.primaryVelocity! < -200) {
                                if (!_isActionsVisible) _toggleActions();
                              } else if (details.primaryVelocity != null &&
                                  details.primaryVelocity! > 200) {
                                if (_isActionsVisible) _toggleActions();
                              }
                            }
                          : null,
                      onTap: _isActionsVisible ? _closeActions : null,
                      child: _buildCardContent(
                        context,
                        race,
                        dateFormat,
                        daysUntil,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCardContent(
    BuildContext context,
    ClubRaceEntity race,
    DateFormat dateFormat,
    int daysUntil,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: widget.isPast ? 0 : 1,
      color: widget.isPast
          ? Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.5)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: widget.isPast
            ? BorderSide.none
            : BorderSide(
                color: AppColors.primary.withValues(alpha: 0.15),
                width: 1,
              ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DateBadge(date: race.date, isPast: widget.isPast),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        race.name,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: widget.isPast ? AppColors.neutral500 : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: widget.isPast
                                ? AppColors.neutral400
                                : AppColors.neutral600,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              race.location,
                              style: AppTypography.bodySmall.copyWith(
                                color: widget.isPast
                                    ? AppColors.neutral400
                                    : AppColors.neutral600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (race.distance != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.straighten,
                              size: 14,
                              color: widget.isPast
                                  ? AppColors.neutral400
                                  : AppColors.neutral600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              race.distance!,
                              style: AppTypography.bodySmall.copyWith(
                                color: widget.isPast
                                    ? AppColors.neutral400
                                    : AppColors.neutral600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (race.description != null && race.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                race.description!,
                style: AppTypography.bodySmall.copyWith(
                  color: widget.isPast
                      ? AppColors.neutral400
                      : AppColors.neutral600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 12,
                  color: widget.isPast ? AppColors.neutral400 : AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  dateFormat.format(race.date),
                  style: AppTypography.labelSmall.copyWith(
                    color:
                        widget.isPast ? AppColors.neutral400 : AppColors.primary,
                  ),
                ),
                if (!widget.isPast && daysUntil >= 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: daysUntil <= 7
                          ? AppColors.error.withValues(alpha: 0.1)
                          : AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      daysUntil == 0
                          ? 'Bugün!'
                          : daysUntil == 1
                              ? 'Yarın'
                              : '$daysUntil gün',
                      style: AppTypography.labelSmall.copyWith(
                        color: daysUntil <= 7
                            ? AppColors.error
                            : AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _createEventFromRace(BuildContext context, ClubRaceEntity race) {
    context.pushNamed(
      RouteNames.createEvent,
      extra: <String, dynamic>{
        'title': race.name,
        'description': race.description,
        'eventType': EventType.race,
        'startDate': race.date,
        'startTime': const TimeOfDay(hour: 9, minute: 0),
        if (race.locationLat != null) 'locationLat': race.locationLat,
        if (race.locationLng != null) 'locationLng': race.locationLng,
        if (race.location.isNotEmpty) 'locationName': race.location,
      },
    );
  }

  void _showDeleteDialog(
      BuildContext context, WidgetRef ref, ClubRaceEntity race) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yarışı Sil'),
        content:
            Text('${race.name} yarışını silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ref
                  .read(clubRaceDeleteProvider.notifier)
                  .deleteRace(race.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Yarış silindi'
                          : 'Yarış silinirken hata oluştu',
                    ),
                    backgroundColor:
                        success ? AppColors.success : AppColors.error,
                  ),
                );
              }
            },
            child: Text(
              'Sil',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        color: color,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  final DateTime date;
  final bool isPast;

  const _DateBadge({required this.date, required this.isPast});

  @override
  Widget build(BuildContext context) {
    final dayFormat = DateFormat('dd');
    final monthFormat = DateFormat('MMM', 'tr_TR');

    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isPast
            ? AppColors.neutral200
            : AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dayFormat.format(date),
            style: AppTypography.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: isPast ? AppColors.neutral500 : AppColors.primary,
              height: 1,
            ),
          ),
          Text(
            monthFormat.format(date).toUpperCase(),
            style: AppTypography.labelSmall.copyWith(
              color: isPast ? AppColors.neutral400 : AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
