import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/ui/responsive.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../members_groups/domain/entities/group_entity.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';
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
  final int _totalSteps = 3;

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

  // Step 3: Group Selection
  String? _selectedGroupId;
  bool _isGroupJoining = false;

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
  void initState() {
    super.initState();
    // Grupları daha kullanıcı bu adıma gelmeden yüklemeye başla ki 3. adımda bekleme/donma hissi oluşmasın.
    Future.microtask(() {
      if (mounted) {
        ref.read(allGroupsProvider.future);
      }
    });
  }

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

      _nextStep();
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

  Future<void> _joinGroupAndComplete() async {
    if (_selectedGroupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen bir grup seçin'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isGroupJoining = true);

    try {
      await ref
          .read(groupMembershipProvider.notifier)
          .joinGroup(_selectedGroupId!);

      if (mounted) {
        // Başarılı - ana sayfaya git
        context.go('/home');
      }
    } on UserAlreadyInGroupException catch (e) {
      if (mounted) {
        final groupName = e.currentGroupName ?? 'bir grup';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Zaten "$groupName" grubuna üyesiniz. Grup değiştirmek için önce mevcut gruptan ayrılmalısınız.',
            ),
            backgroundColor: AppColors.error,
          ),
        );

        // Kullanıcı zaten bir gruba üyeyse onboarding'de takılı kalmaması için mevcut grupla devam etmesini sağla.
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gruba katılırken hata oluştu: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGroupJoining = false);
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
                  _buildGroupSelectionStep(),
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
      case 2:
        return 'Grup Seçimi';
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
                    text: 'Devam Et',
                    onPressed: _saveProfile,
                    isLoading: _isProfileSaving,
                    size: AppButtonSize.large,
                    icon: Icons.arrow_forward,
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

  // ==================== STEP 3: Group Selection ====================
  Widget _buildGroupSelectionStep() {
    final groupsAsync = ref.watch(allGroupsProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.l,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.l,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Solda sola doğru koşan erkek (arka planda)
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
                child: const Text(
                  '🏃‍♂️',
                  style: TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(width: 4),
              // Sağda sola doğru koşan kadın (öne geçmiş gibi)
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
                child: const Text(
                  '🏃‍♀️',
                  style: TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Antrenman Grubunu Seç',
                style: AppTypography.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Seviyene uygun bir grup seçerek antrenmanlarımıza katıl.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.neutral500,
            ),
          ),
          const SizedBox(height: AppSpacing.l),

          // Groups List
          Expanded(
            child: groupsAsync.when(
              data: (groups) {
                if (groups.isEmpty) {
                  return Center(
                    child: Text(
                      'Henüz grup bulunmuyor',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return _buildGroupCard(group);
                  },
                );
              },
              loading: () => const Center(child: LoadingWidget()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: AppColors.error),
                    const SizedBox(height: 16),
                    Text('Gruplar yüklenemedi', style: AppTypography.bodyMedium),
                    TextButton(
                      onPressed: () => ref.invalidate(allGroupsProvider),
                      child: const Text('Tekrar Dene'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

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
                  onPressed: _selectedGroupId != null ? _joinGroupAndComplete : null,
                  isLoading: _isGroupJoining,
                  size: AppButtonSize.large,
                  icon: Icons.check,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(TrainingGroupEntity group) {
    final isSelected = _selectedGroupId == group.id;
    final color = _parseColor(group.color);

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedGroupId = group.id;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppColors.neutral200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Icon, Name, Selection Indicator
            Row(
              children: [
                // Group Icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getGroupIcon(group.icon),
                    color: color,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                
                // Group Name
                Expanded(
                  child: Text(
                    group.name,
                    style: AppTypography.titleLarge.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                // Selection Indicator
                if (isSelected)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
              ],
            ),
            
            // Description
            if (group.description != null && group.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                group.description!,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.neutral700,
                  height: 1.5,
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // Tags and Info Row
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildGroupTag(group.difficultyText, color),
                if (group.targetDistance != null)
                  _buildGroupTag(
                    'Hedef: ${group.targetDistance}',
                    AppColors.neutral600,
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.neutral100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 14,
                        color: AppColors.neutral600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${group.memberCount} üye',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.neutral600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color _parseColor(String colorString) {
    try {
      return Color(int.parse(colorString.replaceFirst('#', '0xFF')));
    } catch (e) {
      return AppColors.primary;
    }
  }

  IconData _getGroupIcon(String iconName) {
    switch (iconName) {
      case 'directions_run':
        return Icons.directions_run;
      case 'directions_walk':
        return Icons.directions_walk;
      case 'speed':
        return Icons.speed;
      case 'timer':
        return Icons.timer;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'emoji_events':
        return Icons.emoji_events;
      default:
        return Icons.directions_run;
    }
  }
}
