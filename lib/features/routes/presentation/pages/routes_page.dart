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
enum RouteListFilter { all, race, normal }

/// Rotalar Listesi Sayfası
class RoutesPage extends ConsumerStatefulWidget {
  const RoutesPage({super.key});

  @override
  ConsumerState<RoutesPage> createState() => _RoutesPageState();
}

class _RoutesPageState extends ConsumerState<RoutesPage> {
  RouteListFilter _filter = RouteListFilter.all;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
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
          final filteredRoutes = routes.where((r) {
            switch (_filter) {
              case RouteListFilter.race:
                return r.isRace;
              case RouteListFilter.normal:
                return !r.isRace;
              case RouteListFilter.all:
                return true;
            }
          }).toList();

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
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              itemCount: filteredRoutes.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<RouteListFilter>(
                            segments: const [
                              ButtonSegment(
                                value: RouteListFilter.all,
                                label: Text('Hepsi'),
                                icon: Icon(Icons.list),
                              ),
                              ButtonSegment(
                                value: RouteListFilter.race,
                                label: Text('Yarış'),
                                icon: Icon(Icons.emoji_events),
                              ),
                              ButtonSegment(
                                value: RouteListFilter.normal,
                                label: Text('Normal'),
                                icon: Icon(Icons.map_outlined),
                              ),
                            ],
                            selected: {_filter},
                            onSelectionChanged: (Set<RouteListFilter> sel) {
                              setState(() => _filter = sel.first);
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final route = filteredRoutes[index - 1];
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
                      '${route.isRace ? 'Yarış' : 'Normal'} · ${route.terrainType.displayName} · ${route.formattedDistance} · ${route.formattedElevationGain}',
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
