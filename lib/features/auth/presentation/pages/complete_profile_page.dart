import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/ui/responsive.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../providers/auth_notifier.dart';

/// Complete Profile Page
class CompleteProfilePage extends ConsumerStatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  ConsumerState<CompleteProfilePage> createState() =>
      _CompleteProfilePageState();
}

class _CompleteProfilePageState extends ConsumerState<CompleteProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _weightController = TextEditingController();

  String? _selectedBloodType;
  String? _selectedTShirtSize;
  String? _shoeSize;
  String? _selectedGender;
  DateTime? _selectedBirthDate;

  bool _isLoading = false;

  final List<String> _bloodTypes = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Bilmiyorum'
  ];

  final List<String> _tshirtSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'];

  final List<String> _genders = [
    'Kadın',
    'Erkek',
    'Belirtmek istemiyorum',
  ];

  String? _genderLabelToCode(String? label) {
    switch (label) {
      case 'Kadın':
        return 'female';
      case 'Erkek':
        return 'male';
      case 'Belirtmek istemiyorum':
        return 'unknown';
      default:
        return null;
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _birthDateController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initialDate = _selectedBirthDate ??
        DateTime(now.year - 25, now.month, now.day);
    final firstDate = DateTime(1900);
    final lastDate = now;

    final picked = await showDatePicker(
      context: context,
      initialDate:
          initialDate.isBefore(firstDate) || initialDate.isAfter(lastDate)
              ? lastDate
              : initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Doğum Tarihini Seç',
    );

    if (picked != null) {
      setState(() {
        _selectedBirthDate = picked;
        _birthDateController.text = _formatDate(picked);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final genderCode = _genderLabelToCode(_selectedGender);
      final birthDateIso =
          _selectedBirthDate?.toIso8601String().split('T').first;
      final weightValue = _weightController.text.trim().isNotEmpty
          ? double.tryParse(_weightController.text.trim())
          : null;

      await ref.read(authNotifierProvider.notifier).updateProfile(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            phone: _phoneController.text.trim().isNotEmpty
                ? _phoneController.text.trim()
                : null,
            bloodType: _selectedBloodType == 'Bilmiyorum'
                ? 'unknown'
                : _selectedBloodType,
            tshirtSize: _selectedTShirtSize,
            shoeSize: _shoeSize,
            gender: genderCode,
            birthDate: birthDateIso,
            weight: weightValue,
          );

      if (mounted) {
        context.go('/home');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilini Tamamla'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: AppSpacing.xl,
            right: AppSpacing.xl,
            top: AppSpacing.xl,
            bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.l,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  'Seni tanıyalım 👋',
                  style: AppTypography.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  'Bu bilgiler kulüp içi organizasyonlar için kullanılacak.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
                SizedBox(height: context.heightPct(0.03)),

                // Name Fields
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _firstNameController,
                        label: 'Ad *',
                        hint: 'Adınız',
                        textCapitalization: TextCapitalization.words,
                        validator: Validators.name,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: AppTextField(
                        controller: _lastNameController,
                        label: 'Soyad *',
                        hint: 'Soyadınız',
                        textCapitalization: TextCapitalization.words,
                        validator: Validators.name,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.m),

                // Phone
                AppTextField(
                  controller: _phoneController,
                  label: 'Telefon',
                  hint: '5XX XXX XX XX',
                  keyboardType: TextInputType.phone,
                  prefixText: '+90 ',
                ),
                const SizedBox(height: AppSpacing.m),

                // Gender & Birth Date
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(
                        label: 'Cinsiyet',
                        value: _selectedGender,
                        items: _genders,
                        onChanged: (value) {
                          setState(() => _selectedGender = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: AppTextField(
                        controller: _birthDateController,
                        label: 'Doğum Tarihi',
                        hint: 'GG.AA.YYYY',
                        readOnly: true,
                        onTap: _pickBirthDate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.m),

                // Weight
                AppTextField(
                  controller: _weightController,
                  label: 'Kilo (kg)',
                  hint: '70',
                  keyboardType: TextInputType.number,
                  validator: Validators.positiveNumber,
                ),
                const SizedBox(height: AppSpacing.m),

                // Blood Type
                _buildDropdown(
                  label: 'Kan Grubu',
                  value: _selectedBloodType,
                  items: _bloodTypes,
                  onChanged: (value) {
                    setState(() => _selectedBloodType = value);
                  },
                ),
                const SizedBox(height: AppSpacing.m),

                // T-Shirt & Shoe Size
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(
                        label: 'Tişört Bedeni',
                        value: _selectedTShirtSize,
                        items: _tshirtSizes,
                        onChanged: (value) {
                          setState(() => _selectedTShirtSize = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: AppTextField(
                        label: 'Ayakkabı No',
                        hint: '42',
                        keyboardType: TextInputType.number,
                        onChanged: (value) => _shoeSize = value,
                        validator: Validators.shoeSize,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // Submit Button
                AppButton(
                  text: 'Devam Et',
                  onPressed: _submit,
                  isLoading: _isLoading,
                  isFullWidth: true,
                  size: AppButtonSize.large,
                ),
                const SizedBox(height: AppSpacing.m),

                // Skip Button
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/home'),
                    child: Text(
                      'Daha sonra tamamla',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: items
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      e,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ))
              .toList(),
          selectedItemBuilder: (context) {
            return items.map((e) {
              return Text(
                e,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              );
            }).toList();
          },
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: 'Seçin',
            filled: true,
            fillColor: Theme.of(context).inputDecorationTheme.fillColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
