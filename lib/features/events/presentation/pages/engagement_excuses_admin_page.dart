import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../data/models/engagement_excuse_model.dart';
import '../providers/engagement_excuse_provider.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// Admin mazaret yönetim sayfası
class EngagementExcusesAdminPage extends ConsumerWidget {
  const EngagementExcusesAdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(engagementExcuseAdminReportsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mazaretler'),
      ),
      body: reportsAsync.when(
        data: (reports) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(engagementExcuseAdminReportsProvider);
            await ref.read(engagementExcuseAdminReportsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ExcuseSection(
                icon: Icons.hourglass_empty,
                title: 'Mazaret Göndermeyenler',
                subtitle: 'Bildirim gönderildi, henüz yanıt yok',
                items: reports.awaitingSubmission,
                showExcuseText: false,
              ),
              const SizedBox(height: 12),
              _ExcuseSection(
                icon: Icons.pending_actions_outlined,
                title: 'Değerlendirme Bekleyenler',
                subtitle: 'Mazaret yazıldı, admin onayı bekleniyor',
                items: reports.submitted,
                showExcuseText: true,
                showActions: true,
              ),
              const SizedBox(height: 12),
              _ExcuseSection(
                icon: Icons.verified_user_outlined,
                title: 'Kabul Edilen Mazaretler',
                subtitle: 'Muafiyet süresi devam edenler',
                items: reports.accepted,
                showExcuseText: true,
                showExemptUntil: true,
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
                Text('Mazaretler yüklenemedi', style: AppTypography.titleMedium),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(engagementExcuseAdminReportsProvider),
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

class _ExcuseSection extends ConsumerStatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<EngagementExcuseItemModel> items;
  final bool showExcuseText;
  final bool showActions;
  final bool showExemptUntil;

  const _ExcuseSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.items,
    this.showExcuseText = false,
    this.showActions = false,
    this.showExemptUntil = false,
  });

  @override
  ConsumerState<_ExcuseSection> createState() => _ExcuseSectionState();
}

class _ExcuseSectionState extends ConsumerState<_ExcuseSection> {
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
                          '${widget.title} (${widget.items.length})',
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.subtitle,
                          style: AppTypography.bodySmall.copyWith(
                            color: ThemeBrightnessHolder.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: ThemeBrightnessHolder.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: widget.items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: EmptyStateWidget(
                        icon: Icons.inbox_outlined,
                        title: 'Kayıt yok',
                        description: 'Bu kategoride mazaret bulunmuyor.',
                      ),
                    )
                  : Column(
                      children: widget.items
                          .map(
                            (item) => _ExcuseItemCard(
                              item: item,
                              showExcuseText: widget.showExcuseText,
                              showActions: widget.showActions,
                              showExemptUntil: widget.showExemptUntil,
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExcuseItemCard extends ConsumerStatefulWidget {
  final EngagementExcuseItemModel item;
  final bool showExcuseText;
  final bool showActions;
  final bool showExemptUntil;

  const _ExcuseItemCard({
    required this.item,
    required this.showExcuseText,
    required this.showActions,
    required this.showExemptUntil,
  });

  @override
  ConsumerState<_ExcuseItemCard> createState() => _ExcuseItemCardState();
}

class _ExcuseItemCardState extends ConsumerState<_ExcuseItemCard> {
  bool _isProcessing = false;

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    return DateFormat('dd.MM.yyyy HH:mm').format(date.toLocal());
  }

  Future<void> _accept() async {
    final result = await showDialog<_AcceptExcuseResult>(
      context: context,
      builder: (context) => _AcceptExcuseDialog(),
    );
    if (result == null || !context.mounted) return;

    setState(() => _isProcessing = true);
    try {
      await ref.read(engagementExcuseActionsProvider).acceptExcuse(
            requestId: widget.item.requestId,
            exemptUntil: result.exemptUntil,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mazaret kabul edildi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _ban() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullanıcıyı Banla'),
        content: Text(
          '${widget.item.fullName} kullanıcısını banlamak istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Banla'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      await ref.read(engagementExcuseActionsProvider).banFromExcuse(
            requestId: widget.item.requestId,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanıcı banlandı')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeBrightnessHolder.scaffoldBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(size: 36, name: item.fullName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fullName,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      EngagementExcuseType.label(item.excuseType),
                      style: AppTypography.labelSmall.copyWith(
                        color: ThemeBrightnessHolder.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Gönderim: ${_formatDate(item.sentAt)}',
            style: AppTypography.labelSmall.copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
          ),
          if (item.submittedAt != null)
            Text(
              'Mazaret tarihi: ${_formatDate(item.submittedAt)}',
              style: AppTypography.labelSmall.copyWith(color: ThemeBrightnessHolder.onSurfaceVariant),
            ),
          if (widget.showExemptUntil)
            Text(
              item.exemptUntil != null
                  ? 'Muafiyet bitişi: ${_formatDate(item.exemptUntil)}'
                  : 'Muafiyet: Süresiz',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.secondaryDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (widget.showExcuseText && item.excuseText != null) ...[
            const SizedBox(height: 8),
            Text(
              item.excuseText!,
              style: AppTypography.bodySmall.copyWith(
                color: ThemeBrightnessHolder.onSurface,
                height: 1.4,
              ),
            ),
          ],
          if (widget.showActions) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _accept,
                    icon: Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Kabul Et'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isProcessing ? null : _ban,
                    icon: Icon(Icons.block, size: 18),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                    label: const Text('Banla'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AcceptExcuseResult {
  final DateTime? exemptUntil;

  const _AcceptExcuseResult(this.exemptUntil);
}

class _AcceptExcuseDialog extends StatefulWidget {
  @override
  State<_AcceptExcuseDialog> createState() => _AcceptExcuseDialogState();
}

class _AcceptExcuseDialogState extends State<_AcceptExcuseDialog> {
  int _selectedMonths = 3;
  bool _indefinite = false;

  DateTime? get _exemptUntil {
    if (_indefinite) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month + _selectedMonths, now.day);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mazareti Kabul Et'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bu süre boyunca kullanıcı ilgili listede görünmez.',
            style: AppTypography.bodySmall.copyWith(
              color: ThemeBrightnessHolder.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Süresiz muafiyet'),
            subtitle: const Text('Belirli bir bitiş tarihi olmadan'),
            value: _indefinite,
            onChanged: (v) => setState(() => _indefinite = v),
          ),
          if (!_indefinite) ...[
            const SizedBox(height: 8),
            Text('Muafiyet süresi', style: AppTypography.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final months in [1, 3, 6, 12])
                  ChoiceChip(
                    label: Text('$months ay'),
                    selected: _selectedMonths == months,
                    onSelected: (_) =>
                        setState(() => _selectedMonths = months),
                  ),
              ],
            ),
            if (_exemptUntil != null) ...[
              const SizedBox(height: 12),
              Text(
                'Bitiş: ${DateFormat('dd.MM.yyyy').format(_exemptUntil!)}',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _AcceptExcuseResult(_exemptUntil)),
          child: const Text('Kabul Et'),
        ),
      ],
    );
  }
}
