import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/ui/responsive.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../providers/auth_notifier.dart';

/// Onboarding Page - Multi-step wizard
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 2;

  // Step 1: Welcome (no form)
  
  // Step 2: Profile
  final _profileFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  String? _selectedBloodType;
  String? _selectedTShirtSize;
  String? _shoeSize;
   // Yeni alanlar
  final _birthDateController = TextEditingController();
  final _weightController = TextEditingController();
  String? _selectedGender;
  DateTime? _selectedBirthDate;
  bool _isProfileSaving = false;

  final List<String> _bloodTypes = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Bilmiyorum'
  ];
  final List<String> _tshirtSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'];
  final List<String> _genders = [
    'Kadın',
    'Erkek',
    'Diğer',
    'Belirtmek istemiyorum',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _phoneController.dispose();
    _birthDateController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  void _nextStep() {
    // Adım değiştirirken odaklanan alan varsa klavyeyi kapat.
    FocusScope.of(context).unfocus();
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    // Geri giderken de klavyeyi kapat ki layout kilitlenmiş gibi hissettirmesin.
    FocusScope.of(context).unfocus();
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
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
    }
  }

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;

    // Profil kaydından önce klavyeyi kapat; bir sonraki adıma geçerken ekranın donmuş gibi görünmesini engeller.
    FocusScope.of(context).unfocus();

    setState(() => _isProfileSaving = true);

    try {
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
        shoeSize: _shoeSize,
        gender: genderCode,
        birthDate: birthDateIso,
        weight: weightValue,
      );

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProfileSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress Indicator
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: _buildProgressIndicator(),
            ),
            
            // Page Content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() => _currentStep = index);
                },
                children: [
                  _buildWelcomeStep(),
                  _buildProfileStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Column(
      children: [
        Row(
          children: List.generate(_totalSteps, (index) {
            final isCompleted = index < _currentStep;
            final isCurrent = index == _currentStep;
            
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: index < _totalSteps - 1 ? 8 : 0),
                height: 4,
                decoration: BoxDecoration(
                  color: isCompleted || isCurrent
                      ? AppColors.primary
                      : AppColors.neutral200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Adım ${_currentStep + 1} / $_totalSteps',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.neutral500,
              ),
            ),
            Text(
              _getStepTitle(_currentStep),
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getStepTitle(int step) {
    switch (step) {
      case 0:
        return 'Hoş Geldin';
      case 1:
        return 'Profil Bilgileri';
      default:
        return '';
    }
  }

  String? _genderLabelToCode(String? label) {
    switch (label) {
      case 'Kadın':
        return 'female';
      case 'Erkek':
        return 'male';
      case 'Diğer':
        return 'other';
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

  // ==================== STEP 1: Welcome ====================
  Widget _buildWelcomeStep() {
    final logoSize = context.imageSize(
      min: 140,
      max: 220,
      fractionOfWidth: 0.5,
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.responsiveValue(
          small: AppSpacing.l,
          medium: AppSpacing.xl,
          large: AppSpacing.xxl,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // TCR Logo
          Image.asset(
            'assets/images/tcr_logo-removed.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
          ),
          SizedBox(height: context.heightPct(0.04)),
          
          Text(
            'TCR Ailesine\nHoş Geldin! 🎉',
            style: AppTypography.displaySmall.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s),
          
          Text(
            'Seni aramızda görmekten mutluluk duyuyoruz.\nBirlikte koşacağız, birlikte başaracağız!',
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.neutral600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s),
          
          Text(
            'Başlamadan önce seni biraz tanıyalım ve\nuygun antrenman grubuna katılmanı sağlayalım.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.neutral500,
            ),
            textAlign: TextAlign.center,
          ),
          
          const Spacer(),
          
          AppButton(
            text: 'Başlayalım',
            onPressed: _nextStep,
            isFullWidth: true,
            size: AppButtonSize.large,
            icon: Icons.arrow_forward,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ==================== STEP 2: Profile ====================
  Widget _buildProfileStep() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.l,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.l,
      ),
      child: Form(
        key: _profileFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: AppSpacing.xl),

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
                const SizedBox(width: AppSpacing.l),
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
                const SizedBox(width: AppSpacing.l),
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

            // Buttons
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'Geri',
                    onPressed: _previousStep,
                    variant: AppButtonVariant.outlined,
                    size: AppButtonSize.large,
                  ),
                ),
                const SizedBox(width: AppSpacing.l),
                Expanded(
                  flex: 2,
                  child: AppButton(
                    text: 'Tamamla',
                    onPressed: _saveProfile,
                    isLoading: _isProfileSaving,
                    size: AppButtonSize.large,
                    icon: Icons.check,
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
          selectedItemBuilder: (context) {
            return items
                .map(
                  (e) => Text(
                    e,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                )
                .toList();
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
