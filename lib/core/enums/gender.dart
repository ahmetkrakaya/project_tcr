enum ListingGender {
  male('male'),
  female('female'),
  unisex('unisex');

  final String value;
  const ListingGender(this.value);

  static ListingGender fromString(String value) {
    return ListingGender.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ListingGender.unisex,
    );
  }
}

enum ListingGenderMode {
  unisex('unisex'),
  gendered('gendered');

  final String value;
  const ListingGenderMode(this.value);

  static ListingGenderMode fromString(String value) {
    return ListingGenderMode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ListingGenderMode.unisex,
    );
  }
}

