import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/track_lane_calculator.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../members_groups/data/models/group_model.dart';
import '../../../members_groups/domain/entities/group_entity.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';
import '../../domain/entities/event_entity.dart' show TrainingTypeEntity;
import '../../utils/coach_text_parser.dart';
import '../providers/event_provider.dart';
import '../widgets/admin_monthly_program_entry_card.dart';
import '../widgets/program_editor_picker_sheet.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

class _DayDraft {
  final TextEditingController workoutController;
  final TextEditingController notesController;
  String? trainingTypeOverride;
  int? trackLane;

  _DayDraft({String workout = '', String notes = ''})
      : workoutController = TextEditingController(text: workout),
        notesController = TextEditingController(text: notes);

  void dispose() {
    workoutController.dispose();
    notesController.dispose();
  }
}

class _GroupDraftSnapshot {
  final List<String> workouts;
  final List<String> coachNotes;
  final List<String?> trainingTypes;
  final List<int?> trackLanes;
  final bool dirty;

  const _GroupDraftSnapshot({
    required this.workouts,
    required this.coachNotes,
    required this.trainingTypes,
    required this.trackLanes,
    this.dirty = false,
  });

  bool get hasContent =>
      workouts.any((w) => w.trim().isNotEmpty) ||
      coachNotes.any((n) => n.trim().isNotEmpty) ||
      trainingTypes.any((t) => t != null);

  static _GroupDraftSnapshot fromDays(List<_DayDraft> days, {bool dirty = false}) {
    return _GroupDraftSnapshot(
      workouts: days.map((d) => d.workoutController.text).toList(),
      coachNotes: days.map((d) => d.notesController.text).toList(),
      trainingTypes: days.map((d) => d.trainingTypeOverride).toList(),
      trackLanes: days.map((d) => d.trackLane).toList(),
      dirty: dirty,
    );
  }
}

enum _ChipStatus { empty, draft, unsaved, saved }

class AdminWeeklyProgramEditorPage extends ConsumerStatefulWidget {
  const AdminWeeklyProgramEditorPage({super.key});

  @override
  ConsumerState<AdminWeeklyProgramEditorPage> createState() =>
      _AdminWeeklyProgramEditorPageState();
}

