import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/services/nominatim_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Harita üzerinden rota konumu seçimi (flutter_map - OpenStreetMap, ücretsiz)
/// Nominatim araması ile mekan/adres araması destekler.
class RouteLocationPicker extends StatefulWidget {
  final double? selectedLat;
  final double? selectedLng;

  /// (latitude, longitude) seçildiğinde çağrılır
  final void Function(double lat, double lng) onLocationSelected;

  /// Arama sonucu seçildiğinde mekan adını döner (EventLocationPickerSheet vb. için)
  final void Function(String placeName)? onPlaceNameResolved;

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
    this.onPlaceNameResolved,
    this.height = 220,
    this.showLabel = true,
  });

  @override
  State<RouteLocationPicker> createState() => _RouteLocationPickerState();
}

class _RouteLocationPickerState extends State<RouteLocationPicker> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<NominatimPlace> _searchResults = [];
  bool _isSearching = false;
  bool _showResults = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();

    if (query.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _showResults = false;
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final results = await NominatimService().search(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _showResults = results.isNotEmpty;
        _isSearching = false;
      });
    });
  }

  void _onPlaceSelected(NominatimPlace place) {
    _searchFocusNode.unfocus();
    _searchController.text = place.shortName;

    setState(() {
      _showResults = false;
      _searchResults = [];
    });

    _mapController.move(LatLng(place.lat, place.lng), 15.0);
    widget.onLocationSelected(place.lat, place.lng);
    widget.onPlaceNameResolved?.call(place.shortName);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _showResults = false;
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final center = (widget.selectedLat != null && widget.selectedLng != null)
        ? LatLng(widget.selectedLat!, widget.selectedLng!)
        : RouteLocationPicker._defaultCenter;
    final initialZoom =
        (widget.selectedLat != null && widget.selectedLng != null) ? 14.0 : 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showLabel) ...[
          Text(
            'Konum',
            style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Haritada rota konumunu seçmek için haritaya dokunun veya arama yapın',
            style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
          ),
          const SizedBox(height: 8),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              border: Border.all(
                color: (widget.selectedLat != null && widget.selectedLng != null)
                    ? AppColors.success
                    : AppColors.neutral300,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                // Harita
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    center: center,
                    zoom: initialZoom,
                    minZoom: 4,
                    maxZoom: 18,
                    onTap: (event, point) {
                      _searchFocusNode.unfocus();
                      setState(() => _showResults = false);
                      widget.onLocationSelected(
                          point.latitude, point.longitude);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'project_tcr',
                      maxZoom: 19,
                    ),
                    if (widget.selectedLat != null &&
                        widget.selectedLng != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(
                                widget.selectedLat!, widget.selectedLng!),
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

                // Arama çubuğu + sonuçlar (harita üzerinde)
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Arama input
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 10),
                              child: Icon(
                                Icons.search,
                                color: AppColors.neutral500,
                                size: 20,
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                onChanged: _onSearchChanged,
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.neutral900,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Mekan, mahalle, sokak ara...',
                                  hintStyle: AppTypography.bodySmall.copyWith(
                                    color: AppColors.neutral400,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                            if (_isSearching)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            else if (_searchController.text.isNotEmpty)
                              GestureDetector(
                                onTap: _clearSearch,
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(
                                    Icons.close,
                                    color: AppColors.neutral500,
                                    size: 18,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Arama sonuçları
                      if (_showResults && _searchResults.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              indent: 36,
                              color: AppColors.neutral200,
                            ),
                            itemBuilder: (context, index) {
                              final place = _searchResults[index];
                              return InkWell(
                                onTap: () => _onPlaceSelected(place),
                                borderRadius: BorderRadius.circular(
                                  index == 0 || index == _searchResults.length - 1
                                      ? 10
                                      : 0,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.place_outlined,
                                        color: AppColors.primary,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          place.shortName,
                                          style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.neutral800,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.showLabel &&
            widget.selectedLat != null &&
            widget.selectedLng != null) ...[
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
                    '${widget.selectedLat!.toStringAsFixed(5)}, ${widget.selectedLng!.toStringAsFixed(5)}',
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
