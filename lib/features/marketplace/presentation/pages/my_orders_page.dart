import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../data/models/order_model.dart';
import '../providers/marketplace_provider.dart';

/// Kullanıcının kendi siparişlerini (alıcı + satıcı) gördüğü sayfa. Sadece kendi siparişleri, durum takibi.
class MyOrdersPage extends ConsumerWidget {
  const MyOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProfileProvider);
    final currentUserId = currentUser?.id;
    final ordersAsync = ref.watch(myOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Siparişlerim'),
      ),
      body: currentUserId == null
          ? const Center(
              child: Text('Siparişlerinizi görmek için giriş yapın'),
            )
          : ordersAsync.when(
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
                          'Henüz siparişiniz yok',
                          style: AppTypography.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'TCR Market\'ten ürün sipariş verebilir veya ilan açarak satıcı olabilirsiniz.',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: () => context.goNamed(RouteNames.marketplace),
                          icon: const Icon(Icons.shopping_bag_outlined),
                          label: const Text('Market\'e Git'),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(myOrdersProvider);
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      final isBuyer = order.buyerId == currentUserId;
                      return _OrderCard(
                        order: order,
                        isBuyer: isBuyer,
                      );
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
                      'Siparişler yüklenemedi',
                      style: AppTypography.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        error.toString().replaceFirst('Exception: ', ''),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(myOrdersProvider),
                      child: const Text('Yeniden Dene'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  final OrderModel order;
  final bool isBuyer;

  const _OrderCard({
    required this.order,
    required this.isBuyer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = _getStatusColor(order.status);
    final statusText = _getStatusText(order.status);
    final listingAsync = ref.watch(listingByIdProvider(order.listingId));

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => _showOrderDetails(context, ref, order, isBuyer, statusText, listingAsync),
      child: Padding(
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isBuyer
                              ? AppColors.primary.withOpacity(0.1)
                              : AppColors.tertiary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isBuyer
                                ? AppColors.primary.withOpacity(0.3)
                                : AppColors.tertiary.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          isBuyer ? 'Alıcı' : 'Satıcı',
                          style: AppTypography.labelSmall.copyWith(
                            color: isBuyer ? AppColors.primary : AppColors.tertiary,
                            fontWeight: FontWeight.w600,
                          ),
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
                const Icon(Icons.chevron_right, color: AppColors.neutral400),
              ],
            ),
            const SizedBox(height: 8),
            listingAsync.when(
              data: (listing) => Text(
                listing.title,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.neutral700,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              loading: () => Text(
                'Ürün yükleniyor...',
                style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
              ),
              error: (_, __) => Text(
                'Ürün bilgisi alınamadı',
                style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: AppColors.neutral500),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd MMM yyyy, HH:mm', 'tr_TR').format(order.createdAt),
                  style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
                ),
                const SizedBox(width: 12),
                Text(
                  order.selectedSize != null && order.selectedSize!.isNotEmpty
                      ? '${order.quantity} adet • ${order.selectedSize} • ₺${order.totalPrice.toStringAsFixed(0)}'
                      : '${order.quantity} adet • ₺${order.totalPrice.toStringAsFixed(0)}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
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

  void _showOrderDetails(
    BuildContext context,
    WidgetRef ref,
    OrderModel order,
    bool isBuyer,
    String statusText,
    AsyncValue listingAsync,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sipariş Detayı'),
        content: SingleChildScrollView(
          child: listingAsync.when(
            data: (listing) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _detailRow('Ürün', listing.title),
                  _detailRow('Sipariş no', '#${order.id.substring(0, 8)}'),
                  _detailRow('Durum', statusText),
                  _detailRow('Rol', isBuyer ? 'Alıcı' : 'Satıcı'),
                  _detailRow('Miktar', '${order.quantity} adet'),
                  if (order.selectedSize != null && order.selectedSize!.isNotEmpty)
                    _detailRow('Beden', order.selectedSize!),
                  _detailRow('Toplam', '₺${order.totalPrice.toStringAsFixed(2)} ${order.currency}'),
                  _detailRow(
                    'Tarih',
                    DateFormat('dd MMM yyyy, HH:mm', 'tr_TR').format(order.createdAt),
                  ),
                  if (order.buyerNote != null)
                    _detailRow('Sipariş notu', order.buyerNote!),
                  if (order.sellerNote != null)
                    _detailRow('Satıcı notu', order.sellerNote!),
                ],
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Text('Ürün bilgisi yüklenemedi: $e'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
          if (order.listingId.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.pushNamed(
                  RouteNames.listingDetail,
                  pathParameters: {'listingId': order.listingId},
                );
              },
              child: const Text('Ürünü Gör'),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
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
}
