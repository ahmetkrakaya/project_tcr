import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../domain/entities/donation_entity.dart';
import '../providers/donation_provider.dart';
import '../providers/donation_stats_provider.dart';

class DonationsPage extends ConsumerStatefulWidget {
  const DonationsPage({super.key});

  @override
  ConsumerState<DonationsPage> createState() => _DonationsPageState();
}

class _DonationsPageState extends ConsumerState<DonationsPage>
    with SingleTickerProviderStateMixin {
  final Set<String> _hiddenDonationIds = <String>{};
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final donationsAsync = ref.watch(allDonationsProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bağışlar'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Bağışlar'),
            Tab(text: 'Sıralamalar'),
            Tab(text: 'İstatistikler'),
          ],
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.favorite_outline),
              tooltip: 'Vakıf Ekle',
              onPressed: () => context.pushNamed(RouteNames.foundations),
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Bağış Ekle',
            onPressed: () => context.pushNamed(RouteNames.donationCreate),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DonationsListTab(
            donationsAsync: donationsAsync,
            isAdmin: isAdmin,
            hiddenDonationIds: _hiddenDonationIds,
            onDeleteOptimistic: _deleteOptimistic,
            onRefresh: () async {
              ref.invalidate(allDonationsProvider);
            },
          ),
          _RankingsTab(
            onRefresh: () async {
              ref.invalidate(allDonationsProvider);
            },
          ),
          _StatsTab(
            onRefresh: () async {
              ref.invalidate(allDonationsProvider);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteOptimistic(DonationEntity donation) async {
    setState(() {
      _hiddenDonationIds.add(donation.id);
    });

    final success = await ref
        .read(donationDeleteProvider.notifier)
        .deleteDonation(donation.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Bağış silindi' : 'Silme sırasında hata oluştu'),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }

    if (!success) {
      setState(() {
        _hiddenDonationIds.remove(donation.id);
      });
    }
  }
}

class _DonationsListTab extends ConsumerWidget {
  final AsyncValue<List<DonationEntity>> donationsAsync;
  final bool isAdmin;
  final Set<String> hiddenDonationIds;
  final Future<void> Function(DonationEntity) onDeleteOptimistic;
  final Future<void> Function() onRefresh;

  const _DonationsListTab({
    required this.donationsAsync,
    required this.isAdmin,
    required this.hiddenDonationIds,
    required this.onDeleteOptimistic,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return donationsAsync.when(
      data: (donations) {
        final visibleDonations = donations
            .where((d) => !hiddenDonationIds.contains(d.id))
            .toList(growable: false);

        if (visibleDonations.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.volunteer_activism_outlined,
            title: 'Henüz bağış eklenmemiş',
            description:
                'Yarışlarda topladığınız bağışları buraya ekleyebilirsiniz',
          );
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: visibleDonations.length,
            itemBuilder: (context, index) {
              final donation = visibleDonations[index];
              return _DonationCard(
                donation: donation,
                rank: index + 1,
                isAdmin: isAdmin,
                onDeleteOptimistic: () => onDeleteOptimistic(donation),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: LoadingWidget()),
      error: (error, _) => Center(
        child: ErrorStateWidget(
          title: 'Bağışlar yüklenemedi',
          message: error.toString(),
          onRetry: onRefresh,
        ),
      ),
    );
  }
}

class _RankingsTab extends ConsumerStatefulWidget {
  final Future<void> Function() onRefresh;

  const _RankingsTab({required this.onRefresh});

  @override
  ConsumerState<_RankingsTab> createState() => _RankingsTabState();
}

class _RankingsTabState extends ConsumerState<_RankingsTab>
    with SingleTickerProviderStateMixin {
  late TabController _subTabController;
  String? _selectedRaceKey;
  String? _selectedFoundationName;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amountFormat = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 0,
    );

    return ref.watch(allDonationsProvider).when(
          data: (donations) {
            if (donations.isEmpty) {
              return const EmptyStateWidget(
                icon: Icons.leaderboard_outlined,
                title: 'Henüz sıralama yok',
                description: 'Bağış eklendikçe sıralamalar oluşacak',
              );
            }
            return Column(
              children: [
                TabBar(
                  controller: _subTabController,
                  tabs: const [
                    Tab(text: 'Kişi'),
                    Tab(text: 'Yarış'),
                    Tab(text: 'Vakıf'),
                  ],
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: widget.onRefresh,
                    child: TabBarView(
                      controller: _subTabController,
                      children: [
                        _UserRankingsList(amountFormat: amountFormat),
                        _RaceBasedRankingsList(
                          amountFormat: amountFormat,
                          selectedRaceKey: _selectedRaceKey,
                          onRaceSelected: (key) =>
                              setState(() => _selectedRaceKey = key),
                        ),
                        _FoundationBasedRankingsList(
                          amountFormat: amountFormat,
                          selectedFoundationName: _selectedFoundationName,
                          onFoundationSelected: (name) =>
                              setState(() => _selectedFoundationName = name),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: LoadingWidget()),
          error: (error, _) => Center(
            child: ErrorStateWidget(
              title: 'Sıralamalar yüklenemedi',
              message: error.toString(),
              onRetry: widget.onRefresh,
            ),
          ),
        );
  }
}

class _UserRankingsList extends ConsumerWidget {
  final NumberFormat amountFormat;

  const _UserRankingsList({required this.amountFormat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(donationUserRankingsProvider);
    return async.when(
      data: (rankings) {
        if (rankings.isEmpty) {
          return const Center(
            child: Text('Henüz veri yok'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: rankings.length,
          itemBuilder: (context, index) {
            final r = rankings[index];
            return _UserRankingCard(
              ranking: r,
              rank: index + 1,
              amountFormat: amountFormat,
              subtitle: '${r.raceCount} yarışta',
            );
          },
        );
      },
      loading: () => const Center(child: LoadingWidget()),
      error: (e, _) => Center(child: Text('Hata: $e')),
    );
  }
}

class _UserRankingCard extends StatelessWidget {
  final DonationUserRanking ranking;
  final int rank;
  final NumberFormat amountFormat;
  final String? subtitle;

  const _UserRankingCard({
    required this.ranking,
    required this.rank,
    required this.amountFormat,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _RankBadge(rank: rank),
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 20,
              backgroundImage: ranking.userAvatarUrl != null
                  ? NetworkImage(ranking.userAvatarUrl!)
                  : null,
              child: ranking.userAvatarUrl == null
                  ? Text(
                      ranking.userName.isNotEmpty
                          ? ranking.userName[0].toUpperCase()
                          : '?',
                      style: AppTypography.titleSmall.copyWith(color: AppColors.primary),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ranking.userName,
                    style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
                    ),
                ],
              ),
            ),
            Text(
              amountFormat.format(ranking.totalAmount),
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RaceBasedRankingsList extends ConsumerWidget {
  final NumberFormat amountFormat;
  final String? selectedRaceKey;
  final void Function(String?) onRaceSelected;

  const _RaceBasedRankingsList({
    required this.amountFormat,
    required this.selectedRaceKey,
    required this.onRaceSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final racesAsync = ref.watch(donationRaceRankingsProvider);

    return racesAsync.when(
      data: (races) {
        if (races.isEmpty) {
          return const Center(
            child: Text('Henüz bağış açılmış yarış yok'),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: DropdownButtonFormField<String>(
                value: selectedRaceKey,
                decoration: InputDecoration(
                  labelText: 'Yarış',
                  hintText: 'Yarış seçin',
                  prefixIcon: const Icon(Icons.directions_run),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: races.map((r) {
                  return DropdownMenuItem(
                    value: r.raceKey,
                    child: Text(
                      r.raceName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: onRaceSelected,
              ),
            ),
            if (selectedRaceKey != null)
              Expanded(
                child: _UserRankingsByRaceList(
                  raceKey: selectedRaceKey!,
                  amountFormat: amountFormat,
                ),
              )
            else
              const Expanded(
                child: Center(
                  child: Text('Sıralama için yukarıdan bir yarış seçin'),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: LoadingWidget()),
      error: (e, _) => Center(child: Text('Hata: $e')),
    );
  }
}

class _UserRankingsByRaceList extends ConsumerWidget {
  final String raceKey;
  final NumberFormat amountFormat;

  const _UserRankingsByRaceList({
    required this.raceKey,
    required this.amountFormat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(donationUserRankingsByRaceProvider(raceKey));

    return async.when(
      data: (rankings) {
        if (rankings.isEmpty) {
          return const Center(child: Text('Bu yarışta henüz bağış kaydı yok'));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: rankings.length,
          itemBuilder: (context, index) {
            final r = rankings[index];
            return _UserRankingCard(
              ranking: r,
              rank: index + 1,
              amountFormat: amountFormat,
              subtitle: null,
            );
          },
        );
      },
      loading: () => const Center(child: LoadingWidget()),
      error: (e, _) => Center(child: Text('Hata: $e')),
    );
  }
}

class _FoundationBasedRankingsList extends ConsumerWidget {
  final NumberFormat amountFormat;
  final String? selectedFoundationName;
  final void Function(String?) onFoundationSelected;

  const _FoundationBasedRankingsList({
    required this.amountFormat,
    required this.selectedFoundationName,
    required this.onFoundationSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foundationsAsync = ref.watch(donationFoundationRankingsProvider);

    return foundationsAsync.when(
      data: (foundations) {
        if (foundations.isEmpty) {
          return const Center(
            child: Text('Henüz bağış açılmış vakıf yok'),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: DropdownButtonFormField<String>(
                value: selectedFoundationName,
                decoration: InputDecoration(
                  labelText: 'Vakıf',
                  hintText: 'Vakıf seçin',
                  prefixIcon: const Icon(Icons.favorite_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: foundations.map((f) {
                  return DropdownMenuItem(
                    value: f.foundationName,
                    child: Text(
                      f.foundationName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: onFoundationSelected,
              ),
            ),
            if (selectedFoundationName != null)
              Expanded(
                child: _UserRankingsByFoundationList(
                  foundationName: selectedFoundationName!,
                  amountFormat: amountFormat,
                ),
              )
            else
              const Expanded(
                child: Center(
                  child: Text('Sıralama için yukarıdan bir vakıf seçin'),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: LoadingWidget()),
      error: (e, _) => Center(child: Text('Hata: $e')),
    );
  }
}

class _UserRankingsByFoundationList extends ConsumerWidget {
  final String foundationName;
  final NumberFormat amountFormat;

  const _UserRankingsByFoundationList({
    required this.foundationName,
    required this.amountFormat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      donationUserRankingsByFoundationProvider(foundationName),
    );

    return async.when(
      data: (rankings) {
        if (rankings.isEmpty) {
          return const Center(
            child: Text('Bu vakıf için henüz bağış kaydı yok'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: rankings.length,
          itemBuilder: (context, index) {
            final r = rankings[index];
            return _UserRankingCard(
              ranking: r,
              rank: index + 1,
              amountFormat: amountFormat,
              subtitle: '${r.raceCount} yarışta',
            );
          },
        );
      },
      loading: () => const Center(child: LoadingWidget()),
      error: (e, _) => Center(child: Text('Hata: $e')),
    );
  }
}

class _StatsTab extends ConsumerWidget {
  final Future<void> Function() onRefresh;

  const _StatsTab({required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amountFormat = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 0,
    );

    return ref.watch(donationTcrStatsProvider).when(
          data: (stats) {
            if (stats.grandTotal == 0 && stats.raceBreakdowns.isEmpty && stats.foundationBreakdowns.isEmpty) {
              return const EmptyStateWidget(
                icon: Icons.analytics_outlined,
                title: 'Henüz istatistik yok',
                description: 'Bağış eklendikçe TCR istatistikleri oluşacak',
              );
            }
            return RefreshIndicator(
              onRefresh: onRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      color: AppColors.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TCR Toplam Bağış',
                              style: AppTypography.titleMedium.copyWith(
                                color: AppColors.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              amountFormat.format(stats.grandTotal),
                              style: AppTypography.headlineMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Yarış Bazlı Toplamlar',
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.neutral700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...stats.raceBreakdowns.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            leading: const Icon(Icons.directions_run, color: AppColors.primary),
                            title: Text(r.raceName, style: AppTypography.titleSmall),
                            subtitle: Text('${r.donorCount} kişi katkı sağladı'),
                            trailing: Text(
                              amountFormat.format(r.totalAmount),
                              style: AppTypography.titleSmall.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Vakıf Bazlı Toplamlar',
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.neutral700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...stats.foundationBreakdowns.map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            leading: Icon(Icons.favorite, color: AppColors.error.withValues(alpha: 0.7)),
                            title: Text(f.foundationName, style: AppTypography.titleSmall),
                            subtitle: Text('${f.donorCount} kişi katkı sağladı'),
                            trailing: Text(
                              amountFormat.format(f.totalAmount),
                              style: AppTypography.titleSmall.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const Center(child: LoadingWidget()),
          error: (error, _) => Center(
            child: ErrorStateWidget(
              title: 'İstatistikler yüklenemedi',
              message: error.toString(),
              onRetry: onRefresh,
            ),
          ),
        );
  }
}

class _DonationCard extends ConsumerWidget {
  final DonationEntity donation;
  final int rank;
  final bool isAdmin;
  final Future<void> Function() onDeleteOptimistic;

  const _DonationCard({
    required this.donation,
    required this.rank,
    required this.isAdmin,
    required this.onDeleteOptimistic,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwn = donation.userId == currentUserId;
    final canDelete = isOwn || isAdmin;
    final canEdit = isOwn && donation.canEdit;
    final dateFormat = DateFormat('d MMM yyyy', 'tr_TR');
    final amountFormat = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 0,
    );

    final card = Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isOwn
            ? BorderSide(
                color: AppColors.primary.withValues(alpha: 0.3), width: 1)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _RankBadge(rank: rank),
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 20,
              backgroundImage: donation.userAvatarUrl != null
                  ? NetworkImage(donation.userAvatarUrl!)
                  : null,
              child: donation.userAvatarUrl == null
                  ? Text(
                      donation.userName.isNotEmpty
                          ? donation.userName[0].toUpperCase()
                          : '?',
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    donation.userName,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        donation.isFromEvent
                            ? Icons.event
                            : Icons.directions_run,
                        size: 13,
                        color: AppColors.neutral500,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          donation.displayRaceName,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.neutral600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.favorite,
                        size: 13,
                        color: AppColors.error.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          donation.foundationName,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    dateFormat.format(donation.effectiveRaceDate),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.neutral400,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amountFormat.format(donation.amount),
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                if (canEdit)
                  InkWell(
                    onTap: () => _showUpdateDialog(context, ref),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.edit,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            'Güncelle',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    if (!canDelete) return card;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Dismissible(
        key: ValueKey(donation.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _confirmDelete(context),
        onDismissed: (_) => onDeleteOptimistic(),
        dismissThresholds: const {DismissDirection.endToStart: 0.4},
        background: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.error,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: child,
              );
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.delete_outline, color: Colors.white, size: 28),
                const SizedBox(height: 4),
                Text(
                  'Sil',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        child: card,
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bağışı Sil'),
        content: Text(
          '${donation.userName} - ${donation.displayRaceName} bağışını silmek istediğinizden emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Sil',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showUpdateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(
      text: donation.amount.toStringAsFixed(0),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bağış Tutarını Güncelle'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Tutar (₺)',
            prefixText: '₺ ',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text.trim());
              if (amount == null || amount <= 0) return;
              Navigator.pop(ctx);
              final success = await ref
                  .read(donationUpdateProvider.notifier)
                  .updateAmount(donation.id, amount);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Bağış tutarı güncellendi'
                          : 'Güncelleme sırasında hata oluştu',
                    ),
                    backgroundColor:
                        success ? AppColors.success : AppColors.error,
                  ),
                );
              }
            },
            child: const Text('Güncelle'),
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;

    switch (rank) {
      case 1:
        bgColor = const Color(0xFFFFD700);
        textColor = const Color(0xFF5D4E00);
        break;
      case 2:
        bgColor = const Color(0xFFC0C0C0);
        textColor = const Color(0xFF4A4A4A);
        break;
      case 3:
        bgColor = const Color(0xFFCD7F32);
        textColor = Colors.white;
        break;
      default:
        bgColor = AppColors.neutral200;
        textColor = AppColors.neutral600;
    }

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: AppTypography.labelSmall.copyWith(
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}
