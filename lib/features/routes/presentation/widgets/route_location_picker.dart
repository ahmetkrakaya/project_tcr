import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Harita üzerinden rota konumu seçimi (flutter_map - OpenStreetMap, ücretsiz)
class RouteLocationPicker extends StatelessWidget {
  final double? selectedLat;
  final double? selectedLng;
  /// (latitude, longitude) seçildiğinde çağrılır
  final void Function(double lat, double lng) onLocationSelected;
  final double height;
  /// Başlık ve açıklama metnini gizler (popup/sheet içinde kullanım için)
  final bool showLabel;

  /// Varsayılan merkez: Denizli
  static const LatLng _defaultCenter = LatLng(37.7833, 29.0947);

  const RouteLocationPicker({
    super.key,
    this.selectedLat,
    this.selectedLng,
    required this.onLocationSelected,
    this.height = 220,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final center = (selectedLat != null && selectedLng != null)
        ? LatLng(selectedLat!, selectedLng!)
        : _defaultCenter;
    final initialZoom = (selectedLat != null && selectedLng != null) ? 14.0 : 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          Text(
            'Konum',
            style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Haritada rota konumunu seçmek için haritaya dokunun',
            style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
          ),
          const SizedBox(height: 8),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              border: Border.all(
                color: (selectedLat != null && selectedLng != null)
                    ? AppColors.success
                    : AppColors.neutral300,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: FlutterMap(
              options: MapOptions(
                center: center,
                zoom: initialZoom,
                minZoom: 4,
                maxZoom: 18,
                onTap: (event, point) => onLocationSelected(point.latitude, point.longitude),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'project_tcr',
                  maxZoom: 19,
                ),
                if (selectedLat != null && selectedLng != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(selectedLat!, selectedLng!),
                        width: 40,
                        height: 40,
                        builder: (context) => const Icon(
                          Icons.location_on,
                          color: AppColors.primary,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (showLabel && selectedLat != null && selectedLng != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${selectedLat!.toStringAsFixed(5)}, ${selectedLng!.toStringAsFixed(5)}',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.success,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
