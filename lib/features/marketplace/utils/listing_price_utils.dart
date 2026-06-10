import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../data/models/listing_model.dart';

bool isListingInStock(ListingModel listing) {
  if (listing.stockBySizeAndGender != null &&
      listing.stockBySizeAndGender!.isNotEmpty) {
    for (final genderMap in listing.stockBySizeAndGender!.values) {
      for (final qty in genderMap.values) {
        if (qty > 0) return true;
      }
    }
    return false;
  }

  if (listing.stockBySize != null && listing.stockBySize!.isNotEmpty) {
    return listing.stockBySize!.values.any((qty) => qty > 0);
  }

  if (listing.stockQuantity == null) return true;
  return listing.stockQuantity! > 0;
}

bool isListingOutOfStock(ListingModel listing) => !isListingInStock(listing);

bool isListingDiscountActive(ListingModel listing, {DateTime? at}) {
  final percent = listing.discountPercent;
  if (percent == null || percent <= 0 || listing.price == null) {
    return false;
  }

  final now = at ?? DateTime.now();
  if (listing.discountStartsAt != null && now.isBefore(listing.discountStartsAt!)) {
    return false;
  }
  if (listing.discountEndsAt != null && now.isAfter(listing.discountEndsAt!)) {
    return false;
  }
  return true;
}

double? listingSalePrice(ListingModel listing, {DateTime? at}) {
  if (!isListingDiscountActive(listing, at: at) || listing.price == null) {
    return null;
  }
  final percent = listing.discountPercent!;
  return (listing.price! * (1 - percent / 100)).roundToDouble();
}

double? listingDisplayPrice(ListingModel listing, {DateTime? at}) {
  return listingSalePrice(listing, at: at) ?? listing.price;
}

String formatListingPrice(double price) {
  final priceString = price.toStringAsFixed(0);
  final buffer = StringBuffer();

  for (var i = 0; i < priceString.length; i++) {
    if (i > 0 && (priceString.length - i) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(priceString[i]);
  }

  return buffer.toString();
}

class ListingPriceDisplay extends StatelessWidget {
  final ListingModel listing;
  final TextStyle? priceStyle;
  final TextStyle? originalPriceStyle;
  final bool compact;

  const ListingPriceDisplay({
    super.key,
    required this.listing,
    this.priceStyle,
    this.originalPriceStyle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (listing.price == null) {
      return Text(
        'Fiyat Sorunuz',
        style: priceStyle ??
            AppTypography.titleMedium.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final hasDiscount = isListingDiscountActive(listing);
    final displayPrice = listingDisplayPrice(listing)!;

    if (!hasDiscount) {
      return Text(
        '₺${formatListingPrice(displayPrice)}',
        style: priceStyle ??
            AppTypography.titleMedium.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final originalStyle = originalPriceStyle ??
        AppTypography.bodySmall.copyWith(
          color: AppColors.neutral500,
          decoration: TextDecoration.lineThrough,
        );
    final saleStyle = priceStyle ??
        AppTypography.titleMedium.copyWith(
          color: AppColors.error,
          fontWeight: FontWeight.w800,
        );

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '₺${formatListingPrice(displayPrice)}',
              style: saleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '₺${formatListingPrice(listing.price!)}',
            style: originalStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '₺${formatListingPrice(displayPrice)}',
          style: saleStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          '₺${formatListingPrice(listing.price!)}',
          style: originalStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
