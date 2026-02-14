import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/route_entity.dart';

/// Rota Harita Görünümü (flutter_map - OpenStreetMap / uydu, ücretsiz)
/// 2D harita + rota çizgisi, başlangıç/bitiş işaretleri, flyover animasyonu.
class RouteMapView extends StatefulWidget {
  final List<RouteCoordinate> coordinates;
  final List<ElevationPoint>? elevationProfile;
  final double? totalDistance;
  final bool is3DMode;
  final bool enableFlyover;
  final VoidCallback? onFlyoverComplete;

  const RouteMapView({
    super.key,
    required this.coordinates,
    this.elevationProfile,
    this.totalDistance,
    this.is3DMode = false,
    this.enableFlyover = false,
    this.onFlyoverComplete,
  });

  @override
  RouteMapViewState createState() => RouteMapViewState();
}

class RouteMapViewState extends State<RouteMapView> {
  final MapController _mapController = MapController();
  bool _isFlying = false;
  LatLng? _runnerPosition;
  bool _showStartPin = true;
  bool _showEndPin = true;
  double _flyoverProgress = 0.0;
  bool _mapReady = false;
  Size? _mapSize;
  static const double _fitPadding = 48.0;

  List<LatLng> get _latLngPoints => widget.coordinates
      .map((c) => LatLng(c.lat, c.lng))
      .toList();

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(RouteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.is3DMode != widget.is3DMode && _mapReady) {
      setState(() {});
    }
    if (widget.enableFlyover && !oldWidget.enableFlyover && !_isFlying) {
      _startFlyover();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.coordinates.isEmpty) {
      return _buildPlaceholder();
    }

