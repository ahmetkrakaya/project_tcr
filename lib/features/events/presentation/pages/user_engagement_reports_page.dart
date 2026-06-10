import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../data/models/engagement_excuse_model.dart';
import '../../data/models/user_engagement_report_model.dart';
import '../../domain/entities/event_entity.dart';
import '../providers/engagement_excuse_provider.dart';
import '../providers/event_provider.dart';
import 'engagement_excuses_admin_page.dart';

/// Admin kullanıcı etkileşim analizleri
class UserEngagementReportsPage extends ConsumerStatefulWidget {
  const UserEngagementReportsPage({super.key});

  @override
  ConsumerState<UserEngagementReportsPage> createState() =>
      _UserEngagementReportsPageState();
}

class _UserEngagementReportsPageState
    extends ConsumerState<UserEngagementReportsPage> {
  String? _selectedEventType;

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(userEngagementReportsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kullanıcı Analizleri'),
        actions: [
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Mazaretler',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EngagementExcusesAdminPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: reportsAsync.when(
        data: (reports) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(userEngagementReportsProvider);
            ref.invalidate(topEventParticipantsProvider(_selectedEventType));
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _CollapsibleReportSection(
                icon: Icons.smartphone,
                title: 'Uygulamayı En Çok Açanlar',
                subtitle: 'Top 10 — tüm zamanlar',
                count: reports.topAppOpeners.length,
                items: reports.topAppOpeners,
                trailingBuilder: (item, index) => _RankBadge(
                  rank: index + 1,
                  value: '${item.openCount ?? 0} açılış',
                ),
              ),
              const SizedBox(height: 12),
              _InactiveUsersReportSection(
                icon: Icons.person_off_outlined,
                title: 'Son 30 Günde Uygulamaya Girmeyenler',
                subtitle: 'Son 30 gün',
                excuseType: EngagementExcuseType.inactiveApp,
                items: reports.inactiveAppUsers,
                trailingBuilder: (item, _) => _DateLabel(
                  label: 'Son kullanım',
                  date: item.lastActivityAt,
                ),
              ),
              const SizedBox(height: 12),
              _TopEventParticipantsSection(
                selectedEventType: _selectedEventType,
                onEventTypeChanged: (value) {
                  setState(() => _selectedEventType = value);
                },
              ),
              const SizedBox(height: 12),
              _InactiveUsersReportSection(
                icon: Icons.event_busy,
                title: 'Son 30 Günde Etkinliğe Katılmayanlar',
                subtitle: 'Son 30 gün',
                excuseType: EngagementExcuseType.inactiveEvent,
                items: reports.inactiveEventUsers,
                trailingBuilder: (item, _) => _DateLabel(
                  label: 'Son katılım',
                  date: item.lastParticipationAt,
                ),
              ),
            ],
          ),
        ),
        loading: () => const Center(child: LoadingWidget()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Rapor yüklenemedi',
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(userEngagementReportsProvider),
                  child: const Text('Tekrar Dene'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopEventParticipantsSection extends ConsumerStatefulWidget {
  final String? selectedEventType;
  final ValueChanged<String?> onEventTypeChanged;

  const _TopEventParticipantsSection({
    required this.selectedEventType,
    required this.onEventTypeChanged,
  });

  @override
  ConsumerState<_TopEventParticipantsSection> createState() =>
      _TopEventParticipantsSectionState();
}

class _TopEventParticipantsSectionState
    extends ConsumerState<_TopEventParticipantsSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final participantsAsync = ref.watch(
      topEventParticipantsProvider(widget.selectedEventType),
    );
    final count = participantsAsync.valueOrNull?.length ?? 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.event_available,
                      size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'En Çok Etkinliğe Katılanlar ($count)',
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Top 10 — RSVP: Katılıyorum',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (participantsAsync.isLoading && _isExpanded)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.neutral500,
                    ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEventTypeFilter(),
                  const SizedBox(height: 12),
                  participantsAsync.when(
                    data: (list) {
                      if (list.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: EmptyStateWidget(
                            icon: Icons.inbox_outlined,
                            title: 'Kayıt yok',
                            description:
                                'Bu kriterlere uygun kullanıcı bulunamadı.',
                          ),
                        );
                      }
                      return Column(
                        children: list.asMap().entries.map((entry) {
                          final item = entry.value;
                          return _UserRow(
                            item: item,
                            trailing: _RankBadge(
                              rank: entry.key + 1,
                              value:
                                  '${item.participationCount ?? 0} etkinlik',
                            ),
                          );
                        }).toList(),
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: LoadingWidget(size: 28),
                      ),
                    ),
                    error: (error, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Liste yüklenemedi: $error',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventTypeFilter() {
    return Row(
      children: [
        Text(
          'Etkinlik türü:',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.neutral600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String?>(
            value: widget.selectedEventType,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Tümü'),
              ),
              ...EventType.values.map(
                (type) => DropdownMenuItem<String?>(
                  value: type.name,
                  child: Text(_eventTypeLabel(type)),
                ),
              ),
            ],
            onChanged: widget.onEventTypeChanged,
          ),
        ),
      ],
    );
  }

  String _eventTypeLabel(EventType type) {
    switch (type) {
      case EventType.training:
        return 'Antrenman';
      case EventType.race:
        return 'Yarış';
      case EventType.social:
        return 'Sosyal';
      case EventType.workshop:
        return 'Atölye';
      case EventType.other:
        return 'Diğer';
    }
  }
}

