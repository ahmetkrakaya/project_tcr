import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/enums/gender.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../members_groups/presentation/providers/group_provider.dart';
import '../../data/models/listing_model.dart';
import '../../data/models/order_model.dart';
import '../../utils/listing_price_utils.dart';
import '../../utils/market_report_utils.dart';
import '../providers/marketplace_provider.dart';

enum _BuyerMode { registered, manual }

/// Elden / geçmiş satış kaydı ekleme ve düzenleme ekranı (admin).
class ManualSalePage extends ConsumerStatefulWidget {
  final String? listingId;
  final String? orderId;

  const ManualSalePage({super.key, this.listingId, this.orderId});

  bool get isEditing => orderId != null;

  @override
  ConsumerState<ManualSalePage> createState() => _ManualSalePageState();
}

class _ManualSalePageState extends ConsumerState<ManualSalePage> {
  final _formKey = GlobalKey<FormState>();
  final _manualNameController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _paidController = TextEditingController();
  final _noteController = TextEditingController();

  ListingModel? _listing;
  _BuyerMode _buyerMode = _BuyerMode.registered;
  UserEntity? _selectedUser;
  String? _selectedSize;
  ListingGender _selectedGender = ListingGender.unisex;
  int _quantity = 1;
  SaleType _saleType = SaleType.regular;
  OrderStatus _status = OrderStatus.completed;
  DateTime _orderDate = DateTime.now();
  DateTime? _deliveryDate;
  DateTime? _paymentDate;
  PaymentMethod? _paymentMethod = PaymentMethod.cash;
  bool _affectsStock = true;
  bool _initialized = false;
  bool _saving = false;

  /// Düzenlemede mevcut satışın stoka geri eklenecek payı.
  String? _originalSize;
  ListingGender? _originalGender;
  int _originalQuantity = 0;
  bool _originalAffectsStock = false;

  /// Aynı veriyi tekrar doldurmayı önlemek için fingerprint.
  String? _hydratedOrderFingerprint;
  String? _hydratedListingFingerprint;

