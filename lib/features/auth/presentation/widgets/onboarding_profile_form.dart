import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/user_entity.dart';
import '../providers/auth_notifier.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

class OnboardingProfileForm extends ConsumerStatefulWidget {
  const OnboardingProfileForm({
    super.key,
    this.initialUser,
    this.onCompletenessChanged,
  });

  final UserEntity? initialUser;
  final ValueChanged<bool>? onCompletenessChanged;

  @override
  OnboardingProfileFormState createState() => OnboardingProfileFormState();
}

class OnboardingProfileFormState extends ConsumerState<OnboardingProfileForm> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _weightController = TextEditingController();
  final _shoeSizeController = TextEditingController();

  String? _selectedBloodType;
  String? _selectedTShirtSize;
  String? _selectedGender;
  DateTime? _selectedBirthDate;

  static const _bloodTypes = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Bilmiyorum',
  ];
  static const _tshirtSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'];
  static const _genders = [
    'Kadın',
    'Erkek',
    'Diğer',
    'Belirtmek istemiyorum',
  ];

  @override
  void initState() {
    super.initState();
    _prefillFromUser(widget.initialUser);
    _phoneController.addListener(_onFieldChanged);
    _weightController.addListener(_onFieldChanged);
    _shoeSizeController.addListener(_onFieldChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyCompleteness());
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onFieldChanged);
    _weightController.removeListener(_onFieldChanged);
    _shoeSizeController.removeListener(_onFieldChanged);
    _phoneController.dispose();
    _birthDateController.dispose();
    _weightController.dispose();
    _shoeSizeController.dispose();
    super.dispose();
  }

  void _onFieldChanged() => _notifyCompleteness();

  void _notifyCompleteness() {
    widget.onCompletenessChanged?.call(isComplete);
  }

  bool get isComplete {
    if (Validators.phone(_phoneController.text.trim()) != null) return false;
    if (_selectedGender == null) return false;
    if (_selectedBirthDate == null) return false;
    final weight = _weightController.text.trim();
    if (Validators.required(weight, 'Kilo') != null) return false;
    if (Validators.positiveNumber(weight) != null) return false;
    if (_selectedBloodType == null) return false;
    if (_selectedTShirtSize == null) return false;
    final shoeSize = _shoeSizeController.text.trim();
    if (Validators.required(shoeSize, 'Ayakkabı numarası') != null) return false;
    if (Validators.shoeSize(shoeSize) != null) return false;
    return true;
  }

  void _prefillFromUser(UserEntity? user) {
    if (user == null) return;
    if (user.phone != null && user.phone!.isNotEmpty) {
      _phoneController.text = user.phone!.replaceFirst(RegExp(r'^\+90\s*'), '');
    }
    _selectedBloodType = _bloodTypeToLabel(user.bloodType);
    _selectedTShirtSize = _tshirtSizeToLabel(user.tshirtSize);
    if (user.shoeSize != null) {
      _shoeSizeController.text = user.shoeSize!;
    }
    _selectedGender = _genderCodeToLabel(user.gender);
    if (user.birthDate != null) {
      _selectedBirthDate = user.birthDate;
      _birthDateController.text = _formatDate(user.birthDate!);
    }
    if (user.weight != null) {
      _weightController.text = user.weight!.toStringAsFixed(
        user.weight! % 1 == 0 ? 0 : 1,
      );
    }
  }

  bool validate() => _formKey.currentState?.validate() ?? false;

  Future<bool> saveProfile() async {
    if (!validate()) return false;

    final genderCode = _genderLabelToCode(_selectedGender);
    final birthDateIso =
        _selectedBirthDate?.toIso8601String().split('T').first;
    final weightValue = _weightController.text.trim().isNotEmpty
        ? double.tryParse(_weightController.text.trim())
        : null;

    await ref.read(authNotifierProvider.notifier).updateProfile(
          phone: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : null,
          bloodType: _selectedBloodType == 'Bilmiyorum'
              ? 'unknown'
              : _selectedBloodType,
          tshirtSize: _selectedTShirtSize,
          shoeSize: _shoeSizeController.text.trim().isNotEmpty
              ? _shoeSizeController.text.trim()
              : null,
          gender: genderCode,
          birthDate: birthDateIso,
          weight: weightValue,
        );
    return true;
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initialDate =
        _selectedBirthDate ?? DateTime(now.year - 25, now.month, now.day);
    final firstDate = DateTime(1900);
    final lastDate = now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(firstDate) || initialDate.isAfter(lastDate)
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
      _notifyCompleteness();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 28,
        right: 28,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seni tanıyalım',
              style: AppTypography.headlineSmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Performans takibi ve doğru gruba yerleşim için bu bilgileri doldur.',
              style: AppTypography.bodyMedium.copyWith(
                color: ThemeBrightnessHolder.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            AppTextField(
              controller: _phoneController,
              label: 'Telefon',
              hint: '5XX XXX XX XX',
              keyboardType: TextInputType.phone,
              prefixText: '+90 ',
              validator: Validators.phone,
            ),
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    label: 'Cinsiyet',
                    value: _selectedGender,
                    items: _genders,
                    onChanged: (value) {
                      setState(() => _selectedGender = value);
                      _notifyCompleteness();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: AppTextField(
                    controller: _birthDateController,
                    label: 'Doğum Tarihi',
                    hint: 'GG.AA.YYYY',
                    readOnly: true,
                    onTap: _pickBirthDate,
                    validator: (_) => _selectedBirthDate == null
                        ? 'Doğum tarihi gerekli'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            AppTextField(
              controller: _weightController,
              label: 'Kilo (kg)',
              hint: '70',
              keyboardType: TextInputType.number,
              validator: (value) =>
                  Validators.required(value, 'Kilo') ??
                  Validators.positiveNumber(value),
            ),
            const SizedBox(height: AppSpacing.m),
            _buildDropdown(
              label: 'Kan Grubu',
              value: _selectedBloodType,
              items: _bloodTypes,
              onChanged: (value) {
                setState(() => _selectedBloodType = value);
                _notifyCompleteness();
              },
            ),
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    label: 'Tişört Bedeni',
                    value: _selectedTShirtSize,
                    items: _tshirtSizes,
                    onChanged: (value) {
                      setState(() => _selectedTShirtSize = value);
                      _notifyCompleteness();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: AppTextField(
                    controller: _shoeSizeController,
                    label: 'Ayakkabı No',
                    hint: '42',
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        Validators.required(value, 'Ayakkabı numarası') ??
                        Validators.shoeSize(value),
                  ),
                ),
              ],
            ),
          ],
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
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    e,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          validator: (value) =>
              value == null ? '$label gerekli' : null,
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

  String? _genderLabelToCode(String? label) {
    return switch (label) {
      'Kadın' => 'female',
      'Erkek' => 'male',
      'Diğer' => 'other',
      'Belirtmek istemiyorum' => 'unknown',
      _ => null,
    };
  }

  String? _bloodTypeToLabel(BloodType type) {
    return switch (type) {
      BloodType.aPositive => 'A+',
      BloodType.aNegative => 'A-',
      BloodType.bPositive => 'B+',
      BloodType.bNegative => 'B-',
      BloodType.abPositive => 'AB+',
      BloodType.abNegative => 'AB-',
      BloodType.oPositive => 'O+',
      BloodType.oNegative => 'O-',
      BloodType.unknown => 'Bilmiyorum',
    };
  }

  String? _genderCodeToLabel(Gender? gender) {
    return switch (gender) {
      Gender.female => 'Kadın',
      Gender.male => 'Erkek',
      Gender.unknown => 'Belirtmek istemiyorum',
      null => null,
    };
  }

  String? _tshirtSizeToLabel(TShirtSize? size) {
    if (size == null) return null;
    return switch (size) {
      TShirtSize.xs => 'XS',
      TShirtSize.s => 'S',
      TShirtSize.m => 'M',
      TShirtSize.l => 'L',
      TShirtSize.xl => 'XL',
      TShirtSize.xxl => 'XXL',
      TShirtSize.xxxl => 'XXXL',
    };
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }
}
