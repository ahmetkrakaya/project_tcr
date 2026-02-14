import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';

/// Profile Edit Page
class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;
  late TextEditingController _bioController;
  late TextEditingController _shoeSizeController;
  late TextEditingController _birthDateController;
  late TextEditingController _weightController;

  String? _selectedBloodType;
  String? _selectedTShirtSize;
  String? _selectedGender;
  DateTime? _selectedBirthDate;
  bool _isLoading = false;
  bool _isUploadingAvatar = false;
  String? _newAvatarUrl;

  final List<String> _bloodTypes = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Bilmiyorum'
  ];
  final List<String> _tshirtSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'];
  final List<String> _genders = [
    'Kadın',
    'Erkek',
    'Belirtmek istemiyorum',
  ];

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProfileProvider);
    _firstNameController = TextEditingController(text: user?.firstName);
    _lastNameController = TextEditingController(text: user?.lastName);
    _phoneController = TextEditingController(text: user?.phone);
    _bioController = TextEditingController(text: user?.bio);
    _shoeSizeController = TextEditingController(text: user?.shoeSize);
    _birthDateController = TextEditingController(
      text: user?.birthDate != null
          ? _formatDate(user!.birthDate!)
          : '',
    );
    _weightController = TextEditingController(
      text: user?.weight != null ? user!.weight!.toStringAsFixed(1) : '',
    );
    _selectedBloodType = _bloodTypeToString(user?.bloodType);
    _selectedTShirtSize = user?.tshirtSize?.name.toUpperCase();
    _selectedGender = _genderEnumToLabel(user?.gender);
  }
  
  String? _bloodTypeToString(dynamic bloodType) {
    if (bloodType == null) return null;
    final str = bloodType.toString().split('.').last;
    switch (str) {
      case 'aPositive': return 'A+';
      case 'aNegative': return 'A-';
      case 'bPositive': return 'B+';
      case 'bNegative': return 'B-';
      case 'abPositive': return 'AB+';
      case 'abNegative': return 'AB-';
      case 'oPositive': return 'O+';
      case 'oNegative': return 'O-';
      case 'unknown': return 'Bilmiyorum';
      default: return null;
    }
  }

  String? _genderEnumToLabel(dynamic gender) {
    if (gender == null) return null;
    final str = gender.toString().split('.').last;
    switch (str) {
      case 'female':
        return 'Kadın';
      case 'male':
        return 'Erkek';
      case 'unknown':
        return 'Belirtmek istemiyorum';
      default:
        return null;
    }
  }

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
    _bioController.dispose();
    _shoeSizeController.dispose();
    _birthDateController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final genderCode = _genderLabelToCode(_selectedGender);
      final birthDateIso = _selectedBirthDate?.toIso8601String().split('T').first;
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
            shoeSize: _shoeSizeController.text.trim().isNotEmpty
                ? _shoeSizeController.text.trim()
                : null,
            bio: _bioController.text.trim().isNotEmpty
                ? _bioController.text.trim()
                : null,
            gender: genderCode,
            birthDate: birthDateIso,
            weight: weightValue,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil güncellendi')),
        );
        context.pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
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
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 500,
        maxHeight: 500,
        imageQuality: 80,
      );

      if (pickedFile == null) return;

      setState(() => _isUploadingAvatar = true);

      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      
      if (userId == null) {
        throw Exception('Kullanıcı bulunamadı');
      }

      final fileExt = pickedFile.name.split('.').last;
      final fileName = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final bytes = await pickedFile.readAsBytes();

      // Upload to storage (bytes kullanarak hem web hem mobil uyumlu)
      await supabase.storage.from('avatars').uploadBinary(
        fileName,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: 'image/$fileExt'),
      );

      // Get public URL
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);

      // Update user profile with new avatar URL
      await supabase.from('users').update({
        'avatar_url': publicUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      setState(() => _newAvatarUrl = publicUrl);

      // Refresh user data
      await ref.read(authNotifierProvider.notifier).refreshUser();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil fotoğrafı güncellendi'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf yüklenemedi: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initialDate = _selectedBirthDate ??
        DateTime(now.year - 25, now.month, now.day);
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profili Düzenle'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _save,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Kaydet'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Avatar
              Center(
                child: Stack(
                  children: [
                    UserAvatar(
                      imageUrl: _newAvatarUrl ?? user?.avatarUrl,
                      name: user?.fullName,
                      size: 100,
                    ),
                    if (_isUploadingAvatar)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                          onPressed: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Name Fields
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _firstNameController,
                      label: 'Ad',
                      textCapitalization: TextCapitalization.words,
                      validator: Validators.name,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AppTextField(
                      controller: _lastNameController,
                      label: 'Soyad',
                      textCapitalization: TextCapitalization.words,
                      validator: Validators.name,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Phone
              AppTextField(
                controller: _phoneController,
                label: 'Telefon',
                hint: '5XX XXX XX XX',
                keyboardType: TextInputType.phone,
                prefixText: '+90 ',
              ),
              const SizedBox(height: 20),

              // Gender & Birth Date
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown(
                      label: 'Cinsiyet',
                      value: _selectedGender,
                      items: _genders,
                      onChanged: (value) =>
                          setState(() => _selectedGender = value),
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
              const SizedBox(height: 20),

              // Weight
              AppTextField(
                controller: _weightController,
                label: 'Kilo (kg)',
                hint: '70',
                keyboardType: TextInputType.number,
                validator: Validators.positiveNumber,
              ),
              const SizedBox(height: 20),

              // Bio
              AppTextField(
                controller: _bioController,
                label: 'Hakkımda',
                hint: 'Kısa bir açıklama...',
                maxLines: 3,
                maxLength: 150,
              ),
              const SizedBox(height: 20),

              // Blood Type
              _buildDropdown(
                label: 'Kan Grubu',
                value: _selectedBloodType,
                items: _bloodTypes,
                onChanged: (value) => setState(() => _selectedBloodType = value),
              ),
              const SizedBox(height: 20),

              // T-Shirt & Shoe Size
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown(
                      label: 'Tişört Bedeni',
                      value: _selectedTShirtSize,
                      items: _tshirtSizes,
                      onChanged: (value) =>
                          setState(() => _selectedTShirtSize = value),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AppTextField(
                      controller: _shoeSizeController,
                      label: 'Ayakkabı No',
                      hint: '42',
                      keyboardType: TextInputType.number,
                      validator: Validators.shoeSize,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
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
          style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w500),
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
