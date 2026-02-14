import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../domain/entities/route_entity.dart';
import '../providers/route_provider.dart';

/// Rotalar Listesi Sayfası
class RoutesPage extends ConsumerWidget {
  const RoutesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routesAsync = ref.watch(allRoutesProvider);
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rotalar'),
        actions: [
          if (isAdminOrCoach)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => context.pushNamed(RouteNames.routeCreate),
            ),
        ],
      ),
      body: routesAsync.when(
        data: (routes) {
          if (routes.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.route,
              title: 'Henüz rota yok',
              description: isAdminOrCoach 
                  ? 'İsim ve konum girerek yeni rota ekleyin'
                  : 'Henüz rota eklenmemiş',
              buttonText: isAdminOrCoach ? 'Rota Ekle' : null,
              onButtonPressed: isAdminOrCoach 
                  ? () => context.pushNamed(RouteNames.routeCreate)
                  : null,
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(allRoutesProvider);
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: routes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final route = routes[index];
                return _RouteListTile(
                  route: route,
                  onTap: () => context.pushNamed(
                    RouteNames.routeDetail,
                    pathParameters: {'routeId': route.id},
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: LoadingWidget()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text('Hata: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(allRoutesProvider),
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kompakt rota liste satırı
class _RouteListTile extends StatelessWidget {
  final RouteEntity route;
  final VoidCallback onTap;

  const _RouteListTile({
    required this.route,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final difficultyColor = _getDifficultyColor(route.difficultyLevel);
    return Material(
      color: Theme.of(context).cardColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Zorluk rengi çubuğu
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                  color: difficultyColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              // İçerik
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      route.name,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${route.terrainType.displayName} · ${route.formattedDistance} · ${route.formattedElevationGain}',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.neutral500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.neutral400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getDifficultyColor(int level) {
    switch (level) {
      case 1:
        return AppColors.success;
      case 2:
        return AppColors.secondaryLight;
      case 3:
        return AppColors.warning;
      case 4:
        return AppColors.error;
      case 5:
        return const Color(0xFF7B1FA2); // Purple
      default:
        return AppColors.neutral600;
    }
  }
}
