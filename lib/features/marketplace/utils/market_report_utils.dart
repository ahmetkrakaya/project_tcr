import 'package:intl/intl.dart';

import '../../../core/enums/gender.dart';
import '../data/models/listing_model.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'tr_TR',
  symbol: '₺',
  decimalDigits: 2,
);

final _compactCurrencyFormat = NumberFormat.currency(
  locale: 'tr_TR',
  symbol: '₺',
  decimalDigits: 0,
);

final _dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');

/// Para birimi formatı: ₺1.234,50
String formatMoney(double? value) {
  if (value == null) return '-';
  return _currencyFormat.format(value);
}

/// Kısa para birimi formatı (kuruşsuz): ₺1.235
String formatMoneyCompact(double? value) {
  if (value == null) return '-';
  return _compactCurrencyFormat.format(value);
}

String formatReportDate(DateTime? date) {
  if (date == null) return '-';
  return _dateFormat.format(date);
}

String genderLabel(ListingGender? gender) {
  return switch (gender) {
    ListingGender.male => 'Erkek',
    ListingGender.female => 'Kadın',
    ListingGender.unisex => 'Unisex',
    null => '-',
  };
}

/// Beden + cinsiyet birleşik etiketi: "Erkek M" veya "M"
String sizeWithGenderLabel(String? size, ListingGender? gender) {
  final normalizedSize = (size == null || size.trim().isEmpty) ? '-' : size.trim();
  if (gender == null || gender == ListingGender.unisex) return normalizedSize;
  return '${genderLabel(gender)} $normalizedSize';
}

/// Ürünün beden seçeneklerini ilanda tanımlandığı sırayla döndürür.
///
/// Bedenler ilanda `size` alanında virgülle ayrılmış tek bir metin olarak
/// tutulur ("S,M,L,XL"); stok haritaları yalnızca stok girilmiş bedenleri
/// içerdiği için tek başına yeterli değildir. Hiç beden tanımlı değilse
/// tek bir "Standart" seçeneği döner.
List<String> listingSizeOptions(ListingModel? listing) {
  if (listing == null) return const [];

  final sizes = <String>[];
  void add(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return;
    if (!sizes.contains(normalized)) sizes.add(normalized);
  }

  listing.size?.split(',').forEach(add);
  listing.stockBySizeAndGender?.keys.forEach(add);
  listing.stockBySize?.keys.forEach(add);

  return sizes.isEmpty ? const ['Standart'] : sizes;
}

/// Belirli beden (+ cinsiyet) için güncel stok adedi.
int listingStockFor(
  ListingModel listing, {
  required String size,
  ListingGender gender = ListingGender.unisex,
}) {
  final normalized = size.trim();
  if (listing.stockBySizeAndGender != null &&
      listing.stockBySizeAndGender!.isNotEmpty) {
    return listing.stockBySizeAndGender![normalized]?[gender] ?? 0;
  }
  if (listing.stockBySize != null && listing.stockBySize!.isNotEmpty) {
    return listing.stockBySize![normalized] ?? 0;
  }
  return listing.stockQuantity ?? 0;
}

/// Stoğu > 0 olan bedenler. [forGender] verilirse sadece o cinsiyet kovası bakılır.
List<String> listingInStockSizeOptions(
  ListingModel? listing, {
  ListingGender? forGender,
  String? includeSize,
}) {
  if (listing == null) return const [];

  final gendered = listing.stockGenderMode == ListingGenderMode.gendered;
  final options = listingSizeOptions(listing).where((size) {
    if (gendered) {
      if (forGender != null && forGender != ListingGender.unisex) {
        return listingStockFor(listing, size: size, gender: forGender) > 0;
      }
      return listingStockFor(listing, size: size, gender: ListingGender.male) >
              0 ||
          listingStockFor(listing, size: size, gender: ListingGender.female) >
              0;
    }
    return listingStockFor(listing, size: size) > 0;
  }).toList();

  final include = includeSize?.trim();
  if (include != null &&
      include.isNotEmpty &&
      !options.contains(include)) {
    options.add(include);
  }
  return options;
}

/// Seçili bedende stoğu > 0 olan cinsiyetler (gendered ürünler için).
List<ListingGender> listingInStockGenderOptions(
  ListingModel? listing, {
  String? size,
  ListingGender? includeGender,
}) {
  if (listing == null ||
      listing.stockGenderMode != ListingGenderMode.gendered) {
    return const [ListingGender.unisex];
  }

  final normalized = size?.trim();
  final options = <ListingGender>[];
  for (final gender in [ListingGender.male, ListingGender.female]) {
    if (normalized == null || normalized.isEmpty) {
      // Beden seçilmeden: herhangi bir bedende stok varsa cinsiyeti göster
      final hasAny = listingSizeOptions(listing).any(
        (s) => listingStockFor(listing, size: s, gender: gender) > 0,
      );
      if (hasAny) options.add(gender);
    } else if (listingStockFor(listing, size: normalized, gender: gender) > 0) {
      options.add(gender);
    }
  }

  if (includeGender != null &&
      includeGender != ListingGender.unisex &&
      !options.contains(includeGender)) {
    options.add(includeGender);
  }
  return options;
}

/// CSV hücresini kaçış karakterleriyle güvenli hale getirir.
String csvCell(Object? value) {
  final text = value?.toString() ?? '';
  if (text.contains(';') || text.contains('"') || text.contains('\n')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

/// Türkçe Excel uyumlu CSV satırı (noktalı virgül ayraçlı).
String csvRow(List<Object?> cells) => cells.map(csvCell).join(';');
