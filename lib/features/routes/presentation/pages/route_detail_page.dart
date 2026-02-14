import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../domain/entities/route_entity.dart';
import '../providers/route_provider.dart';
import '../widgets/route_map_view.dart';
import '../widgets/elevation_chart.dart';

/// Rota Detay Sayfası
class RouteDetailPage extends ConsumerStatefulWidget {
  final String routeId;

  const RouteDetailPage({super.key, required this.routeId});

  @override
  ConsumerState<RouteDetailPage> createState() => _RouteDetailPageState();
}

class _RouteDetailPageState extends ConsumerState<RouteDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _is3DMode = false;

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

  @override
  Widget build(BuildContext context) {
    final routeAsync = ref.watch(routeByIdProvider(widget.routeId));
    final coordinatesAsync = ref.watch(routeCoordinatesProvider(widget.routeId));
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);

    return routeAsync.when(
      data: (route) => _buildContent(context, route, coordinatesAsync, isAdminOrCoach),
      loading: () => const Scaffold(
        body: Center(child: LoadingWidget()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text('Hata: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(routeByIdProvider(widget.routeId)),
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    RouteEntity route,
    AsyncValue<List<RouteCoordinate>> coordinatesAsync,
    bool isAdminOrCoach,
  ) {
    final hasGpx = route.gpxData != null && route.gpxData!.trim().isNotEmpty;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 56,
            pinned: true,
            title: Text(route.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () => _shareRoute(route),
              ),
              if (isAdminOrCoach)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        context.pushNamed(
                          RouteNames.routeEdit,
                          pathParameters: {'routeId': widget.routeId},
                        );
                        break;
                      case 'delete':
                        _showDeleteConfirmation(context);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit),
                          SizedBox(width: 8),
                          Text('Düzenle'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: AppColors.error),
                          SizedBox(width: 8),
                          Text('Rotayı Sil'),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Harita, yükseklik profili: sadece GPX varsa göster
          if (hasGpx)
            SliverToBoxAdapter(
              child: Column(
                children: [
                  // Map Container
                  Container(
                    height: 300,
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        // Map
                        coordinatesAsync.when(
                          data: (coordinates) => coordinates.isEmpty
                              ? _buildNoMapPlaceholder()
                              : RouteMapView(
                                  coordinates: coordinates,
                                  is3DMode: _is3DMode,
                                ),
                          loading: () => const Center(child: LoadingWidget()),
                          error: (_, __) => _buildNoMapPlaceholder(),
                        ),

                        // Harita stili (Harita / Uydu)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildMapStyleButton(Icons.map_outlined, 'Harita', !_is3DMode, () {
                                  setState(() => _is3DMode = false);
                                }),
                                _buildMapStyleButton(Icons.satellite_alt, 'Uydu', _is3DMode, () {
                                  setState(() => _is3DMode = true);
                                }),
                              ],
                            ),
                          ),
                        ),

                        // Fullscreen button
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: FloatingActionButton.small(
                            heroTag: 'fullscreen',
                            onPressed: () => _openFullscreenMap(context, coordinatesAsync, route),
                            backgroundColor: Colors.white,
                            child: const Icon(Icons.fullscreen, color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Elevation Chart
                  if (route.elevationProfile != null && route.elevationProfile!.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ElevationChart(
                        elevationProfile: route.elevationProfile!,
                        totalDistance: route.totalDistance ?? 0,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),

          // Rota İstatistikleri (GPX varsa) + Rota Bilgileri (her zaman)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasGpx) ...[
                    _buildStatsGrid(route),
                    const SizedBox(height: 24),
                  ],
                  _buildRouteInfo(route),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoMapPlaceholder() {
    return Container(
      color: AppColors.neutral200,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 48, color: AppColors.neutral400),
            SizedBox(height: 8),
            Text(
              'Harita verisi yok',
              style: TextStyle(color: AppColors.neutral500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapStyleButton(IconData icon, String tooltip, bool isSelected, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            icon,
            size: 22,
            color: isSelected ? Colors.white : AppColors.neutral600,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(RouteEntity route) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rota İstatistikleri',
            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatCard(
                icon: Icons.straighten,
                iconColor: AppColors.primary,
                value: route.formattedDistance,
                label: 'Toplam Mesafe',
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(
                icon: Icons.trending_up,
                iconColor: AppColors.success,
                value: route.formattedElevationGain,
                label: 'Tırmanış',
              )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard(
                icon: Icons.trending_down,
                iconColor: AppColors.error,
                value: route.elevationLoss != null 
                    ? '${route.elevationLoss!.toInt()} m' 
                    : '-',
                label: 'İniş',
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(
                icon: Icons.landscape,
                iconColor: AppColors.secondary,
                value: route.maxElevation != null 
                    ? '${route.maxElevation!.toInt()} m' 
                    : '-',
                label: 'Maksimum Yükseklik',
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: AppTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.neutral600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInfo(RouteEntity route) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rota Bilgileri',
            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (route.locationLat != null && route.locationLng != null) ...[
            _buildLocationRow(
              route: route,
              onTap: () => _openLocationInMaps(
                route.locationLat!,
                route.locationLng!,
              ),
            ),
            const Divider(height: 24),
          ],
          _buildInfoRow(
            icon: Icons.terrain,
            label: 'Tür',
            value: '${route.terrainType.icon} ${route.terrainType.displayName}',
          ),
          const Divider(height: 24),
          _buildInfoRow(
            icon: Icons.speed,
            label: 'Zorluk Seviyesi',
            value: route.difficultyText,
            valueColor: _getDifficultyColor(route.difficultyLevel),
          ),
          if (route.description != null && route.description!.isNotEmpty) ...[
            const Divider(height: 24),
            _buildInfoRow(
              icon: Icons.description,
              label: 'Açıklama',
              value: route.description!,
              isMultiline: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationRow({
    required RouteEntity route,
    required VoidCallback onTap,
  }) {
    final hasName = route.locationName != null && route.locationName!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(Icons.location_on, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Text(
              'Konum',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.neutral600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasName) ...[
                    Flexible(
                      child: Text(
                        route.locationName!,
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    'Yol Tarifi Al',
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: 16, color: AppColors.primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLocationInMaps(double lat, double lng) async {
    // Pin ile aç: Apple Maps q= ile işaretçi, Android geo:0,0?q= ile işaretçi (yol tarifi için)
    const label = 'Rota Konumu';
    // Async işlemler sonrasında context kullanmamak için messenger'ı başta al
    final messenger = ScaffoldMessenger.of(context);
    final String url = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
        ? 'https://maps.apple.com/?q=${Uri.encodeComponent(label)}@$lat,$lng'
        : (kIsWeb
            ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
            : 'geo:0,0?q=$lat,$lng(${Uri.encodeComponent(label)})');
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final fallback = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
        );
        if (await canLaunchUrl(fallback)) {
          await launchUrl(fallback, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      // Burada artık context yerine daha önce alınan messenger kullanılıyor
      messenger.showSnackBar(
        SnackBar(
          content: Text('Harita açılamadı: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool isMultiline = false,
  }) {
    return Row(
      crossAxisAlignment: isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: AppColors.neutral500),
        const SizedBox(width: 12),
        Text(
          label,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.neutral600),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
            textAlign: isMultiline ? TextAlign.start : TextAlign.end,
          ),
        ),
      ],
    );
  }

  void _shareRoute(RouteEntity route) {
    Share.share(
      'TCR Rotası: ${route.name}\n'
      '📏 ${route.formattedDistance}\n'
      '⛰️ Tırmanış: ${route.formattedElevationGain}\n'
      '${route.terrainType.icon} ${route.terrainType.displayName}',
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    final pageContext = context; // Sayfa context'i (dialog kapanınca bunu kullanacağız)
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rotayı Sil'),
        content: const Text('Bu rotayı silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await ref.read(routeDeleteProvider.notifier).deleteRoute(widget.routeId);
              if (pageContext.mounted) {
                pageContext.goNamed(RouteNames.routes);
              }
            },
            child: const Text('Sil', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _openFullscreenMap(
    BuildContext context,
    AsyncValue<List<RouteCoordinate>> coordinatesAsync,
    RouteEntity route,
  ) {
    coordinatesAsync.whenData((coordinates) {
      if (coordinates.isEmpty) return;
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _FullscreenMapPage(
            coordinates: coordinates,
            elevationProfile: route.elevationProfile,
            totalDistance: route.totalDistance,
            initialIs3D: _is3DMode,
          ),
        ),
      );
    });
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
        return const Color(0xFF7B1FA2);
      default:
        return AppColors.neutral600;
    }
  }
}

/// Fullscreen Harita Sayfası
class _FullscreenMapPage extends StatefulWidget {
  final List<RouteCoordinate> coordinates;
  final List<ElevationPoint>? elevationProfile;
  final double? totalDistance;
  final bool initialIs3D;

  const _FullscreenMapPage({
    required this.coordinates,
    this.elevationProfile,
    this.totalDistance,
    this.initialIs3D = false,
  });

  @override
  State<_FullscreenMapPage> createState() => _FullscreenMapPageState();
}

class _FullscreenMapPageState extends State<_FullscreenMapPage> {
  late bool _is3DMode;
  bool _isFlyoverActive = false;
  final GlobalKey<RouteMapViewState> _mapKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _is3DMode = widget.initialIs3D;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.arrow_back, color: AppColors.neutral700),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Flyover butonu
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _isFlyoverActive ? AppColors.primary : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                _isFlyoverActive ? Icons.stop : Icons.play_arrow,
                color: _isFlyoverActive ? Colors.white : AppColors.primary,
              ),
              tooltip: _isFlyoverActive ? 'Flyover Durdur' : 'Flyover Başlat',
              onPressed: _toggleFlyover,
            ),
          ),
          // Harita stili (Harita / Uydu)
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMapStyleButton(Icons.map_outlined, 'Harita', !_is3DMode, () {
                  setState(() => _is3DMode = false);
                }),
                _buildMapStyleButton(Icons.satellite_alt, 'Uydu', _is3DMode, () {
                  setState(() => _is3DMode = true);
                }),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          RouteMapView(
            key: _mapKey,
            coordinates: widget.coordinates,
            elevationProfile: widget.elevationProfile,
            totalDistance: widget.totalDistance,
            is3DMode: _is3DMode,
            enableFlyover: _isFlyoverActive,
            onFlyoverComplete: () {
              setState(() => _isFlyoverActive = false);
            },
          ),
          // Elevation chart artık RouteMapView içinde gösteriliyor
        ],
      ),
    );
  }

  void _toggleFlyover() {
    setState(() {
      _isFlyoverActive = !_isFlyoverActive;
      if (!_isFlyoverActive) {
        // Durdurmak için state'i güncelle
        _mapKey.currentState?.stopFlyover();
      }
    });
  }

  Widget _buildMapStyleButton(IconData icon, String tooltip, bool isSelected, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            icon,
            size: 22,
            color: isSelected ? Colors.white : AppColors.neutral600,
          ),
        ),
      ),
    );
  }
}
