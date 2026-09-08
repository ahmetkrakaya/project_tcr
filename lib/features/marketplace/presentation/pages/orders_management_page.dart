import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/listing_model.dart';
import '../../data/models/order_model.dart';
import '../providers/marketplace_provider.dart';
import '../../../../core/theme/theme_brightness_holder.dart';

/// Orders Management Page (Admin)
class OrdersManagementPage extends ConsumerStatefulWidget {
  const OrdersManagementPage({super.key});

  @override
  ConsumerState<OrdersManagementPage> createState() => _OrdersManagementPageState();
}

class _OrdersManagementPageState extends ConsumerState<OrdersManagementPage> {
  _StatusFilter _statusFilter = _StatusFilter.pending;
  _PaymentFilter _paymentFilter = _PaymentFilter.all;
  _SaleTypeFilter _saleTypeFilter = _SaleTypeFilter.all;
  String? _listingIdFilter;

  bool get _hasExtraFilters =>
      _paymentFilter != _PaymentFilter.all ||
      _saleTypeFilter != _SaleTypeFilter.all ||
      _listingIdFilter != null;

  bool get _hasNonDefaultFilters =>
      _statusFilter != _StatusFilter.pending || _hasExtraFilters;

  /// Durum sunucu tarafında süzülür; ödeme, satış şekli ve ürün burada uygulanır.
  List<OrderModel> _applyFilters(List<OrderModel> orders) {
    if (!_hasExtraFilters) return orders;
    return orders.where((order) {
      final paymentMatches = switch (_paymentFilter) {
        _PaymentFilter.all => true,
        _PaymentFilter.paid => order.isFullyPaid,
        _PaymentFilter.partial => !order.isFullyPaid && order.paidAmount > 0,
        _PaymentFilter.unpaid => !order.isFullyPaid && order.paidAmount <= 0,
      };
      final saleTypeMatches = _saleTypeFilter.saleType == null ||
          order.saleType == _saleTypeFilter.saleType;
      final listingMatches =
          _listingIdFilter == null || order.listingId == _listingIdFilter;
      return paymentMatches && saleTypeMatches && listingMatches;
    }).toList();
  }

