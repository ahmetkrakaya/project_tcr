import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/report_info_button.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../data/models/engagement_excuse_model.dart';
import '../../data/models/user_engagement_report_model.dart';
import '../../domain/entities/event_entity.dart';
import '../providers/engagement_excuse_provider.dart';
import '../providers/event_provider.dart';
import 'engagement_excuses_admin_page.dart';

const _info = ReportInfo(
  title: 'Kullanıcı Analizleri',
  summary:
      'Uygulama kullanımı ve etkinlik katılımına göre üyeleri özetler; en aktif '
      've en pasif üyeleri görmenizi sağlar.',
  terms: [
    ReportInfoTerm('En Çok Açanlar', 'Uygulamayı en sık açan üyeler.'),
    ReportInfoTerm('Uygulamaya Girmeyenler', 'Son 30 günde uygulamayı açmayanlar.'),
    ReportInfoTerm('Etkinliğe Katılmayanlar', 'Son dönemde etkinliklere gelmeyenler.'),
    ReportInfoTerm('Mazaret', 'Pasif üyeler için kaydedilen gerekçe.'),
  ],
  takeaways: [
    'Pasifleşen üyelere zamanında ulaşıp geri kazanın.',
    'Aktif üyeleri ödüllendirmek bağlılığı artırır.',
    'Mazaretleri inceleyerek gerçek nedenleri anlayın.',
  ],
);

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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kullanıcı Analizleri'),
        actions: [
          IconButton(
            icon: Icon(Icons.fact_check_outlined),
            tooltip: 'Mazaretler',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EngagementExcusesAdminPage(),
                ),
              );
            },
          ),
          const ReportInfoButton(info: _info),
        ],
      ),
      body: reportsAsync.when(
        data: (reports) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(userEngagementReportsProvider);
            ref.invalidate(topEventParticipantsProvider(_selectedEventType));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                'Uygulama kullanımı ve etkinlik katılımına göre özet listeler.',
                style: AppTypography.bodyMedium.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _LeaderboardSection(
                icon: Icons.smartphone_outlined,
                iconColor: AppColors.info,
                title: 'Uygulamayı En Çok Açanlar',
                subtitle: 'Top 10 · tüm zamanlar',
                items: reports.topAppOpeners,
                valueBuilder: (item) => '${item.openCount ?? 0} açılış',
              ),
              const SizedBox(height: 12),
              _InactiveUsersSection(
                icon: Icons.person_off_outlined,
                iconColor: AppColors.warning,
                title: 'Uygulamaya Girmeyenler',
                subtitle: 'Son 30 gün',
                excuseType: EngagementExcuseType.inactiveApp,
                items: reports.inactiveAppUsers,
                dateLabel: 'Son kullanım',
                dateValue: (item) => item.lastActivityAt,
              ),
              const SizedBox(height: 12),
              _TopEventParticipantsSection(
                selectedEventType: _selectedEventType,
                onEventTypeChanged: (value) {
                  setState(() => _selectedEventType = value);
                },
              ),
              const SizedBox(height: 12),
              _InactiveUsersSection(
                icon: Icons.event_busy_outlined,
                iconColor: AppColors.error,
                title: 'Etkinliğe Katılmayanlar',
                subtitle: 'Son 30 gün',
                excuseType: EngagementExcuseType.inactiveEvent,
                items: reports.inactiveEventUsers,
                dateLabel: 'Son katılım',
                dateValue: (item) => item.lastParticipationAt,
              ),
            ],
          ),
        ),
        loading: () => const Center(child: LoadingWidget()),
        error: (error, _) {
          final cs = Theme.of(context).colorScheme;
          return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Rapor yüklenemedi',
                  style: AppTypography.titleSmall.copyWith(color: cs.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: AppTypography.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
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
        );
        },
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  const _SectionShell({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.isExpanded,
    required this.onToggle,
    this.headerAction,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final int count;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget? headerAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: isDark ? 0.2 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: AppTypography.bodySmall.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _CountChip(count: count),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.outline,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Divider(
              height: 1,
              color: cs.outlineVariant,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (headerAction != null) ...[
                    headerAction!,
                    const SizedBox(height: 12),
                  ],
                  child,
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        count.toString(),
        style: AppTypography.labelSmall.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LeaderboardSection extends StatefulWidget {
  const _LeaderboardSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.valueBuilder,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final List<UserEngagementReportItemModel> items;
  final String Function(UserEngagementReportItemModel item) valueBuilder;

  @override
  State<_LeaderboardSection> createState() => _LeaderboardSectionState();
}

class _LeaderboardSectionState extends State<_LeaderboardSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      icon: widget.icon,
      iconColor: widget.iconColor,
      title: widget.title,
      subtitle: widget.subtitle,
      count: widget.items.length,
      isExpanded: _isExpanded,
      onToggle: () => setState(() => _isExpanded = !_isExpanded),
      child: widget.items.isEmpty
          ? const _SectionEmptyState()
          : Column(
              children: widget.items.asMap().entries.map((entry) {
                return _UserListTile(
                  rank: entry.key + 1,
                  name: entry.value.fullName,
                  trailing: widget.valueBuilder(entry.value),
                  showDivider: entry.key < widget.items.length - 1,
                );
              }).toList(),
            ),
    );
  }
}

class _InactiveUsersSection extends ConsumerStatefulWidget {
  const _InactiveUsersSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.excuseType,
    required this.items,
    required this.dateLabel,
    required this.dateValue,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String excuseType;
  final List<UserEngagementReportItemModel> items;
  final String dateLabel;
  final DateTime? Function(UserEngagementReportItemModel item) dateValue;

