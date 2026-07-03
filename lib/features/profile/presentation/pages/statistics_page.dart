import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../admin/presentation/providers/admin_reports_provider.dart';
import '../../../admin/presentation/widgets/person_360_view.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// İstatistikler - kullanıcının kendi "Kişi 360" özeti.
/// [userId] verilirse (admin/koç başka üyeyi görüntülerken) o üyenin verisi gösterilir.
class StatisticsPage extends ConsumerWidget {
  final String? userId;

  const StatisticsPage({super.key, this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProfileProvider);
    final targetUserId = userId ?? currentUser?.id;
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
    final isOther = userId != null && userId != currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('İstatistikler'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: targetUserId == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Kullanıcı bulunamadı.',
                    style: AppTypography.bodyMedium
                        .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
                    textAlign: TextAlign.center),
              ),
            )
          : _buildBody(ref, targetUserId, isAdminOrCoach && isOther),
    );
  }

  Widget _buildBody(WidgetRef ref, String targetUserId, bool showPerfLink) {
    final personAsync = ref.watch(person360Provider(targetUserId));

    return personAsync.when(
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
                      .copyWith(color: ThemeBrightnessHolder.onSurfaceVariant)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    ref.invalidate(person360Provider(targetUserId)),
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      ),
      data: (p) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(person360Provider(targetUserId));
          await ref.read(person360Provider(targetUserId).future);
        },
        child: Person360View(person: p, showPerformanceLink: showPerfLink),
      ),
    );
  }
}