class _InactiveUsersReportSection extends ConsumerStatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String excuseType;
  final List<UserEngagementReportItemModel> items;
  final Widget Function(UserEngagementReportItemModel item, int index)
      trailingBuilder;

  const _InactiveUsersReportSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.excuseType,
    required this.items,
    required this.trailingBuilder,
  });

  @override
  ConsumerState<_InactiveUsersReportSection> createState() =>
      _InactiveUsersReportSectionState();
}

class _InactiveUsersReportSectionState
    extends ConsumerState<_InactiveUsersReportSection> {
  bool _isExpanded = false;
  bool _isSending = false;
  String? _sendingUserId;

  Future<void> _sendToUsers(List<String> userIds) async {
    if (userIds.isEmpty || _isSending) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mazaret Bildir'),
        content: Text(
          userIds.length == 1
              ? 'Seçili kullanıcıya mazaret bildirimi gönderilsin mi?'
              : '${userIds.length} kullanıcıya mazaret bildirimi gönderilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isSending = true;
      if (userIds.length == 1) _sendingUserId = userIds.first;
    });

    try {
      final result =
          await ref.read(engagementExcuseActionsProvider).sendRequests(
                userIds: userIds,
                excuseType: widget.excuseType,
              );
      if (!mounted) return;
      final skipped = result.skippedCount;
      final sent = result.sentCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent > 0
                ? '$sent kullanıcıya gönderildi'
                    '${skipped > 0 ? ', $skipped atlandı' : ''}'
                : 'Gönderilemedi (zaten bekleyen mazaret olabilir)',
          ),
        ),
      );
      ref.invalidate(engagementExcuseAdminReportsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _sendingUserId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(widget.icon, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.title} (${widget.items.length})',
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.subtitle,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.neutral500,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isSending
                              ? null
                              : () => _sendToUsers(
                                    widget.items
                                        .map((e) => e.userId)
                                        .toList(),
                                  ),
                          icon: _isSending && _sendingUserId == null
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_outlined, size: 18),
                          label: const Text('Hepsine Gönder'),
                        ),
                      ),
                    ),
                  if (widget.items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: EmptyStateWidget(
                        icon: Icons.inbox_outlined,
                        title: 'Kayıt yok',
                        description:
                            'Bu kriterlere uygun kullanıcı bulunamadı.',
                      ),
                    )
                  else
                    ...widget.items.asMap().entries.map(
                          (entry) => _UserRow(
                            item: entry.value,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                widget.trailingBuilder(
                                  entry.value,
                                  entry.key,
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Mazaret Bildir',
                                  onPressed: _isSending
                                      ? null
                                      : () => _sendToUsers(
                                            [entry.value.userId],
                                          ),
                                  icon: _isSending &&
                                          _sendingUserId == entry.value.userId
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.send_outlined,
                                          size: 20,
                                          color: AppColors.primary,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CollapsibleReportSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final List<UserEngagementReportItemModel> items;
  final Widget Function(UserEngagementReportItemModel item, int index)
      trailingBuilder;

  const _CollapsibleReportSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.items,
    required this.trailingBuilder,
  });

  @override
  State<_CollapsibleReportSection> createState() =>
      _CollapsibleReportSectionState();
}

class _CollapsibleReportSectionState extends State<_CollapsibleReportSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(widget.icon, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.title} (${widget.count})',
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.subtitle,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.neutral500,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: EmptyStateWidget(
                        icon: Icons.inbox_outlined,
                        title: 'Kayıt yok',
                        description:
                            'Bu kriterlere uygun kullanıcı bulunamadı.',
                      ),
                    )
                  else
                    ...widget.items.asMap().entries.map(
                          (entry) => _UserRow(
                            item: entry.value,
                            trailing: widget.trailingBuilder(
                              entry.value,
                              entry.key,
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final UserEngagementReportItemModel item;
  final Widget trailing;

  const _UserRow({
    required this.item,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          UserAvatar(size: 36, name: item.fullName),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.fullName,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  final String value;

  const _RankBadge({required this.rank, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '#$rank',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.neutral600,
          ),
        ),
      ],
    );
  }
}

class _DateLabel extends StatelessWidget {
  final String label;
  final DateTime? date;

  const _DateLabel({required this.label, this.date});

  @override
  Widget build(BuildContext context) {
    final text = date != null
        ? DateFormat('dd.MM.yyyy').format(date!.toLocal())
        : 'Hiç';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.neutral500,
          ),
        ),
        Text(
          text,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.neutral700,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
