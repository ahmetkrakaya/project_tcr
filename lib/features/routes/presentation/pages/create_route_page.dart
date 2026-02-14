import 'dart:io' if (dart.library.html) 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/route_entity.dart';
import '../providers/route_provider.dart';
import '../widgets/route_location_picker.dart';

/// Rota Ekleme / Düzenleme Sayfası
class CreateRoutePage extends ConsumerStatefulWidget {
  /// Düzenleme modu: dolu ise mevcut rota yüklenir ve güncelleme yapılır
  final String? routeId;

  const CreateRoutePage({super.key, this.routeId});

  @override
  ConsumerState<CreateRoutePage> createState() => _CreateRoutePageState();
}

class _CreateRoutePageState extends ConsumerState<CreateRoutePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _descriptionFocusNode = FocusNode();

  double? _locationLat;
  double? _locationLng;
  String? _gpxContent;
  String? _gpxFileName;
  TerrainType _selectedTerrainType = TerrainType.asphalt;
  int _difficultyLevel = 1;
  bool _isGpxValid = false;
  String? _gpxError;
  bool _editInitialized = false;
  bool _editResetDone = false;

  bool get _isEditMode => widget.routeId != null;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  void _applyRouteData(RouteEntity route) {
    if (_editInitialized) return;
    _nameController.text = route.name;
    _descriptionController.text = route.description ?? '';
    _locationLat = route.locationLat;
    _locationLng = route.locationLng;
    _selectedTerrainType = route.terrainType;
    _difficultyLevel = route.difficultyLevel;
    if (route.gpxData != null && route.gpxData!.isNotEmpty) {
      _gpxContent = route.gpxData;
      _gpxFileName = 'Mevcut rota verisi';
      _isGpxValid = true;
    }
    _editInitialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final creationState = ref.watch(routeCreationProvider);
    final routeAsync = widget.routeId != null
        ? ref.watch(routeByIdProvider(widget.routeId!))
        : null;

    // Düzenleme modunda önceki create state'ini sıfırla (yanlışlıkla pop olmasın)
    if (_isEditMode && !_editResetDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(routeCreationProvider.notifier).reset();
        setState(() => _editResetDone = true);
      });
    }

    // Düzenleme modunda rota verisi geldiğinde formu doldur
    routeAsync?.whenData((route) {
      if (!_editInitialized && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _applyRouteData(route));
        });
      }
    });

    // Listen for success: düzenlemede detay sayfasına, oluşturmada listeye dön
    ref.listen<RouteCreationState>(routeCreationProvider, (previous, next) {
      if (next.createdRoute != null && previous?.createdRoute == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditMode ? 'Rota güncellendi!' : 'Rota başarıyla oluşturuldu!',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        if (_isEditMode && widget.routeId != null) {
          context.goNamed(RouteNames.routeDetail, pathParameters: {'routeId': widget.routeId!});
        } else {
          context.goNamed(RouteNames.routes);
        }
      }
      if (next.error != null && previous?.error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: ${next.error}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    final isLoadingRoute = _isEditMode &&
        (routeAsync == null ||
            routeAsync.isLoading ||
            routeAsync.hasError);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Rota Düzenle' : 'Yeni Rota Ekle'),
        actions: [
          if (creationState.isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16, left: 8),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _canSubmit(creationState) ? _submitRoute : null,
              tooltip: _isEditMode ? 'Kaydet' : 'Oluştur',
            ),
        ],
      ),
      body: isLoadingRoute
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
            // 1. İsim
            AppTextField(
              controller: _nameController,
              label: 'İsim',
              hint: 'Örn: Kadıköy - Moda Sahil Koşusu',
              prefixIcon: Icons.route,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _descriptionFocusNode.requestFocus(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Rota adı gerekli';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _descriptionController,
              focusNode: _descriptionFocusNode,
              label: 'Açıklama (Opsiyonel)',
              hint: 'Rota hakkında kısa bilgi...',
              prefixIcon: Icons.description,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                final creationState = ref.read(routeCreationProvider);
                if (_canSubmit(creationState)) {
                  _submitRoute();
                }
              },
            ),
            const SizedBox(height: 24),

            // 2. Konum (butonla popup’ta harita)
            _buildLocationSection(),
            const SizedBox(height: 24),

            // 3. GPX Dosyası
            _buildGpxPicker(),
            const SizedBox(height: 24),

            // 4. Tür: Asfalt, Trail, Pist
            _buildTerrainTypeSelector(),
            const SizedBox(height: 24),

            // 5. Zorluk Seviyesi
            _buildDifficultySelector(),
          ],
        ),
      ),
    );
  }

  Widget _buildGpxPicker() {
    final hasFile = _gpxFileName != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GPX Dosyası (opsiyonel)',
          style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _pickGpxFile,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _isGpxValid
                    ? AppColors.success.withValues(alpha: 0.08)
                    : _gpxError != null
                        ? AppColors.error.withValues(alpha: 0.08)
                        : AppColors.neutral100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isGpxValid
                      ? AppColors.success
                      : _gpxError != null
                          ? AppColors.error
                          : AppColors.neutral300,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isGpxValid
                        ? Icons.check_circle
                        : _gpxError != null
                            ? Icons.error_outline
                            : Icons.upload_file,
                    color: _isGpxValid
                        ? AppColors.success
                        : _gpxError != null
                            ? AppColors.error
                            : AppColors.neutral500,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasFile
                          ? _gpxFileName!
                          : 'GPX dosyası eklemek için dokunun',
                      style: AppTypography.bodyMedium.copyWith(
                        color: _isGpxValid
                            ? AppColors.success
                            : _gpxError != null
                                ? AppColors.error
                                : AppColors.neutral600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!hasFile)
                        IconButton(
                          tooltip: 'GPX Dosyası Seç',
                          icon: const Icon(Icons.upload_file),
                          color: AppColors.primary,
                          onPressed: _pickGpxFile,
                        ),
                      if (hasFile) ...[
                        IconButton(
                          tooltip: 'Değiştir',
                          icon: const Icon(Icons.edit_document),
                          color: AppColors.primary,
                          onPressed: _pickGpxFile,
                        ),
                        IconButton(
                          tooltip: 'Kaldır',
                          icon: const Icon(Icons.clear),
                          color: AppColors.neutral500,
                          onPressed: () {
                            setState(() {
                              _gpxContent = null;
                              _gpxFileName = null;
                              _isGpxValid = false;
                              _gpxError = null;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_gpxError != null) ...[
          const SizedBox(height: 6),
          Text(
            _gpxError!,
            style: AppTypography.labelSmall.copyWith(color: AppColors.error),
          ),
        ] else ...[
          const SizedBox(height: 6),
          Text(
            'İsteğe bağlı. Desteklenen format: .gpx',
            style: AppTypography.labelSmall.copyWith(color: AppColors.neutral500),
          ),
        ],
      ],
    );
  }

  bool _canSubmit(RouteCreationState creationState) {
    final hasName = _nameController.text.trim().isNotEmpty;
    final hasLocation = _locationLat != null && _locationLng != null;
    return hasName && hasLocation && !creationState.isLoading;
  }

  Widget _buildLocationSection() {
    final hasLocation = _locationLat != null && _locationLng != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Konum',
          style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _showLocationPickerSheet,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: hasLocation
                    ? AppColors.success.withValues(alpha: 0.08)
                    : AppColors.neutral100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasLocation ? AppColors.success : AppColors.neutral300,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hasLocation ? Icons.location_on : Icons.add_location_alt,
                    color: hasLocation ? AppColors.success : AppColors.neutral500,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasLocation
                          ? '${_locationLat!.toStringAsFixed(5)}, ${_locationLng!.toStringAsFixed(5)}'
                          : 'Konum seçmek için dokunun',
                      style: AppTypography.bodyMedium.copyWith(
                        color: hasLocation ? AppColors.success : AppColors.neutral600,
                        fontFamily: hasLocation ? 'monospace' : null,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!hasLocation)
                        IconButton(
                          tooltip: 'Konum Seç',
                          icon: const Icon(Icons.add_location_alt),
                          color: AppColors.primary,
                          onPressed: _showLocationPickerSheet,
                        ),
                      if (hasLocation) ...[
                        IconButton(
                          tooltip: 'Değiştir',
                          icon: const Icon(Icons.edit_location_alt),
                          color: AppColors.primary,
                          onPressed: _showLocationPickerSheet,
                        ),
                        IconButton(
                          tooltip: 'Kaldır',
                          icon: const Icon(Icons.clear),
                          color: AppColors.neutral500,
                          onPressed: () {
                            setState(() {
                              _locationLat = null;
                              _locationLng = null;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showLocationPickerSheet() async {
    final result = await showModalBottomSheet<({double lat, double lng})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _LocationPickerSheet(
        initialLat: _locationLat,
        initialLng: _locationLng,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _locationLat = result.lat;
        _locationLng = result.lng;
      });
    }
  }

  Widget _buildTerrainTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tür',
          style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Row(
          children: TerrainType.values.map((terrain) {
            final isSelected = _selectedTerrainType == terrain;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedTerrainType = terrain),
                child: Container(
                  margin: EdgeInsets.only(
                    right: terrain != TerrainType.values.last ? 8 : 0,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.neutral100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        terrain.icon,
                        style: const TextStyle(fontSize: 24),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        terrain.displayName,
                        style: AppTypography.labelMedium.copyWith(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.neutral600,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDifficultySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Zorluk Seviyesi',
              style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _getDifficultyColor(_difficultyLevel).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _getDifficultyText(_difficultyLevel),
                style: AppTypography.labelMedium.copyWith(
                  color: _getDifficultyColor(_difficultyLevel),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _getDifficultyColor(_difficultyLevel),
            thumbColor: _getDifficultyColor(_difficultyLevel),
            overlayColor: _getDifficultyColor(_difficultyLevel).withValues(alpha: 0.2),
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
          ),
          child: Slider(
            value: _difficultyLevel.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            onChanged: (value) {
              setState(() => _difficultyLevel = value.toInt());
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Çok Kolay',
              style: AppTypography.labelSmall.copyWith(color: AppColors.neutral500),
            ),
            Text(
              'Çok Zor',
              style: AppTypography.labelSmall.copyWith(color: AppColors.neutral500),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickGpxFile() async {
    try {
      // FileType.any kullanıyoruz çünkü Android'de .gpx desteklenmiyor
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final pickedFile = result.files.single;
        final fileName = pickedFile.name.toLowerCase();
        
        // Manuel olarak .gpx veya .xml uzantısını kontrol et
        if (!fileName.endsWith('.gpx') && !fileName.endsWith('.xml')) {
          setState(() {
            _gpxFileName = pickedFile.name;
            _isGpxValid = false;
            _gpxError = 'Lütfen .gpx veya .xml dosyası seçin';
          });
          return;
        }

        String content;
        
        // Önce bytes'tan okumayı dene (web ve mobil için güvenilir)
        if (pickedFile.bytes != null) {
          content = String.fromCharCodes(pickedFile.bytes!);
        } else if (!kIsWeb && pickedFile.path != null) {
          // Mobilde path varsa dosyadan oku
          final file = File(pickedFile.path!);
          content = await file.readAsString();
        } else {
          setState(() {
            _gpxFileName = pickedFile.name;
            _isGpxValid = false;
            _gpxError = 'Dosya içeriği okunamadı';
          });
          return;
        }

        // Validate GPX content
        if (content.contains('<gpx') && content.contains('</gpx>')) {
          setState(() {
            _gpxContent = content;
            _gpxFileName = pickedFile.name;
            _isGpxValid = true;
            _gpxError = null;

            // Auto-fill name from GPX if available
            if (_nameController.text.isEmpty) {
              final nameMatch = RegExp(r'<name>(.*?)</name>').firstMatch(content);
              if (nameMatch != null && nameMatch.group(1) != null) {
                _nameController.text = nameMatch.group(1)!;
              }
            }
          });
        } else {
          setState(() {
            _gpxFileName = pickedFile.name;
            _isGpxValid = false;
            _gpxError = 'Geçersiz GPX formatı. Dosya <gpx> etiketi içermiyor.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _isGpxValid = false;
        _gpxError = 'Dosya seçilemedi: $e';
      });
    }
  }

  Future<void> _submitRoute() async {
    if (!_formKey.currentState!.validate()) return;
    if (_locationLat == null || _locationLng == null) return;

    final notifier = ref.read(routeCreationProvider.notifier);
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim().isNotEmpty
        ? _descriptionController.text.trim()
        : null;
    final terrainType = _selectedTerrainType.name;
    // GPX opsiyonel: geçerli GPX varsa gönder, yoksa null
    final gpxContent = _isGpxValid && _gpxContent != null && _gpxContent!.isNotEmpty
        ? _gpxContent
        : null;

    if (_isEditMode) {
      await notifier.updateRoute(
        routeId: widget.routeId!,
        name: name,
        locationLat: _locationLat!,
        locationLng: _locationLng!,
        description: description,
        terrainType: terrainType,
        difficultyLevel: _difficultyLevel,
        gpxContent: gpxContent,
      );
    } else {
      await notifier.createFromGpxContent(
        name: name,
        gpxContent: gpxContent,
        locationLat: _locationLat!,
        locationLng: _locationLng!,
        description: description,
        terrainType: terrainType,
        difficultyLevel: _difficultyLevel,
      );
    }
  }

  String _getDifficultyText(int level) {
    switch (level) {
      case 1:
        return 'Çok Kolay';
      case 2:
        return 'Kolay';
      case 3:
        return 'Orta';
      case 4:
        return 'Zor';
      case 5:
        return 'Çok Zor';
      default:
        return 'Bilinmiyor';
    }
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

/// Popup içinde konum seçici (harita + Tamam/İptal)
class _LocationPickerSheet extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const _LocationPickerSheet({
    this.initialLat,
    this.initialLng,
  });

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  double? _tempLat;
  double? _tempLng;

  @override
  void initState() {
    super.initState();
    _tempLat = widget.initialLat;
    _tempLng = widget.initialLng;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Başlık + açıklama + boşluk + buton satırı için ayrılan yükseklik (taşma olmaması için)
            const headerHeight = 120.0;
            const buttonRowHeight = 88.0;
            final mapHeight = (constraints.maxHeight - headerHeight - buttonRowHeight).clamp(200.0, 500.0);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Konum Seç',
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Haritada rota konumunu seçmek için haritaya dokunun',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.neutral500,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: mapHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: RouteLocationPicker(
                      selectedLat: _tempLat,
                      selectedLng: _tempLng,
                      onLocationSelected: (lat, lng) {
                        setState(() {
                          _tempLat = lat;
                          _tempLng = lng;
                        });
                      },
                      height: mapHeight,
                      showLabel: false,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('İptal'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: _tempLat != null && _tempLng != null
                              ? () => Navigator.of(context).pop((
                                    lat: _tempLat!,
                                    lng: _tempLng!,
                                  ))
                              : null,
                          child: const Text('Tamam'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
