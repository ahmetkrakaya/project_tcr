import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../providers/group_provider.dart';

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
                  icon: const Icon(Icons.check),
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
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
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
              _buildDifficultySelector(),
              const SizedBox(height: 24),

              // Renk Seçimi
              Text('Grup Rengi', style: AppTypography.labelLarge),
              const SizedBox(height: 12),
              _buildColorSelector(),
              const SizedBox(height: 24),

              // İkon Seçimi
              Text('Grup İkonu', style: AppTypography.labelLarge),
              const SizedBox(height: 12),
              _buildIconSelector(),
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
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
                elevation: 8,
                shadowColor: AppColors.primary.withValues(alpha: 0.5),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    _targetDistanceFocusNode.unfocus();
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
            ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final color = _parseColor(_selectedColor);
    final iconData = _iconOptions
        .firstWhere(
          (i) => i['icon'] == _selectedIcon,
          orElse: () => _iconOptions.first,
        )['iconData'] as IconData;

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
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              iconData,
              color: Colors.white,
              size: 32,
            ),
          ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultySelector() {
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
                color: isSelected ? color.withValues(alpha: 0.2) : AppColors.neutral100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? color : AppColors.neutral200,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '$level',
                    style: AppTypography.titleMedium.copyWith(
                      color: isSelected ? color : AppColors.neutral600,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getDifficultyText(level),
                    style: AppTypography.labelSmall.copyWith(
                      color: isSelected ? color : AppColors.neutral500,
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
                ? const Icon(
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

  Widget _buildIconSelector() {
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
              color: isSelected ? color.withValues(alpha: 0.15) : AppColors.neutral100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : AppColors.neutral200,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Icon(
              option['iconData'] as IconData,
              color: isSelected ? color : AppColors.neutral500,
              size: 28,
            ),
          ),
        );
      }).toList(),
    );
  }

  void _submitForm() {
    if (!_formKey.currentState!.validate()) return;

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
      );
    }
  }

  Color _parseColor(String colorHex) {
    try {
      final hex = colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.primary;
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
