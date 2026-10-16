import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/theme_brightness_holder.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../marketplace/utils/market_report_utils.dart';
import '../../data/datasources/finance_remote_datasource.dart';
import '../../data/models/event_finance_model.dart';

double? parseMoneyInput(String text) {
  final normalized = text.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

String moneyInputText(double? value) {
  if (value == null) return '';
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

class _CostLine {
  final nameController = TextEditingController();
  final valueController = TextEditingController();
  EventCostScope scope = EventCostScope.perPerson;
  PartnerShareType shareType = PartnerShareType.fixed;

  EventFinanceCost toCost() {
    return EventFinanceCost(
      name: nameController.text.trim().isEmpty
          ? 'Gider'
          : nameController.text.trim(),
      scope: scope,
      shareType:
          scope == EventCostScope.event ? PartnerShareType.fixed : shareType,
      shareValue: parseMoneyInput(valueController.text) ?? 0,
    );
  }

  void dispose() {
    nameController.dispose();
    valueController.dispose();
  }
}

/// Etkinlik formundaki "Ücretli etkinlik" bölümünün durumu.
class PaidEventFormController {
  bool isPaid = false;
  final priceController = TextEditingController();
  final List<_CostLine> _costLines = [];

  EventFinanceSettings? _initial;
  double? _initialPrice;
  List<EventFinanceCost> _initialCosts = const [];

  void load(EventFinanceSettings? settings, double? ticketPrice) {
    _initial = settings;
    _initialPrice = ticketPrice;
    isPaid = settings?.isPaid ?? false;
    priceController.text = moneyInputText(ticketPrice);
    _replaceCostLines(settings?.costs ?? const []);
    _initialCosts = _costLines.map((l) => l.toCost()).toList();
    if (isPaid && _costLines.isEmpty) {
      addCostLine(name: 'Mekan');
    }
  }

  double? get ticketPrice => parseMoneyInput(priceController.text);

  List<EventFinanceCost> get costs =>
      _costLines.map((l) => l.toCost()).toList();

  EventFinanceSettings get _previewSettings => EventFinanceSettings(
        eventId: '',
        isPaid: true,
        costs: costs,
      );

  /// Daha önce ayar yoksa ve ücretli açılmadıysa kaydetmeye gerek yok.
  bool get shouldSave => isPaid || _initial != null;

  bool get _pricingChanged {
    if (_initial == null) return false;
    if (ticketPrice != _initialPrice) return true;
    final current = costs;
    if (current.length != _initialCosts.length) return true;
    for (var i = 0; i < current.length; i++) {
      final a = current[i];
      final b = _initialCosts[i];
      if (a.name != b.name ||
          a.scope != b.scope ||
          a.shareType != b.shareType ||
          a.shareValue != b.shareValue) {
        return true;
      }
    }
    return false;
  }

  void addCostLine({String name = '', EventCostScope? scope}) {
    final line = _CostLine();
    line.nameController.text = name;
    if (scope != null) line.scope = scope;
    _costLines.add(line);
  }

  void removeCostLine(int index) {
    if (index < 0 || index >= _costLines.length) return;
    _costLines.removeAt(index).dispose();
  }

  void _replaceCostLines(List<EventFinanceCost> items) {
    for (final line in _costLines) {
      line.dispose();
    }
    _costLines.clear();
    for (final item in items) {
      final line = _CostLine()
        ..scope = item.scope
        ..shareType = item.shareType;
      line.nameController.text = item.name;
      line.valueController.text = moneyInputText(item.shareValue);
      _costLines.add(line);
    }
  }

  String? validate() {
    if (!isPaid) return null;
    final price = ticketPrice;
    if (price == null || price < 0) {
      return 'Ücretli etkinlik için geçerli bir katılım ücreti girin';
    }
    var perPerson = 0.0;
    for (final line in _costLines) {
      final value = parseMoneyInput(line.valueController.text);
      if (line.valueController.text.trim().isNotEmpty &&
          (value == null || value < 0)) {
        return '${line.nameController.text.trim().isEmpty ? 'Gider' : line.nameController.text} tutarı geçersiz';
      }
      if (line.scope == EventCostScope.perPerson &&
          line.shareType == PartnerShareType.percent &&
          (value ?? 0) > 100) {
        return 'Yüzde 100\'ü geçemez';
      }
      if (line.scope == EventCostScope.perPerson) {
        perPerson += line.toCost().amountFor(price);
      }
    }
    if (perPerson > price) {
      return 'Kişi başı giderler katılım ücretinden büyük olamaz';
    }
    return null;
  }

  Future<void> save(FinanceRemoteDataSource dataSource, String eventId) {
    final items = isPaid ? costs : const <EventFinanceCost>[];
    final firstPerPerson = items
        .where((c) => c.scope == EventCostScope.perPerson)
        .firstOrNull;
    return dataSource.setEventFinance(
      eventId: eventId,
      isPaid: isPaid,
      ticketPrice: isPaid ? ticketPrice : null,
      partnerName: firstPerPerson?.name,
      partnerShareType: firstPerPerson?.shareType ?? PartnerShareType.fixed,
      partnerShareValue: firstPerPerson?.shareValue ?? 0,
      applyToUnpaid: _pricingChanged,
      costs: items,
    );
  }

  void dispose() {
    priceController.dispose();
    for (final line in _costLines) {
      line.dispose();
    }
  }
}

/// Etkinlik formunda yalnızca adminlerin gördüğü ücret bölümü.
class PaidEventSection extends StatefulWidget {
  final PaidEventFormController controller;

  const PaidEventSection({super.key, required this.controller});

  @override
  State<PaidEventSection> createState() => _PaidEventSectionState();
}

class _PaidEventSectionState extends State<PaidEventSection> {
  PaidEventFormController get _c => widget.controller;

  static final _moneyFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final price = _c.ticketPrice ?? 0;
    final preview = _c._previewSettings;
    final perPerson = preview.shareFor(price);
    final eventFixed = preview.eventFixedTotal;
    final netPerPerson = price - perPerson;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ücretli Etkinlik', style: AppTypography.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Katılımcılar otomatik satışa eklenir. '
                'Mekan, DJ ve diğer giderler kârdan düşülür.',
                style: AppTypography.bodySmall.copyWith(
                  color: ThemeBrightnessHolder.onSurfaceVariant,
                ),
              ),
            ),
            Switch.adaptive(
              value: _c.isPaid,
              onChanged: (v) => setState(() {
                _c.isPaid = v;
                if (v && _c._costLines.isEmpty) {
                  _c.addCostLine(name: 'Mekan');
                }
              }),
              activeColor: cs.primary,
            ),
          ],
        ),
        if (_c.isPaid) ...[
          const SizedBox(height: 12),
          AppTextField(
            controller: _c.priceController,
            label: 'Katılım ücreti',
            hint: 'Örn: 500',
            suffixText: '₺',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _moneyFormatters,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text('Gider kalemleri', style: AppTypography.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Kişi başı: her biletten düşülür. Etkinlik: tek seferlik (ör. DJ).',
            style: AppTypography.bodySmall.copyWith(
              color: ThemeBrightnessHolder.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _c._costLines.length; i++)
            _CostLineCard(
              key: ObjectKey(_c._costLines[i]),
              line: _c._costLines[i],
              moneyFormatters: _moneyFormatters,
              onChanged: () => setState(() {}),
              onRemove: () => setState(() => _c.removeCostLine(i)),
            ),
          TextButton.icon(
            onPressed: () => setState(() => _c.addCostLine()),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Kalem ekle'),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              'Kişi başı: ${formatMoney(price)} ücret − '
              '${formatMoney(perPerson)} gider = '
              '${formatMoney(netPerPerson)} kasa.'
              '${eventFixed > 0 ? ' Etkinlik gideri ${formatMoney(eventFixed)} ayrıca kârdan düşülür.' : ''}',
              style: AppTypography.bodySmall.copyWith(
                color: ThemeBrightnessHolder.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CostLineCard extends StatelessWidget {
  final _CostLine line;
  final List<TextInputFormatter> moneyFormatters;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _CostLineCard({
    super.key,
    required this.line,
    required this.moneyFormatters,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEvent = line.scope == EventCostScope.event;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: line.nameController,
                  label: 'Kalem',
                  hint: 'Örn: Mekan, DJ',
                  textCapitalization: TextCapitalization.words,
                ),
              ),
              IconButton(
                tooltip: 'Kalemi sil',
                onPressed: onRemove,
                icon: Icon(Icons.close, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PillToggle<EventCostScope>(
            value: line.scope,
            options: const [
              (EventCostScope.perPerson, 'Kişi başı', Icons.person_outline),
              (EventCostScope.event, 'Etkinlik', Icons.event_outlined),
            ],
            onChanged: (scope) {
              line.scope = scope;
              if (scope == EventCostScope.event) {
                line.shareType = PartnerShareType.fixed;
              }
              onChanged();
            },
          ),
          if (!isEvent) ...[
            const SizedBox(height: 8),
            _PillToggle<PartnerShareType>(
              value: line.shareType,
              options: const [
                (PartnerShareType.fixed, 'Sabit', Icons.payments_outlined),
                (PartnerShareType.percent, 'Yüzde', Icons.percent),
              ],
              onChanged: (type) {
                line.shareType = type;
                onChanged();
              },
            ),
          ],
          const SizedBox(height: 8),
          AppTextField(
            controller: line.valueController,
            label: isEvent
                ? 'Etkinlik tutarı'
                : line.shareType == PartnerShareType.fixed
                    ? 'Kişi başı tutar'
                    : 'Yüzde',
            hint: isEvent
                ? 'Örn: 2000'
                : line.shareType == PartnerShareType.fixed
                    ? 'Örn: 400'
                    : 'Örn: 80',
            suffixText: !isEvent && line.shareType == PartnerShareType.percent
                ? '%'
                : '₺',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: moneyFormatters,
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

class _PillToggle<T> extends StatelessWidget {
  final T value;
  final List<(T, String, IconData)> options;
  final ValueChanged<T> onChanged;

  const _PillToggle({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: _PillOption(
                label: option.$2,
                icon: option.$3,
                selected: option.$1 == value,
                onTap: () {
                  if (option.$1 != value) onChanged(option.$1);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _PillOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PillOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: selected ? cs.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
