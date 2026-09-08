import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/route_entity.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// Rota Harita Görünümü (flutter_map - OpenStreetMap / uydu, ücretsiz)
/// 2D harita + rota çizgisi, başlangıç/bitiş işaretleri, flyover animasyonu.
class RouteMapView extends StatefulWidget {
  final List<RouteCoordinate> coordinates;
  final List<ElevationPoint>? elevationProfile;
  final double? totalDistance;
  final bool is3DMode;
  final bool enableFlyover;
  final VoidCallback? onFlyoverComplete;
  final VoidCallback? onFlyoverPaused;

  const RouteMapView({
    super.key,
    required this.coordinates,
    this.elevationProfile,
    this.totalDistance,
    this.is3DMode = false,
    this.enableFlyover = false,
    this.onFlyoverComplete,
    this.onFlyoverPaused,
  });

  @override
  RouteMapViewState createState() => RouteMapViewState();
}

class RouteMapViewState extends State<RouteMapView> {
  final MapController _mapController = MapController();
  bool _isFlying = false;
  bool _isPaused = false;
  int _flyoverRunId = 0;
  LatLng? _runnerPosition;
  bool _showStartPin = true;
  bool _showEndPin = true;
  double _flyoverProgress = 0.0;
  int _segmentIndex = 0;
  double _segmentProgress = 0;
  double _totalDistanceTraveled = 0;
  bool _startMarkerRemoved = false;
  bool _mapReady = false;
  Size? _mapSize;
  List<double> _cumulativeMeters = const [];
  double _totalRouteMeters = 0;
  static const double _fitPadding = 48.0;
  static const double _flyoverFollowZoom = 16.0;
  static const double _routeHitSlopPx = 56.0;

  bool get _hasElevationChart =>
      widget.elevationProfile != null && widget.elevationProfile!.isNotEmpty;

  List<LatLng> get _latLngPoints => widget.coordinates
      .map((c) => LatLng(c.lat, c.lng))
      .toList();