    final center = _calculateCenter();
    final centerLatLng = LatLng(center.lat, center.lng);

    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            if (size.width > 0 && size.height > 0 && size != _mapSize) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && size != _mapSize) {
                  setState(() => _mapSize = size);
                  // Boyut ilk kez belli olduğunda rotayı tekrar sığdır (doğru zoom)
                  if (_mapReady) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _fitBoundsToRoute();
                    });
                  }
                }
              });
            }
            return FlutterMap(
              key: ValueKey('route_map_${widget.is3DMode}'),
              mapController: _mapController,
              options: MapOptions(
                center: centerLatLng,
                zoom: 14,
                minZoom: 4,
                maxZoom: 18,
                onMapReady: _onMapReady,
              ),
              children: [
            TileLayer(
              urlTemplate: widget.is3DMode
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'project_tcr',
              maxZoom: 19,
            ),
            // Rota çizgisi (hafif glow benzeri kalın şeffaf + ana çizgi)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: _latLngPoints,
                  strokeWidth: 10,
                  color: const Color(0xFFD84315).withValues(alpha: 0.35),
                ),
                Polyline(
                  points: _latLngPoints,
                  strokeWidth: 5,
                  color: const Color(0xFFD84315),
                ),
              ],
            ),
            MarkerLayer(
              markers: _buildMarkers(),
            ),
              ],
            );
          },
        ),
        if (_isFlying &&
            widget.elevationProfile != null &&
            widget.elevationProfile!.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _buildFlyoverElevationChart(),
          ),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (widget.coordinates.isEmpty) return markers;

    final start = widget.coordinates.first;
    final end = widget.coordinates.last;

    if (_showStartPin) {
      markers.add(
        Marker(
          point: LatLng(start.lat, start.lng),
          width: 36,
          height: 36,
          builder: (context) => _buildPinWidget(
            color: const Color(0xFF4CAF50),
            label: 'S',
          ),
        ),
      );
    }

    if (_showEndPin) {
      markers.add(
        Marker(
          point: LatLng(end.lat, end.lng),
          width: 36,
          height: 36,
          builder: (context) => _buildPinWidget(
            color: const Color(0xFFE53935),
            label: 'F',
          ),
        ),
      );
    }

    if (_runnerPosition != null) {
      markers.add(
        Marker(
          point: _runnerPosition!,
          width: 44,
          height: 44,
          builder: (context) => _buildRunnerMarker(),
        ),
      );
    }

    return markers;
  }

  Widget _buildPinWidget({required Color color, required String label}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRunnerMarker() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: const Color(0xFFFFC107).withValues(alpha: 0.4),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFFFC107),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Color(0xFF2196F3),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlyoverElevationChart() {
    final profile = widget.elevationProfile!;
    final totalDist = widget.totalDistance ?? 0;

    if (profile.isEmpty || totalDist <= 0) return const SizedBox.shrink();

    double minElev = double.infinity;
    double maxElev = -double.infinity;
    for (final point in profile) {
      if (point.elevation < minElev) minElev = point.elevation;
      if (point.elevation > maxElev) maxElev = point.elevation;
    }
    const minElevRange = 10.0;
    final elevRange = maxElev - minElev;
    final effectiveRange = elevRange > 0 ? elevRange : minElevRange;
    final paddedMin = minElev - (effectiveRange * 0.1);
    final paddedMax = maxElev + (effectiveRange * 0.1);
    final yRange = paddedMax - paddedMin;
    final leftInterval =
        (yRange > 0 ? yRange / 2 : 2.5).clamp(0.1, double.infinity);
    final bottomInterval = (totalDist / 4).clamp(0.01, double.infinity);

    final currentDistance = _flyoverProgress * totalDist;

    double currentElevation = profile.first.elevation;
    for (int i = 0; i < profile.length - 1; i++) {
      if (profile[i].distance <= currentDistance &&
          profile[i + 1].distance >= currentDistance) {
        final ratio = (currentDistance - profile[i].distance) /
            (profile[i + 1].distance - profile[i].distance);
        currentElevation = profile[i].elevation +
            (profile[i + 1].elevation - profile[i].elevation) * ratio;
        break;
      }
    }
    if (currentDistance >= profile.last.distance) {
      currentElevation = profile.last.elevation;
    }

    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 35,
                interval: leftInterval,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toInt()}m',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                interval: bottomInterval,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toStringAsFixed(1)}km',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: totalDist,
          minY: paddedMin,
          maxY: paddedMax,
          lineTouchData: const LineTouchData(enabled: false),
          extraLinesData: ExtraLinesData(
            verticalLines: [
              VerticalLine(
                x: currentDistance,
                color: AppColors.primary,
                strokeWidth: 2,
                dashArray: [4, 2],
              ),
            ],
          ),
          lineBarsData: [
            LineChartBarData(
              spots: profile.map((p) => FlSpot(p.distance, p.elevation)).toList(),
              isCurved: true,
              curveSmoothness: 0.3,
              preventCurveOverShooting: true,
              color: Colors.white,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.3),
                    Colors.white.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            LineChartBarData(
              spots: [FlSpot(currentDistance, currentElevation)],
              isCurved: false,
              color: Colors.transparent,
              barWidth: 0,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 6,
                    color: AppColors.primary,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.neutral200,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 48, color: AppColors.neutral400),
            SizedBox(height: 8),
            Text(
              'Rota koordinatları bulunamadı',
              style: TextStyle(color: AppColors.neutral500),
            ),
          ],
        ),
      ),
    );
  }

  void _onMapReady() {
    _mapReady = true;
    _fitBoundsToRoute();
    if (widget.enableFlyover) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _startFlyover();
      });
    }
  }

  void _fitBoundsToRoute() {
    if (widget.coordinates.isEmpty) return;

    final points = _latLngPoints;
    if (points.isEmpty) return;

    try {
      final bounds = LatLngBounds.fromPoints(points);
      final center = bounds.center;
      final zoom = _zoomLevelForBoundsAndSize(bounds, _mapSize);
      _mapController.move(center, zoom);
    } catch (_) {}
  }

  /// Harita boyutu ve bounds'a göre tüm rotanın görünmesi için zoom seviyesi.
  /// Web Mercator: 360° = 256 * 2^z piksel; en/boy oranı dikkate alınır.
  double _zoomLevelForBoundsAndSize(LatLngBounds bounds, Size? mapSize) {
    const minZoom = 4.0;
    const maxZoom = 18.0;

    final northEast = bounds.northEast;
    final southWest = bounds.southWest;
    double latSpan = (northEast.latitude - southWest.latitude).abs();
    double lngSpan = (northEast.longitude - southWest.longitude).abs();

    // Tek nokta veya çok dar bounds
    if (latSpan < 1e-9) latSpan = 1e-9;
    if (lngSpan < 1e-9) lngSpan = 1e-9;

    if (mapSize != null && mapSize.width > 0 && mapSize.height > 0) {
      final w = (mapSize.width - 2 * _fitPadding) * 0.92;
      final h = (mapSize.height - 2 * _fitPadding) * 0.92;
      if (w > 0 && h > 0) {
        // Web Mercator: 360° = 256*2^z piksel => 2^z = (piksel*360)/(256*derece)
        final zFromLng = math.log((w * 360) / (256 * lngSpan)) / math.ln2;
        final zFromLat = math.log((h * 360) / (256 * latSpan)) / math.ln2;
        final z = math.min(zFromLng, zFromLat).floorToDouble() - 0.3;
        return z.clamp(minZoom, maxZoom);
      }
    }

    // Boyut yoksa: en/boy oranına göre tek span ile tahmini zoom (kısa pist / geniş arazi)
    final span = math.max(latSpan, lngSpan);
    final zoom = 14 - math.log(span * 2) / math.ln2;
    return zoom.clamp(minZoom, maxZoom);
  }

  void _startFlyover() async {
    if (widget.coordinates.isEmpty || _isFlying) return;

    setState(() {
      _isFlying = true;
      _runnerPosition = LatLng(
        widget.coordinates.first.lat,
        widget.coordinates.first.lng,
      );
      _showStartPin = true;
      _showEndPin = false; // %90'da gösterilecek
    });

    final coords = widget.coordinates;

    double totalRouteDistance = 0;
    for (int i = 0; i < coords.length - 1; i++) {
      totalRouteDistance += _distanceBetween(coords[i], coords[i + 1]);
    }
    const double minSpeedMps = 35.0;
    const double maxSpeedMps = 250.0;
    final totalKm = totalRouteDistance / 1000;
    final double flyoverSpeedMps =
        (minSpeedMps + (totalKm * 15)).clamp(minSpeedMps, maxSpeedMps);

    const int frameIntervalMs = 33;
    final double metersPerFrame = flyoverSpeedMps * (frameIntervalMs / 1000);

    double totalDistanceTraveled = 0;
    int currentSegmentIndex = 0;
    double segmentProgress = 0;
    bool startMarkerRemoved = false;

    try {
      // İlk pozisyona git
      _mapController.move(
        LatLng(coords.first.lat, coords.first.lng),
        16,
      );
      await Future.delayed(const Duration(milliseconds: 500));

      while (mounted && _isFlying && currentSegmentIndex < coords.length - 1) {
        final segmentStart = coords[currentSegmentIndex];
        final segmentEnd = coords[currentSegmentIndex + 1];
        final segmentDistance = _distanceBetween(segmentStart, segmentEnd);

        if (segmentDistance < 0.1) {
          currentSegmentIndex++;
          segmentProgress = 0;
          continue;
        }

        final currentLat =
            segmentStart.lat + (segmentEnd.lat - segmentStart.lat) * segmentProgress;
        final currentLng =
            segmentStart.lng + (segmentEnd.lng - segmentStart.lng) * segmentProgress;

        setState(() {
          _runnerPosition = LatLng(currentLat, currentLng);
        });

        _mapController.move(LatLng(currentLat, currentLng), 16);

        final progressInSegment = metersPerFrame / segmentDistance;
        segmentProgress += progressInSegment;

        final currentTotalDistance =
            totalDistanceTraveled + (segmentDistance * segmentProgress);
        final newProgress = (currentTotalDistance / totalRouteDistance).clamp(0.0, 1.0);
        if ((newProgress - _flyoverProgress).abs() > 0.005) {
          setState(() => _flyoverProgress = newProgress);
        }

        if (segmentProgress >= 1.0) {
          currentSegmentIndex++;
          segmentProgress = 0;
          totalDistanceTraveled += segmentDistance;

          final progressPercent =
              ((totalDistanceTraveled / totalRouteDistance) * 100).toInt();

          if (progressPercent >= 10 && !startMarkerRemoved) {
            setState(() => _showStartPin = false);
            startMarkerRemoved = true;
          }

          if (progressPercent >= 90 && _showEndPin == false) {
            setState(() => _showEndPin = true);
          }
        }

        await Future.delayed(const Duration(milliseconds: frameIntervalMs));
      }

      if (mounted && _isFlying) {
        await Future.delayed(const Duration(milliseconds: 800));
        setState(() {
          _runnerPosition = null;
          _showStartPin = true;
          _showEndPin = true;
        });
        _fitBoundsToRoute();
        widget.onFlyoverComplete?.call();
      }
    } catch (e) {
      // ignore
    } finally {
      if (mounted) {
        setState(() {
          _isFlying = false;
          _flyoverProgress = 0.0;
          _runnerPosition = null;
          _showStartPin = true;
          _showEndPin = true;
        });
      }
    }
  }

  double _distanceBetween(RouteCoordinate p1, RouteCoordinate p2) {
    const double earthRadius = 6371000;
    final lat1Rad = p1.lat * math.pi / 180;
    final lat2Rad = p2.lat * math.pi / 180;
    final dLat = (p2.lat - p1.lat) * math.pi / 180;
    final dLng = (p2.lng - p1.lng) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  RouteCoordinate _calculateCenter() {
    if (widget.coordinates.isEmpty) {
      return const RouteCoordinate(lat: 41.0082, lng: 28.9784);
    }

    double sumLat = 0;
    double sumLng = 0;

    for (final coord in widget.coordinates) {
      sumLat += coord.lat;
      sumLng += coord.lng;
    }

    return RouteCoordinate(
      lat: sumLat / widget.coordinates.length,
      lng: sumLng / widget.coordinates.length,
    );
  }

  void stopFlyover() {
    setState(() {
      _isFlying = false;
      _runnerPosition = null;
      _showStartPin = true;
      _showEndPin = true;
    });
  }

  bool get isFlying => _isFlying;
}