class _AdminWeeklyProgramEditorPageState
    extends ConsumerState<AdminWeeklyProgramEditorPage> {
  late DateTime _weekStart;
  String? _selectedGroupId;
  final Set<String> _selectedMemberUserIds = {};
  final List<_DayDraft> _days = List.generate(7, (_) => _DayDraft());
  bool _isLoadingWeek = false;
  bool _isSaving = false;
  bool _dirty = false;
  bool _suppressDirty = false;
  final Map<String, _GroupDraftSnapshot> _draftCache = {};
  final Set<String> _savedDraftKeys = {};

  static const _dayLabels = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(DateTime.now());
    for (var i = 0; i < 7; i++) {
      _days[i].workoutController.addListener(_onFieldChanged);
      _days[i].notesController.addListener(_onFieldChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final groups = ref.read(allGroupsProvider).valueOrNull;
      if (groups != null && groups.isNotEmpty && _selectedGroupId == null) {
        final first = groups.where((g) => g.isActive).firstOrNull ?? groups.first;
        _switchToGroup(first.id);
      }
    });
  }

  @override
  void dispose() {
    for (final d in _days) {
      d.dispose();
    }
    super.dispose();
  }

  void _onFieldChanged() {
    if (_suppressDirty || _dirty) return;
    setState(() => _dirty = true);
  }

  DateTime _mondayOf(DateTime date) {
    final weekday = date.weekday;
    final daysToMonday = weekday == 1 ? 0 : weekday - 1;
    return DateTime(date.year, date.month, date.day - daysToMonday);
  }

  DateTime _dayDate(int index) => _weekStart.add(Duration(days: index));

  String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  String _draftCacheKey(String groupId, Set<String> memberUserIds) {
    if (memberUserIds.isEmpty) return groupId;
    final sorted = memberUserIds.toList()..sort();
    return '$groupId|${sorted.join(',')}';
  }

  String? get _currentDraftKey {
    final groupId = _selectedGroupId;
    if (groupId == null) return null;
    return _draftCacheKey(groupId, _selectedMemberUserIds);
  }

  void _clearDraftCache() {
    _draftCache.clear();
    _savedDraftKeys.clear();
  }

  void _stashCurrentDraft() {
    final key = _currentDraftKey;
    if (key == null) return;
    _draftCache[key] = _GroupDraftSnapshot.fromDays(_days, dirty: _dirty);
  }

  void _applySnapshot(_GroupDraftSnapshot snapshot) {
    _suppressDirty = true;
    for (var i = 0; i < 7; i++) {
      _days[i].workoutController.text = snapshot.workouts[i];
      _days[i].notesController.text = snapshot.coachNotes[i];
      _days[i].trainingTypeOverride = snapshot.trainingTypes[i];
      _days[i].trackLane = snapshot.trackLanes[i];
    }
    _suppressDirty = false;
    _dirty = snapshot.dirty;
  }

  void _applyRowsToDays(
    List<Map<String, dynamic>> rows,
    DateTime weekMonday, {
    bool markDirty = false,
  }) {
    final byDate = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      byDate[r['plan_date'] as String? ?? ''] = r;
    }
    _suppressDirty = true;
    for (var i = 0; i < 7; i++) {
      final row = byDate[_ymd(weekMonday.add(Duration(days: i)))];
      _days[i].workoutController.text = row?['program_content'] as String? ?? '';
      _days[i].notesController.text = row?['coach_notes'] as String? ?? '';
      final tt = row?['training_types'] as Map<String, dynamic>?;
      _days[i].trainingTypeOverride = tt?['name'] as String?;
      final lane = row?['track_lane'];
      if (lane is int &&
          lane >= TrackLaneCalculator.minLane &&
          lane <= TrackLaneCalculator.maxLane) {
        _days[i].trackLane = lane;
      } else if (lane is num) {
        final v = lane.round();
        _days[i].trackLane = v >= TrackLaneCalculator.minLane &&
                v <= TrackLaneCalculator.maxLane
            ? v
            : null;
      } else {
        _days[i].trackLane = null;
      }
    }
    _suppressDirty = false;
    _dirty = markDirty;
  }

  bool get _hasPendingSaves =>
      _dirty || _draftCache.values.any((snapshot) => snapshot.dirty);

  int _countPendingSaves() {
    _stashCurrentDraft();
    return _draftCache.values.where((snapshot) => snapshot.dirty).length;
  }

  ({String groupId, Set<String> memberUserIds}) _parseDraftCacheKey(String key) {
    if (!key.contains('|')) {
      return (groupId: key, memberUserIds: const {});
    }
    final parts = key.split('|');
    final members = parts.length > 1
        ? parts[1].split(',').where((id) => id.isNotEmpty).toSet()
        : <String>{};
    return (groupId: parts[0], memberUserIds: members);
  }

  String _draftLabelForKey(
    String key,
    List<TrainingGroupEntity> groups,
  ) {
    final parsed = _parseDraftCacheKey(key);
    final groupName =
        groups.where((g) => g.id == parsed.groupId).map((g) => g.name).firstOrNull ??
            'Grup';
    if (parsed.memberUserIds.isEmpty) return groupName;
    if (parsed.memberUserIds.length == 1) return '$groupName (sporcu)';
    return '$groupName (${parsed.memberUserIds.length} sporcu)';
  }

  _ChipStatus _groupChipStatus(TrainingGroupEntity group) {
    final key = _draftCacheKey(group.id, const {});
    final isCurrent = group.id == _selectedGroupId && _selectedMemberUserIds.isEmpty;
    if (isCurrent && _dirty) return _ChipStatus.unsaved;
    if (_savedDraftKeys.contains(key)) return _ChipStatus.saved;
    final cached = _draftCache[key];
    if (cached != null && cached.hasContent) {
      return cached.dirty ? _ChipStatus.unsaved : _ChipStatus.draft;
    }
    return _ChipStatus.empty;
  }

  String _weekTitle() {
    final end = _weekStart.add(const Duration(days: 6));
    final fmt = DateFormat('d MMM', 'tr_TR');
    return '${fmt.format(_weekStart)} – ${fmt.format(end)} ${end.year}';
  }

  Color _hexColor(String hex, {Color fallback = AppColors.primary}) {
    try {
      var h = hex.replaceAll('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  String? _trainingTypeLabel(String? name, List<TrainingTypeEntity> types) {
    if (name == null) return null;
    return types.where((t) => t.name == name).map((t) => t.displayName).firstOrNull;
  }

  Future<void> _pickGroup(List<TrainingGroupEntity> activeGroups) async {
    final items = activeGroups
        .map(
          (g) => ProgramPickerItem(
            id: g.id,
            label: g.name,
            subtitle: g.isPerformanceGroup ? 'Performans grubu' : 'Antrenman grubu',
            icon: Icons.groups_rounded,
            accentColor: _hexColor(g.color),
          ),
        )
        .toList();

    final picked = await showProgramSinglePickerSheet(
      context: context,
      title: 'Antrenman grubu',
      subtitle: 'Programın uygulanacağı grubu seçin',
      headerIcon: Icons.groups_rounded,
      items: items,
      selectedId: _selectedGroupId,
      searchable: true,
    );
    if (picked != null) await _switchToGroup(picked);
  }

  Future<void> _pickMembers(List<GroupMemberModel> members) async {
    final items = members
        .map(
          (m) => ProgramPickerItem(
            id: m.userId,
            label: m.userName,
            icon: Icons.person_outline_rounded,
            accentColor: AppColors.secondary,
          ),
        )
        .toList();

    final picked = await showProgramMultiPickerSheet(
      context: context,
      title: 'Sporcular',
      subtitle: 'Aynı programı birden fazla sporcuya atayabilirsiniz',
      items: items,
      selectedIds: _selectedMemberUserIds,
    );
    if (picked != null) await _onMembersChanged(picked);
  }

  Future<void> _pickTrainingType(int dayIndex, List<TrainingTypeEntity> types) async {
    final items = [
      const ProgramPickerItem(
        id: '__auto__',
        label: 'Otomatik',
        subtitle: 'Program metninden tahmin edilir',
        icon: Icons.auto_awesome_rounded,
      ),
      ...types.map(
        (t) => ProgramPickerItem(
          id: t.name,
          label: t.displayName,
          subtitle: t.description,
          icon: Icons.directions_run_rounded,
          accentColor: _hexColor(t.color),
        ),
      ),
    ];

    final current = _days[dayIndex].trainingTypeOverride ?? '__auto__';
    final picked = await showProgramSinglePickerSheet(
      context: context,
      title: 'Antrenman türü',
      subtitle: _dayLabels[dayIndex],
      headerIcon: Icons.fitness_center_rounded,
      items: items,
      selectedId: current,
      searchable: true,
    );
    if (picked == null) return;
    setState(() {
      _days[dayIndex].trainingTypeOverride = picked == '__auto__' ? null : picked;
      _dirty = true;
    });
  }

  Future<void> _pickTrackLane(int dayIndex) async {
    final items = [
      const ProgramPickerItem(
        id: '__none__',
        label: 'Pistte değil',
        subtitle: 'Kulvar dönüşümü uygulanmaz',
        icon: Icons.close_rounded,
      ),
      ...List.generate(
        TrackLaneCalculator.maxLane,
        (i) {
          final lane = i + 1;
          return ProgramPickerItem(
            id: '$lane',
            label: 'Kulvar $lane',
            icon: Icons.track_changes_rounded,
            accentColor: AppColors.tertiary,
          );
        },
      ),
    ];

    final current = _days[dayIndex].trackLane?.toString() ?? '__none__';
    final picked = await showProgramSinglePickerSheet(
      context: context,
      title: 'Pist',
      subtitle: _dayLabels[dayIndex],
      headerIcon: Icons.track_changes_rounded,
      items: items,
      selectedId: current,
    );
    if (picked == null) return;
    setState(() {
      _days[dayIndex].trackLane =
          picked == '__none__' ? null : int.tryParse(picked);
      _dirty = true;
    });
  }

  String _trackLaneLabel(int? lane) {
    if (lane == null) return 'Pistte değil';
    return 'Kulvar $lane';
  }

  void _clearDays() {
    for (var i = 0; i < 7; i++) {
      _days[i].workoutController.text = '';
      _days[i].notesController.text = '';
      _days[i].trainingTypeOverride = null;
      _days[i].trackLane = null;
    }
  }

  Future<void> _loadWeekData({bool clearFirst = false}) async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;

    // Çoklu sporcu: toplu atama modu — tek form, yükleme yapma
    if (_selectedMemberUserIds.length > 1) {
      if (clearFirst) _clearDays();
      setState(() {
        _isLoadingWeek = false;
        _dirty = false;
      });
      return;
    }

    if (clearFirst) _clearDays();
    setState(() => _isLoadingWeek = true);
    _suppressDirty = true;
    try {
      final ds = ref.read(eventDataSourceProvider);
      final rows = await ds.getWeeklyProgramEntries(
        weekStartMonday: _weekStart,
        trainingGroupId: groupId,
        memberUserId: _selectedMemberUserIds.length == 1
            ? _selectedMemberUserIds.first
            : null,
      );
      _applyRowsToDays(rows, _weekStart);
      _stashCurrentDraft();
      final key = _currentDraftKey;
      if (key != null && rows.isNotEmpty) {
        _savedDraftKeys.add(key);
      }
      _suppressDirty = false;
      if (mounted) {
        setState(() {
          _dirty = false;
          _isLoadingWeek = false;
        });
      }
    } catch (e) {
      _suppressDirty = false;
      if (mounted) {
        setState(() => _isLoadingWeek = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Plan yüklenemedi: $e')),
        );
      }
    }
  }

  Future<void> _copyFromPreviousWeek() async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;

    setState(() => _isLoadingWeek = true);
    _suppressDirty = true;
    try {
      final prevMonday = _weekStart.subtract(const Duration(days: 7));
      final ds = ref.read(eventDataSourceProvider);
      final rows = await ds.getWeeklyProgramEntries(
        weekStartMonday: prevMonday,
        trainingGroupId: groupId,
        memberUserId: _selectedMemberUserIds.length == 1
            ? _selectedMemberUserIds.first
            : null,
      );
      _applyRowsToDays(rows, prevMonday, markDirty: true);
      _suppressDirty = false;
      if (mounted) {
        setState(() => _isLoadingWeek = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Geçen haftanın programı kopyalandı')),
        );
      }
    } catch (e) {
      _suppressDirty = false;
      if (mounted) {
        setState(() => _isLoadingWeek = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kopyalama başarısız: $e')),
        );
      }
    }
  }

  Future<void> _copyFromOtherGroup(List<TrainingGroupEntity> activeGroups) async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;

    final sources = activeGroups
        .where((g) => !g.isPerformanceGroup && g.id != groupId)
        .toList();
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kopyalanacak başka antrenman grubu yok')),
      );
      return;
    }

    final items = sources
        .map(
          (g) => ProgramPickerItem(
            id: g.id,
            label: g.name,
            subtitle: _groupChipStatus(g) == _ChipStatus.saved
                ? 'Bu hafta kayıtlı'
                : _draftCache[_draftCacheKey(g.id, const {})]?.hasContent == true
                    ? 'Taslak mevcut'
                    : null,
            icon: Icons.groups_rounded,
            accentColor: _hexColor(g.color),
          ),
        )
        .toList();

    final picked = await showProgramSinglePickerSheet(
      context: context,
      title: 'Gruptan kopyala',
      subtitle: 'Aynı haftanın programını başka gruptan alın',
      headerIcon: Icons.content_copy_rounded,
      items: items,
      searchable: true,
    );
    if (picked == null) return;

    setState(() => _isLoadingWeek = true);
    try {
      final sourceKey = _draftCacheKey(picked, const {});
      final cached = _draftCache[sourceKey];
      if (cached != null && cached.hasContent) {
        _applySnapshot(_GroupDraftSnapshot(
          workouts: cached.workouts,
          coachNotes: cached.coachNotes,
          trainingTypes: cached.trainingTypes,
          trackLanes: cached.trackLanes,
          dirty: true,
        ));
      } else {
        final ds = ref.read(eventDataSourceProvider);
        final rows = await ds.getWeeklyProgramEntries(
          weekStartMonday: _weekStart,
          trainingGroupId: picked,
        );
        if (rows.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Seçilen grupta bu hafta için kayıtlı program yok'),
              ),
            );
          }
          return;
        }
        _applyRowsToDays(rows, _weekStart, markDirty: true);
      }
      if (mounted) {
        final name = sources.where((g) => g.id == picked).map((g) => g.name).firstOrNull;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${name ?? 'Grup'} programından kopyalandı')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kopyalama başarısız: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingWeek = false);
    }
  }

  List<String> _validateSnapshot(_GroupDraftSnapshot snapshot) {
    final parseErrors = <String>[];
    for (var i = 0; i < 7; i++) {
      final text = snapshot.workouts[i].trim();
      if (text.isEmpty || text.toUpperCase() == 'REST') continue;
      final parsed = parseCoachText(text);
      if (!parsed.ok) {
        parseErrors.add('${_dayLabels[i]}: ${parsed.error}');
      }
    }
    return parseErrors;
  }

  List<Map<String, dynamic>> _dayPayloadsFromSnapshot(_GroupDraftSnapshot snapshot) {
    final dayPayloads = <Map<String, dynamic>>[];
    for (var i = 0; i < 7; i++) {
      final text = snapshot.workouts[i].trim();
      final coachNotes = snapshot.coachNotes[i].trim();
      final notesPayload =
          coachNotes.isNotEmpty ? {'coach_notes': coachNotes} : <String, String>{};
      dayPayloads.add({
        'plan_date': _ymd(_dayDate(i)),
        'text': text.isEmpty ? 'REST' : text,
        'training_type_override': snapshot.trainingTypes[i],
        'track_lane': snapshot.trackLanes[i],
        ...notesPayload,
      });
    }
    return dayPayloads;
  }

  Future<List<Map<String, dynamic>>> _persistDraftEntry({
    required String cacheKey,
    required _GroupDraftSnapshot snapshot,
    required TrainingGroupEntity group,
    required Set<String> memberUserIds,
  }) async {
    final ds = ref.read(eventDataSourceProvider);
    final dayPayloads = _dayPayloadsFromSnapshot(snapshot);
    final isPerformance = group.isPerformanceGroup;
    final targets = isPerformance ? memberUserIds.toList() : <String?>[null];
    final allErrors = <Map<String, dynamic>>[];

    for (final memberId in targets) {
      final response = await ds.upsertWeeklyProgram(
        weekStartMonday: _weekStart,
        scopeType: isPerformance ? 'member' : 'group',
        trainingGroupId: group.id,
        memberUserId: memberId,
        days: dayPayloads,
      );
      final errors = (response['errors'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      allErrors.addAll(errors);
    }

    if (allErrors.isEmpty) {
      _draftCache[cacheKey] = _GroupDraftSnapshot(
        workouts: snapshot.workouts,
        coachNotes: snapshot.coachNotes,
        trainingTypes: snapshot.trainingTypes,
        trackLanes: snapshot.trackLanes,
        dirty: false,
      );
      _savedDraftKeys.add(cacheKey);
      if (_currentDraftKey == cacheKey) {
        _dirty = false;
      }
    }

    return allErrors;
  }

  Future<void> _save() async {
    _stashCurrentDraft();

    final groups = ref.read(allGroupsProvider).valueOrNull ?? [];
    final dirtyEntries = _draftCache.entries
        .where((entry) => entry.value.dirty)
        .toList();

    if (dirtyEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedilecek değişiklik yok')),
      );
      return;
    }

    final validationErrors = <String>[];
    for (final entry in dirtyEntries) {
      final parsed = _parseDraftCacheKey(entry.key);
      final group = groups.where((g) => g.id == parsed.groupId).firstOrNull;
      if (group == null) continue;

      final label = _draftLabelForKey(entry.key, groups);
      if (group.isPerformanceGroup && parsed.memberUserIds.isEmpty) {
        validationErrors.add('$label: sporcu seçilmedi');
        continue;
      }

      final errors = _validateSnapshot(entry.value);
      for (final error in errors) {
        validationErrors.add('$label — $error');
      }
    }

    if (validationErrors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationErrors.take(4).join('\n')),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final savedLabels = <String>[];
      final allErrors = <Map<String, dynamic>>[];

      for (final entry in dirtyEntries) {
        final parsed = _parseDraftCacheKey(entry.key);
        final group = groups.where((g) => g.id == parsed.groupId).firstOrNull;
        if (group == null) continue;

        try {
          final errors = await _persistDraftEntry(
            cacheKey: entry.key,
            snapshot: entry.value,
            group: group,
            memberUserIds: parsed.memberUserIds,
          );
          if (errors.isEmpty) {
            savedLabels.add(_draftLabelForKey(entry.key, groups));
          } else {
            allErrors.addAll(errors);
          }
        } catch (e) {
          allErrors.add({'error': '$e'});
        }
      }

      ref.invalidate(userMonthlyProgramsForWindowProvider);
      ref.invalidate(userMonthlyProgramsForMonthProvider);
      ref.invalidate(adminMonthlyProgramsForMonthProvider);

      if (!mounted) return;

      if (allErrors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kısmi hata: ${allErrors.length} kayıt sorunu'),
          ),
        );
      } else {
        final summary = savedLabels.length == 1
            ? '${savedLabels.first} kaydedildi'
            : '${savedLabels.length} program kaydedildi';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(summary)),
        );
      }

      if (_currentDraftKey != null) {
        await _restoreDraftOrLoad();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıt başarısız: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _shiftWeek(int deltaWeeks) async {
    _stashCurrentDraft();
    _clearDraftCache();
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * deltaWeeks));
    });
    await _restoreDraftOrLoad(clearFirst: true);
  }

  Future<void> _restoreDraftOrLoad({bool clearFirst = false}) async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;

    final groups = ref.read(allGroupsProvider).valueOrNull ?? [];
    final group = groups.where((g) => g.id == groupId).firstOrNull;
    if (group?.isPerformanceGroup == true && _selectedMemberUserIds.isEmpty) {
      if (clearFirst) _clearDays();
      setState(() {
        _dirty = false;
        _isLoadingWeek = false;
      });
      return;
    }
    if (group?.isPerformanceGroup == true && _selectedMemberUserIds.length > 1) {
      final key = _currentDraftKey;
      final cached = key != null ? _draftCache[key] : null;
      if (cached != null) {
        _applySnapshot(cached);
        if (mounted) setState(() {});
        return;
      }
      if (clearFirst) _clearDays();
      setState(() {
        _dirty = false;
        _isLoadingWeek = false;
      });
      return;
    }

    final key = _currentDraftKey;
    final cached = key != null ? _draftCache[key] : null;
    if (cached != null) {
      _applySnapshot(cached);
      if (mounted) setState(() {});
      return;
    }

    await _loadWeekData(clearFirst: clearFirst);
  }

  Future<void> _switchToGroup(String groupId) async {
    if (groupId == _selectedGroupId &&
        _selectedMemberUserIds.isEmpty) {
      return;
    }

    final groups = ref.read(allGroupsProvider).valueOrNull ?? [];
    final target = groups.where((g) => g.id == groupId).firstOrNull;
    if (target == null) return;

    _stashCurrentDraft();
    setState(() {
      _selectedGroupId = groupId;
      _selectedMemberUserIds.clear();
    });

    if (target.isPerformanceGroup) {
      _clearDays();
      setState(() => _dirty = false);
      return;
    }

    await _restoreDraftOrLoad(clearFirst: true);
  }

  Future<void> _onMembersChanged(Set<String> userIds) async {
    if (Set<String>.from(userIds).difference(_selectedMemberUserIds).isEmpty &&
        _selectedMemberUserIds.difference(userIds).isEmpty) {
      return;
    }

    _stashCurrentDraft();
    final prevCount = _selectedMemberUserIds.length;
    setState(() {
      _selectedMemberUserIds
        ..clear()
        ..addAll(userIds);
    });

    if (userIds.isEmpty) {
      _clearDays();
      setState(() => _dirty = false);
      return;
    }
    if (userIds.length == 1) {
      await _restoreDraftOrLoad(clearFirst: true);
      return;
    }
    // 1'den çoğa geçişte formu koru; 0'dan çoğa geçişte temizle
    if (prevCount <= 1) {
      if (prevCount == 0) _clearDays();
      setState(() => _dirty = userIds.isNotEmpty);
      return;
    }
    await _restoreDraftOrLoad();
  }

  Widget _buildDayPreviewBody(int dayIndex, List<TrainingTypeEntity> types) {
    final text = _days[dayIndex].workoutController.text;
    final coachNotes = _days[dayIndex].notesController.text.trim();
    final parsed = parseCoachText(text);
    final typeLabel = _trainingTypeLabel(_days[dayIndex].trainingTypeOverride, types);

    if (text.trim().isEmpty || parsed.isRest) {
      if (coachNotes.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(Icons.bedtime_outlined, size: 18, color: ThemeBrightnessHolder.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Dinlenme günü',
                style: AppTypography.bodyMedium.copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
              ),
            ],
          ),
        );
      }
      return AdminMonthlyProgramEntryCard(
        row: {
          'plan_date': _ymd(_dayDate(dayIndex)),
          'program_content': '',
          'coach_notes': coachNotes,
          'track_lane': _days[dayIndex].trackLane,
          'training_groups': {'name': ''},
          'training_types': {'display_name': typeLabel ?? 'Otomatik'},
          'source': 'weekly_editor',
        },
      );
    }
    if (!parsed.ok) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          parsed.error ?? 'Hata',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
        ),
      );
    }
    final previewRow = {
      'plan_date': _ymd(_dayDate(dayIndex)),
      'program_content': parsed.programContent,
      'workout_definition': parsed.workoutDefinition,
      'coach_notes': coachNotes,
      'track_lane': _days[dayIndex].trackLane,
      'training_groups': {'name': ''},
      'training_types': {'display_name': typeLabel ?? 'Otomatik'},
      'source': 'weekly_editor',
    };
    return AdminMonthlyProgramEntryCard(row: previewRow);
  }

  Widget _weekActionTile({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required Color accentColor,
    required ColorScheme cs,
  }) {
    final disabled = onPressed == null;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: disabled ? 0.04 : 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: accentColor.withValues(alpha: disabled ? 0.1 : 0.18),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: disabled ? 0.1 : 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: disabled ? cs.outline : accentColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: AppTypography.labelSmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: disabled ? cs.outline : cs.onSurface,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeekActionBar({
    required bool showCopyFromGroup,
    required List<TrainingTypeEntity> types,
    required List<TrainingGroupEntity> activeGroups,
    required ColorScheme cs,
  }) {
    final disabled = _isLoadingWeek;

    return Row(
      children: [
        _weekActionTile(
          onPressed: disabled ? null : () => _showWeekPreviewSheet(types),
          icon: Icons.visibility_outlined,
          label: 'Önizleme',
          accentColor: cs.primary,
          cs: cs,
        ),
        if (showCopyFromGroup) ...[
          const SizedBox(width: 10),
          _weekActionTile(
            onPressed: disabled ? null : () => _copyFromOtherGroup(activeGroups),
            icon: Icons.copy_all_rounded,
            label: 'Gruptan kopyala',
            accentColor: AppColors.secondary,
            cs: cs,
          ),
        ],
        const SizedBox(width: 10),
        _weekActionTile(
          onPressed: disabled ? null : _copyFromPreviousWeek,
          icon: Icons.history_rounded,
          label: 'Geçen hafta',
          accentColor: AppColors.tertiary,
          cs: cs,
        ),
      ],
    );
  }

  Future<void> _showWeekPreviewSheet(List<TrainingTypeEntity> types) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _WeekProgramPreviewSheet(
        weekTitle: _weekTitle(),
        dayPreviews: List.generate(7, (i) {
          final date = _dayDate(i);
          return _DayPreviewData(
            header:
                '${_dayLabels[i]} ${DateFormat('d MMM', 'tr_TR').format(date)}',
            trainingType:
                _trainingTypeLabel(_days[i].trainingTypeOverride, types) ?? 'Otomatik',
            body: _buildDayPreviewBody(i, types),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) {
      return const Scaffold(
        body: Center(child: Text('Bu sayfaya erişim yetkiniz yok.')),
      );
    }

    final groupsAsync = ref.watch(allGroupsProvider);
    final trainingTypesAsync = ref.watch(trainingTypesProvider);
    final groups = groupsAsync.valueOrNull ?? [];
    final activeGroups = groups.where((g) => g.isActive).toList();
    final selectedGroup =
        activeGroups.where((g) => g.id == _selectedGroupId).firstOrNull;
    final membersAsync = selectedGroup?.isPerformanceGroup == true
        ? ref.watch(_groupMembersCacheProvider(selectedGroup!.id))
        : null;
    final selectedMemberItems = membersAsync?.valueOrNull
            ?.where((m) => _selectedMemberUserIds.contains(m.userId))
            .map(
              (m) => ProgramPickerItem(
                id: m.userId,
                label: m.userName,
                icon: Icons.person_outline_rounded,
              ),
            )
            .toList() ??
        [];
    final pendingSaveCount = _countPendingSaves();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Haftalık Program'),
        actions: [
          if (_hasPendingSaves)
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      pendingSaveCount > 1 ? 'Tümünü kaydet' : 'Kaydet',
                    ),
            ),
        ],
      ),
      body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_isLoadingWeek)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(),
                  ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _shiftWeek(-1),
                      icon: Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        _weekTitle(),
                        textAlign: TextAlign.center,
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _shiftWeek(1),
                      icon: Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ProgramEditorPickerField(
                  label: 'Antrenman grubu',
                  valueText: selectedGroup?.name,
                  hintText: 'Grup seçin',
                  onTap: activeGroups.isEmpty
                      ? null
                      : () => _pickGroup(activeGroups),
                ),
                if (selectedGroup?.isPerformanceGroup == true) ...[
                  const SizedBox(height: 12),
                  membersAsync == null
                      ? const SizedBox.shrink()
                      : membersAsync.when(
                          loading: () => const ProgramEditorPickerField(
                            label: 'Sporcular',
                            hintText: 'Yükleniyor…',
                            enabled: false,
                          ),
                          error: (_, __) => const ProgramEditorPickerField(
                            label: 'Sporcular',
                            hintText: 'Liste alınamadı',
                            enabled: false,
                          ),
                          data: (members) => ProgramEditorMultiPickerField(
                            label: 'Sporcular',
                            hintText: 'Sporcu seçin (birden fazla olabilir)',
                            selectedItems: selectedMemberItems,
                            onTap: () => _pickMembers(members),
                          ),
                        ),
                  if (_selectedMemberUserIds.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Toplu atama modu: program ${_selectedMemberUserIds.length} sporcuya kaydedilir',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                AbsorbPointer(
                  absorbing: _isLoadingWeek,
                  child: Opacity(
                    opacity: _isLoadingWeek ? 0.55 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List.generate(7, (i) {
                  final date = _dayDate(i);
                  final parsed = parseCoachText(_days[i].workoutController.text);
                  final hasError = _days[i].workoutController.text.trim().isNotEmpty &&
                      !parsed.ok &&
                      !parsed.isRest;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      key: ValueKey('day-$i'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_dayLabels[i]} ${DateFormat('d MMM', 'tr_TR').format(date)}',
                          style: AppTypography.labelMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        trainingTypesAsync.when(
                          data: (types) {
                            final typeLabel = _trainingTypeLabel(
                                  _days[i].trainingTypeOverride,
                                  types,
                                ) ??
                                'Otomatik';
                            return Row(
                              children: [
                                Expanded(
                                  child: ProgramEditorPickerField(
                                    label: 'Antrenman türü',
                                    valueText: typeLabel,
                                    hintText: 'Otomatik',
                                    onTap: () => _pickTrainingType(i, types),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ProgramEditorPickerField(
                                    label: 'Pist',
                                    valueText: _trackLaneLabel(_days[i].trackLane),
                                    hintText: 'Pistte değil',
                                    onTap: () => _pickTrackLane(i),
                                  ),
                                ),
                              ],
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _days[i].workoutController,
                          maxLines: 3,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            color: cs.onSurface,
                          ),
                          decoration: InputDecoration(
                            hintText: '60dk 6:00/5:50 veya REST',
                            filled: true,
                            fillColor: cs.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: hasError ? AppColors.error : cs.outlineVariant,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: hasError ? AppColors.error : cs.outlineVariant,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: hasError ? AppColors.error : cs.primary,
                              ),
                            ),
                            isDense: true,
                          ),
                        ),
                        if (hasError)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              parsed.error ?? '',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _days[i].notesController,
                          maxLines: 2,
                          style: TextStyle(color: cs.onSurface),
                          decoration: InputDecoration(
                            labelText: 'Koç notu',
                            labelStyle: TextStyle(color: cs.onSurfaceVariant),
                            hintText: 'Sporcuya görünecek serbest not (isteğe bağlı)',
                            filled: true,
                            fillColor: cs.surfaceContainerHigh,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: cs.outlineVariant),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: cs.outlineVariant),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: cs.primary),
                            ),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  );
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildWeekActionBar(
                  showCopyFromGroup: selectedGroup != null &&
                      !selectedGroup.isPerformanceGroup,
                  types: trainingTypesAsync.valueOrNull ?? [],
                  activeGroups: activeGroups,
                  cs: cs,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isSaving || !_hasPendingSaves ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(Icons.save),
                  label: Text(
                    pendingSaveCount > 1
                        ? 'Tüm taslakları kaydet ($pendingSaveCount)'
                        : 'Haftayı kaydet',
                  ),
                ),
              ],
            ),
    );
  }
}

class _DayPreviewData {
  final String header;
  final String trainingType;
  final Widget body;

  const _DayPreviewData({
    required this.header,
    required this.trainingType,
    required this.body,
  });
}

class _WeekProgramPreviewSheet extends StatelessWidget {
  final String weekTitle;
  final List<_DayPreviewData> dayPreviews;

  const _WeekProgramPreviewSheet({
    required this.weekTitle,
    required this.dayPreviews,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.visibility_outlined,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Haftalık önizleme',
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            weekTitle,
                            style: AppTypography.bodySmall.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      tooltip: 'Kapat',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: dayPreviews.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final day = dayPreviews[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                day.header,
                                style: AppTypography.titleSmall.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.secondary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  day.trainingType,
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          day.body,
                        ],
                      ),
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

final _groupMembersCacheProvider = FutureProvider.family<List<GroupMemberModel>, String>(
  (ref, groupId) async {
    final ds = ref.watch(groupDataSourceProvider);
    return ds.getGroupMembers(groupId);
  },
);
