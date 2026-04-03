import 'dart:io' if (dart.library.html) 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

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
import '../../data/datasources/route_remote_datasource.dart';
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

class _GpxVariantDraft {
  String label;
  String? fileName;
  String? gpxContent;
  Uint8List? gpxBytes;
  bool isValid;
  String? error;

  _GpxVariantDraft({
    required this.label,
    this.fileName,
    this.gpxContent,
    this.gpxBytes,
    this.isValid = false,
  });
}

class _CreateRoutePageState extends ConsumerState<CreateRoutePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _descriptionFocusNode = FocusNode();

  double? _locationLat;
  double? _locationLng;

  final List<_GpxVariantDraft> _gpxVariants = [];
  TerrainType _selectedTerrainType = TerrainType.asphalt;
  bool _isRace = false;
  int _difficultyLevel = 1;
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
    _isRace = route.isRace;

    _gpxVariants.clear();
    final variants = route.gpxVariants;
    if (variants.isNotEmpty) {
      for (final v in variants) {
        final content = v.gpxData;
        _gpxVariants.add(_GpxVariantDraft(
          label: v.label,
          fileName: 'Mevcut rota verisi',
          gpxContent: content,
          gpxBytes: content != null && content.isNotEmpty
              ? Uint8List.fromList(utf8.encode(content))
              : null,
          isValid: content != null && content.isNotEmpty,
        ));
      }
    } else if (route.gpxData != null && route.gpxData!.isNotEmpty) {
      // Geriye dönük güvenlik
      final content = route.gpxData!;
      _gpxVariants.add(_GpxVariantDraft(
        label: 'Default',
        fileName: 'Mevcut rota verisi',
        gpxContent: content,
        gpxBytes: Uint8List.fromList(utf8.encode(content)),
        isValid: true,
      ));
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

            // 5. Yarış Rotası / Normal Rota
            _buildRouteCategorySelector(),
            const SizedBox(height: 24),

            // 6. Zorluk Seviyesi
            _buildDifficultySelector(),
          ],
        ),
      ),
    );
  }

  Widget _buildGpxPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GPX Varyantları (opsiyonel)',
          style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),

        if (_gpxVariants.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.neutral100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.neutral200),
            ),
            child: Row(
              children: [
                Icon(Icons.route_outlined, color: AppColors.neutral500),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Farklı mesafeler için birden fazla GPX ekleyebilirsiniz.',
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.neutral600),
                  ),
                ),
                IconButton(
                  tooltip: 'Mesafe ekle',
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppColors.primary,
                  onPressed: () {
                    setState(() {
                      final nextIndex = _gpxVariants.length + 1;
                      _gpxVariants.add(_GpxVariantDraft(
                        label: nextIndex == 1 ? 'Default' : 'Variant $nextIndex',
                      ));
                    });
                  },
                ),
              ],
            ),
          ),
        ] else ...[
          Column(
            children: [
              ...List.generate(_gpxVariants.length, (i) {
                final v = _gpxVariants[i];
                final hasFile = v.gpxContent != null && v.gpxContent!.isNotEmpty;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: v.isValid
                          ? AppColors.success.withValues(alpha: 0.08)
                          : v.error != null
                              ? AppColors.error.withValues(alpha: 0.08)
                              : AppColors.neutral100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: v.isValid
                            ? AppColors.success
                            : v.error != null
                                ? AppColors.error
                                : AppColors.neutral300,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              v.isValid
                                  ? Icons.check_circle
                                  : v.error != null
                                      ? Icons.error_outline
                                      : Icons.upload_file,
                              color: v.isValid
                                  ? AppColors.success
                                  : v.error != null
                                      ? AppColors.error
                                      : AppColors.neutral500,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                initialValue: v.label,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  labelText: 'Etiket (örn. 21K)',
                                ),
                                onChanged: (val) {
                                  v.label = val;
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: 'Varyantı kaldır',
                              icon: const Icon(Icons.delete_outline),
                              color: AppColors.neutral500,
                              onPressed: () {
                                setState(() {
                                  _gpxVariants.removeAt(i);
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        InkWell(
                          onTap: () => _pickGpxFileForVariant(i),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.neutral300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  hasFile ? Icons.edit_document : Icons.upload_file,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  hasFile ? (v.fileName ?? 'GPX yüklendi') : 'GPX seçin',
                                  style: AppTypography.bodyMedium.copyWith(color: AppColors.neutral700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (v.error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            v.error!,
                            style: AppTypography.labelSmall.copyWith(color: AppColors.error),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          Text(
                            'İsteğe bağlı. Desteklenen format: .gpx',
                            style: AppTypography.labelSmall.copyWith(color: AppColors.neutral500),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      final nextIndex = _gpxVariants.length + 1;
                      _gpxVariants.add(_GpxVariantDraft(
                        label: 'Variant $nextIndex',
                      ));
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Varyant Ekle'),
                ),
              ),
            ],
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

  Widget _buildRouteCategorySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Kategori',
          style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _isRace = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _isRace
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.neutral100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isRace ? AppColors.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.emoji_events, size: 26),
                      const SizedBox(height: 6),
                      Text(
                        'Yarış Rotası',
                        style: AppTypography.labelMedium.copyWith(
                          color: _isRace ? AppColors.primary : AppColors.neutral600,
                          fontWeight: _isRace ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _isRace = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: !_isRace
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.neutral100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: !_isRace ? AppColors.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.map_outlined, size: 26),
                      const SizedBox(height: 6),
                      Text(
                        'Normal Rota',
                        style: AppTypography.labelMedium.copyWith(
                          color: !_isRace ? AppColors.primary : AppColors.neutral600,
                          fontWeight: !_isRace ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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

  Future<void> _pickGpxFileForVariant(int index) async {
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
            _gpxVariants[index].fileName = pickedFile.name;
            _gpxVariants[index].isValid = false;
            _gpxVariants[index].error = 'Lütfen .gpx veya .xml dosyası seçin';
          });
          return;
        }

        String? content;
        Uint8List? bytes;

        // Önce bytes'tan okumayı dene (web ve mobil için güvenilir)
        if (pickedFile.bytes != null) {
          bytes = pickedFile.bytes!;
          content = String.fromCharCodes(bytes);
        } else if (!kIsWeb && pickedFile.path != null) {
          final file = File(pickedFile.path!);
          bytes = await file.readAsBytes();
          content = String.fromCharCodes(bytes);
        }

        if (content == null || content.isEmpty || bytes == null) {
          setState(() {
            _gpxVariants[index].fileName = pickedFile.name;
            _gpxVariants[index].isValid = false;
            _gpxVariants[index].error = 'Dosya içeriği okunamadı';
          });
          return;
        }

        final gpxText = content;

        // Validate GPX content
        if (gpxText.contains('<gpx') && gpxText.contains('</gpx>')) {
          setState(() {
            _gpxVariants[index].gpxContent = gpxText;
            _gpxVariants[index].gpxBytes = bytes;
            _gpxVariants[index].fileName = pickedFile.name;
            _gpxVariants[index].isValid = true;
            _gpxVariants[index].error = null;

            // Auto-fill name from GPX if available
            if (_nameController.text.isEmpty) {
              final nameMatch = RegExp(r'<name>(.*?)</name>').firstMatch(gpxText);
              if (nameMatch != null && nameMatch.group(1) != null) {
                _nameController.text = nameMatch.group(1)!;
              }
            }
          });
        } else {
          setState(() {
            _gpxVariants[index].fileName = pickedFile.name;
            _gpxVariants[index].isValid = false;
            _gpxVariants[index].gpxContent = null;
            _gpxVariants[index].gpxBytes = null;
            _gpxVariants[index].error = 'Geçersiz GPX formatı. Dosya <gpx> etiketi içermiyor.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _gpxVariants[index].isValid = false;
        _gpxVariants[index].error = 'Dosya seçilemedi: $e';
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
    final isRace = _isRace;

    // GPX opsiyonel: yalnızca dosyası seçilmiş/valid olan varyantları kaydet.
    final validVariants = _gpxVariants
        .where((v) =>
            v.isValid &&
            v.gpxContent != null &&
            v.gpxContent!.isNotEmpty &&
            v.gpxBytes != null)
        .map((v) => RouteGpxVariantInput(
              label: v.label.trim().isNotEmpty ? v.label.trim() : 'Default',
              gpxContent: v.gpxContent!,
              gpxBytes: v.gpxBytes!,
            ))
        .toList();

    if (_isEditMode) {
      await notifier.updateRouteWithGpxVariants(
        routeId: widget.routeId!,
        name: name,
        variants: validVariants,
        locationLat: _locationLat!,
        locationLng: _locationLng!,
        description: description,
        terrainType: terrainType,
        isRace: isRace,
        difficultyLevel: _difficultyLevel,
        locationName: null,
      );
    } else {
      await notifier.createFromGpxVariants(
        name: name,
        variants: validVariants,
        locationLat: _locationLat!,
        locationLng: _locationLng!,
        description: description,
        terrainType: terrainType,
        isRace: isRace,
        difficultyLevel: _difficultyLevel,
        locationName: null,
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
                    'Haritada dokunarak veya arama yaparak konum seçin',
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
