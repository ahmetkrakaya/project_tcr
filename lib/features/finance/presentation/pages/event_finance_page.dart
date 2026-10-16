import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../marketplace/data/models/order_model.dart';
import '../../../marketplace/utils/market_report_utils.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';
import '../../data/models/event_finance_model.dart';
import '../../utils/finance_excel_export.dart';
import '../providers/finance_provider.dart';
import '../widgets/paid_event_section.dart';

/// Tek etkinliğin satış, tahsilat ve kâr özeti (yalnızca admin).
class EventFinancePage extends ConsumerStatefulWidget {
  final String eventId;

  const EventFinancePage({super.key, required this.eventId});

  @override
  ConsumerState<EventFinancePage> createState() => _EventFinancePageState();
}

class _EventFinancePageState extends ConsumerState<EventFinancePage> {
  bool _exporting = false;
  final Map<String, _SaleFlags> _saleOverrides = {};

  void _refresh() => invalidateEventFinanceCaches(ref, widget.eventId);

  Future<void> _toggleSale(
    EventSaleRow sale, {
    bool? paid,
    bool? attended,
  }) async {
    if (_saleOverrides.containsKey(sale.id)) return;
    setState(() => _saleOverrides[sale.id] = (paid: paid, attended: attended));
    try {
      final ds = ref.read(financeDataSourceProvider);
      if (attended != null) {
        await ds.setEventSaleAttendance(sale.id, attended);
      }
      if (paid != null) {
        await ds.updateEventSale(sale.id, {
          'paid_amount': paid ? sale.totalPrice : 0,
          'payment_method':
              paid ? (sale.paymentMethod ?? PaymentMethod.cash).value : null,
          'payment_date': paid
              ? (sale.paymentDate ?? DateTime.now())
                  .toIso8601String()
                  .split('T')
                  .first
              : null,
        });
      }
      _refresh();
      try {
        await ref.read(eventFinanceDetailProvider(widget.eventId).future);
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Güncellenemedi: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
    if (mounted) setState(() => _saleOverrides.remove(sale.id));
  }

  Rect _shareOriginFor(BuildContext originContext) {
    final box = originContext.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final rect = Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      );
      if (rect.width > 0 && rect.height > 0) return rect;
    }
    final size = MediaQuery.of(originContext).size;
    return Rect.fromLTWH(size.width / 2 - 1, size.height / 2 - 1, 2, 2);
  }

  Future<void> _exportExcel(
    BuildContext buttonContext,
    EventFinanceDetail? detail,
  ) async {
    if (detail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rapor henüz yüklenmedi')),
      );
      return;
    }

