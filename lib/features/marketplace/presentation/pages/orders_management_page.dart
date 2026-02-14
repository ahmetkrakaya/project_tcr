import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/order_model.dart';
import '../providers/marketplace_provider.dart';

/// Orders Management Page (Admin)
class OrdersManagementPage extends ConsumerStatefulWidget {
  const OrdersManagementPage({super.key});

  @override
  ConsumerState<OrdersManagementPage> createState() => _OrdersManagementPageState();
}

class _OrdersManagementPageState extends ConsumerState<OrdersManagementPage> {
  OrderStatus? _selectedStatus;

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

    final ordersAsync = ref.watch(allOrdersProvider(_selectedStatus));

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
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                bottom: BorderSide(color: AppColors.neutral200),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'Durum:',
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PopupMenuButton<OrderStatus?>(
                    onSelected: (OrderStatus? status) {
                      // Her zaman setState çağır, aynı değer olsa bile
                      setState(() {
                        _selectedStatus = status;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariantLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.neutral300),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _getStatusFilterText(_selectedStatus),
                              style: AppTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  itemBuilder: (BuildContext context) {
                    return [
                      PopupMenuItem<OrderStatus?>(
                        value: null,
                        onTap: () {
                          // onTap ile de setState çağır
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            setState(() {
                              _selectedStatus = null;
                            });
                          });
                        },
                        child: Row(
                          children: [
                            Icon(
                              _selectedStatus == null ? Icons.check : null,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text('Tümü'),
                          ],
                        ),
                      ),
                      PopupMenuItem<OrderStatus?>(
                        value: OrderStatus.pending,
                        child: Row(
                          children: [
                            Icon(
                              _selectedStatus == OrderStatus.pending ? Icons.check : null,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text('Beklemede'),
                          ],
                        ),
                      ),
                      PopupMenuItem<OrderStatus?>(
                        value: OrderStatus.confirmed,
                        child: Row(
                          children: [
                            Icon(
                              _selectedStatus == OrderStatus.confirmed ? Icons.check : null,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text('Onaylandı'),
                          ],
                        ),
                      ),
                      PopupMenuItem<OrderStatus?>(
                        value: OrderStatus.completed,
                        child: Row(
                          children: [
                            Icon(
                              _selectedStatus == OrderStatus.completed ? Icons.check : null,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text('Tamamlandı'),
                          ],
                        ),
                      ),
                      PopupMenuItem<OrderStatus?>(
                        value: OrderStatus.cancelled,
                        child: Row(
                          children: [
                            Icon(
                              _selectedStatus == OrderStatus.cancelled ? Icons.check : null,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text('İptal'),
                          ],
                        ),
                      ),
                    ];
                  },
                ),
            )],
            ),
          ),
          // Orders List
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: AppColors.neutral400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Sipariş bulunamadı',
                          style: AppTypography.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedStatus == null
                              ? 'Henüz sipariş yok'
                              : 'Bu durumda sipariş bulunmuyor',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(allOrdersProvider(_selectedStatus));
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
                        color: AppColors.neutral500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        ref.invalidate(allOrdersProvider(_selectedStatus));
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

  String _getStatusFilterText(OrderStatus? status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Beklemede';
      case OrderStatus.confirmed:
        return 'Onaylandı';
      case OrderStatus.completed:
        return 'Tamamlandı';
      case OrderStatus.cancelled:
        return 'İptal';
      case null:
        return 'Tümü';
    }
  }

  Widget _buildOrderCard(BuildContext context, OrderModel order) {
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
                      child: Row(
                        children: [
                          Text(
                            'Sipariş #${order.id.substring(0, 8)}',
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: statusColor.withOpacity(0.3)),
                            ),
                            child: Text(
                              statusText,
                              style: AppTypography.labelSmall.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Spacer for buttons
                    const SizedBox(width: 80),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 14,
                      color: AppColors.neutral500,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.buyerName ?? 'Bilinmeyen',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral600,
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
                      color: AppColors.neutral500,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        DateFormat('dd MMM yyyy, HH:mm', 'tr_TR').format(order.createdAt),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        order.selectedSize != null && order.selectedSize!.isNotEmpty
                            ? '${order.quantity} adet • ${order.selectedSize} • ${order.totalPrice.toStringAsFixed(2)} ${order.currency}'
                            : '${order.quantity} adet • ${order.totalPrice.toStringAsFixed(2)} ${order.currency}',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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
                  icon: const Icon(Icons.info_outline, size: 20),
                  tooltip: 'Detaylar',
                  color: AppColors.neutral600,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  onPressed: () {
                    _showStatusUpdateDialog(context, order);
                  },
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: 'Durum Güncelle',
                  color: AppColors.primary,
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
                      _buildDetailRow('Alıcı', order.buyerName ?? 'Bilinmeyen'),
                      _buildDetailRow('Miktar', '${order.quantity} adet'),
                      if (order.selectedSize != null && order.selectedSize!.isNotEmpty)
                        _buildDetailRow('Beden', order.selectedSize!),
                      _buildDetailRow('Toplam', '${order.totalPrice.toStringAsFixed(2)} ${order.currency}'),
                      _buildDetailRow('Durum', _getStatusText(order.status)),
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
                color: AppColors.neutral500,
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
                    color: AppColors.neutral500,
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
                    border: OutlineInputBorder(),
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
                          ref.invalidate(allOrdersProvider(_selectedStatus));
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
