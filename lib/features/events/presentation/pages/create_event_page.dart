import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/vdot_calculator.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';
import '../../../members_groups/presentation/widgets/event_group_programs_editor.dart';
import '../../../routes/domain/entities/route_entity.dart';
import '../../../routes/presentation/providers/route_provider.dart';
import '../../data/models/event_model.dart';
import '../../domain/entities/event_entity.dart';
import '../../domain/entities/event_template_entity.dart';
import '../providers/event_provider.dart';
import '../widgets/event_location_picker_sheet.dart';
import '../widgets/template_selector_sheet.dart';

/// Create/Edit Event Page
class CreateEventPage extends ConsumerStatefulWidget {
  final String? eventId;
  /// Tekrarlayan düzenlemede: 'only_this' | 'all_future' (route query param)
  final String? editRecurrenceScope;

  const CreateEventPage({super.key, this.eventId, this.editRecurrenceScope});

  @override
  ConsumerState<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends ConsumerState<CreateEventPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _descriptionFocusNode = FocusNode();
  final _startDateFocusNode = FocusNode();
  final _startTimeFocusNode = FocusNode();
  final _endDateFocusNode = FocusNode();
  final _endTimeFocusNode = FocusNode();
  final _trackLengthFocusNode = FocusNode();
  final _startDateDisplayController = TextEditingController();
  final _startTimeDisplayController = TextEditingController();
  final _endDateDisplayController = TextEditingController();
  final _endTimeDisplayController = TextEditingController();

  EventType _selectedEventType = EventType.training;
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  DateTime? _endDate;
  TimeOfDay? _endTime;
  String? _selectedRouteId;
  /// Antrenman/yarış dışı etkinliklerde haritadan seçilen konum (rota yok)
  double? _pickedLocationLat;
  double? _pickedLocationLng;
  String? _pickedLocationName;
  String? _pickedLocationAddress;
  List<EventGroupProgramItem> _groupPrograms = [];
  bool _isLoading = false;
  bool _isEditing = false;
  /// Antrenman için: team = toplu (Katılıyorum var), individual = isteğe bağlı bireysel
  String _participationType = 'team';
  /// Pist rotada pace bazlı kulvar: lanes + isteğe bağlı pist uzunluğu (km)
  List<LaneEntity> _laneConfigLanes = [];
  double? _trackLengthKmOverride;

  /// Tekrarlayan etkinlik
  bool _isRecurring = false;
  String _recurrenceFreq = 'weekly'; // weekly | monthly | yearly
  Set<int> _recurrenceWeeklyDays = {}; // 1=Pzt .. 7=Paz (DateTime.weekday)
  int? _recurrenceMonthDay; // 1-31
  int? _recurrenceYearMonth; // 1-12
  int? _recurrenceYearDay; // 1-31
  DateTime? _recurrenceEndDate;

  /// Sadece antrenman türünde grup programları bölümü gösterilir (yarışta yok)
  bool get _showGroupPrograms => _selectedEventType == EventType.training;

  /// Sadece antrenman türünde Katılım türü (Ekip/Bireysel) seçimi gösterilir
  bool get _showParticipationTypeSelector => _selectedEventType == EventType.training;

  /// Bireysel antrenmanda rota/saat/bitiş yok; sadece tarih ve grup programları
  bool get _isIndividualParticipationForm =>
      _selectedEventType == EventType.training && _participationType == 'individual';

  /// Antrenman veya yarış ise rota seçimi (bireysel antrenmanda rota yok); değilse haritadan konum seçimi
  bool get _showRouteSelector =>
      (_selectedEventType == EventType.training ||
          _selectedEventType == EventType.race) &&
      _participationType != 'individual';
  bool get _showLocationPicker => !_showRouteSelector &&
      _selectedEventType != EventType.training; // training'de bireysel de olsa konum yok

  @override
  void initState() {
    super.initState();
    _startDateDisplayController.text =
        DateFormat('dd MMM yyyy', 'tr_TR').format(_startDate);
    _startTimeDisplayController.text =
        '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
    _endDateDisplayController.text = 'Seçin';
    _endTimeDisplayController.text = 'Seçin';
    _trackLengthFocusNode.addListener(() {
      setState(() {}); // Klavye kapatma butonunu göstermek/gizlemek için
    });
    if (widget.eventId != null) {
      _isEditing = true;
      _loadEventData();
    }
  }

  Future<void> _loadEventData() async {
    try {
      final event = await ref.read(eventByIdProvider(widget.eventId!).future);
      
      // Grup programlarını yükle
      final groupPrograms = await ref.read(eventGroupProgramsProvider(widget.eventId!).future);
      final allGroups = await ref.read(allGroupsProvider.future);
      
      final programItems = <EventGroupProgramItem>[];
      for (final program in groupPrograms) {
        final group = allGroups.firstWhere(
          (g) => g.id == program.trainingGroupId,
          orElse: () => allGroups.first,
        );
        programItems.add(EventGroupProgramItem(
          id: program.id,
          group: group,
          programContent: program.programContent,
          workoutDefinition: program.workoutDefinition,
          routeId: program.routeId,
          routeName: program.routeName,
          trainingTypeId: program.trainingTypeId,
          trainingTypeName: program.trainingTypeName,
          trainingTypeColor: program.trainingTypeColor,
          thresholdOffsetMinSeconds: program.thresholdOffsetMinSeconds,
          thresholdOffsetMaxSeconds: program.thresholdOffsetMaxSeconds,
        ));
      }
      
      setState(() {
        _titleController.text = event.title;
        _descriptionController.text = event.description ?? '';
        _selectedEventType = event.eventType;
        _startDate = event.startTime;
        _startTime = TimeOfDay.fromDateTime(event.startTime);
        if (event.endTime != null) {
          _endDate = event.endTime;
          _endTime = TimeOfDay.fromDateTime(event.endTime!);
        }
        _selectedRouteId = event.routeId;
        _groupPrograms = programItems;
        // Rota yoksa ama konum varsa (önceki konum seçimi) harita konumunu yükle
        if (event.routeId == null &&
            event.locationLat != null &&
            event.locationLng != null) {
          _pickedLocationLat = event.locationLat;
          _pickedLocationLng = event.locationLng;
          _pickedLocationName = event.locationName;
          _pickedLocationAddress = event.locationAddress;
        } else {
          _pickedLocationLat = null;
          _pickedLocationLng = null;
          _pickedLocationName = null;
          _pickedLocationAddress = null;
        }
        _participationType = event.participationType ?? 'team';
        _laneConfigLanes = event.laneConfig?.lanes.toList() ?? [];
        _trackLengthKmOverride = event.laneConfig?.trackLengthKm;
        _isRecurring = event.isRecurring;
        _recurrenceEndDate = event.recurrenceEndDate;
        if (event.recurrenceRule != null && event.recurrenceRule!.isNotEmpty) {
          _applyRecurrenceRuleToState(event.recurrenceRule!);
        }
        _updateDateTimeDisplayControllers();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Etkinlik yüklenemedi: $e')),
        );
      }
    }
  }