  @override
  void dispose() {
    _manualNameController.dispose();
    _unitPriceController.dispose();
    _paidController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      invalidateMarketplaceCachesForWidget(
        ref,
        listingId: widget.listingId,
        orderId: widget.orderId,
        refreshListingsGrid: false,
      );
    });
  }

  double get _unitPrice =>
      double.tryParse(_unitPriceController.text.replaceAll(',', '.')) ?? 0;

  double get _totalPrice => _unitPrice * _quantity;

  double get _paidAmount =>
      double.tryParse(_paidController.text.replaceAll(',', '.')) ?? 0;

  /// Stoğu olan bedenler. Düzenlenen satışın bedeni listede yoksa eklenir.
  List<String> get _sizeOptions {
    if (!_affectsStock) {
      final options = listingSizeOptions(_listing).toList();
      final current = _selectedSize?.trim();
      if (current != null &&
          current.isNotEmpty &&
          !options.contains(current)) {
        options.add(current);
      }
      return options;
    }
    return listingInStockSizeOptions(
      _listing,
      forGender: _isGendered ? _selectedGender : null,
      includeSize: widget.isEditing ? _selectedSize : null,
    );
  }

  List<ListingGender> get _genderOptions {
    if (!_affectsStock) {
      return const [ListingGender.male, ListingGender.female];
    }
    // Cinsiyet, seçili bedene kilitlenmez; stoğu olan tüm cinsiyetler listelenir.
    // Aksi halde L/Erkek seçiliyken Kadın'a geçilemez (Kadın L stoku yoksa).
    return listingInStockGenderOptions(
      _listing,
      includeGender: widget.isEditing ? _selectedGender : null,
    );
  }

  bool get _isGendered =>
      _listing?.stockGenderMode == ListingGenderMode.gendered;

  /// Seçili beden/cinsiyet için satılabilir stok (düzenlemede orijinal adet geri eklenir).
  int? get _availableStock {
    final listing = _listing;
    final size = _selectedSize;
    if (listing == null || size == null || size.trim().isEmpty) return null;

    var stock = listingStockFor(
      listing,
      size: size,
      gender: _isGendered ? _selectedGender : ListingGender.unisex,
    );

    if (widget.isEditing &&
        _originalAffectsStock &&
        _selectedSize == _originalSize &&
        (!_isGendered || _selectedGender == _originalGender)) {
      stock += _originalQuantity;
    }
    return stock;
  }

  /// Seçili cinsiyeti ürünün stok moduna ve stoğa uyarlar.
  void _normalizeGender() {
    if (!_isGendered) {
      _selectedGender = ListingGender.unisex;
      return;
    }
    final options = _genderOptions;
    if (options.isEmpty) {
      _selectedGender = ListingGender.male;
    } else if (!options.contains(_selectedGender)) {
      _selectedGender = options.first;
    }
  }

  void _normalizeSizeAndGender() {
    _normalizeGender();
    final sizes = _sizeOptions;
    if (sizes.isEmpty) {
      _selectedSize = null;
      return;
    }
    if (_selectedSize == null || !sizes.contains(_selectedSize)) {
      _selectedSize = sizes.first;
    }
    _normalizeGender();
    _clampQuantityToStock();
  }

  void _clampQuantityToStock() {
    if (!_affectsStock) return;
    final available = _availableStock;
    if (available == null) return;
    if (available <= 0) {
      _quantity = 1;
    } else if (_quantity > available) {
      _quantity = available;
    }
  }

  void _applyListing(ListingModel listing, {bool resetPrice = true}) {
    _listing = listing;
    _normalizeSizeAndGender();
    if (resetPrice) {
      final price = listingDisplayPrice(listing) ?? listing.price ?? 0;
      _unitPriceController.text = price > 0 ? price.toStringAsFixed(0) : '';
      _syncPaidWithTotal();
    }
  }

  void _syncPaidWithTotal() {
    if (_status == OrderStatus.completed && _saleType != SaleType.gift) {
      _paidController.text = _totalPrice.toStringAsFixed(0);
    } else if (_saleType == SaleType.gift) {
      _paidController.text = '0';
    }
  }

  void _onSaleTypeChanged(SaleType type) {
    setState(() {
      _saleType = type;
      if (type == SaleType.gift) {
        _unitPriceController.text = '0';
        _paidController.text = '0';
      } else if (_unitPrice == 0 && _listing != null) {
        final price = listingDisplayPrice(_listing!) ?? _listing!.price ?? 0;
        _unitPriceController.text = price > 0 ? price.toStringAsFixed(0) : '';
      }
      _syncPaidWithTotal();
    });
  }

  Future<void> _pickDate({
    required DateTime? initial,
    required ValueChanged<DateTime?> onPicked,
    bool clearable = false,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('tr', 'TR'),
    );
    if (picked != null) {
      onPicked(picked);
    } else if (clearable && initial != null) {
      // Kullanıcı seçim yapmadan kapattığında mevcut değeri koru
      onPicked(initial);
    }
  }

  Future<void> _selectUser(List<UserEntity> users) async {
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
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final listing = _listing;
    if (listing == null) {
      _showError('Önce bir ürün seçin');
      return;
    }
    if (_buyerMode == _BuyerMode.registered && _selectedUser == null) {
      _showError('Bir üye seçin veya serbest ad-soyad girin');
      return;
    }
    if (_affectsStock) {
      if (_sizeOptions.isEmpty || _selectedSize == null) {
        _showError('Bu üründe satılabilir stok yok');
        return;
      }
      final available = _availableStock;
      if (available != null && _quantity > available) {
        _showError('Stokta sadece $available adet var');
        return;
      }
    }

    setState(() => _saving = true);

    final sale = OrderModel(
      id: widget.orderId ?? '',
      listingId: listing.id,
      buyerId: _buyerMode == _BuyerMode.registered ? _selectedUser!.id : null,
      manualBuyerName: _buyerMode == _BuyerMode.manual
          ? _manualNameController.text.trim()
          : null,
      quantity: _quantity,
      totalPrice: _totalPrice,
      currency: listing.currency,
      status: _status,
      sellerNote: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      selectedSize: _selectedSize,
      selectedGender: _selectedGender,
      isManual: true,
      saleType: _saleType,
      unitPrice: _unitPrice,
      orderDate: _orderDate,
      deliveryDate: _deliveryDate,
      paymentDate: _paymentDate,
      paymentMethod: _paymentMethod,
      paidAmount: _paidAmount,
      affectsStock: _affectsStock,
      createdAt: DateTime.now(),
    );

    final notifier = ref.read(manualSaleProvider.notifier);
    final success = widget.isEditing
        ? await notifier.updateSale(widget.orderId!, sale)
        : await notifier.createSale(sale);

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEditing ? 'Satış güncellendi' : 'Satış kaydedildi'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(manualSaleProvider).error;
      _showError('Kaydedilemedi: $error');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Satış Ekle')),
        body: const Center(child: Text('Bu sayfaya erişim yetkiniz yok')),
      );
    }

    final listingsAsync = ref.watch(adminListingsProvider);
    ref.listen<AsyncValue<List<ListingModel>>>(adminListingsProvider, (_, next) {
      next.whenData(_onListingsRefreshed);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Satışı Düzenle' : 'Elden Satış Ekle'),
      ),
      body: listingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ürünler alınamadı: $e')),
        data: (listings) {
          if (listings.isEmpty) {
            return const Center(child: Text('Önce bir ürün oluşturmalısınız'));
          }
          if (widget.isEditing) {
            return _buildEditingForm(listings);
          }
          _ensureInitialized(listings, null);
          return _buildForm(listings);
        },
      ),
    );
  }

  Widget _buildEditingForm(List<ListingModel> listings) {
    final orderAsync = ref.watch(orderByIdProvider(widget.orderId!));
    return orderAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Satış alınamadı: $e')),
      data: (order) {
        // Pasife alınmış ürünler aktif listede olmadığı için ayrıca çekilir
        var available = listings;
        if (!listings.any((l) => l.id == order.listingId)) {
          final orderListing =
              ref.watch(listingByIdProvider(order.listingId)).valueOrNull;
          if (orderListing == null) {
            return const Center(child: CircularProgressIndicator());
          }
          available = [orderListing, ...listings];
        }

        _ensureInitialized(available, order);
        return _buildForm(available);
      },
    );
  }

  void _ensureInitialized(List<ListingModel> listings, OrderModel? order) {
    final targetId = order?.listingId ?? widget.listingId ?? _listing?.id;
    final listing = targetId != null
        ? listings.where((l) => l.id == targetId).firstOrNull
        : null;

    if (listing != null) {
      final listingFp =
          '${listing.id}:${listing.updatedAt?.millisecondsSinceEpoch}:'
          '${listing.stockQuantity}:${listing.stockBySize}:'
          '${listing.stockBySizeAndGender}:${listing.price}:'
          '${listing.discountPercent}:${listing.size}:${listing.stockGenderMode.value}';
      if (_hydratedListingFingerprint != listingFp) {
        _hydratedListingFingerprint = listingFp;
        final keepPrice = _initialized && order == null;
        _applyListing(listing, resetPrice: !keepPrice && order == null);
      }
    }

    if (order != null) {
      final orderFp =
          '${order.id}:${order.updatedAt?.millisecondsSinceEpoch}:'
          '${order.quantity}:${order.unitPrice}:${order.totalPrice}:'
          '${order.paidAmount}:${order.selectedSize}:${order.selectedGender}:'
          '${order.status.value}:${order.saleType.value}:${order.affectsStock}:'
          '${order.orderDate}:${order.deliveryDate}:${order.paymentDate}:'
          '${order.paymentMethod}:${order.sellerNote}:${order.manualBuyerName}:'
          '${order.buyerId}';
      if (_hydratedOrderFingerprint == orderFp) {
        _initialized = true;
        return;
      }
      _hydratedOrderFingerprint = orderFp;

      _buyerMode =
          order.buyerId != null ? _BuyerMode.registered : _BuyerMode.manual;
      _manualNameController.text = order.manualBuyerName ?? '';
      _selectedSize = order.selectedSize ?? _selectedSize;
      _selectedGender = order.selectedGender ?? _selectedGender;
      _originalSize = order.selectedSize;
      _originalGender = order.selectedGender;
      _originalQuantity = order.quantity;
      _originalAffectsStock = order.affectsStock &&
          (order.status == OrderStatus.confirmed ||
              order.status == OrderStatus.completed);
      _normalizeSizeAndGender();
      _quantity = order.quantity;
      _saleType = order.saleType;
      _status = order.status;
      _orderDate = order.effectiveOrderDate;
      _deliveryDate = order.deliveryDate;
      _paymentDate = order.paymentDate;
      _paymentMethod = order.paymentMethod;
      _affectsStock = order.affectsStock;
      _noteController.text = order.sellerNote ?? '';
      _unitPriceController.text =
          (order.unitPrice ?? order.totalPrice / order.quantity)
              .toStringAsFixed(0);
      _paidController.text = order.paidAmount.toStringAsFixed(0);

      if (order.buyerId != null) {
        final usersAsync = ref.read(activeUsersProvider);
        _selectedUser = usersAsync.valueOrNull
            ?.where((u) => u.id == order.buyerId)
            .firstOrNull;
      }
    }

    _initialized = true;
  }

  void _onListingsRefreshed(List<ListingModel> listings) {
    if (!_initialized) return;
    final currentId = _listing?.id;
    if (currentId == null) return;
    final fresh = listings.where((l) => l.id == currentId).firstOrNull;
    if (fresh == null) return;

    final listingFp =
        '${fresh.id}:${fresh.updatedAt?.millisecondsSinceEpoch}:'
        '${fresh.stockQuantity}:${fresh.stockBySize}:'
        '${fresh.stockBySizeAndGender}:${fresh.price}:'
        '${fresh.discountPercent}:${fresh.size}:${fresh.stockGenderMode.value}';
    if (_hydratedListingFingerprint == listingFp) return;

    setState(() {
      _hydratedListingFingerprint = listingFp;
      _listing = fresh;
      _normalizeSizeAndGender();
    });
  }

  Widget _buildForm(List<ListingModel> listings) {
    final cs = Theme.of(context).colorScheme;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _sectionTitle('Ürün'),
          AppCard(
            child: DropdownButtonFormField<String>(
              initialValue: _listing?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Ürün',
                border: InputBorder.none,
              ),
              items: listings
                  .map(
                    (l) => DropdownMenuItem(
                      value: l.id,
                      child: Text(l.title, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              validator: (value) => value == null ? 'Ürün seçin' : null,
              onChanged: widget.isEditing
                  ? null
                  : (value) {
                      final selected =
                          listings.where((l) => l.id == value).firstOrNull;
                      if (selected != null) {
                        setState(() => _applyListing(selected));
                      }
                    },
            ),
          ),
          if (widget.isEditing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Düzenlemede ürün değiştirilemez.',
                style: AppTypography.bodySmall
                    .copyWith(color: cs.onSurfaceVariant),
              ),
            ),

          const SizedBox(height: 20),
          _sectionTitle('Alıcı'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<_BuyerMode>(
                  segments: const [
                    ButtonSegment(
                      value: _BuyerMode.registered,
                      label: Text('Üye'),
                      icon: Icon(Icons.person),
                    ),
                    ButtonSegment(
                      value: _BuyerMode.manual,
                      label: Text('Serbest'),
                      icon: Icon(Icons.edit),
                    ),
                  ],
                  selected: {_buyerMode},
                  onSelectionChanged: (selection) =>
                      setState(() => _buyerMode = selection.first),
                ),
                const SizedBox(height: 12),
                if (_buyerMode == _BuyerMode.registered)
                  _buildUserSelector(cs)
                else
                  TextFormField(
                    controller: _manualNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Ad Soyad',
                      hintText: 'Örn. Ahmet Yılmaz',
                    ),
                    validator: (value) {
                      if (_buyerMode != _BuyerMode.manual) return null;
                      if (value == null || value.trim().isEmpty) {
                        return 'Ad soyad girin';
                      }
                      return null;
                    },
                  ),
                if (_buyerMode == _BuyerMode.manual)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Serbest isimle kaydedilen satışlar puan kazandırmaz.',
                      style: AppTypography.bodySmall
                          .copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _sectionTitle('Beden ve Adet'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_listing != null &&
                    _affectsStock &&
                    _sizeOptions.isEmpty) ...[
                  Text(
                    'Bu üründe satılabilir stok yok. Önce Üretim ve Maliyet’ten stok ekleyin veya “Stoktan düş”ü kapatın.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.error),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    if (_isGendered) ...[
                      Expanded(
                        child: DropdownButtonFormField<ListingGender>(
                          value: _genderOptions.contains(_selectedGender)
                              ? _selectedGender
                              : null,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Cinsiyet'),
                          items: _genderOptions
                              .map(
                                (gender) => DropdownMenuItem(
                                  value: gender,
                                  child: Text(genderLabel(gender)),
                                ),
                              )
                              .toList(),
                          onChanged: _genderOptions.isEmpty
                              ? null
                              : (value) => setState(() {
                                    _selectedGender =
                                        value ?? _selectedGender;
                                    // Cinsiyet değişince o cinsiyetin stoklu bedenine geç
                                    final sizes = _sizeOptions;
                                    _selectedSize =
                                        sizes.isNotEmpty ? sizes.first : null;
                                    _clampQuantityToStock();
                                    _syncPaidWithTotal();
                                  }),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _sizeOptions.contains(_selectedSize)
                            ? _selectedSize
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Beden'),
                        items: _sizeOptions
                            .map((size) {
                              final stock = _listing == null
                                  ? null
                                  : listingStockFor(
                                      _listing!,
                                      size: size,
                                      gender: _isGendered
                                          ? _selectedGender
                                          : ListingGender.unisex,
                                    );
                              final label = _affectsStock && stock != null
                                  ? '$size ($stock)'
                                  : size;
                              return DropdownMenuItem(
                                value: size,
                                child: Text(label),
                              );
                            })
                            .toList(),
                        onChanged: _sizeOptions.isEmpty
                            ? null
                            : (value) => setState(() {
                                  _selectedSize = value;
                                  _clampQuantityToStock();
                                  _syncPaidWithTotal();
                                }),
                        validator: (value) {
                          if (_affectsStock &&
                              (_sizeOptions.isEmpty || value == null)) {
                            return 'Stokta beden yok';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Adet', style: AppTypography.bodyMedium),
                    if (_affectsStock && _availableStock != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Stok: $_availableStock',
                        style: AppTypography.bodySmall.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const Spacer(),
                    IconButton.filledTonal(
                      onPressed: _quantity > 1
                          ? () => setState(() {
                                _quantity--;
                                _syncPaidWithTotal();
                              })
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '$_quantity',
                        style: AppTypography.titleMedium,
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () {
                        final max = _affectsStock ? _availableStock : null;
                        if (max != null && _quantity >= max) return;
                        setState(() {
                          _quantity++;
                          _syncPaidWithTotal();
                        });
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _sectionTitle('Fiyat'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<SaleType>(
                  segments: SaleType.values
                      .map((type) => ButtonSegment(
                            value: type,
                            label: Text(type.label),
                          ))
                      .toList(),
                  selected: {_saleType},
                  onSelectionChanged: (selection) =>
                      _onSaleTypeChanged(selection.first),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _unitPriceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Birim satış fiyatı',
                    prefixText: '₺ ',
                    helperText: _listing?.price != null
                        ? 'Market fiyatı: ${formatMoneyCompact(_listing!.price)}'
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (_saleType == SaleType.gift) return null;
                    final parsed =
                        double.tryParse((value ?? '').replaceAll(',', '.'));
                    if (parsed == null || parsed <= 0) {
                      return 'Geçerli bir fiyat girin';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text('Toplam', style: AppTypography.bodyMedium),
                      const Spacer(),
                      Text(
                        formatMoney(_totalPrice),
                        style: AppTypography.titleMedium
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _sectionTitle('Tarihler'),
          AppCard(
            child: Column(
              children: [
                _dateTile(
                  label: 'Sipariş tarihi',
                  value: _orderDate,
                  onTap: () => _pickDate(
                    initial: _orderDate,
                    onPicked: (date) =>
                        setState(() => _orderDate = date ?? _orderDate),
                  ),
                ),
                _dateTile(
                  label: 'Teslim tarihi',
                  value: _deliveryDate,
                  onClear: _deliveryDate != null
                      ? () => setState(() => _deliveryDate = null)
                      : null,
                  onTap: () => _pickDate(
                    initial: _deliveryDate,
                    onPicked: (date) => setState(() => _deliveryDate = date),
                  ),
                ),
                _dateTile(
                  label: 'Ödeme tarihi',
                  value: _paymentDate,
                  onClear: _paymentDate != null
                      ? () => setState(() => _paymentDate = null)
                      : null,
                  onTap: () => _pickDate(
                    initial: _paymentDate,
                    onPicked: (date) => setState(() => _paymentDate = date),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _sectionTitle('Ödeme'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<PaymentMethod?>(
                  initialValue: _paymentMethod,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Ödeme şekli'),
                  items: [
                    const DropdownMenuItem<PaymentMethod?>(
                      value: null,
                      child: Text('Belirtilmedi'),
                    ),
                    ...PaymentMethod.values.map(
                      (method) => DropdownMenuItem<PaymentMethod?>(
                        value: method,
                        child: Text(method.label),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _paymentMethod = value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _paidController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Tahsil edilen tutar',
                    prefixText: '₺ ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _totalPrice - _paidAmount > 0
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle,
                      size: 18,
                      color: _totalPrice - _paidAmount > 0
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _totalPrice - _paidAmount > 0
                          ? 'Kalan borç: ${formatMoney(_totalPrice - _paidAmount)}'
                          : 'Tamamı tahsil edildi',
                      style: AppTypography.bodySmall,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() {
                        _paidController.text = _totalPrice.toStringAsFixed(0);
                      }),
                      child: const Text('Tamamı'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _sectionTitle('Durum ve Stok'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<OrderStatus>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Satış durumu'),
                  items: const [
                    DropdownMenuItem(
                      value: OrderStatus.completed,
                      child: Text('Tamamlandı'),
                    ),
                    DropdownMenuItem(
                      value: OrderStatus.confirmed,
                      child: Text('Onaylandı'),
                    ),
                    DropdownMenuItem(
                      value: OrderStatus.pending,
                      child: Text('Beklemede'),
                    ),
                    DropdownMenuItem(
                      value: OrderStatus.cancelled,
                      child: Text('İptal'),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _status = value ?? _status;
                    _syncPaidWithTotal();
                  }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _affectsStock,
                  onChanged: (value) => setState(() {
                    _affectsStock = value;
                    _normalizeSizeAndGender();
                    _syncPaidWithTotal();
                  }),
                  title: const Text('Stoktan düş'),
                  subtitle: Text(
                    'Kapalıysa bu kayıt stok miktarını değiştirmez.',
                    style: AppTypography.bodySmall
                        .copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                TextFormField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Not (opsiyonel)',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(widget.isEditing ? 'Değişiklikleri Kaydet' : 'Satışı Kaydet'),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSelector(ColorScheme cs) {
    final usersAsync = ref.watch(activeUsersProvider);

    return usersAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Üyeler alınamadı: $e'),
      data: (users) {
        // Düzenleme modunda üyeler sonradan yüklenirse eşleştir
        if (_selectedUser == null && widget.isEditing) {
          final orderBuyerId =
              ref.read(orderByIdProvider(widget.orderId!)).valueOrNull?.buyerId;
          if (orderBuyerId != null) {
            _selectedUser =
                users.where((u) => u.id == orderBuyerId).firstOrNull;
          }
        }

        return InkWell(
          onTap: () => _selectUser(users),
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Üye'),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedUser?.fullName ?? 'Üye seçin',
                    style: AppTypography.bodyMedium.copyWith(
                      color: _selectedUser == null ? cs.onSurfaceVariant : null,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.calendar_today, size: 20),
      title: Text(label, style: AppTypography.bodyMedium),
      subtitle: Text(formatReportDate(value)),
      trailing: onClear != null
          ? IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: onClear,
            )
          : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Üye seçmek için aranabilir bottom sheet.
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
