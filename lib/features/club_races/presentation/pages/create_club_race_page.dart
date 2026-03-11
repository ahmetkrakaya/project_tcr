import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../events/presentation/widgets/event_location_picker_sheet.dart';
import '../../domain/entities/club_race_entity.dart';
import '../providers/club_race_provider.dart';

/// Yeni Yarış Ekleme / Düzenleme Sayfası (Admin Only)
class CreateClubRacePage extends ConsumerStatefulWidget {
  final ClubRaceEntity? race;

  const CreateClubRacePage({super.key, this.race});

  @override
  ConsumerState<CreateClubRacePage> createState() => _CreateClubRacePageState();
}

class _CreateClubRacePageState extends ConsumerState<CreateClubRacePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _distanceController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _selectedDate;
  double? _locationLat;
  double? _locationLng;
  String? _locationName;

  bool get _isEditing => widget.race != null;

  @override
  void initState() {
    super.initState();
    if (widget.race != null) {
      final race = widget.race!;
      _nameController.text = race.name;
      _distanceController.text = race.distance ?? '';
      _descriptionController.text = race.description ?? '';
      _selectedDate = race.date;
      _locationLat = race.locationLat;
      _locationLng = race.locationLng;
      _locationName = race.location;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _distanceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final creationState = ref.watch(clubRaceCreationProvider);
    final updateState = ref.watch(clubRaceUpdateProvider);
    final isLoading = creationState is AsyncLoading || updateState is AsyncLoading;
    final dateFormat = DateFormat('d MMMM yyyy, EEEE', 'tr_TR');
    final hasLocation = _locationLat != null && _locationLng != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Yarışı Düzenle' : 'Yeni Yarış Ekle'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppTextField(
              controller: _nameController,
              label: 'Yarış Adı',
              hint: 'ör: İstanbul Maratonu',
              prefixIcon: Icons.emoji_events_outlined,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Yarış adı gerekli';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            GestureDetector(
              onTap: _pickDate,
              child: AbsorbPointer(
                child: AppTextField(
                  controller: TextEditingController(
                    text: _selectedDate != null
                        ? dateFormat.format(_selectedDate!)
                        : '',
                  ),
                  label: 'Tarih',
                  hint: 'Yarış tarihini seçin',
                  prefixIcon: Icons.calendar_today,
                  validator: (value) {
                    if (_selectedDate == null) {
                      return 'Tarih seçilmeli';
                    }
                    return null;
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Konum seçimi (flutter_map)
            Text(
              'Konum',
              style: AppTypography.labelLarge.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickLocation,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: hasLocation
                        ? AppColors.primary.withValues(alpha: 0.3)
                        : AppColors.neutral300,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: hasLocation
                      ? AppColors.primary.withValues(alpha: 0.05)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      hasLocation
                          ? Icons.location_on
                          : Icons.location_on_outlined,
                      color: hasLocation
                          ? AppColors.primary
                          : AppColors.neutral500,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasLocation
                                ? (_locationName ?? 'Konum seçildi')
                                : 'Haritadan konum seçin',
                            style: AppTypography.bodyMedium.copyWith(
                              color: hasLocation ? null : AppColors.neutral500,
                            ),
                          ),
                          if (hasLocation)
                            Text(
                              '${_locationLat!.toStringAsFixed(4)}, ${_locationLng!.toStringAsFixed(4)}',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.neutral500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.neutral400,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            AppTextField(
              controller: _distanceController,
              label: 'Mesafe (opsiyonel)',
              hint: 'ör: 10K, Yarı Maraton, 42K',
              prefixIcon: Icons.straighten,
            ),
            const SizedBox(height: 16),

            AppTextField(
              controller: _descriptionController,
              label: 'Açıklama (opsiyonel)',
              hint: 'Yarış hakkında kısa bilgi',
              prefixIcon: Icons.description_outlined,
              maxLines: 3,
              minLines: 1,
            ),
            const SizedBox(height: 32),

            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isEditing ? 'Kaydet' : 'Yarışı Ekle'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('tr', 'TR'),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickLocation() async {
    final result = await EventLocationPickerSheet.show(
      context,
      initialLat: _locationLat,
      initialLng: _locationLng,
      initialName: _locationName,
    );
    if (result != null && mounted) {
      setState(() {
        _locationLat = result.lat;
        _locationLng = result.lng;
        _locationName = result.name;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_locationLat == null || _locationLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen haritadan bir konum seçin'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final name = _nameController.text.trim();
    final location = _locationName ?? 'Yarış konumu';
    final distance = _distanceController.text.trim().isEmpty
        ? null
        : _distanceController.text.trim();
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();

    bool success;
    if (_isEditing) {
      success = await ref.read(clubRaceUpdateProvider.notifier).updateRace(
            raceId: widget.race!.id,
            name: name,
            date: _selectedDate!,
            location: location,
            locationLat: _locationLat,
            locationLng: _locationLng,
            distance: distance,
            description: description,
          );
    } else {
      success = await ref.read(clubRaceCreationProvider.notifier).createRace(
            name: name,
            date: _selectedDate!,
            location: location,
            locationLat: _locationLat,
            locationLng: _locationLng,
            distance: distance,
            description: description,
          );
    }

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Yarış güncellendi' : 'Yarış eklendi'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing
                ? 'Yarış güncellenirken hata oluştu'
                : 'Yarış eklenirken hata oluştu'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
