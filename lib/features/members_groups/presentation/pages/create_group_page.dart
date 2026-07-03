import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../providers/group_provider.dart';
import '../widgets/group_avatar.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// Grup Oluşturma Sayfası (Admin/Coach)
class CreateGroupPage extends ConsumerStatefulWidget {
  final String? groupId; // Düzenleme için

  const CreateGroupPage({super.key, this.groupId});

  @override
  ConsumerState<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends ConsumerState<CreateGroupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _targetDistanceController = TextEditingController();
  final _descriptionFocusNode = FocusNode();
  final _targetDistanceFocusNode = FocusNode();

  int _selectedDifficulty = 1;
  String _selectedColor = '#3B82F6';
  String _selectedIcon = 'directions_run';
  String _selectedGroupType = 'normal';
  String _visualType = 'icon';
  String? _imageUrl;
  Uint8List? _localImageBytes;
  bool _isUploadingImage = false;
  String _targetDistanceUnit = 'km'; // km veya m
  bool _isEditing = false;

  final List<Map<String, dynamic>> _colorOptions = [
    {'color': '#EF4444', 'name': 'Kırmızı'},
    {'color': '#F59E0B', 'name': 'Turuncu'},
    {'color': '#10B981', 'name': 'Yeşil'},
    {'color': '#3B82F6', 'name': 'Mavi'},
    {'color': '#8B5CF6', 'name': 'Mor'},
    {'color': '#EC4899', 'name': 'Pembe'},
  ];

  final List<Map<String, dynamic>> _iconOptions = [
    {'icon': 'directions_run', 'name': 'Koşu', 'iconData': Icons.directions_run},
    {'icon': 'directions_walk', 'name': 'Yürüyüş', 'iconData': Icons.directions_walk},
    {'icon': 'accessibility_new', 'name': 'Başlangıç', 'iconData': Icons.accessibility_new},
    {'icon': 'fitness_center', 'name': 'Fitness', 'iconData': Icons.fitness_center},
    {'icon': 'sports', 'name': 'Spor', 'iconData': Icons.sports},
  ];

  @override
  void initState() {
    super.initState();
    // Grup adı ve hedef mesafe değiştiğinde önizlemeyi güncelle
    _nameController.addListener(() {
      setState(() {}); // Önizleme kartını güncellemek için
    });
    _targetDistanceController.addListener(() {
      setState(() {}); // Önizleme kartını güncellemek için
    });
    // Klavye kapatma butonunu göstermek/gizlemek için
    _targetDistanceFocusNode.addListener(() {
      setState(() {}); // Klavye kapatma butonunu güncellemek için
    });
    if (widget.groupId != null) {
      _isEditing = true;
      _loadGroupData();
    }
  }

