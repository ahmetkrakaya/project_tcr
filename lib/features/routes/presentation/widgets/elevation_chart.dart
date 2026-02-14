import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/route_entity.dart';

/// Elevation Profili Grafiği
class ElevationChart extends StatefulWidget {
  final List<ElevationPoint> elevationProfile;
  final double totalDistance;

  const ElevationChart({
    super.key,
    required this.elevationProfile,
    required this.totalDistance,
  });

  @override
  State<ElevationChart> createState() => _ElevationChartState();
}

class _ElevationChartState extends State<ElevationChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.elevationProfile.isEmpty) {
      return const SizedBox.shrink();
    }

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Yükseklik Profili',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_touchedIndex != null && _touchedIndex! < widget.elevationProfile.length)
                _buildTouchedInfo(),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: LineChart(
              _buildChartData(),
              duration: const Duration(milliseconds: 150),
            ),
          ),
          const SizedBox(height: 8),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(AppColors.success, 'Düz'),
              const SizedBox(width: 16),
              _buildLegendItem(AppColors.warning, 'Orta'),
              const SizedBox(width: 16),
              _buildLegendItem(AppColors.error, 'Dik'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTouchedInfo() {
    final point = widget.elevationProfile[_touchedIndex!];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${point.distance.toStringAsFixed(1)} km • ${point.elevation.toInt()} m',
        style: AppTypography.labelMedium.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.neutral600,
          ),
        ),
      ],
    );
  }

  LineChartData _buildChartData() {
    // Calculate min/max elevation
    double minElev = double.infinity;
    double maxElev = -double.infinity;

    for (final point in widget.elevationProfile) {
      if (point.elevation < minElev) minElev = point.elevation;
      if (point.elevation > maxElev) maxElev = point.elevation;
    }

    // Add padding; düz pistlerde (tüm noktalar aynı yükseklikte) aralık 0 olmasın
    final elevRange = maxElev - minElev;
    const minRange = 10.0; // metre - tamamen düz rotalar için minimum görünür aralık
    final effectiveRange = elevRange > 0 ? elevRange : minRange;
    final paddedMin = minElev - (effectiveRange * 0.1);
    final paddedMax = maxElev + (effectiveRange * 0.1);
    final yRange = paddedMax - paddedMin;
    // fl_chart horizontalInterval 0 olamaz (düz pist hatası)
    final horizontalInterval = (yRange > 0 ? yRange / 4 : 2.5).clamp(0.1, double.infinity);

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: horizontalInterval,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: AppColors.neutral200,
            strokeWidth: 1,
            dashArray: [5, 5],
          );
        },
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: horizontalInterval,
            getTitlesWidget: (value, meta) {
              return Text(
                '${value.toInt()}m',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.neutral500,
                  fontSize: 10,
                ),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: widget.totalDistance > 0 ? widget.totalDistance / 5 : 1,
            getTitlesWidget: (value, meta) {
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${value.toStringAsFixed(1)}km',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.neutral500,
                    fontSize: 10,
                  ),
                ),
              );
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: widget.totalDistance > 0 ? widget.totalDistance : 1,
      minY: paddedMin,
      maxY: paddedMax,
      lineTouchData: LineTouchData(
        enabled: true,
        touchCallback: (event, response) {
          setState(() {
            if (response?.lineBarSpots != null && response!.lineBarSpots!.isNotEmpty) {
              _touchedIndex = response.lineBarSpots!.first.spotIndex;
            } else {
              _touchedIndex = null;
            }
          });
        },
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (touchedSpot) => AppColors.neutral800,
          tooltipRoundedRadius: 8,
          tooltipPadding: const EdgeInsets.all(8),
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              return LineTooltipItem(
                '${spot.y.toInt()} m\n${spot.x.toStringAsFixed(1)} km',
                AppTypography.labelSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              );
            }).toList();
          },
        ),
        handleBuiltInTouches: true,
      ),
      lineBarsData: [
        // Eğim bazlı renkli segmentler (önce bunlar çizilir, altta kalır)
        ..._buildGradientSegments(paddedMin),
        // Ana çizgi (üstte, daha ince)
        LineChartBarData(
          spots: widget.elevationProfile
              .map((p) => FlSpot(p.distance, p.elevation))
              .toList(),
          isCurved: true,
          curveSmoothness: 0.3,
          preventCurveOverShooting: true,
          color: AppColors.neutral700,
          barWidth: 2,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              // Show dots only for touched point
              if (index == _touchedIndex) {
                return FlDotCirclePainter(
                  radius: 6,
                  color: AppColors.primary,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                );
              }
              return FlDotCirclePainter(
                radius: 0,
                color: Colors.transparent,
                strokeWidth: 0,
                strokeColor: Colors.transparent,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                AppColors.neutral300.withValues(alpha: 0.2),
                AppColors.neutral300.withValues(alpha: 0.0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }

  /// Eğime göre renkli segmentler oluştur
  /// Ardışık noktaları aynı eğim kategorisindeyse birleştirir
  List<LineChartBarData> _buildGradientSegments(double minY) {
    if (widget.elevationProfile.length < 2) return [];

    final segments = <LineChartBarData>[];
    final points = widget.elevationProfile;

    // İlk segmenti başlat
    List<FlSpot> currentSegmentSpots = [
      FlSpot(points[0].distance, points[0].elevation),
    ];
    Color? currentSegmentColor;

    for (int i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];

      final distanceDiff = next.distance - current.distance; // km
      if (distanceDiff <= 0) continue;

      final elevationDiff = next.elevation - current.elevation; // m
      
      // Eğim hesapla: (yükseklik farkı / mesafe) * 100 = % eğim
      final slopePercent = (elevationDiff / (distanceDiff * 1000)) * 100;
      final absSlope = slopePercent.abs();

      // Renk belirle
      Color segmentColor;
      if (absSlope < 3) {
        segmentColor = AppColors.success; // Düz: < %3
      } else if (absSlope < 8) {
        segmentColor = AppColors.warning; // Orta: %3-8
      } else {
        segmentColor = AppColors.error; // Dik: > %8
      }

      // Eğer renk değiştiyse veya ilk segmentse, önceki segmenti kaydet ve yeni segment başlat
      final prevColor = currentSegmentColor;
      if (prevColor != null && prevColor != segmentColor) {
        // Önceki segmenti kaydet
        if (currentSegmentSpots.length >= 2) {
          segments.add(
            LineChartBarData(
              spots: currentSegmentSpots,
              isCurved: true,
              curveSmoothness: 0.3,
              preventCurveOverShooting: true,
              color: prevColor,
              barWidth: 5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: prevColor.withValues(alpha: 0.15),
              ),
            ),
          );
        }
        // Yeni segment başlat
        currentSegmentSpots = [
          FlSpot(current.distance, current.elevation),
        ];
      }

      // Mevcut noktayı segmente ekle
      currentSegmentSpots.add(FlSpot(next.distance, next.elevation));
      currentSegmentColor = segmentColor;
    }

    // Son segmenti kaydet
    final finalColor = currentSegmentColor;
    if (currentSegmentSpots.length >= 2 && finalColor != null) {
      segments.add(
        LineChartBarData(
          spots: currentSegmentSpots,
          isCurved: true,
          curveSmoothness: 0.3,
          preventCurveOverShooting: true,
          color: finalColor,
          barWidth: 5,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: finalColor.withValues(alpha: 0.15),
          ),
        ),
      );
    }

    return segments;
  }
}