  void _clearFilters() {
    setState(() {
      _statusFilter = _StatusFilter.pending;
      _paymentFilter = _PaymentFilter.all;
      _saleTypeFilter = _SaleTypeFilter.all;
      _listingIdFilter = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sipariş Yönetimi')),
        body: const Center(
          child: Text('Bu sayfaya erişim yetkiniz yok'),
        ),
      );
    }

    final ordersAsync = ref.watch(allOrdersProvider(_statusFilter.status));
    final listingsAsync = ref.watch(adminListingsProvider);
    final cs = Theme.of(context).colorScheme;
    final listings = listingsAsync.valueOrNull ?? const <ListingModel>[];
    final selectedListingTitle = _listingFilterLabel(listings);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sipariş Yönetimi'),
      ),
      body: Column(
        children: [
          // Status Filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: cs.outlineVariant),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _filterButton<_StatusFilter>(
                        label: 'Durum',
                        selected: _statusFilter,
                        options: _StatusFilter.values,
                        labelOf: (filter) => filter.label,
                        isActive: _statusFilter != _StatusFilter.pending,
                        onSelected: (filter) =>
                            setState(() => _statusFilter = filter),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _filterButton<_PaymentFilter>(
                        label: 'Ödeme',
                        selected: _paymentFilter,
                        options: _PaymentFilter.values,
                        labelOf: (filter) => filter.label,
                        isActive: _paymentFilter != _PaymentFilter.all,
                        onSelected: (filter) =>
                            setState(() => _paymentFilter = filter),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _filterButton<_SaleTypeFilter>(
                        label: 'Satış şekli',
                        selected: _saleTypeFilter,
                        options: _SaleTypeFilter.values,
                        labelOf: (filter) => filter.label,
                        isActive: _saleTypeFilter != _SaleTypeFilter.all,
                        onSelected: (filter) =>
                            setState(() => _saleTypeFilter = filter),
                      ),
                    ),
                    if (_hasNonDefaultFilters) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                        label: const Text('Temizle'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                _productFilterButton(
                  selectedTitle: selectedListingTitle,
                  isActive: _listingIdFilter != null,
                  listings: listings,
                  isLoading: listingsAsync.isLoading,
                ),
              ],
            ),
          ),
          // Orders List
          Expanded(
            child: ordersAsync.when(
              data: (allOrders) {
                final orders = _applyFilters(allOrders);
                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: ThemeBrightnessHolder.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Sipariş bulunamadı',
                          style: AppTypography.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _hasNonDefaultFilters
                              ? 'Seçilen filtrelere uyan sipariş yok'
                              : 'Bekleyen sipariş yok',
                          style: AppTypography.bodySmall.copyWith(
                            color: ThemeBrightnessHolder.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(allOrdersProvider(_statusFilter.status));
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return _buildOrderCard(context, order);
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: AppColors.error),
                    const SizedBox(height: 16),
                    Text(
                      'Bir hata oluştu',
                      style: AppTypography.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      style: AppTypography.bodySmall.copyWith(
                        color: ThemeBrightnessHolder.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        ref.invalidate(allOrdersProvider(_statusFilter.status));
                      },
                      child: const Text('Yeniden Dene'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _listingFilterLabel(List<ListingModel> listings) {
    if (_listingIdFilter == null) return 'Tümü';
    for (final listing in listings) {
      if (listing.id == _listingIdFilter) return listing.title;
    }
    return 'Ürün';
  }

  Widget _productFilterButton({
    required String selectedTitle,
    required bool isActive,
    required List<ListingModel> listings,
    required bool isLoading,
  }) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      onSelected: (id) => setState(() {
        _listingIdFilter = id.isEmpty ? null : id;
      }),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: '',
          child: Row(
            children: [
              Icon(
                _listingIdFilter == null ? Icons.check : null,
                size: 20,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('Tümü')),
            ],
          ),
        ),
        if (isLoading)
          const PopupMenuItem<String>(
            enabled: false,
            value: '__loading__',
            child: Text('Ürünler yükleniyor...'),
          )
        else if (listings.isEmpty)
          const PopupMenuItem<String>(
            enabled: false,
            value: '__empty__',
            child: Text('Ürün bulunamadı'),
          )
        else
          for (final listing in listings)
            PopupMenuItem<String>(
              value: listing.id,
              child: Row(
                children: [
                  Icon(
                    listing.id == _listingIdFilter ? Icons.check : null,
                    size: 20,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      listing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
      ],
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? cs.primary.withValues(alpha: 0.12) : cs.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? cs.primary : cs.outline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Ürün: $selectedTitle',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w500,
                  color: isActive ? cs.primary : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: isActive ? cs.primary : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterButton<T>({
    required String label,
    required T selected,
    required List<T> options,
    required String Function(T) labelOf,
    required bool isActive,
    required ValueChanged<T> onSelected,
  }) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<T>(
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<T>(
            value: option,
            child: Row(
              children: [
                Icon(
                  option == selected ? Icons.check : null,
                  size: 20,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Text(labelOf(option)),
              ],
            ),
          ),
      ],
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? cs.primary.withValues(alpha: 0.12) : cs.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? cs.primary : cs.outline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$label: ${labelOf(selected)}',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w500,
                  color: isActive ? cs.primary : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: isActive ? cs.primary : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, OrderModel order) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(order.status);
    final statusText = _getStatusText(order.status);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      // Rozetler sığmazsa alt satıra insin: sipariş türüne göre
                      // sayıları değiştiği için tek satıra sabitlenemez.
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Sipariş #${order.id.substring(0, 8)}',
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          _buildBadge(statusText, statusColor),
                          if (order.isManual)
                            _buildBadge('Elden', AppColors.info),
                          if (order.saleType != SaleType.regular)
                            _buildBadge(
                              order.saleType.label,
                              order.saleType == SaleType.gift
                                  ? AppColors.secondaryLight
                                  : AppColors.warning,
                            ),
                        ],
                      ),
                    ),
                    // Sağ üstteki üç aksiyon butonuna ayrılan yer
                    const SizedBox(width: 104),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 14,
                      color: ThemeBrightnessHolder.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.buyerDisplayName,
                        style: AppTypography.bodySmall.copyWith(
                          color: ThemeBrightnessHolder.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: ThemeBrightnessHolder.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('dd MMM yyyy, HH:mm', 'tr_TR').format(order.createdAt),
                      style: AppTypography.bodySmall.copyWith(
                        color: ThemeBrightnessHolder.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order.selectedSize != null && order.selectedSize!.isNotEmpty
                            ? '${order.quantity} adet • ${order.selectedSize} • ${order.totalPrice.toStringAsFixed(2)} ${order.currency}'
                            : '${order.quantity} adet • ${order.totalPrice.toStringAsFixed(2)} ${order.currency}',
                        style: AppTypography.bodySmall.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (order.status != OrderStatus.cancelled &&
                    order.saleType != SaleType.gift) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        order.isFullyPaid
                            ? Icons.check_circle_outline
                            : Icons.pending_actions,
                        size: 14,
                        color: order.isFullyPaid
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        order.isFullyPaid
                            ? 'Ödeme tamamlandı'
                            : 'Kalan borç: ${order.outstandingAmount.toStringAsFixed(2)} ${order.currency}',
                        style: AppTypography.bodySmall.copyWith(
                          color: order.isFullyPaid
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Action Buttons - Top Right
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () {
                    _showOrderDetailsDialog(context, order);
                  },
                  icon: Icon(Icons.info_outline, size: 20),
                  tooltip: 'Detaylar',
                  color: ThemeBrightnessHolder.onSurfaceVariant,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  onPressed: () async {
                    await context.pushNamed(
                      RouteNames.manualSale,
                      queryParameters: {
                        'listingId': order.listingId,
                        'orderId': order.id,
                      },
                    );
                    ref.invalidate(allOrdersProvider(_statusFilter.status));
                  },
                  icon: Icon(Icons.tune, size: 20),
                  tooltip: 'Satış Detayları',
                  color: ThemeBrightnessHolder.onSurfaceVariant,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  onPressed: () {
                    _showStatusUpdateDialog(context, order);
                  },
                  icon: Icon(Icons.edit, size: 20),
                  tooltip: 'Durum Güncelle',
                  color: cs.primary,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.completed:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }

  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Beklemede';
      case OrderStatus.confirmed:
        return 'Onaylandı';
      case OrderStatus.completed:
        return 'Tamamlandı';
      case OrderStatus.cancelled:
        return 'İptal';
    }
  }

  void _showOrderDetailsDialog(BuildContext context, OrderModel order) {
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final listingAsync = ref.watch(listingByIdProvider(order.listingId));
          
          return AlertDialog(
            title: const Text('Sipariş Detayları'),
            content: SingleChildScrollView(
              child: listingAsync.when(
                data: (listing) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDetailRow('Sipariş ID', order.id),
                      _buildDetailRow('Ürün Adı', listing.title),
                      _buildDetailRow('Alıcı', order.buyerDisplayName),
                      if (order.isManual)
                        _buildDetailRow('Kaynak', 'Elden satış'),
                      _buildDetailRow('Satış Tipi', order.saleType.label),
                      _buildDetailRow('Miktar', '${order.quantity} adet'),
                      if (order.selectedSize != null && order.selectedSize!.isNotEmpty)
                        _buildDetailRow('Beden', order.selectedSize!),
                      _buildDetailRow('Toplam', '${order.totalPrice.toStringAsFixed(2)} ${order.currency}'),
                      _buildDetailRow(
                        'Tahsil Edilen',
                        '${order.paidAmount.toStringAsFixed(2)} ${order.currency}',
                      ),
                      if (order.outstandingAmount > 0)
                        _buildDetailRow(
                          'Kalan Borç',
                          '${order.outstandingAmount.toStringAsFixed(2)} ${order.currency}',
                        ),
                      if (order.paymentMethod != null)
                        _buildDetailRow('Ödeme Şekli', order.paymentMethod!.label),
                      _buildDetailRow('Durum', _getStatusText(order.status)),
                      if (order.orderDate != null)
                        _buildDetailRow(
                          'Sipariş Tarihi',
                          DateFormat('dd MMM yyyy', 'tr_TR').format(order.orderDate!),
                        ),
                      if (order.deliveryDate != null)
                        _buildDetailRow(
                          'Teslim Tarihi',
                          DateFormat('dd MMM yyyy', 'tr_TR').format(order.deliveryDate!),
                        ),
                      if (order.paymentDate != null)
                        _buildDetailRow(
                          'Ödeme Tarihi',
                          DateFormat('dd MMM yyyy', 'tr_TR').format(order.paymentDate!),
                        ),
                      if (order.buyerNote != null)
                        _buildDetailRow('Alıcı Notu', order.buyerNote!),
                      if (order.sellerNote != null)
                        _buildDetailRow('Satıcı Notu', order.sellerNote!),
                      _buildDetailRow(
                        'Oluşturulma',
                        DateFormat('dd MMM yyyy, HH:mm', 'tr_TR').format(order.createdAt),
                      ),
                      if (order.updatedAt != null)
                        _buildDetailRow(
                          'Güncellenme',
                          DateFormat('dd MMM yyyy, HH:mm', 'tr_TR').format(order.updatedAt!),
                        ),
                    ],
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, _) => Text('Ürün bilgisi yüklenemedi: $error'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Kapat'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: AppTypography.bodySmall.copyWith(
                color: ThemeBrightnessHolder.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  void _showStatusUpdateDialog(BuildContext context, OrderModel order) {
    OrderStatus? newStatus;
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Sipariş Durumu Güncelle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mevcut Durum: ${_getStatusText(order.status)}',
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Yeni Durum',
                  style: AppTypography.bodySmall.copyWith(
                    color: ThemeBrightnessHolder.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                ...OrderStatus.values.map((status) {
                  if (status == order.status) return const SizedBox.shrink();
                  return RadioListTile<OrderStatus>(
                    title: Text(_getStatusText(status)),
                    value: status,
                    groupValue: newStatus,
                    onChanged: (value) {
                      setDialogState(() {
                        newStatus = value;
                      });
                    },
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  );
                }),
                const SizedBox(height: 16),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Not (Opsiyonel)',
                    hintText: 'Durum değişikliği için not ekleyin',
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: newStatus == null
                  ? null
                  : () async {
                      if (newStatus != null) {
                        final updateNotifier = ref.read(updateOrderStatusProvider.notifier);
                        await updateNotifier.updateOrderStatus(
                          order.id,
                          newStatus!,
                          note: noteController.text.isEmpty ? null : noteController.text,
                        );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ref.invalidate(allOrdersProvider(_statusFilter.status));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Sipariş durumu güncellendi'),
                            ),
                          );
                        }
                      }
                    },
              child: const Text('Güncelle'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sipariş durumu filtresi. Sunucu sorgusuna `status` olarak geçer; "Tümü"
/// için null gönderilir.
enum _StatusFilter {
  all('Tümü', null),
  pending('Beklemede', OrderStatus.pending),
  confirmed('Onaylandı', OrderStatus.confirmed),
  completed('Tamamlandı', OrderStatus.completed),
  cancelled('İptal', OrderStatus.cancelled);

  final String label;
  final OrderStatus? status;
  const _StatusFilter(this.label, this.status);
}

/// Tahsilat durumu filtresi.
enum _PaymentFilter {
  all('Tümü'),
  paid('Ödendi'),
  partial('Kısmi ödendi'),
  unpaid('Ödenmedi');

  final String label;
  const _PaymentFilter(this.label);
}

/// Satış şekli filtresi (normal / indirimli / hediye).
enum _SaleTypeFilter {
  all('Tümü', null),
  regular('Normal', SaleType.regular),
  discounted('İndirimli', SaleType.discounted),
  gift('Hediye', SaleType.gift);

  final String label;
  final SaleType? saleType;
  const _SaleTypeFilter(this.label, this.saleType);
}
