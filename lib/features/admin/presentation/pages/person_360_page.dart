import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/report_info_button.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';
import '../providers/admin_reports_provider.dart';
import '../widgets/person_360_view.dart';

const _info = ReportInfo(
  title: 'Kişi 360',
  summary:
      'Tek bir üyenin tüm bilgilerini tek ekranda birleştirir: istatistik, '
      'antrenman yükü, puan, Strava ve son aktiviteler.',
  terms: [
    ReportInfoTerm('VDOT', 'Koşu performans seviyesini gösteren tahmini değer.'),
    ReportInfoTerm('CTL/ATL/TSB', 'Fitness / yorgunluk / form dengesi.'),
    ReportInfoTerm('ACWR', 'Akut/Kronik yük oranı; sakatlık riski göstergesi.'),
    ReportInfoTerm('Puan', 'Yarış katılımlarından toplanan toplam puan.'),
  ],
  takeaways: [
    'Bireysel görüşme öncesi hızlı durum özeti için kullanın.',
    'Form ve aktiflik birlikte değerlendirilince daha anlamlıdır.',
    'Performans detayına kısayoldan ulaşabilirsiniz.',
  ],
);

class Person360Page extends ConsumerStatefulWidget {
  const Person360Page({super.key});

  @override
  ConsumerState<Person360Page> createState() => _Person360PageState();
}

class _Person360PageState extends ConsumerState<Person360Page> {
  final _searchController = TextEditingController();
  String? _selectedUserId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kişi 360'),
        actions: const [ReportInfoButton(info: _info)],
      ),
      body: !isAdminOrCoach
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Bu sayfaya erişim yetkiniz yok.',
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.neutral500),
                    textAlign: TextAlign.center),
              ),
            )
          : _selectedUserId == null
              ? _buildSearch()
              : _buildDetail(_selectedUserId!),
    );
  }

  Widget _buildSearch() {
    final usersAsync = ref.watch(activeUsersProvider);
    final query = _searchController.text.toLowerCase().trim();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: AppSearchField(
            controller: _searchController,
            hint: 'Üye ara...',
            onChanged: (_) => setState(() {}),
            onClear: () => setState(() {}),
          ),
        ),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: LoadingWidget()),
            error: (e, _) => Center(child: Text('Hata: $e')),
            data: (users) {
              final filtered = query.isEmpty
                  ? users
                  : users
                      .where((u) => u.fullName.toLowerCase().contains(query))
                      .toList();
              if (filtered.isEmpty) {
                return Center(
                  child: Text('Üye bulunamadı',
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.neutral500)),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final u = filtered[i];
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: UserAvatar(
                          imageUrl: u.avatarUrl, name: u.fullName, size: 40),
                      title: Text(u.fullName),
                      subtitle: u.hasVdot
                          ? Text('VDOT ${u.vdot!.toStringAsFixed(1)}')
                          : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() => _selectedUserId = u.id),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDetail(String userId) {
    final personAsync = ref.watch(person360Provider(userId));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _selectedUserId = null),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Üye listesine dön'),
            ),
          ),
        ),
        Expanded(
          child: personAsync.when(
            loading: () => const Center(child: LoadingWidget()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Yüklenemedi', style: AppTypography.titleSmall),
                    const SizedBox(height: 8),
                    Text(e.toString(),
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.neutral500)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(person360Provider(userId)),
                      child: const Text('Tekrar Dene'),
                    ),
                  ],
                ),
              ),
            ),
            data: (p) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(person360Provider(userId));
                await ref.read(person360Provider(userId).future);
              },
              child: Person360View(person: p, showPerformanceLink: true),
            ),
          ),
        ),
      ],
    );
  }
}
