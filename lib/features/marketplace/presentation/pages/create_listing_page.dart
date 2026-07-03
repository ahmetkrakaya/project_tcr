import 'dart:io' if (dart.library.html) 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/enums/gender.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/listing_model.dart';
import '../../utils/listing_price_utils.dart';
import '../providers/marketplace_provider.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// Create Listing Page
class CreateListingPage extends ConsumerStatefulWidget {
  final String? listingId;

  const CreateListingPage({super.key, this.listingId});

  @override
  ConsumerState<CreateListingPage> createState() => _CreateListingPageState();
}

class _CreateListingPageState extends ConsumerState<CreateListingPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _brandController = TextEditingController();
  final _sizeController = TextEditingController();
  final _externalUrlController = TextEditingController();
  final _stockQuantityController = TextEditingController();
  final _discountPercentController = TextEditingController();

  bool _discountEnabled = false;
  DateTime? _discountStartsAt;
  DateTime? _discountEndsAt;

  // Focus nodes for keyboard navigation
  final _titleFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _brandFocus = FocusNode();
  final _sizeFocus = FocusNode();
  final _stockFocus = FocusNode();

  ListingType _selectedType = ListingType.tcrProduct;
  ListingCategory _selectedCategory = ListingCategory.other;
  List<String> _imageUrls = [];
  List<String> _originalImageUrls = [];
  final List<XFile> _selectedImageFiles = [];
  bool _isSubmitting = false;
  ListingGenderMode _stockGenderMode = ListingGenderMode.unisex;

  // Beden bazlı stok yönetimi
  List<String> _sizes = [];
  final Map<String, TextEditingController> _stockBySizeControllers = {};
  final Map<String, Map<ListingGender, TextEditingController>>
      _stockBySizeGenderControllers = {};

  @override
  void initState() {
    super.initState();
    if (widget.listingId != null) {
      _loadListingData();
    }
    // Focus listeners for keyboard close button
    _priceFocus.addListener(_onFocusChange);
    _stockFocus.addListener(_onFocusChange);
    // Size controller listener for beden bazlı stok
    _sizeController.addListener(_onSizeChanged);
  }

  void _onFocusChange() {
    setState(() {});
  }

  void _onSizeChanged() {
    final sizeText = _sizeController.text.trim();
    if (sizeText.isEmpty) {
      // Beden yoksa, beden bazlı stok controller'ları temizle
      if (_sizes.isNotEmpty) {
        for (final controller in _stockBySizeControllers.values) {
          controller.dispose();
        }
        _stockBySizeControllers.clear();
        for (final genderMap in _stockBySizeGenderControllers.values) {
          for (final controller in genderMap.values) {
            controller.dispose();
          }
        }
        _stockBySizeGenderControllers.clear();
        _sizes.clear();
        setState(() {});
      }
      return;
    }

    // Bedenleri parse et (virgülle ayrılmış)
    final newSizes = sizeText.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    
    // Eğer bedenler değiştiyse controller'ları güncelle
    if (newSizes.join(',') != _sizes.join(',')) {
      // Mevcut değerleri kaydet
      final savedUnisex = <String, String>{};
      final savedMale = <String, String>{};
      final savedFemale = <String, String>{};
      for (final size in _sizes) {
        savedUnisex[size] = _stockBySizeControllers[size]?.text ?? '';
        savedMale[size] = _stockBySizeGenderControllers[size]?[ListingGender.male]?.text ?? '';
        savedFemale[size] = _stockBySizeGenderControllers[size]?[ListingGender.female]?.text ?? '';
      }

      // Artık kullanılmayan bedenlerin controller'larını dispose et
      for (final size in _sizes) {
        if (!newSizes.contains(size)) {
          _stockBySizeControllers[size]?.dispose();
          _stockBySizeControllers.remove(size);
          _stockBySizeGenderControllers[size]?.values.forEach((c) => c.dispose());
          _stockBySizeGenderControllers.remove(size);
        }
      }

      // Yeni bedenlere controller oluştur, eskiler varsa değerlerini koru
      _sizes = newSizes;
      for (final size in _sizes) {
        if (!_stockBySizeControllers.containsKey(size)) {
          _stockBySizeControllers[size] = TextEditingController(
            text: savedUnisex[size] ?? '',
          );
        }
        if (!_stockBySizeGenderControllers.containsKey(size)) {
          _stockBySizeGenderControllers[size] = {
            ListingGender.male: TextEditingController(
              text: savedMale[size] ?? '',
            ),
            ListingGender.female: TextEditingController(
              text: savedFemale[size] ?? '',
            ),
          };
        }
      }
      setState(() {});
    }
  }

  Future<void> _loadListingData() async {
    if (widget.listingId == null) return;

    final listing = await ref.read(listingByIdProvider(widget.listingId!).future);
    if (!mounted) return;

    setState(() {
      _titleController.text = listing.title;
      _descriptionController.text = listing.description ?? '';
      _priceController.text = listing.price?.toStringAsFixed(0) ?? '';
      _brandController.text = listing.brand ?? '';
      _sizeController.text = listing.size ?? '';
      _externalUrlController.text = listing.externalUrl ?? '';
      _stockQuantityController.text = listing.stockQuantity?.toString() ?? '';
      _selectedType = listing.listingType;
      _selectedCategory = listing.category;
      _imageUrls = List<String>.from(listing.imageUrls);
      _originalImageUrls = List<String>.from(listing.imageUrls);
      _stockGenderMode = listing.stockGenderMode;
      _discountEnabled = listing.discountPercent != null;
      _discountPercentController.text =
          listing.discountPercent?.toString() ?? '';
      _discountStartsAt = listing.discountStartsAt?.toLocal();
      _discountEndsAt = listing.discountEndsAt?.toLocal();
    });

    // Beden bazlı stok alanlarını populate et
    _onSizeChanged();

    if (listing.stockGenderMode == ListingGenderMode.gendered &&
        listing.stockBySizeAndGender != null &&
        listing.stockBySizeAndGender!.isNotEmpty) {
      listing.stockBySizeAndGender!.forEach((size, genderMap) {
        final controllers = _stockBySizeGenderControllers[size];
        if (controllers != null) {
          final maleQty = genderMap[ListingGender.male];
          final femaleQty = genderMap[ListingGender.female];
          if (maleQty != null) {
            controllers[ListingGender.male]?.text = maleQty.toString();
          }
          if (femaleQty != null) {
            controllers[ListingGender.female]?.text = femaleQty.toString();
          }
        }
      });
    } else if (listing.stockBySize != null &&
        listing.stockBySize!.isNotEmpty) {
      listing.stockBySize!.forEach((size, qty) {
        final controller = _stockBySizeControllers[size];
        if (controller != null) {
          controller.text = qty.toString();
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _brandController.dispose();
    _sizeController.removeListener(_onSizeChanged);
    _sizeController.dispose();
    _externalUrlController.dispose();
    _stockQuantityController.dispose();
    _discountPercentController.dispose();
    _priceFocus.removeListener(_onFocusChange);
    _stockFocus.removeListener(_onFocusChange);
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    _priceFocus.dispose();
    _brandFocus.dispose();
    _sizeFocus.dispose();
    _stockFocus.dispose();
    // Beden bazlı stok controller'larını temizle
    for (final controller in _stockBySizeControllers.values) {
      controller.dispose();
    }
    _stockBySizeControllers.clear();
    for (final genderMap in _stockBySizeGenderControllers.values) {
      for (final controller in genderMap.values) {
        controller.dispose();
      }
    }
    _stockBySizeGenderControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.listingId != null;
    final isAdmin = ref.watch(isAdminProvider);

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Yeni İlan'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 64, color: AppColors.error),
                const SizedBox(height: 16),
                Text(
                  'Sadece adminler ilan oluşturabilir',
                  style: AppTypography.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'TCR ürünleri sadece adminler tarafından oluşturulabilir.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: ThemeBrightnessHolder.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBackground =
        ThemeBrightnessHolder.scaffoldBackground;

    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        title: Text(isEdit ? 'İlanı Düzenle' : 'Yeni İlan'),
        actions: [
          _isSubmitting
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: Icon(Icons.check),
                  tooltip: isEdit ? 'Güncelle' : 'Oluştur',
                  onPressed: _handleSubmit,
                ),
        ],
      ),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                _buildFormSection(
                  title: 'Görseller',
                  subtitle: 'Ürün fotoğraflarını ekleyin',
                  child: _buildImagePicker(),
                ),
                const SizedBox(height: 24),
                _buildFormSection(
                  title: 'Temel Bilgiler',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCategoryField(),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _titleController,
                        focusNode: _titleFocus,
                        hint: 'Ürün başlığı',
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _descriptionFocus.requestFocus(),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Başlık gereklidir';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _descriptionController,
                        focusNode: _descriptionFocus,
                        hint: 'Ürün açıklaması (opsiyonel)',
                        maxLines: 4,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _priceFocus.requestFocus(),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _priceController,
                              focusNode: _priceFocus,
                              hint: 'Fiyat (₺)',
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => _brandFocus.requestFocus(),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Fiyat gereklidir';
                                }
                                final price = double.tryParse(value);
                                if (price == null || price <= 0) {
                                  return 'Geçerli bir fiyat giriniz';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: _brandController,
                              focusNode: _brandFocus,
                              hint: 'Marka adı',
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => _sizeFocus.requestFocus(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildFormSection(
                  title: 'İndirim',
                  subtitle: 'Belirli bir süre için yüzde indirim uygulayın',
                  child: _buildDiscountSection(),
                ),
                const SizedBox(height: 24),
                _buildFormSection(
                  title: 'Beden & Stok',
                  subtitle: 'Beden girerseniz her beden için ayrı stok tanımlayın',
                  child: _buildStockSection(),
                ),
              ],
            ),
          ),
          // Klavye açıkken sağ üstte kapatma butonu (klavye üzerinde)
          Builder(
            builder: (context) {
              final priceHasFocus = _priceFocus.hasFocus;
              final stockHasFocus = _stockFocus.hasFocus;
              final keyboardBottom = MediaQuery.of(context).viewInsets.bottom;
              final shouldShow = priceHasFocus || stockHasFocus;
              
              if (shouldShow) {
                final cs = Theme.of(context).colorScheme;
                return Positioned(
                  bottom: keyboardBottom + 16,
                  right: 20,
                  child: Material(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(20),
                    elevation: 8,
                    shadowColor: cs.primary.withValues(alpha: 0.5),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        if (_priceFocus.hasFocus) {
                          _priceFocus.unfocus();
                        }
                        if (_stockFocus.hasFocus) {
                          _stockFocus.unfocus();
                        }
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.keyboard_hide,
                          size: 24,
                          color: cs.onPrimary,
                        ),
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFormSection({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    final panelColor = cs.surfaceContainerHighest;
    final borderColor = cs.outlineVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: AppTypography.labelSmall.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTypography.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildCategoryField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: _showCategoryMenu,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: ThemeBrightnessHolder.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeBrightnessHolder.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kategori',
                    style: AppTypography.labelSmall.copyWith(
                      color: ThemeBrightnessHolder.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getCategoryName(_selectedCategory),
                    style: AppTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: ThemeBrightnessHolder.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountSection() {
    final dateFormat = DateFormat('d MMM yyyy, HH:mm', 'tr_TR');
    final basePrice = double.tryParse(_priceController.text.trim());
    final percent = int.tryParse(_discountPercentController.text.trim());
  final previewListing = (_discountEnabled &&
          basePrice != null &&
          percent != null &&
          _discountStartsAt != null &&
          _discountEndsAt != null)
      ? ListingModel(
          id: '',
          sellerId: '',
          listingType: _selectedType,
          category: _selectedCategory,
          title: _titleController.text,
          price: basePrice,
          discountPercent: percent,
          discountStartsAt: _discountStartsAt,
          discountEndsAt: _discountEndsAt,
          createdAt: DateTime.now(),
        )
      : null;
    final previewPrice = previewListing != null
        ? listingDisplayPrice(previewListing)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('İndirim uygula'),
          subtitle: const Text('Süreli kampanya fiyatı tanımlayın'),
          value: _discountEnabled,
          activeThumbColor: Theme.of(context).colorScheme.primary,
          activeTrackColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
          onChanged: (value) {
            setState(() {
              _discountEnabled = value;
              if (value && _discountStartsAt == null) {
                final now = DateTime.now();
                _discountStartsAt = DateTime(
                  now.year,
                  now.month,
                  now.day,
                  now.hour,
                  now.minute,
                );
                _discountEndsAt = _discountStartsAt!.add(const Duration(days: 7));
              }
            });
          },
        ),
        if (_discountEnabled) ...[
          const SizedBox(height: 8),
          AppTextField(
            controller: _discountPercentController,
            hint: 'İndirim oranı (%)',
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            validator: (value) {
              if (!_discountEnabled) return null;
              if (value == null || value.trim().isEmpty) {
                return 'İndirim oranı gerekli';
              }
              final parsed = int.tryParse(value.trim());
              if (parsed == null || parsed < 1 || parsed > 100) {
                return '1-100 arası bir değer girin';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _buildDiscountDateTile(
            label: 'Başlangıç',
            value: _discountStartsAt,
            dateFormat: dateFormat,
            onPick: () => _pickDiscountDateTime(isStart: true),
          ),
          const SizedBox(height: 8),
          _buildDiscountDateTile(
            label: 'Bitiş',
            value: _discountEndsAt,
            dateFormat: dateFormat,
            onPick: () => _pickDiscountDateTime(isStart: false),
          ),
          if (previewPrice != null) ...[
            const SizedBox(height: 12),
            Text(
              'İndirimli fiyat: ₺${formatListingPrice(previewPrice)}',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildDiscountDateTile({
    required String label,
    required DateTime? value,
    required DateFormat dateFormat,
    required VoidCallback onPick,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: ThemeBrightnessHolder.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeBrightnessHolder.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.labelSmall.copyWith(
                      color: ThemeBrightnessHolder.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value != null ? dateFormat.format(value) : 'Tarih seçin',
                    style: AppTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.calendar_today_outlined, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDiscountDateTime({required bool isStart}) async {
    final initial = isStart
        ? (_discountStartsAt ?? DateTime.now())
        : (_discountEndsAt ?? _discountStartsAt?.add(const Duration(days: 7)) ?? DateTime.now());

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isStart) {
        _discountStartsAt = picked;
        if (_discountEndsAt != null && !_discountEndsAt!.isAfter(picked)) {
          _discountEndsAt = picked.add(const Duration(days: 1));
        }
      } else {
        _discountEndsAt = picked;
      }
    });
  }

  ({int? percent, DateTime? startsAt, DateTime? endsAt}) _resolveDiscountFields() {
    if (!_discountEnabled) {
      return (percent: null, startsAt: null, endsAt: null);
    }

    final percent = int.tryParse(_discountPercentController.text.trim());
    if (percent == null || percent < 1 || percent > 100) {
      throw const FormatException('Geçerli bir indirim oranı girin (1-100)');
    }
    if (_discountStartsAt == null || _discountEndsAt == null) {
      throw const FormatException('İndirim başlangıç ve bitiş tarihlerini seçin');
    }
    if (!_discountEndsAt!.isAfter(_discountStartsAt!)) {
      throw const FormatException('Bitiş tarihi başlangıçtan sonra olmalı');
    }

    return (
      percent: percent,
      startsAt: _discountStartsAt,
      endsAt: _discountEndsAt,
    );
  }

  Widget _buildStockSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stok tipi',
          style: AppTypography.labelMedium.copyWith(
            color: ThemeBrightnessHolder.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ThemeBrightnessHolder.outlineVariant),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              _buildStockGenderModeChip(
                mode: ListingGenderMode.unisex,
                label: 'Unisex',
              ),
              const SizedBox(width: 4),
              _buildStockGenderModeChip(
                mode: ListingGenderMode.gendered,
                label: 'Erkek / Kadın',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _sizeController,
          focusNode: _sizeFocus,
          hint: 'Beden / numara (ör. S, M, L)',
          textInputAction: TextInputAction.next,
          onSubmitted: (_) {
            if (_sizes.isEmpty) {
              _stockFocus.requestFocus();
            }
          },
        ),
        if (_sizes.isEmpty &&
            _stockGenderMode == ListingGenderMode.unisex) ...[
          const SizedBox(height: 16),
          AppTextField(
            controller: _stockQuantityController,
            focusNode: _stockFocus,
            hint: 'Genel stok (boş = sınırsız)',
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
          ),
        ],
        if (_sizes.isNotEmpty &&
            _stockGenderMode == ListingGenderMode.unisex) ...[
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Text(
            'Beden bazlı stok',
            style: AppTypography.labelMedium.copyWith(
              color: ThemeBrightnessHolder.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ..._sizes.asMap().entries.map((entry) {
            final index = entry.key;
            final size = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == _sizes.length - 1 ? 0 : 12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    height: 48,
                    child: Center(
                      child: Text(
                        size,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppTextField(
                      controller: _stockBySizeControllers[size]!,
                      hint: 'Stok adedi',
                      keyboardType: TextInputType.number,
                      textInputAction: index == _sizes.length - 1
                          ? TextInputAction.done
                          : TextInputAction.next,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        if (_sizes.isNotEmpty &&
            _stockGenderMode == ListingGenderMode.gendered) ...[
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Text(
            'Beden + cinsiyet stoku',
            style: AppTypography.labelMedium.copyWith(
              color: ThemeBrightnessHolder.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ..._sizes.asMap().entries.map((entry) {
            final index = entry.key;
            final size = entry.value;
            final controllers = _stockBySizeGenderControllers[size]!;
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == _sizes.length - 1 ? 0 : 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    size,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: controllers[ListingGender.male]!,
                          hint: 'Erkek',
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppTextField(
                          controller: controllers[ListingGender.female]!,
                          hint: 'Kadın',
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  String _getCategoryName(ListingCategory category) {
    switch (category) {
      case ListingCategory.runningShoes:
        return 'Koşu Ayakkabısı';
      case ListingCategory.sportsWear:
        return 'Spor Giyim';
      case ListingCategory.accessories:
        return 'Aksesuar';
      case ListingCategory.watchesTrackers:
        return 'Saat/Takip Cihazı';
      case ListingCategory.nutrition:
        return 'Beslenme';
      case ListingCategory.equipment:
        return 'Ekipman';
      case ListingCategory.books:
        return 'Kitap';
      case ListingCategory.other:
        return 'Diğer';
    }
  }

  Widget _buildStockGenderModeChip({
    required ListingGenderMode mode,
    required String label,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _stockGenderMode == mode;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _stockGenderMode = mode;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? cs.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: AppTypography.titleSmall.copyWith(
                color: isSelected ? cs.onPrimary : cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCategoryMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text(
                      'Kategori Seçin',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              // Category List
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: ListingCategory.values.length,
                  itemBuilder: (context, index) {
                    final category = ListingCategory.values[index];
                    final isSelected = category == _selectedCategory;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      title: Text(
                        _getCategoryName(category),
                        style: AppTypography.bodyLarge.copyWith(
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected ? cs.primary : cs.onSurface,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle,
                              color: cs.primary,
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedCategory = category;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      },
    );
  }


  Widget _buildImagePicker() {
    final hasImages =
        _imageUrls.isNotEmpty || _selectedImageFiles.isNotEmpty;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasImages) ...[
          SizedBox(
            height: 108,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _imageUrls.length + _selectedImageFiles.length,
              itemBuilder: (context, index) {
                if (index < _imageUrls.length) {
                  return _buildImageThumbnail(
                    imageUrl: _imageUrls[index],
                    onDelete: () {
                      setState(() {
                        _imageUrls.removeAt(index);
                      });
                    },
                  );
                }

                final fileIndex = index - _imageUrls.length;
                return _buildImageThumbnail(
                  imageFile: _selectedImageFiles[fileIndex],
                  onDelete: () {
                    setState(() {
                      _selectedImageFiles.removeAt(fileIndex);
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isSubmitting ? null : _pickImages,
            icon: Icon(Icons.add_photo_alternate_outlined),
            label: Text(hasImages ? 'Görsel Ekle' : 'İlk görseli ekle'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.primary,
              side: BorderSide(
                color: cs.primary.withValues(alpha: 0.4),
              ),
              backgroundColor: cs.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        if (_selectedImageFiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${_selectedImageFiles.length} görsel kayıt sırasında yüklenecek',
              style: AppTypography.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageThumbnail({
    String? imageUrl,
    XFile? imageFile,
    required VoidCallback onDelete,
  }) {
    return Container(
      width: 108,
      height: 108,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeBrightnessHolder.outlineVariant),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imageUrl != null
                ? Image.network(
                    imageUrl,
                    width: 108,
                    height: 108,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: AppColors.neutral200,
                      child: Icon(Icons.broken_image),
                    ),
                  )
                : kIsWeb
                    ? Image.network(
                        imageFile!.path,
                        width: 108,
                        height: 108,
                        fit: BoxFit.cover,
                      )
                    : Image.file(
                        File(imageFile!.path),
                        width: 108,
                        height: 108,
                        fit: BoxFit.cover,
                      ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.close, size: 18, color: Colors.white),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onDelete,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImages() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.photo_library),
              title: const Text('Galeriden Seç'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt),
              title: const Text('Kamera ile Çek'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFiles.isEmpty) return;

      setState(() {
        _selectedImageFiles.addAll(pickedFiles);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Görsel seçilemedi: $e')),
        );
      }
    }
  }

  Future<void> _uploadImages() async {
    if (_selectedImageFiles.isEmpty) return;

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      if (userId == null) {
        throw Exception('Kullanıcı bulunamadı');
      }

      final uploadedUrls = <String>[];

      for (final xFile in _selectedImageFiles) {
        final fileExt = xFile.name.split('.').last;
        final fileName =
            'listing_${userId}_${DateTime.now().millisecondsSinceEpoch}_${uploadedUrls.length}.$fileExt';

        // Upload to storage (bytes ile hem web hem mobil uyumlu)
        final bytes = await xFile.readAsBytes();
        await supabase.storage.from('listing-images').uploadBinary(
              fileName,
              bytes,
              fileOptions: FileOptions(upsert: true, contentType: 'image/$fileExt'),
            );

        // Get public URL
        final publicUrl =
            supabase.storage.from('listing-images').getPublicUrl(fileName);

        uploadedUrls.add(publicUrl);
      }

      setState(() {
        _imageUrls.addAll(uploadedUrls);
        _selectedImageFiles.clear();
      });
    } catch (e) {
      throw Exception('Görseller yüklenemedi: $e');
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      late final ({int? percent, DateTime? startsAt, DateTime? endsAt}) discountFields;
      try {
        discountFields = _resolveDiscountFields();
      } on FormatException catch (e) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
        return;
      }

      // Upload images first (if any selected)
      if (_selectedImageFiles.isNotEmpty) {
        await _uploadImages();
      }

      // Price is required, validation already done in form
      final price = double.parse(_priceController.text);
      
      // Stok yönetimi
      int? stockQuantity;
      Map<String, int>? stockBySize;
      Map<String, Map<ListingGender, int>>? stockBySizeAndGender;
      
      if (_sizes.isNotEmpty &&
          _stockGenderMode == ListingGenderMode.gendered) {
        // Beden + cinsiyet bazlı stok
        stockBySizeAndGender = {};
        for (final size in _sizes) {
          final genderControllers = _stockBySizeGenderControllers[size];
          if (genderControllers == null) continue;

          final maleText = genderControllers[ListingGender.male]!.text.trim();
          final femaleText = genderControllers[ListingGender.female]!.text.trim();

          final byGender = <ListingGender, int>{};
          if (maleText.isNotEmpty) {
            final qty = int.tryParse(maleText);
            if (qty != null && qty >= 0) {
              byGender[ListingGender.male] = qty;
            }
          }
          if (femaleText.isNotEmpty) {
            final qty = int.tryParse(femaleText);
            if (qty != null && qty >= 0) {
              byGender[ListingGender.female] = qty;
            }
          }

          if (byGender.isNotEmpty) {
            stockBySizeAndGender[size] = byGender;
          }
        }

        if (stockBySizeAndGender.isEmpty) {
          stockBySizeAndGender = null;
        }
      } else if (_sizes.isNotEmpty) {
        // Beden bazlı stok (unisex)
        stockBySize = {};
        for (final size in _sizes) {
          final controller = _stockBySizeControllers[size];
          if (controller != null && controller.text.trim().isNotEmpty) {
            final quantity = int.tryParse(controller.text.trim());
            if (quantity != null && quantity >= 0) {
              stockBySize[size] = quantity;
            }
          }
        }
        if (stockBySize.isEmpty) {
          stockBySize = null;
        }
      } else {
        // Genel stok (sadece unisex)
        stockQuantity = _stockQuantityController.text.isEmpty
            ? null
            : int.tryParse(_stockQuantityController.text);
      }

      if (widget.listingId != null) {
        // Görseller değiştiyse (yeni yükleme ya da kaldırma) güncelle, yoksa dokunma
        final imagesChanged = _imageUrls.length != _originalImageUrls.length ||
            !_imageUrls.every((url) => _originalImageUrls.contains(url));

        // Update
        await ref.read(createListingProvider.notifier).updateListing(
              listingId: widget.listingId!,
              listingType: _selectedType,
              category: _selectedCategory,
              title: _titleController.text,
              description: _descriptionController.text.isEmpty
                  ? null
                  : _descriptionController.text,
              price: price,
              condition: null,
              brand: _brandController.text.isEmpty ? null : _brandController.text,
              size: _sizeController.text.isEmpty ? null : _sizeController.text,
              externalUrl: _externalUrlController.text.isEmpty
                  ? null
                  : _externalUrlController.text,
              stockQuantity: stockQuantity,
              stockBySize: stockBySize,
              imageUrls: imagesChanged ? _imageUrls : null,
              stockGenderMode: _stockGenderMode,
              stockBySizeAndGender: stockBySizeAndGender,
              discountPercent: discountFields.percent,
              discountStartsAt: discountFields.startsAt,
              discountEndsAt: discountFields.endsAt,
            );
      } else {
        // Create
        await ref.read(createListingProvider.notifier).createListing(
              listingType: _selectedType,
              category: _selectedCategory,
              title: _titleController.text,
              description: _descriptionController.text.isEmpty
                  ? null
                  : _descriptionController.text,
              price: price,
              condition: null,
              brand: _brandController.text.isEmpty ? null : _brandController.text,
              size: _sizeController.text.isEmpty ? null : _sizeController.text,
              externalUrl: _externalUrlController.text.isEmpty
                  ? null
                  : _externalUrlController.text,
              stockQuantity: stockQuantity,
              stockBySize: stockBySize,
              imageUrls: _imageUrls,
              stockGenderMode: _stockGenderMode,
              stockBySizeAndGender: stockBySizeAndGender,
              discountPercent: discountFields.percent,
              discountStartsAt: discountFields.startsAt,
              discountEndsAt: discountFields.endsAt,
            );
      }

      if (mounted) {
        final result = ref.read(createListingProvider);
        result.when(
          data: (listing) async {
            if (listing != null) {
              // Liste önbelleğini yenile
              await ref.read(listingsProvider.notifier).refresh();

              // Detay ve kullanıcı ilanları önbelleklerini geçersiz kıl
              ref.invalidate(listingByIdProvider(listing.id));
              ref.invalidate(userListingsProvider);

              if (!mounted) return;

              if (widget.listingId != null) {
                // Edit sonrası ilan detayına dön
                context.goNamed(
                  RouteNames.listingDetail,
                  pathParameters: {'listingId': listing.id},
                );
              } else {
                // Yeni ilan sonrası marketplace listesine dön
                context.goNamed(RouteNames.marketplace);
              }
            }
          },
          loading: () {},
          error: (error, stack) {
            setState(() {
              _isSubmitting = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Hata: $error'),
                backgroundColor: AppColors.error,
              ),
            );
          },
        );
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bir hata oluştu: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
