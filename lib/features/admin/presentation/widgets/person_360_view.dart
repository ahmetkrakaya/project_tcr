import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/vdot_calculator.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../data/models/admin_reports_models.dart';

/// Kisi 360 detayinin yeniden kullanilabilir gorunumu.
/// Hem admin "Kisi 360" hem de kullanicinin kendi istatistik sayfasinda kullanilir.
class Person360View extends StatelessWidget {
  const Person360View({
    super.key,
    required this.person,
    this.showPerformanceLink = false,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 32),
  });

  final Person360 person;
  final bool showPerformanceLink;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: padding,
      children: [
        _header(context, person),
        const SizedBox(height: 12),
        _quickStats(person),
        const SizedBox(height: 12),
        _trainingLoad(person),
        const SizedBox(height: 12),
        _recent(person),
      ],
    );
  }

  Widget _header(BuildContext context, Person360 p) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          UserAvatar(imageUrl: p.avatarUrl, name: p.fullName, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.fullName,
                    style: AppTypography.titleMedium
                        .copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (p.groupName != null) _chip(Icons.group, p.groupName!),
                    if (p.vdot != null)
                      _chip(Icons.speed, 'VDOT ${p.vdot!.toStringAsFixed(1)}'),
                    _chip(
                      p.stravaConnected ? Icons.link : Icons.link_off,
                      p.stravaConnected ? 'Strava bağlı' : 'Strava yok',
                      color: p.stravaConnected
                          ? AppColors.success
                          : AppColors.neutral500,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (showPerformanceLink)
            IconButton(
              tooltip: 'Performans detayı',
              icon: const Icon(Icons.monitor_heart_outlined),
              onPressed: () => context.pushNamed(
                RouteNames.adminTrainingLoadDetail,
                pathParameters: {'userId': p.userId},
                extra: p.fullName,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, {Color? color}) {
    final c = color ?? AppColors.neutral600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(label, style: AppTypography.labelSmall.copyWith(color: c)),
        ],
      ),
    );
  }

  Widget _quickStats(Person360 p) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Genel İstatistik',
              style: AppTypography.titleSmall
                  .copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('${p.totalDistanceKm.toStringAsFixed(0)} km', 'Toplam',
                  AppColors.primary),
              _stat('${p.totalActivities}', 'Aktivite', AppColors.info),
              _stat('${p.thisWeekKm.toStringAsFixed(0)} km', 'Bu Hafta',
                  AppColors.success),
              _stat('${p.totalPoints}', 'Puan', AppColors.warning),
            ],
          ),
          if (p.lastAppOpenAt != null) ...[
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.access_time,
                    size: 14, color: AppColors.neutral500),
                const SizedBox(width: 6),
                Text(
                  'Son uygulama açılışı: ${DateFormat('d MMM yyyy', 'tr').format(p.lastAppOpenAt!)}',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.neutral600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _trainingLoad(Person360 p) {
    if (p.ctl == null && p.tsb == null) return const SizedBox.shrink();
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Antrenman Yükü',
              style: AppTypography.titleSmall
                  .copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat(p.ctl?.round().toString() ?? '-', 'CTL', AppColors.info),
              _stat(p.atl?.round().toString() ?? '-', 'ATL',
                  AppColors.warning),
              _stat(
                p.tsb == null
                    ? '-'
                    : (p.tsb! >= 0 ? '+' : '') + p.tsb!.round().toString(),
                'TSB',
                (p.tsb ?? 0) >= 0 ? AppColors.success : AppColors.error,
              ),
              _stat(p.acwr?.toStringAsFixed(2) ?? '-', 'ACWR',
                  _acwrColor(p.acwr)),
            ],
          ),
        ],
      ),
    );
  }

  Color _acwrColor(double? acwr) {
    if (acwr == null) return AppColors.neutral500;
    if (acwr > 1.5 || acwr < 0.8) return AppColors.error;
    if (acwr > 1.3) return AppColors.warning;
    return AppColors.success;
  }

  Widget _recent(Person360 p) {
    if (p.recentActivities.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.all(16),
        child: Text('Son aktivite yok',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.neutral500)),
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Son Aktiviteler',
              style: AppTypography.titleSmall
                  .copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...p.recentActivities.map((a) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.directions_run,
                        size: 18, color: AppColors.neutral500),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title ?? 'Koşu',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyMedium
                                  .copyWith(fontWeight: FontWeight.w500)),
                          if (a.startTime != null)
                            Text(
                                DateFormat('d MMM', 'tr').format(a.startTime!),
                                style: AppTypography.labelSmall
                                    .copyWith(color: AppColors.neutral500)),
                        ],
                      ),
                    ),
                    Text('${a.distanceKm.toStringAsFixed(1)} km',
                        style: AppTypography.bodyMedium
                            .copyWith(fontWeight: FontWeight.w600)),
                    if (a.paceSeconds != null) ...[
                      const SizedBox(width: 10),
                      Text('${VdotCalculator.formatPace(a.paceSeconds!)}/km',
                          style: AppTypography.labelMedium
                              .copyWith(color: AppColors.neutral600)),
                    ],
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, Color color) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: AppTypography.titleSmall
                    .copyWith(fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.neutral500),
                textAlign: TextAlign.center),
          ],
        ),
      );
}