  @override
  void initState() {
    super.initState();
    _rebuildRouteMetrics();
    if (_hasElevationChart && widget.coordinates.isNotEmpty) {
      _applyProgress(0);
    }
  }

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
    if (!identical(oldWidget.coordinates, widget.coordinates)) {
      _rebuildRouteMetrics();
      if (_hasElevationChart && widget.coordinates.isNotEmpty) {
        _applyProgress(_flyoverProgress);
      }
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
        if (_hasElevationChart)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onTapDown: (details) => _seekFromMapLocal(details.localPosition),
              onPanStart: (details) => _seekFromMapLocal(details.localPosition),
              onPanUpdate: (details) => _seekFromMapLocal(details.localPosition),
              child: _RouteScrubHitTarget(isNearRoute: _isNearRouteLocal),
            ),
          ),
        if (_hasElevationChart)
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
          width: 52,
          height: 52,
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

    const leftAxis = 35.0;
    const bottomAxis = 18.0;
    const padLeft = 8.0;
    const padRight = 8.0;
    const padTop = 8.0;
    const padBottom = 4.0;
    const popupWidth = 86.0;
    const popupHeight = 44.0;

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plotLeft = padLeft + leftAxis;
          final plotTop = padTop;
          final plotWidth =
              (constraints.maxWidth - plotLeft - padRight).clamp(1.0, double.infinity);
          final plotHeight = (constraints.maxHeight - plotTop - padBottom - bottomAxis)
              .clamp(1.0, double.infinity);

          final t = (currentDistance / totalDist).clamp(0.0, 1.0);
          final elevT = yRange > 0
              ? ((currentElevation - paddedMin) / yRange).clamp(0.0, 1.0)
              : 0.5;
          final dotX = plotLeft + t * plotWidth;
          final dotY = plotTop + plotHeight * (1 - elevT);

          var popupLeft = dotX - popupWidth / 2;
          popupLeft = popupLeft.clamp(4.0, constraints.maxWidth - popupWidth - 4);
          final popupTop = (dotY - popupHeight - 6).clamp(-36.0, plotTop + plotHeight - 8);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                _seekFromChartLocalX(details.localPosition.dx, plotLeft, plotWidth),
            onPanStart: (details) =>
                _seekFromChartLocalX(details.localPosition.dx, plotLeft, plotWidth),
            onPanUpdate: (details) =>
                _seekFromChartLocalX(details.localPosition.dx, plotLeft, plotWidth),
            child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(padLeft, padTop, padRight, padBottom),
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: leftAxis,
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
                          reservedSize: bottomAxis,
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
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
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
                        spots: profile
                            .map((p) => FlSpot(p.distance, p.elevation))
                            .toList(),
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
                  duration: Duration.zero,
                ),
              ),
              Positioned(
                left: popupLeft,
                top: popupTop,
                width: popupWidth,
                child: IgnorePointer(
                  child: _buildKmElevationPopup(currentDistance, currentElevation),
                ),
              ),
            ],
          ),
          );
        },
      ),
    );
  }

  Widget _buildKmElevationPopup(double km, double elevation) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${km.toStringAsFixed(2)} km',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              Text(
                '${elevation.round()} m',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -6),
          child: Icon(
            Icons.arrow_drop_down,
            color: AppColors.primary,
            size: 18,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.neutral200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 48, color: ThemeBrightnessHolder.outline),
            SizedBox(height: 8),
            Text(
              'Rota koordinatları bulunamadı',
              style: TextStyle(color: ThemeBrightnessHolder.onSurfaceVariant),
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
      final fitSize = _hasElevationChart && _mapSize != null
          ? Size(_mapSize!.width, math.max(1, _mapSize!.height - 148))
          : _mapSize;
      final zoom = _zoomLevelForBoundsAndSize(bounds, fitSize);
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

    final atEnd = _flyoverProgress >= 0.999;
    final resuming =
        !atEnd && _runnerPosition != null && _flyoverProgress > 0.001;
    final runId = ++_flyoverRunId;

    setState(() {
      _isFlying = true;
      _isPaused = false;
      if (!resuming) {
        _runnerPosition = LatLng(
          widget.coordinates.first.lat,
          widget.coordinates.first.lng,
        );
        _showStartPin = true;
        _showEndPin = false;
        _flyoverProgress = 0.0;
        _segmentIndex = 0;
        _segmentProgress = 0;
        _totalDistanceTraveled = 0;
        _startMarkerRemoved = false;
      } else {
        _startMarkerRemoved = _flyoverProgress >= 0.10;
        _showStartPin = !_startMarkerRemoved;
        _showEndPin = _flyoverProgress >= 0.90;
      }
    });

    final coords = widget.coordinates;

    double totalRouteDistance = 0;
    for (int i = 0; i < coords.length - 1; i++) {
      totalRouteDistance += _distanceBetween(coords[i], coords[i + 1]);
    }
    if (totalRouteDistance <= 0) {
      _clearFlyover();
      widget.onFlyoverComplete?.call();
      return;
    }

    const double minSpeedMps = 35.0;
    const double maxSpeedMps = 250.0;
    final totalKm = totalRouteDistance / 1000;
    final double flyoverSpeedMps =
        (minSpeedMps + (totalKm * 15)).clamp(minSpeedMps, maxSpeedMps);

    const int frameIntervalMs = 33;
    final double metersPerFrame = flyoverSpeedMps * (frameIntervalMs / 1000);

    try {
      if (!resuming) {
        _mapController.move(
          LatLng(coords.first.lat, coords.first.lng),
          _flyoverFollowZoom,
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted || runId != _flyoverRunId || !_isFlying) return;
      } else if (_runnerPosition != null) {
        _mapController.move(_runnerPosition!, _flyoverFollowZoom);
      }

      while (mounted &&
          _isFlying &&
          runId == _flyoverRunId &&
          _segmentIndex < coords.length - 1) {
        final segmentStart = coords[_segmentIndex];
        final segmentEnd = coords[_segmentIndex + 1];
        final segmentDistance = _distanceBetween(segmentStart, segmentEnd);

        if (segmentDistance < 0.1) {
          _segmentIndex++;
          _segmentProgress = 0;
          continue;
        }

        final currentLat = segmentStart.lat +
            (segmentEnd.lat - segmentStart.lat) * _segmentProgress;
        final currentLng = segmentStart.lng +
            (segmentEnd.lng - segmentStart.lng) * _segmentProgress;
        final currentTotalDistance =
            _totalDistanceTraveled + (segmentDistance * _segmentProgress);
        final newProgress =
            (currentTotalDistance / totalRouteDistance).clamp(0.0, 1.0);

        setState(() {
          _runnerPosition = LatLng(currentLat, currentLng);
          _flyoverProgress = newProgress;
        });

        _mapController.move(
          LatLng(currentLat, currentLng),
          _flyoverFollowZoom,
        );

        _segmentProgress += metersPerFrame / segmentDistance;

        if (_segmentProgress >= 1.0) {
          _segmentIndex++;
          _segmentProgress = 0;
          _totalDistanceTraveled += segmentDistance;

          final progressPercent =
              ((_totalDistanceTraveled / totalRouteDistance) * 100).toInt();

          if (progressPercent >= 10 && !_startMarkerRemoved) {
            setState(() => _showStartPin = false);
            _startMarkerRemoved = true;
          }

          if (progressPercent >= 90 && !_showEndPin) {
            setState(() => _showEndPin = true);
          }
        }

        await Future.delayed(const Duration(milliseconds: frameIntervalMs));
      }

      if (!mounted || runId != _flyoverRunId || !_isFlying) return;

      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted || runId != _flyoverRunId || !_isFlying) return;

      _fitBoundsToRoute();
      _clearFlyover();
      widget.onFlyoverComplete?.call();
    } catch (_) {
      if (mounted && runId == _flyoverRunId && !_isPaused) {
        _clearFlyover();
      }
    }
  }

  void _clearFlyover() {
    setState(() {
      _isFlying = false;
      _isPaused = false;
      _showStartPin = true;
      _showEndPin = true;
      _startMarkerRemoved = false;
    });
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
    if (!_isFlying && !_isPaused) return;
    _flyoverRunId++;
    setState(() {
      _isFlying = false;
      _isPaused = _runnerPosition != null;
      _showStartPin = true;
      _showEndPin = true;
    });
  }

  bool get isFlying => _isFlying;

  bool get isPaused => _isPaused;

  void _pausePlaybackForScrub() {
    if (!_isFlying) return;
    _flyoverRunId++;
    _isFlying = false;
    _isPaused = true;
    _showStartPin = true;
    _showEndPin = true;
    widget.onFlyoverPaused?.call();
  }

  void _rebuildRouteMetrics() {
    final coords = widget.coordinates;
    if (coords.length < 2) {
      _cumulativeMeters = const [0];
      _totalRouteMeters = 0;
      return;
    }
    final cumulative = List<double>.filled(coords.length, 0);
    for (int i = 1; i < coords.length; i++) {
      cumulative[i] = cumulative[i - 1] + _distanceBetween(coords[i - 1], coords[i]);
    }
    _cumulativeMeters = cumulative;
    _totalRouteMeters = cumulative.last;
  }

  void _seekFromChartLocalX(double localX, double plotLeft, double plotWidth) {
    if (plotWidth <= 0) return;
    _seekToProgress(((localX - plotLeft) / plotWidth).clamp(0.0, 1.0));
  }

  void _seekFromMapLocal(Offset local) {
    if (!_mapReady) return;
    try {
      final latlng =
          _mapController.pointToLatLng(CustomPoint(local.dx, local.dy));
      final hit = _nearestOnRoute(latlng);
      if (hit != null) _seekToProgress(hit.progress);
    } catch (_) {}
  }

  bool _isNearRouteLocal(Offset local) {
    if (!_mapReady || widget.coordinates.length < 2) return false;
    try {
      final latlng =
          _mapController.pointToLatLng(CustomPoint(local.dx, local.dy));
      final hit = _nearestOnRoute(latlng);
      if (hit == null) return false;
      final snap = _mapController.latLngToScreenPoint(hit.position);
      return (local - Offset(snap.x.toDouble(), snap.y.toDouble())).distance <=
          _routeHitSlopPx;
    } catch (_) {
      return false;
    }
  }

  void _seekToProgress(double progress) {
    _pausePlaybackForScrub();
    setState(() => _applyProgress(progress));
  }

  void _applyProgress(double progress) {
    progress = progress.clamp(0.0, 1.0);
    final coords = widget.coordinates;
    if (coords.isEmpty) return;

    if (coords.length == 1 || _totalRouteMeters <= 0) {
      _flyoverProgress = progress;
      _segmentIndex = 0;
      _segmentProgress = 0;
      _totalDistanceTraveled = 0;
      _runnerPosition = LatLng(coords.first.lat, coords.first.lng);
      return;
    }

    if (_cumulativeMeters.length != coords.length) {
      _rebuildRouteMetrics();
    }

    final targetMeters = _totalRouteMeters * progress;
    var i = 0;
    while (i < coords.length - 2 && _cumulativeMeters[i + 1] < targetMeters) {
      i++;
    }
    final segStart = _cumulativeMeters[i];
    final segLen = _cumulativeMeters[i + 1] - segStart;
    final t = segLen > 0.1
        ? ((targetMeters - segStart) / segLen).clamp(0.0, 1.0)
        : 0.0;
    final start = coords[i];
    final end = coords[i + 1];

    _flyoverProgress = progress;
    _segmentIndex = i;
    _segmentProgress = t;
    _totalDistanceTraveled = segStart;
    _runnerPosition = LatLng(
      start.lat + (end.lat - start.lat) * t,
      start.lng + (end.lng - start.lng) * t,
    );
    if (!_isFlying) {
      _showStartPin = true;
      _showEndPin = true;
    }
  }

  _RouteHit? _nearestOnRoute(LatLng point) {
    final coords = widget.coordinates;
    if (coords.length < 2 || _totalRouteMeters <= 0) return null;
    if (_cumulativeMeters.length != coords.length) {
      _rebuildRouteMetrics();
    }

    var bestDist2 = double.infinity;
    var bestIndex = 0;
    var bestT = 0.0;

    for (int i = 0; i < coords.length - 1; i++) {
      final a = coords[i];
      final b = coords[i + 1];
      final dx = b.lng - a.lng;
      final dy = b.lat - a.lat;
      final len2 = dx * dx + dy * dy;
      var t = 0.0;
      if (len2 > 0) {
        t = ((point.longitude - a.lng) * dx + (point.latitude - a.lat) * dy) /
            len2;
        t = t.clamp(0.0, 1.0);
      }
      final lat = a.lat + (b.lat - a.lat) * t;
      final lng = a.lng + (b.lng - a.lng) * t;
      final dLat = point.latitude - lat;
      final dLng = point.longitude - lng;
      final d2 = dLat * dLat + dLng * dLng;
      if (d2 < bestDist2) {
        bestDist2 = d2;
        bestIndex = i;
        bestT = t;
      }
    }

    final start = coords[bestIndex];
    final end = coords[bestIndex + 1];
    final meters = _cumulativeMeters[bestIndex] +
        (_cumulativeMeters[bestIndex + 1] - _cumulativeMeters[bestIndex]) *
            bestT;
    return _RouteHit(
      position: LatLng(
        start.lat + (end.lat - start.lat) * bestT,
        start.lng + (end.lng - start.lng) * bestT,
      ),
      progress: (meters / _totalRouteMeters).clamp(0.0, 1.0),
    );
  }
}

class _RouteHit {
  final LatLng position;
  final double progress;

  const _RouteHit({required this.position, required this.progress});
}

class _RouteScrubHitTarget extends LeafRenderObjectWidget {
  final bool Function(Offset local) isNearRoute;

  const _RouteScrubHitTarget({required this.isNearRoute});

  @override
  RenderBox createRenderObject(BuildContext context) {
    return _RouteScrubHitRenderBox(isNearRoute: isNearRoute);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RouteScrubHitRenderBox renderObject,
  ) {
    renderObject.isNearRoute = isNearRoute;
  }
}

class _RouteScrubHitRenderBox extends RenderBox {
  _RouteScrubHitRenderBox({required this.isNearRoute});

  bool Function(Offset local) isNearRoute;

  @override
  void performLayout() {
    size = constraints.biggest;
  }

  @override
  bool hitTestSelf(Offset position) => isNearRoute(position);
}
