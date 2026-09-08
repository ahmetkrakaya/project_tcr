import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/report_info_button.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../providers/user_points_leaderboard_provider.dart';

final _dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');

const _info = ReportInfo(
  title: 'Kullanıcı Puanları',
  summary:
      'Üyelerin etkinlik katılımları ve market alışverişlerinden kazandığı '
      'puanları gösterir. Puanlar otomatik hesaplanır ve toplam puana göre '
      'sıralanır.',
  dataSources: const [
    'Etkinlik katılımları (RSVP: Katılıyorum)',
    'Market siparişleri (iptal edilmemiş)',
  ],
  calculations: const [
    ReportInfoTerm(
      'Yarış',
      'Katıldığınız yarış mesafesi kadar puan. Örn. 21 km yarış → 21 puan. '
      'Mesafe; seçilen kategori (21K vb.), rota veya aynı gün Strava koşusundan alınır.',
    ),
    ReportInfoTerm(
      'Antrenman',
      'Her katılımda 1 puan.',
    ),
    ReportInfoTerm(
      'Diğer etkinlikler',
      'Sosyal, workshop ve diğer türlerde her katılımda 2 puan.',
    ),
    ReportInfoTerm(
      'Market siparişi',
      'Sipariş tutarının yüzde 5’i kadar puan (en yakın tam sayıya yuvarlanır). '
      'Örn. 200 TL sipariş → 10 puan.',
    ),
  ],
  terms: const [
    ReportInfoTerm(
      'Katılım puanı',
      'Yalnızca “Katılıyorum” yanıtı verilen etkinlikler puan kazandırır.',
    ),
    ReportInfoTerm(
      'Toplam puan',
      'Tüm etkinlik ve sipariş puanlarının toplamı.',
    ),
  ],
  takeaways: const [
    'Liste, aktif üyeleri toplam puana göre azalan sırada gösterir.',
    'Bir üyeye dokunarak nereden ne kadar puan kazandığını görebilirsiniz.',
    'RSVP iptali veya sipariş iptali ilgili puanı geri alır.',
    'Geçmiş katılımlar ve siparişler de puan hesabına dahildir.',
  ],
);

class UserPointsLeaderboardPage extends ConsumerWidget {
  const UserPointsLeaderboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final isAdmin = ref.watch(isAdminProvider);
    final dataAsync = ref.watch(userPointsLeaderboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kullanıcı Puanları'),
        actions: const [ReportInfoButton(info: _info)],
      ),
      body: !isAdmin
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Bu sayfaya erişim yetkiniz yok.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : dataAsync.when(
              data: (items) {
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(userPointsLeaderboardProvider);
                    await ref.read(userPointsLeaderboardProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: cs.outlineVariant,
                    ),
                    itemBuilder: (context, index) {
                      final e = items[index];
                      final rank = index + 1;

                      return ListTile(
                        onTap: () => _showPointsDetail(context, e),
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            UserAvatar(
                              imageUrl: e.avatarUrl,
                              name: e.fullName,
                              size: 44,
                              showBorder: false,
                            ),
                            Positioned(
                              left: -6,
                              top: -6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: cs.surface,
                                    width: 2,
                                  ),
                                ),
                                child: Text(
                                  '$rank',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: isDark
                                        ? Colors.white
                                        : cs.onPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          e.fullName,
                          style: AppTypography.titleSmall.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.warningLight
                                    .withValues(alpha: 0.18)
                                : const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(12),
                            border: isDark
                                ? Border.all(
                                    color: AppColors.warningLight
                                        .withValues(alpha: 0.35),
                                  )
                                : null,
                          ),
                          child: Text(
                            '${e.points}',
                            style: AppTypography.titleSmall.copyWith(
                              color: isDark
                                  ? AppColors.warningLight
                                  : const Color(0xFFFF8F00),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Puanlar yüklenemedi: $err',
                    style: AppTypography.bodyMedium.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
    );
  }

  void _showPointsDetail(BuildContext context, UserPointsEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _UserPointsDetailSheet(entry: entry),
    );
  }
}

class _UserPointsDetailSheet extends ConsumerWidget {
  final UserPointsEntry entry;

  const _UserPointsDetailSheet({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final detailAsync = ref.watch(userPointsDetailProvider(entry));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  UserAvatar(
                    imageUrl: entry.avatarUrl,
                    name: entry.fullName,
                    size: 40,
                    showBorder: false,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.fullName,
                          style: AppTypography.titleMedium
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Toplam ${entry.points} puan',
                          style: AppTypography.bodySmall
                              .copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: detailAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Puan detayı alınamadı: $e',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                data: (detail) {
                  if (detail.items.isEmpty) {
                    return const Center(
                      child: Text('Henüz puan kaydı yok'),
                    );
                  }

                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _summaryChip(
                              context,
                              label: 'Etkinlik',
                              value: detail.eventPoints,
                              icon: Icons.event_outlined,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _summaryChip(
                              context,
                              label: 'Market',
                              value: detail.orderPoints,
                              icon: Icons.storefront_outlined,
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Puan geçmişi',
                        style: AppTypography.titleSmall
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...detail.items.map(
                        (item) => _PointHistoryTile(
                          item: item,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _summaryChip(
    BuildContext context, {
    required String label,
    required int value,
    required IconData icon,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: AppTypography.bodySmall),
          ),
          Text(
            '$value',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.warningLight : const Color(0xFFFF8F00),
            ),
          ),
        ],
      ),
    );
  }
}

class _PointHistoryTile extends StatelessWidget {
  final UserPointsDetailItem item;
  final bool isDark;

  const _PointHistoryTile({
    required this.item,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (item.isEvent ? cs.primary : AppColors.info)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              item.isEvent ? Icons.event_outlined : Icons.storefront_outlined,
              size: 18,
              color: item.isEvent ? cs.primary : AppColors.info,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: AppTypography.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                if (item.subtitle != null && item.subtitle!.isNotEmpty)
                  Text(
                    item.subtitle!,
                    style: AppTypography.bodySmall
                        .copyWith(color: cs.onSurfaceVariant),
                  ),
                if (item.date != null)
                  Text(
                    _dateFormat.format(item.date!),
                    style: AppTypography.labelSmall
                        .copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '+${item.points}',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.warningLight : const Color(0xFFFF8F00),
            ),
          ),
        ],
      ),
    );
  }
}