  /// Şablon seçici göster
  Future<void> _showTemplateSelector() async {
    final template = await TemplateSelectorSheet.show(context);
    if (template != null && mounted) {
      await _loadFromTemplate(template);
    }
  }

  /// Şablondan form doldur
  Future<void> _loadFromTemplate(EventTemplateEntity template) async {
    try {
      final allGroups = await ref.read(allGroupsProvider.future);
      
      // Şablon grup programlarını EventGroupProgramItem'a dönüştür
      final programItems = <EventGroupProgramItem>[];
      for (final program in template.groupPrograms) {
        final group = allGroups.firstWhere(
          (g) => g.id == program.trainingGroupId,
          orElse: () => allGroups.first,
        );
        programItems.add(EventGroupProgramItem(
          id: null,
          group: group,
          programContent: program.programContent,
          workoutDefinition: program.workoutDefinition,
          routeId: program.routeId,
          routeName: program.routeName,
          trainingTypeId: program.trainingTypeId,
          trainingTypeName: program.trainingTypeName,
          trainingTypeColor: program.trainingTypeColor,
          thresholdOffsetMinSeconds: program.thresholdOffsetMinSeconds,
          thresholdOffsetMaxSeconds: program.thresholdOffsetMaxSeconds,
        ));
      }

      setState(() {
        _titleController.text = template.name;
        _descriptionController.text = template.description ?? '';
        _selectedEventType = template.eventType;
        if (template.defaultStartTime != null) {
          _startTime = template.defaultStartTime!;
        }
        if (template.durationMinutes != null) {
          // End time hesapla
          final startDateTime = DateTime(
            _startDate.year,
            _startDate.month,
            _startDate.day,
            _startTime.hour,
            _startTime.minute,
          );
          final endDateTime = startDateTime.add(
            Duration(minutes: template.durationMinutes!),
          );
          _endDate = endDateTime;
          _endTime = TimeOfDay.fromDateTime(endDateTime);
        }
        _selectedRouteId = template.routeId;
        _groupPrograms = template.eventType == EventType.training ? programItems : [];
        _pickedLocationLat = null;
        _pickedLocationLng = null;
        _pickedLocationName = null;
        _pickedLocationAddress = null;
        _participationType = template.participationType;
        _laneConfigLanes = template.laneConfig?.lanes.toList() ?? [];
        _trackLengthKmOverride = template.laneConfig?.trackLengthKm;
        _updateDateTimeDisplayControllers();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Şablon yüklendi: ${template.name}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Şablon yüklenemedi: $e')),
        );
      }
    }
  }

