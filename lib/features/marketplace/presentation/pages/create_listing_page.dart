import 'dart:io' if (dart.library.html) 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/listing_model.dart';
import '../providers/marketplace_provider.dart';

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
  final List<XFile> _selectedImageFiles = [];
  bool _isSubmitting = false;
  
  // Beden bazlı stok yönetimi
  List<String> _sizes = [];
  final Map<String, TextEditingController> _stockBySizeControllers = {};

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
        _sizes.clear();
        setState(() {});
      }
      return;
    }

    // Bedenleri parse et (virgülle ayrılmış)
    final newSizes = sizeText.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    
    // Eğer bedenler değiştiyse controller'ları güncelle
    if (newSizes.join(',') != _sizes.join(',')) {
      // Eski controller'ları temizle
      for (final controller in _stockBySizeControllers.values) {
        controller.dispose();
      }
      _stockBySizeControllers.clear();
      
      // Yeni controller'ları oluştur
      _sizes = newSizes;
      for (final size in _sizes) {
        _stockBySizeControllers[size] = TextEditingController();
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
      _imageUrls = listing.imageUrls;
    });
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
                    color: AppColors.neutral500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
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
                  icon: const Icon(Icons.check),
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
              padding: const EdgeInsets.all(20),
              children: [
            // Category & Title Row
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _showCategoryMenu,
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: 56,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariantLight,
                        border: Border.all(
                          color: Colors.transparent,
                          width: 0,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _getCategoryName(_selectedCategory),
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.neutral500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            color: AppColors.neutral500,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppTextField(
                    controller: _titleController,
                    focusNode: _titleFocus,
                    hint: 'Ürün başlığı',
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) {
                      _descriptionFocus.requestFocus();
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Başlık gereklidir';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Description
            AppTextField(
              controller: _descriptionController,
              focusNode: _descriptionFocus,
              hint: 'Ürün açıklaması (opsiyonel)',
              maxLines: 4,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) {
                _priceFocus.requestFocus();
              },
            ),
            const SizedBox(height: 20),

            // Price & Brand Row
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _priceController,
                    focusNode: _priceFocus,
                    hint: 'Fiyat (₺)',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) {
                      _brandFocus.requestFocus();
                    },
                    
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
                const SizedBox(width: 16),
                Expanded(
                  child: AppTextField(
                    controller: _brandController,
                    focusNode: _brandFocus,
                    hint: 'Marka adı',
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) {
                      _sizeFocus.requestFocus();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Size & Stock Row
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _sizeController,
                    focusNode: _sizeFocus,
                    hint: 'Beden/Numara (virgülle ayırın: S, M, L)',
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) {
                      if (_sizes.isEmpty) {
                        _stockFocus.requestFocus();
                      }
                    },
                  ),
                ),
                if (_sizes.isEmpty) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: AppTextField(
                      controller: _stockQuantityController,
                      focusNode: _stockFocus,
                      hint: 'Stok (boş = sınırsız)',
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                    ),
                  ),
                ],
              ],
            ),
            
            // Beden Bazlı Stok Yönetimi
            if (_sizes.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.inventory_2,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Beden Bazlı Stok',
                          style: AppTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ..._sizes.map((size) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppTextField(
                          controller: _stockBySizeControllers[size]!,
                          hint: '$size beden stok miktarı (boş = stok yok)',
                          keyboardType: TextInputType.number,
                          textInputAction: _sizes.indexOf(size) == _sizes.length - 1
                              ? TextInputAction.done
                              : TextInputAction.next,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Images Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.neutral200,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.neutral300,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.photo_library, 
                        size: 20, 
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Görseller',
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildImagePicker(),
                ],
              ),
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
                return Positioned(
                  bottom: keyboardBottom + 16,
                  right: 20,
                  child: Material(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                    elevation: 8,
                    shadowColor: AppColors.primary.withValues(alpha: 0.5),
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
                        child: const Icon(
                          Icons.keyboard_hide,
                          size: 24,
                          color: Colors.white,
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

  void _showCategoryMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  color: AppColors.neutral300,
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
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
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
                          color: isSelected ? AppColors.primary : AppColors.onSurfaceLight,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle,
                              color: AppColors.primary,
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
      ),
    );
  }


  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected Images Grid
        if (_imageUrls.isNotEmpty || _selectedImageFiles.isNotEmpty)
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _imageUrls.length + _selectedImageFiles.length,
              itemBuilder: (context, index) {
                if (index < _imageUrls.length) {
                  // Existing uploaded image
                  return _buildImageThumbnail(
                    imageUrl: _imageUrls[index],
                    onDelete: () {
                      setState(() {
                        _imageUrls.removeAt(index);
                      });
                    },
                  );
                } else {
                  // New selected file
                  final fileIndex = index - _imageUrls.length;
                  return _buildImageThumbnail(
                    imageFile: _selectedImageFiles[fileIndex],
                    onDelete: () {
                      setState(() {
                        _selectedImageFiles.removeAt(fileIndex);
                      });
                    },
                  );
                }
              },
            ),
          ),
        const SizedBox(height: 12),
        // Add Image Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isSubmitting ? null : _pickImages,
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('Görsel Ekle'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        if (_selectedImageFiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_selectedImageFiles.length} görsel seçildi. Oluştur butonuna basıldığında yüklenecek.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
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
      width: 120,
      height: 120,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.neutral300),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl != null
                ? Image.network(
                    imageUrl,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: AppColors.neutral200,
                      child: const Icon(Icons.broken_image),
                    ),
                  )
                : kIsWeb
                    ? Image.network(
                        imageFile!.path,
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                      )
                    : Image.file(
                        File(imageFile!.path),
                        width: 120,
                        height: 120,
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
                icon: const Icon(Icons.close, size: 18, color: Colors.white),
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
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeriden Seç'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
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
      // Upload images first (if any selected)
      if (_selectedImageFiles.isNotEmpty) {
        await _uploadImages();
      }

      // Price is required, validation already done in form
      final price = double.parse(_priceController.text);
      
      // Stok yönetimi: Eğer beden varsa beden bazlı, yoksa genel stok
      int? stockQuantity;
      Map<String, int>? stockBySize;
      
      if (_sizes.isNotEmpty) {
        // Beden bazlı stok
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
        // Eğer hiç stok girilmemişse null yap
        if (stockBySize.isEmpty) {
          stockBySize = null;
        }
      } else {
        // Genel stok
        stockQuantity = _stockQuantityController.text.isEmpty
            ? null
            : int.tryParse(_stockQuantityController.text);
      }

      if (widget.listingId != null) {
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
              imageUrls: _imageUrls,
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
            );
      }

      if (mounted) {
        final result = ref.read(createListingProvider);
        result.when(
          data: (listing) async {
            if (listing != null) {
              // Refresh marketplace listings and wait for it to complete
              await ref.read(listingsProvider.notifier).refresh();
              
              if (mounted) {
                // Navigate to marketplace page after refresh
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
