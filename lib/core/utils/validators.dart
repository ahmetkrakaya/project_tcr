class Validators {
  Validators._();

  /// Email doğrulama
  static String? email(String? value) {
    if (value == null || value.isEmpty) {
      return 'E-posta adresi gerekli';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Geçerli bir e-posta adresi girin';
    }
    return null;
  }

  /// Telefon numarası doğrulama
  static String? phone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Telefon numarası gerekli';
    }
    final cleaned = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (!RegExp(r'^[0-9]{10,11}$').hasMatch(cleaned)) {
      return 'Geçerli bir telefon numarası girin';
    }
    return null;
  }

  /// İsim doğrulama
  static String? name(String? value) {
    if (value == null || value.isEmpty) {
      return 'Bu alan gerekli';
    }
    if (value.length < 2) {
      return 'En az 2 karakter olmalı';
    }
    if (value.length > 50) {
      return 'En fazla 50 karakter olabilir';
    }
    return null;
  }

  /// Zorunlu alan doğrulama
  static String? required(String? value, [String? fieldName]) {
    if (value == null || value.isEmpty) {
      return fieldName != null ? '$fieldName gerekli' : 'Bu alan gerekli';
    }
    return null;
  }

  /// Minimum uzunluk doğrulama
  static String? Function(String?) minLength(int min) {
    return (String? value) {
      if (value == null || value.isEmpty) {
        return null; // required validator'ı kontrol eder
      }
      if (value.length < min) {
        return 'En az $min karakter olmalı';
      }
      return null;
    };
  }

  /// Maximum uzunluk doğrulama
  static String? Function(String?) maxLength(int max) {
    return (String? value) {
      if (value == null || value.isEmpty) {
        return null;
      }
      if (value.length > max) {
        return 'En fazla $max karakter olabilir';
      }
      return null;
    };
  }

  /// Sayı doğrulama
  static String? number(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    if (double.tryParse(value) == null) {
      return 'Geçerli bir sayı girin';
    }
    return null;
  }

  /// Pozitif sayı doğrulama
  static String? positiveNumber(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final number = double.tryParse(value);
    if (number == null) {
      return 'Geçerli bir sayı girin';
    }
    if (number <= 0) {
      return 'Pozitif bir sayı girin';
    }
    return null;
  }

  /// Fiyat doğrulama
  static String? price(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final price = double.tryParse(value);
    if (price == null) {
      return 'Geçerli bir fiyat girin';
    }
    if (price < 0) {
      return 'Fiyat negatif olamaz';
    }
    return null;
  }

  /// Referans kodu doğrulama
  static String? referralCode(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Opsiyonel
    }
    if (value.length != 6) {
      return 'Referans kodu 6 karakter olmalı';
    }
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(value.toUpperCase())) {
      return 'Geçersiz referans kodu';
    }
    return null;
  }

  /// Ayakkabı numarası doğrulama
  static String? shoeSize(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final size = double.tryParse(value);
    if (size == null) {
      return 'Geçerli bir numara girin';
    }
    if (size < 30 || size > 50) {
      return 'Numara 30-50 arasında olmalı';
    }
    return null;
  }

  /// Birden fazla validator birleştirme
  static String? Function(String?) combine(List<String? Function(String?)> validators) {
    return (String? value) {
      for (final validator in validators) {
        final result = validator(value);
        if (result != null) {
          return result;
        }
      }
      return null;
    };
  }

  /// URL doğrulama
  static String? url(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      final uri = Uri.parse(value);
      if (!uri.isAbsolute || (!uri.scheme.startsWith('http'))) {
        return 'Geçerli bir URL girin';
      }
    } catch (_) {
      return 'Geçerli bir URL girin';
    }
    return null;
  }
}
