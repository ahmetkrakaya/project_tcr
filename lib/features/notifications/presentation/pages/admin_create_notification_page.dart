import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/datasources/notification_remote_datasource.dart';
import '../providers/notification_provider.dart';

class AdminCreateNotificationPage extends ConsumerStatefulWidget {
  const AdminCreateNotificationPage({super.key});

  @override
  ConsumerState<AdminCreateNotificationPage> createState() =>
      _AdminCreateNotificationPageState();
}

class _AdminCreateNotificationPageState
    extends ConsumerState<AdminCreateNotificationPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  bool _sendNow = true;
  DateTime? _scheduledAt;

  _AudienceType _audienceType = _AudienceType.everyone;
  final Set<_RoleFilter> _selectedRoles = <_RoleFilter>{};
  final Set<String> _selectedGroupIds = <String>{};
  _IntegrationTarget _integrationTarget = _IntegrationTarget.stravaConnected;
  String? _routeTarget;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final senderState = ref.watch(adminNotificationSenderProvider);
    final groupsAsync = ref.watch(adminNotificationGroupsProvider);

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bildirim Oluştur')),
        body: const Center(child: Text('Bu sayfaya erişim yetkiniz yok.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirim Oluştur'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: senderState.isLoading ? null : _submit,
              tooltip: _sendNow ? 'Gönder' : 'Planla',
              icon: senderState.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              maxLength: 90,
              decoration: const InputDecoration(
                labelText: 'Başlık',
                hintText: 'Bildirim başlığı',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Başlık zorunlu';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bodyController,
              maxLines: 5,
              maxLength: 400,
              decoration: const InputDecoration(
                labelText: 'İçerik',
                hintText: 'Bildirim metni',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'İçerik zorunlu';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _SectionTitle('Hedef Kitle'),
            DropdownButtonFormField<_AudienceType>(
              value: _audienceType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Hedef Kitle Tipi',
              ),
              items: _AudienceType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(type.label),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _audienceType = v;
                });
              },
            ),
            if (_audienceType == _AudienceType.roles) ...[
              const SizedBox(height: 12),
              _buildMultiSelectField<_RoleFilter>(
                label: 'Roller',
                hint: 'Bir veya daha fazla rol seç',
                items: _RoleFilter.values,
                selectedItems: _selectedRoles,
                itemLabel: (item) => item.label,
                onPick: () async {
                  final result = await _showMultiSelectSheet<_RoleFilter>(
                    title: 'Rolleri Seç',
                    items: _RoleFilter.values,
                    selectedItems: _selectedRoles,
                    itemLabel: (item) => item.label,
                  );
                  if (result == null) return;
                  setState(() {
                    _selectedRoles
                      ..clear()
                      ..addAll(result);
                  });
                },
                summaryBuilder: (selected) {
                  if (selected.isEmpty) return 'Seçilmedi';
                  return selected.map((e) => e.label).join(', ');
                },
              ),
            ],
            if (_audienceType == _AudienceType.groups) ...[
              const SizedBox(height: 16),
              _SectionTitle('Grup Filtreleri (çoklu seçim)'),
              groupsAsync.when(
                data: (groups) {
                  if (groups.isEmpty) {
                    return const Text('Aktif grup bulunamadı.');
                  }
                  return _buildMultiSelectField<AdminTrainingGroup>(
                    label: 'Gruplar',
                    hint: 'Bir veya daha fazla grup seç',
                    items: groups,
                    selectedItems: groups
                        .where((group) => _selectedGroupIds.contains(group.id))
                        .toSet(),
                    itemLabel: (item) => item.name,
                    onPick: () async {
                      final selectedGroups =
                          groups.where((g) => _selectedGroupIds.contains(g.id)).toSet();
                      final result = await _showMultiSelectSheet<AdminTrainingGroup>(
                        title: 'Grupları Seç',
                        items: groups,
                        selectedItems: selectedGroups,
                        itemLabel: (item) => item.name,
                      );
                      if (result == null) return;
                      setState(() {
                        _selectedGroupIds
                          ..clear()
                          ..addAll(result.map((g) => g.id));
                      });
                    },
                    summaryBuilder: (selected) {
                      if (selected.isEmpty) return 'Seçilmedi';
                      if (selected.length == 1) return selected.first.name;
                      return '${selected.length} grup seçildi';
                    },
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Gruplar yüklenemedi.'),
              ),
            ],
            if (_audienceType == _AudienceType.integration) ...[
              const SizedBox(height: 16),
              _SectionTitle('Entegrasyon Filtresi'),
              DropdownButtonFormField<_IntegrationTarget>(
                value: _integrationTarget,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Entegrasyon',
                ),
                items: _IntegrationTarget.values
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(v.label),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _integrationTarget = v;
                  });
                },
              ),
            ],
            const SizedBox(height: 20),
            _SectionTitle('Bildirimde Açılacak Sayfa (opsiyonel)'),
            DropdownButtonFormField<String?>(
              value: _routeTarget,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Yönlendirme',
              ),
              items: const [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Yok'),
                ),
                DropdownMenuItem<String?>(
                  value: 'integrations',
                  child: Text('Bağlantılar'),
                ),
                DropdownMenuItem<String?>(
                  value: 'pace_calculator',
                  child: Text('VDOT Hesaplayıcı'),
                ),
                DropdownMenuItem<String?>(
                  value: 'notifications',
                  child: Text('Bildirimler'),
                ),
                DropdownMenuItem<String?>(
                  value: 'groups',
                  child: Text('Gruplar'),
                ),
              ],
              onChanged: (v) => setState(() => _routeTarget = v),
            ),
            const SizedBox(height: 20),
            _SectionTitle('Gönderim Zamanı'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Şimdi gönder'),
              value: _sendNow,
              onChanged: (v) => setState(() {
                _sendNow = v;
                if (v) _scheduledAt = null;
              }),
            ),
            if (!_sendNow)
              OutlinedButton.icon(
                onPressed: _pickScheduleDateTime,
                icon: const Icon(Icons.schedule),
                label: Text(
                  _scheduledAt == null
                      ? 'Tarih ve saat seç'
                      : 'Seçilen: ${_formatDateTime(_scheduledAt!)}',
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _pickScheduleDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  String _formatDateTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_sendNow && _scheduledAt == null) {
      _showMessage('Lütfen planlı gönderim için tarih/saat seçin.');
      return;
    }
    if (_audienceType == _AudienceType.roles && _selectedRoles.isEmpty) {
      _showMessage('Rol bazlı gönderim için en az bir rol seçin.');
      return;
    }
    if (_audienceType == _AudienceType.groups && _selectedGroupIds.isEmpty) {
      _showMessage('Grup bazlı gönderim için en az bir grup seçin.');
      return;
    }
    final audience = _buildAudiencePayload();
    try {
      await ref.read(adminNotificationSenderProvider.notifier).send(
            title: _titleController.text.trim(),
            body: _bodyController.text.trim(),
            audience: audience,
            scheduleAt: _sendNow ? null : _scheduledAt,
            routeTarget: _routeTarget,
          );
      if (!mounted) return;
      _showMessage(_sendNow
          ? 'Bildirim gönderildi.'
          : 'Bildirim planlandı, zamanı geldiğinde gönderilecek.');
      Navigator.of(context).maybePop();
    } catch (e) {
      _showMessage('İşlem başarısız: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  AdminNotificationAudience _buildAudiencePayload() {
    bool everyone = false;
    bool admins = false;
    bool coaches = false;
    bool members = false;

    if (_audienceType == _AudienceType.everyone) {
      everyone = true;
    } else if (_audienceType == _AudienceType.roles) {
      admins = _selectedRoles.contains(_RoleFilter.admin);
      coaches = _selectedRoles.contains(_RoleFilter.coach);
      members = _selectedRoles.contains(_RoleFilter.member);
    }

    final isGroupAudience = _audienceType == _AudienceType.groups;
    final integration = _audienceType == _AudienceType.integration
        ? _integrationTarget
        : null;

    return AdminNotificationAudience(
      everyone: everyone,
      admins: admins,
      coaches: coaches,
      members: members,
      groupIds: isGroupAudience ? _selectedGroupIds.toList() : const [],
      stravaConnected: integration == _IntegrationTarget.stravaConnected
          ? true
          : integration == _IntegrationTarget.stravaNotConnected
              ? false
              : null,
      garminConnected: integration == _IntegrationTarget.garminConnected
          ? true
          : integration == _IntegrationTarget.garminNotConnected
              ? false
              : null,
      vdotMissing: integration == _IntegrationTarget.vdotMissing,
    );
  }

  Widget _buildMultiSelectField<T>({
    required String label,
    required String hint,
    required List<T> items,
    required Set<T> selectedItems,
    required String Function(T item) itemLabel,
    required Future<void> Function() onPick,
    required String Function(Set<T> selected) summaryBuilder,
  }) {
    return InkWell(
      onTap: items.isEmpty ? null : onPick,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          selectedItems.isEmpty ? hint : summaryBuilder(selectedItems),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selectedItems.isEmpty ? AppColors.neutral500 : null,
              ),
        ),
      ),
    );
  }

  Future<Set<T>?> _showMultiSelectSheet<T>({
    required String title,
    required List<T> items,
    required Set<T> selectedItems,
    required String Function(T item) itemLabel,
  }) async {
    final temp = <T>{...selectedItems};
    return showModalBottomSheet<Set<T>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(<T>{...temp}),
                          child: const Text('Tamam'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final selected = temp.contains(item);
                          return CheckboxListTile(
                            value: selected,
                            contentPadding: EdgeInsets.zero,
                            title: Text(itemLabel(item)),
                            onChanged: (v) {
                              setSheetState(() {
                                if (v == true) {
                                  temp.add(item);
                                } else {
                                  temp.remove(item);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

enum _AudienceType {
  everyone('Herkes'),
  roles('Rol bazlı'),
  groups('Grup bazlı'),
  integration('Entegrasyon bazlı');

  final String label;
  const _AudienceType(this.label);
}

enum _RoleFilter {
  admin('Admin'),
  coach('Koç'),
  member('Kullanıcı');

  final String label;
  const _RoleFilter(this.label);
}

enum _IntegrationTarget {
  stravaConnected('Strava bağlı olanlar'),
  stravaNotConnected('Strava bağlı olmayanlar'),
  garminConnected('Garmin bağlı olanlar'),
  garminNotConnected('Garmin bağlı olmayanlar'),
  vdotMissing('VDOT hesaplamamış olanlar');

  final String label;
  const _IntegrationTarget(this.label);
}