  @override
  ConsumerState<_InactiveUsersSection> createState() =>
      _InactiveUsersSectionState();
}

class _InactiveUsersSectionState extends ConsumerState<_InactiveUsersSection> {
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
    return _SectionShell(
      icon: widget.icon,
      iconColor: widget.iconColor,
      title: widget.title,
      subtitle: widget.subtitle,
      count: widget.items.length,
      isExpanded: _isExpanded,
      onToggle: () => setState(() => _isExpanded = !_isExpanded),
      headerAction: widget.items.isEmpty
          ? null
          : Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _isSending
                    ? null
                    : () => _sendToUsers(
                          widget.items.map((e) => e.userId).toList(),
                        ),
                icon: _isSending && _sendingUserId == null
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.send_outlined, size: 18),
                label: const Text('Tümüne bildir'),
              ),
            ),
      child: widget.items.isEmpty
          ? const _SectionEmptyState()
          : Column(
              children: widget.items.asMap().entries.map((entry) {
                final item = entry.value;
                final date = widget.dateValue(item);
                final dateText = date != null
                    ? DateFormat('d MMM yyyy').format(date.toLocal())
                    : 'Hiç';

                return _UserListTile(
                  name: item.fullName,
                  subtitle: '${widget.dateLabel}: $dateText',
                  trailing: _SendButton(
                    isLoading: _isSending && _sendingUserId == item.userId,
                    onPressed: _isSending
                        ? null
                        : () => _sendToUsers([item.userId]),
                  ),
                  showDivider: entry.key < widget.items.length - 1,
                );
              }).toList(),
            ),
    );
  }
}

class _TopEventParticipantsSection extends ConsumerStatefulWidget {
  const _TopEventParticipantsSection({
    required this.selectedEventType,
    required this.onEventTypeChanged,
  });

  final String? selectedEventType;
  final ValueChanged<String?> onEventTypeChanged;

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

    return _SectionShell(
      icon: Icons.event_available_outlined,
      iconColor: AppColors.tertiary,
      title: 'En Çok Etkinliğe Katılanlar',
      subtitle: 'Top 10 · Katılıyorum RSVP',
      count: count,
      isExpanded: _isExpanded,
      onToggle: () => setState(() => _isExpanded = !_isExpanded),
      headerAction: _EventTypeChips(
        selectedEventType: widget.selectedEventType,
        onChanged: widget.onEventTypeChanged,
      ),
      child: participantsAsync.when(
        data: (list) {
          if (list.isEmpty) return const _SectionEmptyState();
          return Column(
            children: list.asMap().entries.map((entry) {
              return _UserListTile(
                rank: entry.key + 1,
                name: entry.value.fullName,
                trailing: '${entry.value.participationCount ?? 0} etkinlik',
                showDivider: entry.key < list.length - 1,
              );
            }).toList(),
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: LoadingWidget(size: 28)),
        ),
        error: (error, _) => Text(
          'Liste yüklenemedi: $error',
          style: AppTypography.bodySmall.copyWith(color: AppColors.error),
        ),
      ),
    );
  }
}

class _EventTypeChips extends StatelessWidget {
  const _EventTypeChips({
    required this.selectedEventType,
    required this.onChanged,
  });

  final String? selectedEventType;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final options = <({String? value, String label})>[
      (value: null, label: 'Tümü'),
      (value: EventType.training.name, label: 'Antrenman'),
      (value: EventType.race.name, label: 'Yarış'),
      (value: EventType.social.name, label: 'Sosyal'),
      (value: EventType.workshop.name, label: 'Atölye'),
      (value: EventType.other.name, label: 'Diğer'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = selectedEventType == option.value;
        return FilterChip(
          label: Text(option.label),
          selected: isSelected,
          showCheckmark: false,
          onSelected: (_) => onChanged(option.value),
          labelStyle: AppTypography.labelSmall.copyWith(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
          ),
          selectedColor: cs.primary.withValues(alpha: 0.2),
          backgroundColor: cs.surfaceContainerHighest,
          checkmarkColor: cs.primary,
          side: BorderSide(
            color: isSelected ? cs.primary : cs.outlineVariant,
          ),
        );
      }).toList(),
    );
  }
}

class _UserListTile extends StatelessWidget {
  const _UserListTile({
    this.rank,
    required this.name,
    this.subtitle,
    required this.trailing,
    this.showDivider = false,
  });

  final int? rank;
  final String name;
  final String? subtitle;
  final dynamic trailing;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              if (rank != null) ...[
                _RankIndicator(rank: rank!),
                const SizedBox(width: 10),
              ],
              UserAvatar(name: name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppTypography.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing is Widget
                  ? trailing as Widget
                  : _ValueLabel(text: trailing as String),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.6),
          ),
      ],
    );
  }
}

class _RankIndicator extends StatelessWidget {
  const _RankIndicator({required this.rank});

  final int rank;

  Color _color(BuildContext context) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFB300);
      case 2:
        return const Color(0xFF9E9E9E);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: Text(
        '#$rank',
        style: AppTypography.labelSmall.copyWith(
          color: _color(context),
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ValueLabel extends StatelessWidget {
  const _ValueLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: AppTypography.labelSmall.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
      textAlign: TextAlign.right,
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 36,
          height: 36,
          child: isLoading
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                )
              : Icon(
                  Icons.send_outlined,
                  size: 18,
                  color: cs.primary,
                ),
        ),
      ),
    );
  }
}

class _SectionEmptyState extends StatelessWidget {
  const _SectionEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: EmptyStateWidget(
        icon: Icons.inbox_outlined,
        title: 'Kayıt yok',
        description: 'Bu kriterlere uygun kullanıcı bulunamadı.',
      ),
    );
  }
}