  Future<void> _loadGroupData() async {
    try {
      final group = await ref.read(groupByIdProvider(widget.groupId!).future);
      setState(() {
        _nameController.text = group.name;
        _descriptionController.text = group.description ?? '';
        _targetDistanceController.text = group.targetDistance ?? '';
        _selectedDifficulty = group.difficultyLevel;
        _selectedColor = group.color;
        _selectedIcon = group.icon;
        _selectedGroupType = group.groupType;
        if (group.hasImage) {
          _visualType = 'photo';
          _imageUrl = group.imageUrl;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Grup yüklenemedi: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _targetDistanceController.dispose();
    _descriptionFocusNode.dispose();
    _targetDistanceFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final creationState = ref.watch(groupCreationProvider);
    final cs = Theme.of(context).colorScheme;

    ref.listen<GroupCreationState>(groupCreationProvider, (prev, next) {
      if (next.createdGroup != null && prev?.createdGroup != next.createdGroup) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Grup güncellendi' : 'Grup oluşturuldu'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
      if (next.error != null && prev?.error != next.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: ${next.error}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Grup Düzenle' : 'Yeni Grup'),
        actions: [
          creationState.isLoading
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
                  tooltip: _isEditing ? 'Güncelle' : 'Grup Oluştur',
                  onPressed: _submitForm,
                ),
        ],
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Önizleme
              _buildPreview(),
              const SizedBox(height: 24),

              // Grup Türü
              _buildGroupTypeSelector(context),
              const SizedBox(height: 24),

              // Grup Adı
              AppTextField(
                controller: _nameController,
                label: 'Grup Adı',
                hint: 'Örn: 21K, 10K, Yürü-Koş',
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _descriptionFocusNode.requestFocus(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Grup adı gerekli';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Açıklama
              AppTextField(
                controller: _descriptionController,
                focusNode: _descriptionFocusNode,
                label: 'Açıklama',
                hint: 'Grup hakkında kısa bilgi',
                maxLines: 3,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _targetDistanceFocusNode.requestFocus(),
              ),
              const SizedBox(height: 16),

              // Hedef Mesafe + Birim seçimi
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hedef Mesafe (Opsiyonel)',
                    style: AppTypography.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _targetDistanceController,
                          focusNode: _targetDistanceFocusNode,
                          label: null,
                          hint: 'Mesafe',
                          prefixIcon: Icons.straighten,
                          keyboardType: const TextInputType.numberWithOptions(decimal: false),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            // Done basıldığında formu gönder
                            if (!creationState.isLoading) {
                              _submitForm();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 100,
                        child: DropdownButtonFormField<String>(
                          value: _targetDistanceUnit,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'km',
                              child: Text('km'),
                            ),
                            DropdownMenuItem(
                              value: 'm',
                              child: Text('m'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _targetDistanceUnit = value;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Zorluk Seviyesi
              Text('Zorluk Seviyesi', style: AppTypography.labelLarge),
              const SizedBox(height: 12),
              _buildDifficultySelector(context),
              const SizedBox(height: 24),

              // Görsel Türü
              _buildVisualTypeSelector(context),
              const SizedBox(height: 24),

              // Renk Seçimi
              Text('Grup Rengi', style: AppTypography.labelLarge),
              const SizedBox(height: 12),
              _buildColorSelector(),
              const SizedBox(height: 24),

              if (_visualType == 'icon') ...[
                Text('Grup İkonu', style: AppTypography.labelLarge),
                const SizedBox(height: 12),
                _buildIconSelector(context),
              ] else ...[
                Text('Grup Fotoğrafı', style: AppTypography.labelLarge),
                const SizedBox(height: 12),
                _buildPhotoSelector(context),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
          // Klavye açıkken sağ üstte kapatma butonu (klavye üzerinde)
          if (_targetDistanceFocusNode.hasFocus)
            Positioned(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              right: 20,
              child: Material(
                color: cs.primary,
                borderRadius: BorderRadius.circular(20),
                elevation: 8,
                shadowColor: cs.primary.withValues(alpha: 0.5),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    _targetDistanceFocusNode.unfocus();
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
            ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final color = _parseColor(_selectedColor);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color,
            color.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildPreviewAvatar(),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nameController.text.isEmpty
                      ? 'Grup Adı'
                      : _nameController.text,
                  style: AppTypography.titleLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_targetDistanceController.text.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Hedef: ${_targetDistanceController.text} $_targetDistanceUnit',
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _selectedGroupType == 'performance' ? 'Performans Grubu' : 'Normal Grup',
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTypeSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Grup Türü', style: AppTypography.labelLarge),
        const SizedBox(height: 12),
        _buildGroupTypeOption(
          context,
          type: 'normal',
          title: 'Normal Grup',
          description: 'Antrenman programı tüm grup üyelerine uygulanır.',
          icon: Icons.groups_outlined,
        ),
        const SizedBox(height: 8),
        _buildGroupTypeOption(
          context,
          type: 'performance',
          title: 'Performans Grubu',
          description: 'Her üye için ayrı antrenman programı tanımlanır.',
          icon: Icons.star_outline,
        ),
        const SizedBox(height: 8),
        Text(
          'Her iki grup türüne katılım admin onayı ile yapılır.',
          style: AppTypography.bodySmall.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildGroupTypeOption(
    BuildContext context, {
    required String type,
    required String title,
    required String description,
    required IconData icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedGroupType == type;
    final accentColor = type == 'performance' ? cs.secondary : cs.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedGroupType = type),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: 0.12)
                : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? accentColor : cs.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isSelected ? accentColor : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: AppTypography.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: accentColor, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDifficultySelector(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: List.generate(5, (index) {
        final level = index + 1;
        final isSelected = _selectedDifficulty == level;
        final color = _getDifficultyColor(level);

        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedDifficulty = level),
            child: Container(
              margin: EdgeInsets.only(right: index < 4 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.2)
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? color : cs.outlineVariant,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '$level',
                    style: AppTypography.titleMedium.copyWith(
                      color: isSelected ? color : cs.onSurface,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getDifficultyText(level),
                    style: AppTypography.labelSmall.copyWith(
                      color: isSelected ? color : cs.onSurfaceVariant,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildColorSelector() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _colorOptions.map((option) {
        final color = _parseColor(option['color'] as String);
        final isSelected = _selectedColor == option['color'];

        return GestureDetector(
          onTap: () => setState(() => _selectedColor = option['color'] as String),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 3,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: isSelected
                ? Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 24,
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPreviewAvatar() {
    if (_visualType == 'photo' && _localImageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          _localImageBytes!,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
        ),
      );
    }

    return GroupAvatar(
      imageUrl: _visualType == 'photo' ? _imageUrl : null,
      icon: _selectedIcon,
      color: _selectedColor,
      size: 64,
      borderRadius: 16,
      isPerformanceGroup: _selectedGroupType == 'performance',
    );
  }

  Widget _buildVisualTypeSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Görsel', style: AppTypography.labelLarge),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildVisualTypeChip(
                context,
                type: 'icon',
                label: 'İkon',
                icon: Icons.emoji_emotions_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildVisualTypeChip(
                context,
                type: 'photo',
                label: 'Fotoğraf',
                icon: Icons.photo_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVisualTypeChip(
    BuildContext context, {
    required String type,
    required String label,
    required IconData icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _visualType == type;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _visualType = type),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? cs.primary.withValues(alpha: 0.12)
                : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? cs.primary : cs.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? cs.primary : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoSelector(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPhoto =
        _localImageBytes != null || (_imageUrl != null && _imageUrl!.isNotEmpty);

    return Center(
      child: Stack(
        children: [
          GestureDetector(
            onTap: _isUploadingImage ? null : _pickGroupPhoto,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: _isUploadingImage
                  ? const Center(child: CircularProgressIndicator())
                  : hasPhoto
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: _localImageBytes != null
                              ? Image.memory(
                                  _localImageBytes!,
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                )
                              : GroupAvatar(
                                  imageUrl: _imageUrl,
                                  icon: _selectedIcon,
                                  color: _selectedColor,
                                  size: 120,
                                  borderRadius: 20,
                                ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_a_photo_outlined,
                              size: 32,
                              color: cs.outline,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Fotoğraf Seç',
                              style: AppTypography.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
            ),
          ),
          if (hasPhoto && !_isUploadingImage)
            Positioned(
              right: 0,
              bottom: 0,
              child: Material(
                color: cs.primary,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: Icon(Icons.edit, color: cs.onPrimary, size: 18),
                  onPressed: _pickGroupPhoto,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickGroupPhoto() async {
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
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (pickedFile == null) return;

      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _localImageBytes = bytes;
        _visualType = 'photo';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf seçilemedi: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<String?> _uploadGroupImage() async {
    if (_localImageBytes == null) return _imageUrl;

    setState(() => _isUploadingImage = true);
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Kullanıcı bulunamadı');

      final groupKey = widget.groupId ?? userId;
      final fileName =
          '$groupKey/group_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage.from('group-images').uploadBinary(
            fileName,
            _localImageBytes!,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      return supabase.storage.from('group-images').getPublicUrl(fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf yüklenemedi: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  Widget _buildIconSelector(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _iconOptions.map((option) {
        final isSelected = _selectedIcon == option['icon'];
        final color = _parseColor(_selectedColor);

        return GestureDetector(
          onTap: () => setState(() => _selectedIcon = option['icon'] as String),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.15)
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : cs.outlineVariant,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Icon(
              option['iconData'] as IconData,
              color: isSelected ? color : cs.onSurfaceVariant,
              size: 28,
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_visualType == 'photo' &&
        _localImageBytes == null &&
        (_imageUrl == null || _imageUrl!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir grup fotoğrafı seçin')),
      );
      return;
    }

    String? finalImageUrl;
    if (_visualType == 'photo') {
      finalImageUrl = await _uploadGroupImage();
      if (finalImageUrl == null && _localImageBytes != null) return;
    }

    final notifier = ref.read(groupCreationProvider.notifier);

    if (_isEditing) {
      notifier.updateGroup(
        groupId: widget.groupId!,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        targetDistance: _targetDistanceController.text.trim().isNotEmpty
            ? _targetDistanceController.text.trim()
            : null,
        difficultyLevel: _selectedDifficulty,
        color: _selectedColor,
        icon: _selectedIcon,
        imageUrl: finalImageUrl,
        groupType: _selectedGroupType,
      );
    } else {
      notifier.createGroup(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        targetDistance: _targetDistanceController.text.trim().isNotEmpty
            ? _targetDistanceController.text.trim()
            : null,
        difficultyLevel: _selectedDifficulty,
        color: _selectedColor,
        icon: _selectedIcon,
        imageUrl: finalImageUrl,
        groupType: _selectedGroupType,
      );
    }
  }

  Color _parseColor(String colorHex) {
    try {
      final hex = colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return ThemeBrightnessHolder.primary;
    }
  }

  Color _getDifficultyColor(int level) {
    switch (level) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.lightGreen;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.deepOrange;
      case 5:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getDifficultyText(int level) {
    switch (level) {
      case 1:
        return 'Başlangıç';
      case 2:
        return 'Kolay';
      case 3:
        return 'Orta';
      case 4:
        return 'Zor';
      case 5:
        return 'Çok Zor';
      default:
        return '';
    }
  }
}
