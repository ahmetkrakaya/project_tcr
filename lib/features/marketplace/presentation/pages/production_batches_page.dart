import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/enums/gender.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/listing_model.dart';
import '../../data/models/production_batch_model.dart';
import '../../utils/market_report_utils.dart';
import '../providers/marketplace_provider.dart';

/// Ürünün üretim partilerini (adet + birim maliyet) yöneten admin ekranı.
class ProductionBatchesPage extends ConsumerStatefulWidget {
  final String listingId;

  const ProductionBatchesPage({super.key, required this.listingId});

  @override
  ConsumerState<ProductionBatchesPage> createState() =>
      _ProductionBatchesPageState();
}

class _ProductionBatchesPageState extends ConsumerState<ProductionBatchesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      invalidateMarketplaceCachesForWidget(
        ref,
        listingId: widget.listingId,
        refreshListingsGrid: false,
      );
    });
  }

  String get listingId => widget.listingId;

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Üretim ve Maliyet')),
        body: const Center(child: Text('Bu sayfaya erişim yetkiniz yok')),
      );
    }

    final batchesAsync = ref.watch(productionBatchesProvider(listingId));
    final listingAsync = ref.watch(listingByIdProvider(listingId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Üretim ve Maliyet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Parti Ekle',
            onPressed: () => _openBatchEditor(context, ref),
          ),
        ],
        bottom: listingAsync.valueOrNull != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8, right: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      listingAsync.value!.title,
                      style: AppTypography.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: batchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Partiler alınamadı: $e')),
        data: (batches) {
          final totalQty =
              batches.fold<int>(0, (sum, b) => sum + b.totalQuantity);
          final totalCost =
              batches.fold<double>(0, (sum, b) => sum + b.totalCost);
          final avgCost = totalQty > 0 ? totalCost / totalQty : null;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _ListingVariantsCard(listingId: listingId),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  children: [
                    _summaryRow('Toplam üretim adedi', '$totalQty'),
                    const Divider(height: 20),
                    _summaryRow(
                        'Ortalama birim maliyet', formatMoney(avgCost)),
                    const Divider(height: 20),
                    _summaryRow(
                      'Toplam üretim maliyeti',
                      formatMoney(totalCost),
                      emphasize: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (batches.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      const Text('Henüz üretim partisi eklenmemiş'),
                      const SizedBox(height: 4),
                      Text(
                        'Parti ekledikçe stok adetleri otomatik güncellenir.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                )
              else
                ...batches.map(
                  (batch) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _BatchCard(
                      batch: batch,
                      onEdit: () =>
                          _openBatchEditor(context, ref, batch: batch),
                      onDelete: () => _confirmDelete(context, ref, batch),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool emphasize = false}) {
    return Row(
      children: [
        Text(label, style: AppTypography.bodyMedium),
        const Spacer(),
        Text(
          value,
          style: emphasize
              ? AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold)
              : AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Future<void> _openBatchEditor(
    BuildContext context,
    WidgetRef ref, {
    ProductionBatch? batch,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BatchEditorSheet(
        listingId: listingId,
        batch: batch,
      ),
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Üretim partisi kaydedildi'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ProductionBatch batch,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Partiyi sil'),
        content: Text(
          '${batch.totalQuantity} adetlik üretim partisi silinecek ve stoktan düşülecek. Emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref
        .read(manualSaleProvider.notifier)
        .deleteProductionBatch(batch.id, listingId);
  }
}

/// Ürünün beden listesi ve unisex/gendered stok tipini yönetir.
class _ListingVariantsCard extends ConsumerStatefulWidget {
  final String listingId;

  const _ListingVariantsCard({required this.listingId});

  @override
  ConsumerState<_ListingVariantsCard> createState() =>
      _ListingVariantsCardState();
}

class _ListingVariantsCardState extends ConsumerState<_ListingVariantsCard> {
  final _newSizeController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _newSizeController.dispose();
    super.dispose();
  }

  Future<void> _persist({
    required ListingModel listing,
    required List<String> sizes,
    required ListingGenderMode mode,
  }) async {
    setState(() => _saving = true);
    final sizeText = sizes.isEmpty ? null : sizes.join(', ');
    final ok = await ref
        .read(manualSaleProvider.notifier)
        .updateListingSizesAndGenderMode(
          listingId: widget.listingId,
          size: sizeText,
          stockGenderMode: mode,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      final error = ref.read(manualSaleProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Güncellenemedi: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final listingAsync = ref.watch(listingByIdProvider(widget.listingId));
    final listing = listingAsync.valueOrNull;
    if (listing == null) {
      return const SizedBox.shrink();
    }

    final sizes = listingSizeOptions(listing).toList();
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Beden ve cinsiyet',
            style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Stok adetleri üretim partilerinden güncellenir.',
            style: AppTypography.bodySmall.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ModeChip(
                  label: 'Unisex',
                  selected: listing.stockGenderMode == ListingGenderMode.unisex,
                  onTap: _saving
                      ? null
                      : () => _persist(
                            listing: listing,
                            sizes: sizes,
                            mode: ListingGenderMode.unisex,
                          ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeChip(
                  label: 'Erkek / Kadın',
                  selected:
                      listing.stockGenderMode == ListingGenderMode.gendered,
                  onTap: _saving
                      ? null
                      : () => _persist(
                            listing: listing,
                            sizes: sizes,
                            mode: ListingGenderMode.gendered,
                          ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (sizes.isEmpty)
            Text(
              'Henüz beden yok. Aşağıdan ekleyin.',
              style: AppTypography.bodySmall,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sizes
                  .map(
                    (size) => InputChip(
                      label: Text(size),
                      onDeleted: _saving
                          ? null
                          : () {
                              final next = [...sizes]..remove(size);
                              _persist(
                                listing: listing,
                                sizes: next,
                                mode: listing.stockGenderMode,
                              );
                            },
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newSizeController,
                  decoration: const InputDecoration(
                    hintText: 'Yeni beden (ör. XL)',
                    isDense: true,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _addSize(listing, sizes),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : () => _addSize(listing, sizes),
                child: const Text('Ekle'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addSize(ListingModel listing, List<String> sizes) {
    final value = _newSizeController.text.trim();
    if (value.isEmpty) return;
    if (sizes.any((s) => s.toLowerCase() == value.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu beden zaten var')),
      );
      return;
    }
    _newSizeController.clear();
    _persist(
      listing: listing,
      sizes: [...sizes, value],
      mode: listing.stockGenderMode,
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: selected ? cs.onPrimary : cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchCard extends StatelessWidget {
  final ProductionBatch batch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BatchCard({
    required this.batch,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatReportDate(batch.producedAt),
                  style: AppTypography.titleSmall
                      .copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: onEdit,
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 20, color: AppColors.error),
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: batch.items
                .map(
                  (item) => Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${sizeWithGenderLabel(item.size, item.gender)}: ${item.quantity}',
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('Adet', '${batch.totalQuantity}'),
              const SizedBox(width: 20),
              _stat('Birim', formatMoney(batch.unitCost)),
              const SizedBox(width: 20),
              _stat('Toplam', formatMoney(batch.totalCost)),
            ],
          ),
          if (batch.note != null && batch.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              batch.note!,
              style: AppTypography.bodySmall
                  .copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelSmall),
        Text(value,
            style:
                AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Parti ekleme/düzenleme formu.
class _BatchEditorSheet extends ConsumerStatefulWidget {
  final String listingId;
  final ProductionBatch? batch;

  const _BatchEditorSheet({
    required this.listingId,
    this.batch,
  });

  @override
  ConsumerState<_BatchEditorSheet> createState() => _BatchEditorSheetState();
}

class _BatchEditorSheetState extends ConsumerState<_BatchEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _unitCostController = TextEditingController();
  final _noteController = TextEditingController();
  final Map<String, TextEditingController> _quantityControllers = {};

  late DateTime _producedAt;
  ListingModel? _listing;
  List<_SizeSlot> _slots = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final batch = widget.batch;
    _producedAt = batch?.producedAt ?? DateTime.now();
    _unitCostController.text = batch != null
        ? batch.unitCost.toStringAsFixed(batch.unitCost % 1 == 0 ? 0 : 2)
        : '';
    _noteController.text = batch?.note ?? '';
    _listing = ref.read(listingByIdProvider(widget.listingId)).valueOrNull;
    _syncSlots();
  }

  /// Ürünün beden/cinsiyet kombinasyonlarını çıkarır.
  /// Ürünün tanımlı bedeni yoksa tek "Standart" satırı gösterilir.
  List<_SizeSlot> _buildSlots() {
    final listing = _listing;
    final genders = listing?.stockGenderMode == ListingGenderMode.gendered
        ? const [ListingGender.male, ListingGender.female]
        : const [ListingGender.unisex];

    final sizes = listingSizeOptions(listing).toList();

    // Mevcut partide olup üründe tanımsız kalan bedenleri de göster
    for (final item in widget.batch?.items ?? const <ProductionBatchItem>[]) {
      if (!sizes.contains(item.size)) sizes.add(item.size);
    }

    if (sizes.isEmpty) sizes.add('Standart');

    return [
      for (final size in sizes)
        for (final gender in genders) _SizeSlot(size: size, gender: gender),
    ];
  }

  /// Slot listesini ürüne göre kurar. Ürün sheet açıldıktan sonra yüklenirse
  /// tekrar çağrılır; girilmiş adetler korunur.
  void _syncSlots() {
    _slots = _buildSlots();
    final validKeys = _slots.map((slot) => slot.key).toSet();

    for (final key in _quantityControllers.keys.toList()) {
      if (!validKeys.contains(key)) {
        _quantityControllers.remove(key)!.dispose();
      }
    }

    for (final slot in _slots) {
      if (_quantityControllers.containsKey(slot.key)) continue;
      final existing = widget.batch?.items
          .where((i) => i.size == slot.size && i.gender == slot.gender)
          .firstOrNull;
      _quantityControllers[slot.key] = TextEditingController(
        text: existing != null ? '${existing.quantity}' : '',
      );
    }
  }

  @override
  void dispose() {
    _unitCostController.dispose();
    _noteController.dispose();
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int get _totalQuantity {
    return _quantityControllers.values.fold<int>(
      0,
      (sum, controller) => sum + (int.tryParse(controller.text) ?? 0),
    );
  }

  double get _unitCost =>
      double.tryParse(_unitCostController.text.replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final items = <ProductionBatchItem>[];
    for (final slot in _slots) {
      final quantity = int.tryParse(_quantityControllers[slot.key]!.text) ?? 0;
      if (quantity > 0) {
        items.add(ProductionBatchItem(
          size: slot.size,
          gender: slot.gender,
          quantity: quantity,
        ));
      }
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('En az bir beden için adet girin'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    // Kullanılan bedenleri ürüne yaz (eksik bedenler parti kaydıyla eklenmiş olsun)
    final usedSizes = items.map((i) => i.size).toSet().toList()..sort();
    final existingSizes = listingSizeOptions(_listing).toList();
    final mergedSizes = {...existingSizes, ...usedSizes}.toList();
    if (mergedSizes.join(',') != existingSizes.join(',')) {
      await ref.read(manualSaleProvider.notifier).updateListingSizesAndGenderMode(
            listingId: widget.listingId,
            size: mergedSizes.isEmpty ? null : mergedSizes.join(', '),
            stockGenderMode:
                _listing?.stockGenderMode ?? ListingGenderMode.unisex,
          );
    }

    final success =
        await ref.read(manualSaleProvider.notifier).saveProductionBatch(
              batchId: widget.batch?.id,
              listingId: widget.listingId,
              unitCost: _unitCost,
              producedAt: _producedAt,
              note: _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
              items: items,
            );

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(manualSaleProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kaydedilemedi: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final listingAsync = ref.watch(listingByIdProvider(widget.listingId));

    // Sheet, ürün yüklenmeden açılmış olabilir; geldiğinde bedenleri kur.
    final listing = listingAsync.valueOrNull;
    if (listing != null && !identical(listing, _listing)) {
      _listing = listing;
      _syncSlots();
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Form(
            key: _formKey,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(
                  widget.batch == null ? 'Yeni Üretim Partisi' : 'Partiyi Düzenle',
                  style: AppTypography.titleMedium
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _unitCostController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Birim üretim maliyeti',
                    prefixText: '₺ ',
                    helperText: 'Tüm bedenler için aynı maliyet uygulanır.',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final parsed =
                        double.tryParse((value ?? '').replaceAll(',', '.'));
                    if (parsed == null || parsed < 0) {
                      return 'Geçerli bir maliyet girin';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today, size: 20),
                  title: const Text('Üretim tarihi'),
                  subtitle: Text(formatReportDate(_producedAt)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _producedAt,
                      firstDate: DateTime(2015),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      locale: const Locale('tr', 'TR'),
                    );
                    if (picked != null) setState(() => _producedAt = picked);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Beden bazlı adetler',
                  style: AppTypography.titleSmall
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Girilen adetler stoka eklenir. Partiyi düzenler/silerseniz stok da güncellenir.',
                  style: AppTypography.bodySmall,
                ),
                if (listingAsync.isLoading)
                  Text(
                    'Ürün bedenleri yükleniyor...',
                    style: AppTypography.bodySmall,
                  )
                else if (listingAsync.hasError)
                  Text(
                    'Ürün bilgisi alınamadı, bedenler listelenemiyor.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.error),
                  ),
                const SizedBox(height: 8),
                ..._slots.map(
                  (slot) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            sizeWithGenderLabel(slot.size, slot.gender),
                            style: AppTypography.bodyMedium,
                          ),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: _quantityControllers[slot.key],
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              hintText: '0',
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('Toplam adet'),
                          const Spacer(),
                          Text('$_totalQuantity',
                              style: AppTypography.bodyLarge
                                  .copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text('Toplam üretim maliyeti'),
                          const Spacer(),
                          Text(
                            formatMoney(_totalQuantity * _unitCost),
                            style: AppTypography.titleMedium
                                .copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Not (opsiyonel)',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Kaydet'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SizeSlot {
  final String size;
  final ListingGender gender;

  const _SizeSlot({required this.size, required this.gender});

  String get key => '$size::${gender.value}';
}