    final shareOrigin = _shareOriginFor(buttonContext);
    setState(() => _exporting = true);
    try {
      final bytes = buildEventFinanceXlsx(detail);
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '')
          .substring(0, 15);
      final file = File('${dir.path}/etkinlik_finans_$stamp.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        sharePositionOrigin: shareOrigin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel oluşturulamadı: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _addSale(EventFinanceDetail detail) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddSaleSheet(
        eventId: widget.eventId,
        ticketPrice: detail.ticketPrice,
        menuOptions: detail.menuOptions,
      ),
    );
    if (saved == true) _refresh();
  }

  Future<void> _editSale(EventSaleRow sale, EventFinanceDetail detail) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditSaleSheet(
        sale: sale,
        ticketPrice: detail.ticketPrice,
        menuOptions: detail.menuOptions,
      ),
    );
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Satış ve Tahsilat')),
        body: const Center(child: Text('Bu sayfaya erişim yetkiniz yok')),
      );
    }

    final detailAsync = ref.watch(eventFinanceDetailProvider(widget.eventId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Satış ve Tahsilat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: 'Katılımcı ekle',
            onPressed: detailAsync.hasValue
                ? () => _addSale(detailAsync.requireValue)
                : null,
          ),
          Builder(
            builder: (buttonContext) => IconButton(
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              tooltip: 'Excel olarak paylaş',
              onPressed: _exporting
                  ? null
                  : () => _exportExcel(buttonContext, detailAsync.valueOrNull),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Rapor alınamadı: $e', textAlign: TextAlign.center),
          ),
        ),
        data: (detail) => RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _EventHeader(detail: detail),
              const SizedBox(height: 16),
              _EventOverview(detail: detail),
              if (detail.costs.isNotEmpty) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 4),
                  child: Text(
                    'Gider kalemleri',
                    style: AppTypography.titleSmall
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                _CostBreakdown(
                  costs: detail.costs,
                  ticketPrice: detail.ticketPrice ?? 0,
                  summary: detail.summary,
                ),
              ],
              const SizedBox(height: 20),
              _EventSalesList(
                sales: detail.sales,
                overrides: _saleOverrides,
                onTogglePaid: (sale, value) => _toggleSale(sale, paid: value),
                onToggleAttended: (sale, value) =>
                    _toggleSale(sale, attended: value),
                onOpen: (sale) => _editSale(sale, detail),
                onAdd: () => _addSale(detail),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventHeader extends StatelessWidget {
  final EventFinanceDetail detail;

  const _EventHeader({required this.detail});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = [
      formatReportDate(detail.startTime),
      if (detail.locationName != null) detail.locationName!,
      if (detail.ticketPrice != null)
        'Ücret ${formatMoneyCompact(detail.ticketPrice)}',
    ].join(' · ');

    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.event_outlined),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.title,
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                subtitle,
                style:
                    AppTypography.bodySmall.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EventOverview extends StatelessWidget {
  final EventFinanceDetail detail;

  const _EventOverview({required this.detail});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final summary = detail.summary;
    final profit = summary.netProfit;
    final profitColor = profit >= 0 ? AppColors.success : AppColors.error;

    final active = detail.sales.where((s) => !s.isCancelled).toList();
    final payable = active.where((s) => s.saleType != SaleType.gift).toList();
    final paidCount = payable.where((s) => s.outstanding <= 0.009).length;
    final openCount = payable.length - paidCount;

    final mix = [
      if (summary.regularCount > 0) '${summary.regularCount} normal',
      if (summary.discountedCount > 0) '${summary.discountedCount} indirimli',
      if (summary.giftCount > 0) '${summary.giftCount} hediye',
      for (final menu in detail.menuOptions)
        '$menu ${active.where((s) => s.menuChoice == menu).fold<int>(0, (sum, s) => sum + s.quantity)}',
    ].join(' · ');

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kulüp kârı',
            style: AppTypography.labelMedium.copyWith(color: muted),
          ),
          const SizedBox(height: 2),
          Text(
            _signedMoney(profit),
            style: AppTypography.headlineSmall.copyWith(
              fontWeight: FontWeight.w800,
              color: profitColor,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Tahsil edilene göre ${_signedMoney(summary.totalPaid - summary.totalPartnerShare)}',
            style: AppTypography.bodySmall.copyWith(color: muted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _CountPill(label: 'Katılımcı', value: '${summary.participantCount}'),
              const SizedBox(width: 8),
              _CountPill(
                label: 'Katıldı',
                value: '${active.where((s) => s.checkedIn).length}',
              ),
              const SizedBox(width: 8),
              _CountPill(label: 'Ödedi', value: '$paidCount'),
              const SizedBox(width: 8),
              _CountPill(label: 'Ödemedi', value: '$openCount'),
            ],
          ),
          if (payable.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (paidCount / payable.length).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest,
                color: cs.primary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          _line(context, 'Brüt ciro', formatMoneyCompact(summary.totalSales)),
          _line(context, 'Toplam gider',
              formatMoneyCompact(summary.totalPartnerShare)),
          if (summary.eventFixedCost > 0) ...[
            _line(context, 'Kişi başı giderler',
                formatMoneyCompact(summary.perPersonCost)),
            _line(context, 'Etkinlik gideri',
                formatMoneyCompact(summary.eventFixedCost)),
          ],
          _line(context, 'Tahsil edilen', formatMoneyCompact(summary.totalPaid)),
          _line(
            context,
            'Kalan alacak',
            formatMoneyCompact(summary.outstanding),
            valueColor: summary.outstanding > 0.5 ? AppColors.warning : null,
          ),
          if (mix.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(mix, style: AppTypography.labelSmall.copyWith(color: muted)),
          ],
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final String label;
  final String value;

  const _CountPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style:
                  AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

String _signedMoney(double value) {
  final text = formatMoneyCompact(value.abs());
  if (value < -0.5) return '-$text';
  if (value > 0.5) return '+$text';
  return text;
}

class _CostBreakdown extends StatelessWidget {
  final List<EventFinanceCost> costs;
  final double ticketPrice;
  final EventFinanceSummary summary;

  const _CostBreakdown({
    required this.costs,
    required this.ticketPrice,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < costs.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${costs[i].name} · ${costs[i].scope.label}',
                      style: AppTypography.bodySmall.copyWith(color: muted),
                    ),
                  ),
                  Text(
                    costs[i].scope == EventCostScope.event
                        ? formatMoney(costs[i].shareValue)
                        : costs[i].shareType == PartnerShareType.percent
                            ? '%${moneyInputText(costs[i].shareValue)}  (${formatMoney(costs[i].amountFor(ticketPrice))}/kişi)'
                            : '${formatMoney(costs[i].shareValue)} / kişi',
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          if (summary.eventFixedCost > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Etkinlik gideri ${formatMoney(summary.eventFixedCost)} kârdan düşüldü.',
              style: AppTypography.labelSmall.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

typedef _SaleFlags = ({bool? paid, bool? attended});

bool _isSalePaid(EventSaleRow sale, _SaleFlags? override) {
  if (sale.saleType == SaleType.gift) return true;
  return override?.paid ?? sale.outstanding <= 0.009;
}

bool _isSaleAttended(EventSaleRow sale, _SaleFlags? override) {
  return override?.attended ?? sale.checkedIn;
}

class _EventSalesList extends StatefulWidget {
  final List<EventSaleRow> sales;
  final Map<String, _SaleFlags> overrides;
  final void Function(EventSaleRow sale, bool paid) onTogglePaid;
  final void Function(EventSaleRow sale, bool attended) onToggleAttended;
  final ValueChanged<EventSaleRow> onOpen;
  final VoidCallback onAdd;

  const _EventSalesList({
    required this.sales,
    required this.overrides,
    required this.onTogglePaid,
    required this.onToggleAttended,
    required this.onOpen,
    required this.onAdd,
  });

  @override
  State<_EventSalesList> createState() => _EventSalesListState();
}

class _EventSalesListState extends State<_EventSalesList> {
  bool _onlyOpen = false;

  bool _needsAction(EventSaleRow sale) {
    if (sale.isCancelled) return false;
    final override = widget.overrides[sale.id];
    return !_isSaleAttended(sale, override) || !_isSalePaid(sale, override);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final ordered = List<EventSaleRow>.from(widget.sales)
      ..sort(compareEventSales);
    final openCount = ordered.where(_needsAction).length;
    final visible = _onlyOpen ? ordered.where(_needsAction).toList() : ordered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Satış geçmişi',
                style: AppTypography.titleSmall
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            _OpenFilter(
              onlyOpen: _onlyOpen,
              openCount: openCount,
              onChanged: (value) => setState(() => _onlyOpen = value),
            ),
            IconButton(
              onPressed: widget.onAdd,
              icon: const Icon(Icons.add, size: 20),
              visualDensity: VisualDensity.compact,
              tooltip: 'Katılımcı ekle',
            ),
          ],
        ),
        Text(
          'Katılım ve tahsilatı buradan işaretle.',
          style: AppTypography.labelSmall.copyWith(color: muted),
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                widget.sales.isEmpty
                    ? 'Henüz satış kaydı yok'
                    : 'Gösterilecek satış yok',
              ),
            ),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _EventSaleTile(
                    sale: visible[i],
                    paid: _isSalePaid(visible[i], widget.overrides[visible[i].id]),
                    attended: _isSaleAttended(
                        visible[i], widget.overrides[visible[i].id]),
                    onTogglePaid: widget.onTogglePaid,
                    onToggleAttended: widget.onToggleAttended,
                    onOpen: widget.onOpen,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _OpenFilter extends StatelessWidget {
  final bool onlyOpen;
  final int openCount;
  final ValueChanged<bool> onChanged;

  const _OpenFilter({
    required this.onlyOpen,
    required this.openCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip(context, 'Tümü', !onlyOpen, () => onChanged(false)),
          _chip(
            context,
            openCount > 0 ? 'Eksik $openCount' : 'Eksik',
            onlyOpen,
            () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: selected ? cs.onPrimary : cs.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _EventSaleTile extends StatelessWidget {
  final EventSaleRow sale;
  final bool paid;
  final bool attended;
  final void Function(EventSaleRow sale, bool paid) onTogglePaid;
  final void Function(EventSaleRow sale, bool attended) onToggleAttended;
  final ValueChanged<EventSaleRow> onOpen;

  const _EventSaleTile({
    required this.sale,
    required this.paid,
    required this.attended,
    required this.onTogglePaid,
    required this.onToggleAttended,
    required this.onOpen,
  });

  Color _accent() {
    if (sale.isCancelled) return const Color(0xFFB0B8C1);
    if (!attended && !paid) return AppColors.error;
    if (!paid) return AppColors.warning;
    if (!attended) return AppColors.info;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cancelled = sale.isCancelled;
    final accent = _accent();
    final details = [
      if (sale.menuChoice != null) sale.menuChoice!,
      '${sale.quantity} adet',
      sale.saleType.label,
      formatMoneyCompact(sale.totalPrice),
      if (cancelled) sale.status.label,
    ].join(' · ');

    return InkWell(
      onTap: () => onOpen(sale),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.buyerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      decoration:
                          cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall
                        .copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            _FlagBox(
              label: 'Katıldı',
              value: attended,
              enabled: !cancelled,
              onChanged: (value) => onToggleAttended(sale, value),
            ),
            if (sale.saleType == SaleType.gift)
              SizedBox(
                width: 52,
                child: Text(
                  'Hediye',
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.success),
                ),
              )
            else
              _FlagBox(
                label: 'Tahsil',
                value: paid,
                enabled: !cancelled,
                onChanged: (value) => onTogglePaid(sale, value),
              ),
            IconButton(
              onPressed: () => onOpen(sale),
              icon: const Icon(Icons.more_horiz, size: 20),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Düzenle veya sil',
            ),
          ],
        ),
      ),
    );
  }
}

class _FlagBox extends StatelessWidget {
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _FlagBox({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              value: value,
              onChanged: enabled ? (next) => onChanged(next ?? false) : null,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              fontSize: 10,
              color: enabled ? cs.onSurfaceVariant : cs.outline,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddSaleSheet extends ConsumerStatefulWidget {
  final String eventId;
  final double? ticketPrice;
  final List<String> menuOptions;

  const _AddSaleSheet({
    required this.eventId,
    this.ticketPrice,
    this.menuOptions = const [],
  });

  @override
  ConsumerState<_AddSaleSheet> createState() => _AddSaleSheetState();
}

class _AddSaleSheetState extends ConsumerState<_AddSaleSheet> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _notesController = TextEditingController();
  bool _useMember = true;
  UserEntity? _selectedUser;
  SaleType _saleType = SaleType.regular;
  int _quantity = 1;
  bool _markPaid = false;
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  bool _saving = false;
  String? _menuChoice;

  bool get _requiresMenu => widget.menuOptions.length >= 2;

  @override
  void initState() {
    super.initState();
    _priceController.text = moneyInputText(widget.ticketPrice);
    if (_requiresMenu) _menuChoice = widget.menuOptions.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickUser(List<UserEntity> users) async {
    final selected = await showModalBottomSheet<UserEntity>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _UserPickerSheet(users: users),
    );
    if (selected != null) {
      setState(() => _selectedUser = selected);
    }
  }

  Future<void> _save() async {
    if (_useMember && _selectedUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bir üye seçin')),
      );
      return;
    }
    if (!_useMember && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad-soyad girin')),
      );
      return;
    }
    if (_requiresMenu &&
        (_menuChoice == null || !widget.menuOptions.contains(_menuChoice))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bir menü seçin')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final ds = ref.read(financeDataSourceProvider);
      await ds.addEventSale(
        eventId: widget.eventId,
        userId: _useMember ? _selectedUser?.id : null,
        buyerName: _useMember ? _selectedUser?.fullName : _nameController.text,
        quantity: _quantity,
        saleType: _saleType,
        unitPrice: _saleType == SaleType.gift
            ? 0
            : parseMoneyInput(_priceController.text),
        notes: _notesController.text,
        menuChoice: _requiresMenu ? _menuChoice : null,
      );

      if (_markPaid && _saleType != SaleType.gift) {
        final detail = await ds.getEventFinanceDetail(widget.eventId);
        EventSaleRow? created;
        if (_useMember && _selectedUser != null) {
          created = detail.sales
              .where((s) => s.userId == _selectedUser!.id && !s.isCancelled)
              .firstOrNull;
        } else {
          final name = _nameController.text.trim();
          created = detail.sales
              .where((s) =>
                  s.isManual &&
                  s.buyerName.toLowerCase() == name.toLowerCase() &&
                  !s.isCancelled)
              .firstOrNull;
        }
        if (created != null) {
          await ds.updateEventSale(created.id, {
            'paid_amount': created.totalPrice,
            'payment_method': _paymentMethod.value,
            'payment_date': DateTime.now().toIso8601String().split('T').first,
            'status': 'confirmed',
          });
        }
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(activeUsersProvider);

    return _DismissibleSheet(
      children: [
              Text('Katılımcı ekle', style: AppTypography.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Üye')),
                  ButtonSegment(value: false, label: Text('Ad-soyad')),
                ],
                selected: {_useMember},
                onSelectionChanged: (s) => setState(() => _useMember = s.first),
              ),
              const SizedBox(height: 12),
              if (_useMember)
                usersAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Üyeler alınamadı: $e'),
                  data: (users) => InkWell(
                    onTap: () => _pickUser(users),
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Üye'),
                      child: Text(_selectedUser?.fullName ?? 'Üye seçin'),
                    ),
                  ),
                )
              else
                AppTextField(
                  controller: _nameController,
                  label: 'Ad soyad',
                  textCapitalization: TextCapitalization.words,
                ),
              if (_requiresMenu) ...[
                const SizedBox(height: 12),
                Text('Menü', style: AppTypography.labelLarge),
                const SizedBox(height: 4),
                ...widget.menuOptions.map(
                  (menu) => RadioListTile<String>(
                    value: menu,
                    groupValue: _menuChoice,
                    contentPadding: EdgeInsets.zero,
                    title: Text(menu),
                    onChanged: (value) => setState(() => _menuChoice = value),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SegmentedButton<SaleType>(
                segments: SaleType.values
                    .map((t) => ButtonSegment(value: t, label: Text(t.label)))
                    .toList(),
                selected: {_saleType},
                onSelectionChanged: (s) => setState(() {
                  _saleType = s.first;
                  if (_saleType == SaleType.gift) {
                    _priceController.text = '0';
                    _markPaid = false;
                  } else if (parseMoneyInput(_priceController.text) == 0) {
                    _priceController.text = moneyInputText(widget.ticketPrice);
                  }
                }),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _priceController,
                label: 'Birim fiyat',
                suffixText: '₺',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                enabled: _saleType != SaleType.gift,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Adet'),
                  const Spacer(),
                  IconButton(
                    onPressed: _quantity > 1
                        ? () => setState(() => _quantity--)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$_quantity', style: AppTypography.titleMedium),
                  IconButton(
                    onPressed: () => setState(() => _quantity++),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (_saleType != SaleType.gift) ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ödendi olarak işaretle'),
                  value: _markPaid,
                  onChanged: (v) => setState(() => _markPaid = v),
                ),
                if (_markPaid)
                  DropdownButtonFormField<PaymentMethod>(
                    initialValue: _paymentMethod,
                    decoration: const InputDecoration(labelText: 'Ödeme şekli'),
                    items: PaymentMethod.values
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m.label),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _paymentMethod = v);
                    },
                  ),
              ],
              const SizedBox(height: 12),
              AppTextField(
                controller: _notesController,
                label: 'Not (opsiyonel)',
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ),
      ],
    );
  }
}

class _EditSaleSheet extends ConsumerStatefulWidget {
  final EventSaleRow sale;
  final double? ticketPrice;
  final List<String> menuOptions;

  const _EditSaleSheet({
    required this.sale,
    this.ticketPrice,
    this.menuOptions = const [],
  });

  @override
  ConsumerState<_EditSaleSheet> createState() => _EditSaleSheetState();
}

class _EditSaleSheetState extends ConsumerState<_EditSaleSheet> {
  late final TextEditingController _priceController;
  late final TextEditingController _paidController;
  late final TextEditingController _notesController;
  late SaleType _saleType;
  late EventSaleStatus _status;
  late int _quantity;
  PaymentMethod? _paymentMethod;
  DateTime? _paymentDate;
  bool _saving = false;
  String? _menuChoice;

  EventSaleRow get sale => widget.sale;
  bool get _requiresMenu => widget.menuOptions.length >= 2;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(text: moneyInputText(sale.unitPrice));
    _paidController = TextEditingController(text: moneyInputText(sale.paidAmount));
    _notesController = TextEditingController(text: sale.notes ?? '');
    _saleType = sale.saleType;
    _status = sale.status;
    _quantity = sale.quantity;
    _paymentMethod = sale.paymentMethod;
    _paymentDate = sale.paymentDate;
    if (_requiresMenu) {
      _menuChoice = widget.menuOptions.contains(sale.menuChoice)
          ? sale.menuChoice
          : widget.menuOptions.first;
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    _paidController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _unitPrice => parseMoneyInput(_priceController.text) ?? 0;
  double get _total => _unitPrice * _quantity;

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('tr', 'TR'),
    );
    if (picked != null) setState(() => _paymentDate = picked);
  }

  void _markPaid() {
    setState(() {
      _paidController.text = moneyInputText(_total);
      _paymentDate ??= DateTime.now();
      _paymentMethod ??= PaymentMethod.cash;
      if (_status == EventSaleStatus.cancelled) {
        _status = EventSaleStatus.confirmed;
      }
    });
  }

  Future<void> _save() async {
    if (_requiresMenu &&
        (_menuChoice == null || !widget.menuOptions.contains(_menuChoice))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bir menü seçin')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(financeDataSourceProvider).updateEventSale(sale.id, {
        'quantity': _quantity,
        'sale_type': _saleType.value,
        'unit_price': _saleType == SaleType.gift ? 0 : _unitPrice,
        'paid_amount': parseMoneyInput(_paidController.text) ?? 0,
        'payment_method': _paymentMethod?.value,
        'payment_date': _paymentDate?.toIso8601String().split('T').first,
        'status': _status.value,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        if (_requiresMenu) 'menu_choice': _menuChoice,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kaydı sil'),
        content: Text('${sale.buyerName} kaydı silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(financeDataSourceProvider).deleteEventSale(sale.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DismissibleSheet(
      children: [
              Text(sale.buyerName, style: AppTypography.titleMedium),
              Text(
                sale.isManual ? 'Manuel kayıt' : 'RSVP kaydı',
                style: AppTypography.bodySmall,
              ),
              if (_requiresMenu) ...[
                const SizedBox(height: 12),
                Text('Menü', style: AppTypography.labelLarge),
                ...widget.menuOptions.map(
                  (menu) => RadioListTile<String>(
                    value: menu,
                    groupValue: _menuChoice,
                    contentPadding: EdgeInsets.zero,
                    title: Text(menu),
                    onChanged: (value) => setState(() => _menuChoice = value),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SegmentedButton<SaleType>(
                segments: SaleType.values
                    .map((t) => ButtonSegment(value: t, label: Text(t.label)))
                    .toList(),
                selected: {_saleType},
                onSelectionChanged: (s) => setState(() {
                  _saleType = s.first;
                  if (_saleType == SaleType.gift) {
                    _priceController.text = '0';
                    _paidController.text = '0';
                  }
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<EventSaleStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Durum'),
                items: EventSaleStatus.values
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _status = v);
                },
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _priceController,
                label: 'Birim fiyat',
                suffixText: '₺',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                enabled: _saleType != SaleType.gift,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Adet'),
                  const Spacer(),
                  IconButton(
                    onPressed: _quantity > 1
                        ? () => setState(() => _quantity--)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$_quantity', style: AppTypography.titleMedium),
                  IconButton(
                    onPressed: () => setState(() => _quantity++),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              Text(
                'Toplam: ${formatMoney(_total)}',
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _paidController,
                label: 'Tahsil edilen',
                suffixText: '₺',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _markPaid,
                  child: const Text('Tamamını ödendi işaretle'),
                ),
              ),
              DropdownButtonFormField<PaymentMethod?>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Ödeme şekli'),
                items: [
                  const DropdownMenuItem<PaymentMethod?>(
                    value: null,
                    child: Text('Seçilmedi'),
                  ),
                  ...PaymentMethod.values.map(
                    (m) => DropdownMenuItem(value: m, child: Text(m.label)),
                  ),
                ],
                onChanged: (v) => setState(() => _paymentMethod = v),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ödeme tarihi'),
                subtitle: Text(
                  _paymentDate == null
                      ? 'Seçilmedi'
                      : formatReportDate(_paymentDate),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_paymentDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _paymentDate = null),
                      ),
                    const Icon(Icons.calendar_today_outlined),
                  ],
                ),
                onTap: _pickPaymentDate,
              ),
              AppTextField(
                controller: _notesController,
                label: 'Not',
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ),
              TextButton(
                onPressed: _saving ? null : _delete,
                child: Text(
                  'Kaydı sil',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
      ],
    );
  }
}

/// Kasa formunu aşağı çekince kaydetmeden kapatır.
class _DismissibleSheet extends StatefulWidget {
  final List<Widget> children;

  const _DismissibleSheet({required this.children});

  @override
  State<_DismissibleSheet> createState() => _DismissibleSheetState();
}

class _DismissibleSheetState extends State<_DismissibleSheet> {
  bool _closing = false;
  double _handlePull = 0;
  double _overscroll = 0;

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final topGap = MediaQuery.paddingOf(context).top + 8;

    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: Material(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                _handlePull += details.primaryDelta ?? 0;
                if (_handlePull > 28) _close();
              },
              onVerticalDragEnd: (_) => _handlePull = 0,
              onVerticalDragCancel: () => _handlePull = 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is OverscrollNotification &&
                      notification.metrics.pixels <= 0 &&
                      notification.overscroll < 0) {
                    _overscroll += notification.overscroll;
                    if (_overscroll < -36) _close();
                  } else if (notification is ScrollEndNotification) {
                    _overscroll = 0;
                  }
                  return false;
                },
                child: ListView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottom),
                  children: widget.children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserPickerSheet extends StatefulWidget {
  final List<UserEntity> users;

  const _UserPickerSheet({required this.users});

  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.trim().isEmpty
        ? widget.users
        : widget.users
            .where((u) =>
                u.fullName.toLowerCase().contains(_query.trim().toLowerCase()))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Üye ara',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final user = filtered[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: user.avatarUrl != null
                          ? NetworkImage(user.avatarUrl!)
                          : null,
                      child: user.avatarUrl == null
                          ? Text(user.fullName.isNotEmpty
                              ? user.fullName[0].toUpperCase()
                              : '?')
                          : null,
                    ),
                    title: Text(user.fullName),
                    onTap: () => Navigator.of(context).pop(user),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