  void _updateDateTimeDisplayControllers() {
    _startDateDisplayController.text =
        DateFormat('dd MMM yyyy', 'tr_TR').format(_startDate);
    _startTimeDisplayController.text =
        '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
    _endDateDisplayController.text = _endDate != null
        ? DateFormat('dd MMM yyyy', 'tr_TR').format(_endDate!)
        : 'Seçin';
    _endTimeDisplayController.text = _endTime != null
        ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}'
        : 'Seçin';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    _startDateFocusNode.dispose();
    _startTimeFocusNode.dispose();
    _endDateFocusNode.dispose();
    _endTimeFocusNode.dispose();
    _trackLengthFocusNode.dispose();
    _startDateDisplayController.dispose();
    _startTimeDisplayController.dispose();
    _endDateDisplayController.dispose();
    _endTimeDisplayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Etkinlik Düzenle' : 'Yeni Etkinlik'),
        actions: [
          // Şablondan oluştur butonu (sadece yeni etkinlik oluştururken)
          if (!_isEditing && !_isLoading)
            IconButton(
              icon: const Icon(Icons.bookmark_outline),
              tooltip: 'Şablondan Oluştur',
              onPressed: _showTemplateSelector,
            ),
          _isLoading
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
                  tooltip: _isEditing ? 'Güncelle' : 'Kaydet',
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
              // Etkinlik Türü + Katılım türü (antrenmanda) aynı satırda
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Etkinlik Türü', style: AppTypography.labelLarge),
                        const SizedBox(height: 8),
                        _buildEventTypeSelector(),
                      ],
                    ),
                  ),
                  if (_showParticipationTypeSelector) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Katılım türü', style: AppTypography.labelLarge),
                          const SizedBox(height: 8),
                          _buildParticipationTypeSelector(),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              if (_showParticipationTypeSelector) ...[
                const SizedBox(height: 6),
                Text(
                  'Ekip: toplu antrenman, katılım kaydı alınır. Bireysel: isteğe bağlı antrenman, katılım kaydı yok.',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
                ),
                const SizedBox(height: 24),
              ] else const SizedBox(height: 24),

              // Etkinlik adı (başlık yok)
              AppTextField(
                controller: _titleController,
                label: null,
                hint: 'Örn: Track Run',
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _descriptionFocusNode.requestFocus(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Etkinlik adı gerekli';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              // Açıklama hemen altında (başlık yok)
              AppTextField(
                controller: _descriptionController,
                focusNode: _descriptionFocusNode,
                label: null,
                hint: 'Etkinlik hakkında detaylı bilgi...',
                maxLines: 4,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _startDateFocusNode.requestFocus(),
              ),
              const SizedBox(height: 24),

              // Date & Time (Bireysel antrenmanda sadece tarih; toplu etkinlikte tarih + saat + bitiş)
              Row(
                children: [
                  Expanded(
                    child: _buildDateField(
                      label: 'Tarih',
                      value: _startDate,
                      onTap: () => _selectDate(isStart: true),
                      focusNode: _startDateFocusNode,
                      textInputAction: _isIndividualParticipationForm
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onSubmitted: _isIndividualParticipationForm
                          ? (_) => _submitForm()
                          : (_) => _startTimeFocusNode.requestFocus(),
                      displayController: _startDateDisplayController,
                    ),
                  ),
                  if (!_isIndividualParticipationForm) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTimeField(
                        label: 'Saat',
                        value: _startTime,
                        onTap: () => _selectTime(isStart: true),
                        focusNode: _startTimeFocusNode,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _endDateFocusNode.requestFocus(),
                        displayController: _startTimeDisplayController,
                      ),
                    ),
                  ],
                ],
              ),
              if (!_isIndividualParticipationForm) const SizedBox(height: 16),
              // End Date & Time (Optional) - Bireysel antrenmanda yok
              if (!_isIndividualParticipationForm)
                Row(
                  children: [
                    Expanded(
                      child: _buildDateField(
                        label: 'Bitiş Tarihi (Opsiyonel)',
                        value: _endDate,
                        onTap: () => _selectDate(isStart: false),
                        focusNode: _endDateFocusNode,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _endTimeFocusNode.requestFocus(),
                        displayController: _endDateDisplayController,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTimeField(
                        label: 'Bitiş Saati',
                        value: _endTime,
                        onTap: () => _selectTime(isStart: false),
                        focusNode: _endTimeFocusNode,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submitForm(),
                        displayController: _endTimeDisplayController,
                      ),
                    ),
                  ],
                ),
              if (!_isIndividualParticipationForm) const SizedBox(height: 24),
              const SizedBox(height: 24),

              // Tekrarlayan etkinlik
              _buildRecurrenceSection(),
              const SizedBox(height: 24),

              // Rota (antrenman/yarış) veya Konum seçimi (sosyal, workshop, diğer)
              if (_showRouteSelector) ...[
                Text('Rota', style: AppTypography.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Konum adı ve adres seçilen rotadan alınır.',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
                ),
                const SizedBox(height: 12),
                _buildRouteSelector(),
              ],
              if (_showLocationPicker) ...[
                Text('Konum seçimi', style: AppTypography.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Haritadan buluşma noktası seçin (örn. kafe, toplanma yeri). Rota eklemenize gerek yok.',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
                ),
                const SizedBox(height: 12),
                _buildLocationPicker(),
              ],
              const SizedBox(height: 24),

              // Group Programs Editor (Sadece Antrenman etkinliklerinde; yarışta yok)
              if (_showGroupPrograms) ...[
                EventGroupProgramsEditor(
                  programs: _groupPrograms,
                  onChanged: (programs) {
                    setState(() => _groupPrograms = programs);
                  },
                ),
                const SizedBox(height: 24),
              ],

              // Pist kulvarları (sadece rota pist ise)
              if (_showGroupPrograms && _selectedRouteId != null) ...[
                _buildLaneConfigSection(),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
          // Klavye açıkken sağ üstte kapatma butonu (klavye üzerinde)
          if (_trackLengthFocusNode.hasFocus)
            Positioned(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              right: 20,
              child: Material(
                color: AppColors.tertiary,
                borderRadius: BorderRadius.circular(20),
                elevation: 8,
                shadowColor: AppColors.tertiary.withValues(alpha: 0.5),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    _trackLengthFocusNode.unfocus();
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

  void _onEventTypeChanged(EventType? type) {
    if (type == null) return;
    setState(() {
      _selectedEventType = type;
      if (type == EventType.social ||
          type == EventType.workshop ||
          type == EventType.other) {
        _selectedRouteId = null;
        _groupPrograms = [];
      }
      if (type == EventType.race || type == EventType.training) {
        _groupPrograms = type == EventType.race ? [] : _groupPrograms;
        _pickedLocationLat = null;
        _pickedLocationLng = null;
        _pickedLocationName = null;
        _pickedLocationAddress = null;
      }
      if (type != EventType.training) _participationType = 'team';
    });
  }

  Widget _buildEventTypeSelector() {
    return DropdownButtonFormField<EventType>(
      value: _selectedEventType,
      isExpanded: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
      ),
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: _getEventTypeColor(_selectedEventType),
      ),
      dropdownColor: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      selectedItemBuilder: (context) => EventType.values.map((type) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getEventTypeIcon(type),
              size: 22,
              color: _getEventTypeColor(type),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                type.displayName,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: _selectedEventType == type ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        );
      }).toList(),
      items: EventType.values.map((type) {
        return DropdownMenuItem<EventType>(
          value: type,
          child: Row(
            children: [
              Icon(
                _getEventTypeIcon(type),
                size: 22,
                color: _getEventTypeColor(type),
              ),
              const SizedBox(width: 12),
              Text(
                type.displayName,
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: _selectedEventType == type ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: _onEventTypeChanged,
    );
  }

  Widget _buildParticipationTypeSelector() {
    return DropdownButtonFormField<String>(
      value: _participationType,
      isExpanded: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
      ),
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: _participationType == 'team' ? AppColors.tertiary : AppColors.primary,
      ),
      dropdownColor: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      selectedItemBuilder: (context) => [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups, size: 22, color: AppColors.tertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Ekip',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 22, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Bireysel',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ],
      items: const [
        DropdownMenuItem(
          value: 'team',
          child: Row(
            children: [
              Icon(Icons.groups, size: 22, color: AppColors.tertiary),
              SizedBox(width: 12),
              Text('Ekip'),
            ],
          ),
        ),
        DropdownMenuItem(
          value: 'individual',
          child: Row(
            children: [
              Icon(Icons.person_outline, size: 22, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Bireysel'),
            ],
          ),
        ),
      ],
      onChanged: (String? value) {
        if (value == null) return;
        setState(() {
          _participationType = value;
          if (value == 'individual') {
            _selectedRouteId = null;
            _endDate = null;
            _endTime = null;
          }
        });
      },
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
    required TextEditingController displayController,
  }) {
    return TextFormField(
      controller: displayController,
      focusNode: focusNode,
      readOnly: true,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      onTap: onTap,
      style: AppTypography.bodyMedium.copyWith(
        color: value != null ? null : AppColors.neutral500,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildTimeField({
    required String label,
    required TimeOfDay? value,
    required VoidCallback onTap,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
    required TextEditingController displayController,
  }) {
    return TextFormField(
      controller: displayController,
      focusNode: focusNode,
      readOnly: true,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      onTap: onTap,
      style: AppTypography.bodyMedium.copyWith(
        color: value != null ? null : AppColors.neutral500,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.access_time),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Future<void> _selectDate({required bool isStart}) async {
    final initialDate = isStart ? _startDate : (_endDate ?? _startDate);
    final now = DateTime.now();
    final lastDate = now.add(const Duration(days: 365));
    DateTime selectedDate = initialDate;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.45,
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Başlık çubuğu (iPhone tarzı)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('İptal'),
                    ),
                    Text(
                      isStart ? 'Tarih seçin' : 'Bitiş tarihi seçin',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Tamam'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: initialDate,
                  minimumDate: now,
                  maximumDate: lastDate,
                  onDateTimeChanged: (DateTime value) {
                    selectedDate = value;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      setState(() {
        if (isStart) {
          _startDate = selectedDate;
        } else {
          _endDate = selectedDate;
        }
        _updateDateTimeDisplayControllers();
      });
    }
  }

  Future<void> _selectTime({required bool isStart}) async {
    final initialTime = isStart ? _startTime : (_endTime ?? _startTime);
    final initialDateTime = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      initialTime.hour,
      initialTime.minute,
    );
    TimeOfDay selectedTime = initialTime;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.4,
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('İptal'),
                    ),
                    Text(
                      isStart ? 'Saat seçin' : 'Bitiş saati seçin',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Tamam'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: initialDateTime,
                  use24hFormat: true,
                  onDateTimeChanged: (DateTime value) {
                    selectedTime = TimeOfDay(hour: value.hour, minute: value.minute);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      setState(() {
        if (isStart) {
          _startTime = selectedTime;
        } else {
          _endTime = selectedTime;
        }
        _updateDateTimeDisplayControllers();
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final dataSource = ref.read(eventDataSourceProvider);

      // Bireysel antrenmanda sadece tarih; saat 00:00, bitiş yok
      final startDateTime = _isIndividualParticipationForm
          ? DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0)
          : DateTime(
              _startDate.year,
              _startDate.month,
              _startDate.day,
              _startTime.hour,
              _startTime.minute,
            );

      DateTime? endDateTime;
      if (!_isIndividualParticipationForm &&
          _endDate != null &&
          _endTime != null) {
        endDateTime = DateTime(
          _endDate!.year,
          _endDate!.month,
          _endDate!.day,
          _endTime!.hour,
          _endTime!.minute,
        );
      }

      final userId = Supabase.instance.client.auth.currentUser?.id;

      if (userId == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      if (_isRecurring && _buildRecurrenceRule() == null) {
        throw Exception('Tekrarlama için en az bir gün veya geçerli tarih seçin');
      }

      // Grup programları validation'ı - sadece antrenman türünde zorunlu
      if (_showGroupPrograms) {
        // Grup programları zorunlu - en az bir grup olmalı
        if (_groupPrograms.isEmpty) {
          throw Exception('En az bir grup programı eklenmelidir');
        }
        
        // Her grubun antrenman türü seçilmiş olmalı
        for (final program in _groupPrograms) {
          if (program.trainingTypeId == null || program.trainingTypeId!.isEmpty) {
            throw Exception('${program.group.name} grubu için antrenman türü seçilmelidir');
          }
        }
      }

      // Konum: antrenman/yarışta rotadan (bireysel antrenmanda yok), diğer türlerde haritadan seçilen konum
      String? locationName;
      String? locationAddress;
      double? locationLat;
      double? locationLng;
      String? routeId;

      RouteEntity? selectedRouteForLane;
      if (!_isIndividualParticipationForm &&
          _showRouteSelector &&
          _selectedRouteId != null) {
        final routes = await ref.read(allRoutesProvider.future);
        try {
          final selectedRoute = routes.firstWhere((r) => r.id == _selectedRouteId);
          selectedRouteForLane = selectedRoute;
          locationName = selectedRoute.name;
          locationAddress = selectedRoute.locationName;
          locationLat = selectedRoute.locationLat;
          locationLng = selectedRoute.locationLng;
          routeId = _selectedRouteId;
        } catch (_) {}
      } else if (_showLocationPicker &&
          _pickedLocationLat != null &&
          _pickedLocationLng != null) {
        locationName = _pickedLocationName?.isNotEmpty == true
            ? _pickedLocationName
            : 'Seçilen konum';
        locationAddress = _pickedLocationAddress;
        locationLat = _pickedLocationLat;
        locationLng = _pickedLocationLng;
        routeId = null;
      }

      // Güncelleme durumunda mevcut etkinliği yükle ve korunması gereken değerleri al
      EventModel? existingEvent;
      if (_isEditing && widget.eventId != null) {
        existingEvent = await dataSource.getEventById(widget.eventId!);
      }

      final eventModel = EventModel(
        id: widget.eventId ?? '',
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        eventType: _selectedEventType.name,
        status: 'published',
        startTime: startDateTime,
        endTime: endDateTime,
        locationName: locationName,
        locationAddress: locationAddress,
        locationLat: locationLat,
        locationLng: locationLng,
        routeId: routeId,
        trainingTypeId: null, // Artık genel antrenman türü yok, her grup için ayrı seçiliyor
        weatherNote: null,
        coachNotes: null,
        createdBy: userId,
        createdAt: existingEvent?.createdAt ?? DateTime.now(),
        participationType: _selectedEventType == EventType.training
            ? _participationType
            : 'team',
        laneConfig: (selectedRouteForLane?.terrainType == TerrainType.track &&
                _laneConfigLanes.isNotEmpty)
            ? LaneConfigEntity(
                trackLengthKm: _trackLengthKmOverride,
                lanes: _laneConfigLanes,
              )
            : null,
        // Güncelleme durumunda mevcut değerleri koru
        bannerImageUrl: existingEvent?.bannerImageUrl,
        isPinned: existingEvent?.isPinned ?? false,
        pinnedAt: existingEvent?.pinnedAt,
        // Tekrarlayan etkinlik (ilk oluşturmada veya düzenlemede)
        isRecurring: _isRecurring,
        recurrenceRule: _isRecurring ? _buildRecurrenceRule() : null,
        parentEventId: null,
        recurrenceEndDate: _recurrenceEndDate,
        isRecurrenceException: widget.editRecurrenceScope == 'only_this' || (existingEvent?.isRecurrenceException ?? false),
      );

      String createdEventId;
      
      if (_isEditing) {
        if (widget.editRecurrenceScope == 'all_future') {
          await dataSource.updateRecurringSeriesFromEvent(widget.eventId!, eventModel.toJson());
          createdEventId = widget.eventId!;
        } else {
          await dataSource.updateEvent(eventModel);
          createdEventId = widget.eventId!;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Etkinlik güncellendi')),
          );
        }
      } else {
        final created = await dataSource.createEvent(eventModel);
        createdEventId = created.id;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Etkinlik oluşturuldu')),
          );
        }
      }

      // Grup programlarını kaydet (sadece antrenman etkinliklerinde; yarışta yok)
      if (_showGroupPrograms && _groupPrograms.isNotEmpty) {
        final groupDataSource = ref.read(groupDataSourceProvider);
        final programModels = _groupPrograms
            .asMap()
            .entries
            .map((entry) => entry.value.toModel(createdEventId, entry.key))
            .toList();
        await groupDataSource.saveEventGroupPrograms(createdEventId, programModels);
      }

      // Refresh providers
      ref.invalidate(allEventsProvider);
      ref.invalidate(upcomingEventsProvider);
      ref.invalidate(thisWeekEventsProvider);
      if (_isEditing) {
        ref.invalidate(eventByIdProvider(widget.eventId!));
        ref.invalidate(eventGroupProgramsProvider(widget.eventId!));
        ref.invalidate(userEventGroupProgramsProvider(widget.eventId!));
      }

      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Color _getEventTypeColor(EventType type) {
    switch (type) {
      case EventType.training:
        return AppColors.secondary;
      case EventType.race:
        return AppColors.error;
      case EventType.social:
        return AppColors.tertiary;
      case EventType.workshop:
        return AppColors.primary;
      case EventType.other:
        return AppColors.neutral600;
    }
  }

  IconData _getEventTypeIcon(EventType type) {
    switch (type) {
      case EventType.training:
        return Icons.directions_run;
      case EventType.race:
        return Icons.emoji_events;
      case EventType.social:
        return Icons.groups;
      case EventType.workshop:
        return Icons.school;
      case EventType.other:
        return Icons.event;
    }
  }

  /// "4:30" -> 270; geçersizse null
  /// Pace seçici: dk:sn/km (bottom sheet ile CupertinoPicker)
  Future<void> _showPacePicker(BuildContext context, int? currentSeconds, void Function(int) onSelected) async {
    final totalSeconds = currentSeconds ?? 300;
    final minutes = (totalSeconds ~/ 60).clamp(0, 20);
    final seconds = (totalSeconds % 60).clamp(0, 59);
    int selectedMinutes = minutes;
    int selectedSeconds = seconds;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: 260,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('İptal'),
                  ),
                  Text('Pace seç (dk:sn/km)', style: AppTypography.titleMedium),
                  TextButton(
                    onPressed: () {
                      final total = selectedMinutes * 60 + selectedSeconds;
                      onSelected(total);
                      Navigator.pop(ctx);
                    },
                    child: Text('Tamam', style: AppTypography.labelMedium.copyWith(color: AppColors.primary)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: selectedMinutes),
                      onSelectedItemChanged: (v) => selectedMinutes = v,
                      children: List.generate(21, (i) => Center(child: Text('$i dk'))),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: selectedSeconds),
                      onSelectedItemChanged: (v) => selectedSeconds = v,
                      children: List.generate(60, (i) => Center(child: Text('$i sn'))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLaneConfigSection() {
    final routesAsync = ref.watch(allRoutesProvider);
    return routesAsync.when(
      data: (routes) {
        final idx = routes.indexWhere((r) => r.id == _selectedRouteId);
        if (idx < 0) return const SizedBox.shrink();
        final selectedRoute = routes[idx];
        if (selectedRoute.terrainType != TerrainType.track) {
          return const SizedBox.shrink();
        }
        final defaultTrackKm = selectedRoute.totalDistance ?? 0.4;
        return _buildLaneConfigCard(defaultTrackKm);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  /// Standart 8 kulvar: 4:00-4:30, 4:30-5:00, ..., 7:30-8:00 (dakika:sn/km)
  void _addStandardEightLanes() {
    setState(() {
      _laneConfigLanes.clear();
      for (int i = 0; i < 8; i++) {
        final minSec = 240 + (i * 30); // 4:00 = 240, 4:30 = 270, ...
        final maxSec = minSec + 30;
        _laneConfigLanes.add(LaneEntity(
          laneNumber: i + 1,
          paceMinSecPerKm: minSec,
          paceMaxSecPerKm: maxSec,
          label: null,
        ));
      }
    });
  }

  Widget _buildLaneConfigCard(double defaultTrackKm) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.tertiary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.track_changes, size: 20, color: AppColors.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pist kulvarları (pace bazlı)',
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Kulvar numarası ve pace aralığını (dk:sn/km, örn. 4:30) girin. Aynı pace\'taki koşucular aynı kulvara düşer.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.neutral600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          // Pist uzunluğu (klavye kapatma butonu ile)
          Builder(
            builder: (context) {
              final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
              final hasFocus = _trackLengthFocusNode.hasFocus;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.neutral200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.straighten, size: 18, color: AppColors.neutral600),
                        const SizedBox(width: 8),
                        Text('Pist uzunluğu:', style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 72,
                          child: TextFormField(
                            focusNode: _trackLengthFocusNode,
                            initialValue: _trackLengthKmOverride != null
                                ? _trackLengthKmOverride!.toStringAsFixed(2)
                                : defaultTrackKm.toStringAsFixed(2),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '0.4',
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (v) {
                              final n = double.tryParse(v.replaceAll(',', '.'));
                              setState(() => _trackLengthKmOverride = n);
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'km',
                          style: AppTypography.labelSmall.copyWith(color: AppColors.neutral500),
                        ),
                      ],
                    ),
                  ),
                  // Klavye açıkken sağ üstte kapatma butonu
                  if (hasFocus && isKeyboardVisible)
                    Positioned(
                      top: -12,
                      right: -12,
                      child: GestureDetector(
                        onTap: () {
                          _trackLengthFocusNode.unfocus();
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.tertiary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.tertiary.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.keyboard_hide,
                            size: 22,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          // Kulvar listesi veya boş durum
          if (_laneConfigLanes.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.neutral200,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.neutral300),
              ),
              child: Column(
                children: [
                  Icon(Icons.track_changes, size: 40, color: AppColors.neutral400),
                  const SizedBox(height: 8),
                  Text(
                    'Henüz kulvar tanımlanmadı',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.neutral600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tek tek ekleyin veya standart 8 kulvarı kullanın.',
                    style: AppTypography.labelSmall.copyWith(color: AppColors.neutral500),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final basePace = 270;
                            setState(() {
                              _laneConfigLanes.add(LaneEntity(
                                laneNumber: 1,
                                paceMinSecPerKm: basePace,
                                paceMaxSecPerKm: basePace + 30,
                                label: null,
                              ));
                            });
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Kulvar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _addStandardEightLanes,
                          icon: const Icon(Icons.format_list_numbered, size: 18),
                          label: const Text('8 kulvar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            ...List.generate(_laneConfigLanes.length, (i) {
              final lane = _laneConfigLanes[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildLaneRow(i, lane),
              );
            }),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () {
                    final nextNum = _laneConfigLanes.isEmpty
                        ? 1
                        : (_laneConfigLanes.map((e) => e.laneNumber).reduce((a, b) => a > b ? a : b) + 1);
                    final basePace = 270 + (_laneConfigLanes.length * 30);
                    setState(() {
                      _laneConfigLanes.add(LaneEntity(
                        laneNumber: nextNum.clamp(1, 99),
                        paceMinSecPerKm: basePace,
                        paceMaxSecPerKm: basePace + 30,
                        label: null,
                      ));
                    });
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Kulvar ekle'),
                ),
                if (_laneConfigLanes.length < 8)
                  TextButton.icon(
                    onPressed: _addStandardEightLanes,
                    icon: const Icon(Icons.format_list_numbered, size: 16),
                    label: const Text('8 kulvar'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLaneRow(int index, LaneEntity lane) {
    final keySeed = '${index}_${lane.paceMinSecPerKm}_${lane.paceMaxSecPerKm}_${lane.label}';
    final invalidRange = lane.paceMinSecPerKm > lane.paceMaxSecPerKm;
    return Container(
      key: ValueKey('row_$keySeed'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: invalidRange ? AppColors.error.withValues(alpha: 0.5) : AppColors.neutral200,
          width: invalidRange ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.tertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${lane.laneNumber}',
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.tertiary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _PaceSelectorChip(
                        label: 'Min pace',
                        valueSeconds: lane.paceMinSecPerKm,
                        hasError: invalidRange,
                        onTap: () async {
                          await _showPacePicker(context, lane.paceMinSecPerKm, (sec) {
                            setState(() {
                              _laneConfigLanes = List.from(_laneConfigLanes);
                              _laneConfigLanes[index] = LaneEntity(
                                laneNumber: lane.laneNumber,
                                paceMinSecPerKm: sec,
                                paceMaxSecPerKm: lane.paceMaxSecPerKm,
                                label: lane.label,
                              );
                            });
                          });
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text('–', style: TextStyle(color: AppColors.neutral500)),
                    ),
                    Expanded(
                      child: _PaceSelectorChip(
                        label: 'Max pace',
                        valueSeconds: lane.paceMaxSecPerKm,
                        onTap: () async {
                          await _showPacePicker(context, lane.paceMaxSecPerKm, (sec) {
                            setState(() {
                              _laneConfigLanes = List.from(_laneConfigLanes);
                              _laneConfigLanes[index] = LaneEntity(
                                laneNumber: lane.laneNumber,
                                paceMinSecPerKm: lane.paceMinSecPerKm,
                                paceMaxSecPerKm: sec,
                                label: lane.label,
                              );
                            });
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 22),
                onPressed: () {
                  setState(() => _laneConfigLanes.removeAt(index));
                },
                color: AppColors.error,
                tooltip: 'Kulvarı kaldır',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecurrenceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.repeat, size: 22, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tekrarlayan etkinlik',
                style: AppTypography.titleMedium,
              ),
            ),
            Switch(
              value: _isRecurring,
              onChanged: (v) {
                setState(() {
                  _isRecurring = v;
                  if (v && _recurrenceWeeklyDays.isEmpty && _recurrenceFreq == 'weekly') {
                    _recurrenceWeeklyDays = {_startDate.weekday};
                  }
                  if (v && _recurrenceFreq == 'monthly' && _recurrenceMonthDay == null) {
                    _recurrenceMonthDay = _startDate.day;
                  }
                  if (v && _recurrenceFreq == 'yearly' && (_recurrenceYearMonth == null || _recurrenceYearDay == null)) {
                    _recurrenceYearMonth = _startDate.month;
                    _recurrenceYearDay = _startDate.day;
                  }
                });
              },
              activeColor: AppColors.primary,
            ),
          ],
        ),
        if (_isRecurring) ...[
          const SizedBox(height: 12),
          Text('Sıklık', style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'weekly', label: Text('Haftalık'), icon: Icon(Icons.calendar_view_week)),
              ButtonSegment(value: 'monthly', label: Text('Aylık'), icon: Icon(Icons.calendar_month)),
              ButtonSegment(value: 'yearly', label: Text('Yıllık'), icon: Icon(Icons.calendar_today)),
            ],
            selected: {_recurrenceFreq},
            onSelectionChanged: (Set<String> sel) {
              setState(() {
                _recurrenceFreq = sel.first;
                if (_recurrenceFreq == 'monthly' && _recurrenceMonthDay == null) {
                  _recurrenceMonthDay = _startDate.day;
                }
                if (_recurrenceFreq == 'yearly') {
                  _recurrenceYearMonth ??= _startDate.month;
                  _recurrenceYearDay ??= _startDate.day;
                }
              });
            },
          ),
          const SizedBox(height: 12),
          if (_recurrenceFreq == 'weekly') ...[
            Text('Günler', style: AppTypography.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'].asMap().entries.map((e) {
                final dayNum = e.key + 1;
                final selected = _recurrenceWeeklyDays.contains(dayNum);
                return FilterChip(
                  label: Text(e.value),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _recurrenceWeeklyDays = Set.from(_recurrenceWeeklyDays)..add(dayNum);
                      } else {
                        _recurrenceWeeklyDays = Set.from(_recurrenceWeeklyDays)..remove(dayNum);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
          if (_recurrenceFreq == 'monthly') ...[
            Text('Ayın günü (1-31)', style: AppTypography.labelLarge),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              value: _recurrenceMonthDay ?? _startDate.day,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              items: List.generate(31, (i) => i + 1).map((d) => DropdownMenuItem(value: d, child: Text('$d'))).toList(),
              onChanged: (v) => setState(() => _recurrenceMonthDay = v),
            ),
          ],
          if (_recurrenceFreq == 'yearly') ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ay', style: AppTypography.labelLarge),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int>(
                        value: _recurrenceYearMonth ?? _startDate.month,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                        items: [
                          for (int m = 1; m <= 12; m++)
                            DropdownMenuItem(
                              value: m,
                              child: Text(DateFormat.MMM('tr_TR').format(DateTime(2000, m))),
                            ),
                        ],
                        onChanged: (v) => setState(() => _recurrenceYearMonth = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gün', style: AppTypography.labelLarge),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int>(
                        value: _recurrenceYearDay ?? _startDate.day,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                        items: List.generate(31, (i) => i + 1).map((d) => DropdownMenuItem(value: d, child: Text('$d'))).toList(),
                        onChanged: (v) => setState(() => _recurrenceYearDay = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text('Tekrarlama bitiş tarihi (opsiyonel)', style: AppTypography.labelLarge),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _recurrenceEndDate ?? _startDate.add(const Duration(days: 365)),
                firstDate: _startDate,
                lastDate: _startDate.add(const Duration(days: 365 * 5)),
              );
              if (picked != null) setState(() => _recurrenceEndDate = picked);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              child: Text(
                _recurrenceEndDate != null
                    ? DateFormat('dd MMM yyyy', 'tr_TR').format(_recurrenceEndDate!)
                    : 'Seçin',
                style: AppTypography.bodyMedium,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String? _buildRecurrenceRule() {
    if (!_isRecurring) return null;
    switch (_recurrenceFreq) {
      case 'weekly':
        if (_recurrenceWeeklyDays.isEmpty) return null;
        const days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
        final byday = _recurrenceWeeklyDays.toList()..sort();
        return 'FREQ=WEEKLY;BYDAY=${byday.map((d) => days[d - 1]).join(',')}';
      case 'monthly':
        final d = _recurrenceMonthDay ?? 1;
        return 'FREQ=MONTHLY;BYMONTHDAY=$d';
      case 'yearly':
        final m = _recurrenceYearMonth ?? 1;
        final d = _recurrenceYearDay ?? 1;
        return 'FREQ=YEARLY;BYMONTH=$m;BYMONTHDAY=$d';
      default:
        return null;
    }
  }

  void _applyRecurrenceRuleToState(String rule) {
    final upper = rule.toUpperCase();
    if (upper.contains('FREQ=WEEKLY') && upper.contains('BYDAY=')) {
      _recurrenceFreq = 'weekly';
      final bydayMatch = RegExp(r'BYDAY=([A-Z,]+)', caseSensitive: false).firstMatch(rule);
      if (bydayMatch != null) {
        const dayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
        _recurrenceWeeklyDays = bydayMatch.group(1)!.split(',').map((c) {
          final i = dayCodes.indexOf(c.trim().toUpperCase());
          return i >= 0 ? i + 1 : 0;
        }).where((e) => e > 0).toSet();
      }
    } else if (upper.contains('FREQ=MONTHLY') && upper.contains('BYMONTHDAY=')) {
      _recurrenceFreq = 'monthly';
      final m = RegExp(r'BYMONTHDAY=(\d+)', caseSensitive: false).firstMatch(rule);
      if (m != null) _recurrenceMonthDay = int.tryParse(m.group(1)!);
    } else if (upper.contains('FREQ=YEARLY')) {
      _recurrenceFreq = 'yearly';
      final mm = RegExp(r'BYMONTH=(\d+)', caseSensitive: false).firstMatch(rule);
      final dd = RegExp(r'BYMONTHDAY=(\d+)', caseSensitive: false).firstMatch(rule);
      if (mm != null) _recurrenceYearMonth = int.tryParse(mm.group(1)!);
      if (dd != null) _recurrenceYearDay = int.tryParse(dd.group(1)!);
    }
  }

  Widget _buildRouteSelector() {
    final routesAsync = ref.watch(allRoutesProvider);

    return routesAsync.when(
      data: (routes) {
        if (routes.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.neutral100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.neutral200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.map_outlined,
                  color: AppColors.neutral400,
                ),
                const SizedBox(width: 12),
                Text(
                  'Henüz rota eklenmemiş',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
              ],
            ),
          );
        }

        final selectedRoute = _selectedRouteId != null
            ? routes.firstWhere(
                (r) => r.id == _selectedRouteId,
                orElse: () => routes.first,
              )
            : null;

        return InkWell(
          onTap: () => _showRouteSelectionSheet(routes),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: selectedRoute != null
                  ? AppColors.tertiaryContainer.withValues(alpha: 0.3)
                  : AppColors.neutral100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selectedRoute != null
                    ? AppColors.tertiary.withValues(alpha: 0.5)
                    : AppColors.neutral200,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: selectedRoute != null
                        ? AppColors.tertiary.withValues(alpha: 0.2)
                        : AppColors.neutral200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.map_outlined,
                    color: selectedRoute != null
                        ? AppColors.tertiary
                        : AppColors.neutral400,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedRoute?.name ?? 'Rota Seçin',
                        style: AppTypography.titleSmall.copyWith(
                          color: selectedRoute != null
                              ? AppColors.neutral900
                              : AppColors.neutral500,
                        ),
                      ),
                      if (selectedRoute != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${selectedRoute.formattedDistance} • ${selectedRoute.formattedElevationGain} yükseliş',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selectedRoute != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      setState(() => _selectedRouteId = null);
                    },
                    color: AppColors.neutral400,
                  )
                else
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.neutral400,
                  ),
              ],
            ),
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.neutral100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: 12),
            Text(
              'Rotalar yüklenemedi',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationPicker() {
    final hasLocation = _pickedLocationLat != null && _pickedLocationLng != null;
    final displayName = _pickedLocationName?.isNotEmpty == true
        ? _pickedLocationName!
        : (hasLocation ? 'Haritada seçilen konum' : null);

    return InkWell(
      onTap: () async {
        final result = await EventLocationPickerSheet.show(
          context,
          initialLat: _pickedLocationLat,
          initialLng: _pickedLocationLng,
          initialName: _pickedLocationName,
        );
        if (result != null && mounted) {
          setState(() {
            _pickedLocationLat = result.lat;
            _pickedLocationLng = result.lng;
            _pickedLocationName = result.name;
            _pickedLocationAddress = null; // Harita seçiminde adres yok
          });
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasLocation
              ? AppColors.tertiaryContainer.withValues(alpha: 0.3)
              : AppColors.neutral100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasLocation
                ? AppColors.tertiary.withValues(alpha: 0.5)
                : AppColors.neutral200,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: hasLocation
                    ? AppColors.tertiary.withValues(alpha: 0.2)
                    : AppColors.neutral200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.location_on_outlined,
                color: hasLocation ? AppColors.tertiary : AppColors.neutral400,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName ?? 'Konum seçin',
                    style: AppTypography.titleSmall.copyWith(
                      color: hasLocation
                          ? AppColors.neutral900
                          : AppColors.neutral500,
                    ),
                  ),
                  if (hasLocation) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_pickedLocationLat!.toStringAsFixed(5)}, ${_pickedLocationLng!.toStringAsFixed(5)}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.neutral500,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (hasLocation)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() {
                    _pickedLocationLat = null;
                    _pickedLocationLng = null;
                    _pickedLocationName = null;
                    _pickedLocationAddress = null;
                  });
                },
                color: AppColors.neutral400,
              )
            else
              const Icon(
                Icons.chevron_right,
                color: AppColors.neutral400,
              ),
          ],
        ),
      ),
    );
  }

  void _showRouteSelectionSheet(List<RouteEntity> routes) {
    final parentContext = context;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
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
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Rota Seçin', style: AppTypography.titleLarge),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add),
                          tooltip: 'Yeni rota ekle',
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            parentContext.pushNamed(RouteNames.routeCreate);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Route list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: routes.length,
                  itemBuilder: (context, index) {
                    final route = routes[index];
                    final isSelected = route.id == _selectedRouteId;

                    return ListTile(
                      leading: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.tertiary.withValues(alpha: 0.2)
                              : AppColors.neutral100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.map_outlined,
                          color: isSelected
                              ? AppColors.tertiary
                              : AppColors.neutral400,
                        ),
                      ),
                      title: Text(
                        route.name,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        '${route.formattedDistance} • ${route.formattedElevationGain} yükseliş • ${route.terrainType.displayName}',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral500,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: AppColors.tertiary,
                            )
                          : null,
                      onTap: () {
                        setState(() => _selectedRouteId = route.id);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tıklanınca pace picker açan chip (pist kulvarı min/max pace)
class _PaceSelectorChip extends StatelessWidget {
  final String label;
  final int valueSeconds;
  final bool hasError;
  final VoidCallback onTap;

  const _PaceSelectorChip({
    required this.label,
    required this.valueSeconds,
    this.hasError = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = VdotCalculator.formatPace(valueSeconds);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: hasError ? AppColors.error : AppColors.neutral300,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.neutral600)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(text, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 20, color: AppColors.neutral500),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
