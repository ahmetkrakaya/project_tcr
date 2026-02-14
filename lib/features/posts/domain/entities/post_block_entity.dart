/// Post Block Entity - Notion benzeri dinamik içerik blokları
class PostBlockEntity {
  final String id;
  final String postId;
  final PostBlockType type;
  final String content;
  final String? subContent;
  final String? imageUrl;
  final String? color;
  final String? icon;
  final int orderIndex;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const PostBlockEntity({
    required this.id,
    required this.postId,
    required this.type,
    required this.content,
    this.subContent,
    this.imageUrl,
    this.color,
    this.icon,
    required this.orderIndex,
    required this.createdAt,
    this.updatedAt,
  });

  /// Blok rengini döndür (hex string'den Color'a dönüştürme UI'da yapılacak)
  String get displayColor => color ?? type.defaultColor;
}

/// Blok türleri
enum PostBlockType {
  /// Ana başlık
  header,

  /// Alt başlık
  subheader,

  /// Zaman çizelgesi öğesi (10:00-19:00 Kit Dağıtımı)
  scheduleItem,

  /// Uyarı kutusu (Kırmızı - Önemli uyarılar)
  warning,

  /// Bilgi kutusu (Mavi)
  info,

  /// Başarı/İpucu kutusu (Yeşil)
  tip,

  /// Normal metin paragrafı
  text,

  /// Alıntı
  quote,

  /// Liste öğesi
  listItem,

  /// Kontrol listesi öğesi
  checklistItem,

  /// Ayırıcı çizgi
  divider,

  /// Görsel
  image,

  /// Yarış sonuçları
  raceResults;

  static PostBlockType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'header':
        return PostBlockType.header;
      case 'subheader':
        return PostBlockType.subheader;
      case 'schedule_item':
        return PostBlockType.scheduleItem;
      case 'warning':
        return PostBlockType.warning;
      case 'info':
        return PostBlockType.info;
      case 'tip':
        return PostBlockType.tip;
      case 'text':
        return PostBlockType.text;
      case 'quote':
        return PostBlockType.quote;
      case 'list_item':
        return PostBlockType.listItem;
      case 'checklist_item':
        return PostBlockType.checklistItem;
      case 'divider':
        return PostBlockType.divider;
      case 'image':
        return PostBlockType.image;
      case 'race_results':
        return PostBlockType.raceResults;
      default:
        return PostBlockType.text;
    }
  }

  String toDbString() {
    switch (this) {
      case PostBlockType.header:
        return 'header';
      case PostBlockType.subheader:
        return 'subheader';
      case PostBlockType.scheduleItem:
        return 'schedule_item';
      case PostBlockType.warning:
        return 'warning';
      case PostBlockType.info:
        return 'info';
      case PostBlockType.tip:
        return 'tip';
      case PostBlockType.text:
        return 'text';
      case PostBlockType.quote:
        return 'quote';
      case PostBlockType.listItem:
        return 'list_item';
      case PostBlockType.checklistItem:
        return 'checklist_item';
      case PostBlockType.divider:
        return 'divider';
      case PostBlockType.image:
        return 'image';
      case PostBlockType.raceResults:
        return 'race_results';
    }
  }

  String get displayName {
    switch (this) {
      case PostBlockType.header:
        return 'Başlık';
      case PostBlockType.subheader:
        return 'Alt Başlık';
      case PostBlockType.scheduleItem:
        return 'Program Öğesi';
      case PostBlockType.warning:
        return 'Uyarı';
      case PostBlockType.info:
        return 'Bilgi';
      case PostBlockType.tip:
        return 'İpucu';
      case PostBlockType.text:
        return 'Metin';
      case PostBlockType.quote:
        return 'Alıntı';
      case PostBlockType.listItem:
        return 'Liste Öğesi';
      case PostBlockType.checklistItem:
        return 'Kontrol Öğesi';
      case PostBlockType.divider:
        return 'Ayırıcı';
      case PostBlockType.image:
        return 'Görsel';
      case PostBlockType.raceResults:
        return 'Yarış Sonuçları';
    }
  }

  String get defaultColor {
    switch (this) {
      case PostBlockType.header:
        return '#1E3A5F'; // Primary
      case PostBlockType.subheader:
        return '#3D5A80'; // Primary Light
      case PostBlockType.scheduleItem:
        return '#2E7D32'; // Secondary (Yeşil)
      case PostBlockType.warning:
        return '#D32F2F'; // Error (Kırmızı)
      case PostBlockType.info:
        return '#1976D2'; // Info (Mavi)
      case PostBlockType.tip:
        return '#388E3C'; // Success (Yeşil)
      case PostBlockType.text:
        return '#424242'; // Neutral
      case PostBlockType.quote:
        return '#7B1FA2'; // Purple
      case PostBlockType.listItem:
        return '#FF5722'; // Tertiary (Turuncu)
      case PostBlockType.checklistItem:
        return '#2E7D32'; // Secondary
      case PostBlockType.divider:
        return '#BDBDBD'; // Neutral 400
      case PostBlockType.image:
        return '#424242'; // Neutral
      case PostBlockType.raceResults:
        return '#1E3A5F'; // Primary
    }
  }

  String get defaultIcon {
    switch (this) {
      case PostBlockType.header:
        return '📅';
      case PostBlockType.subheader:
        return '📌';
      case PostBlockType.scheduleItem:
        return '⏰';
      case PostBlockType.warning:
        return '⚠️';
      case PostBlockType.info:
        return 'ℹ️';
      case PostBlockType.tip:
        return '💡';
      case PostBlockType.text:
        return '';
      case PostBlockType.quote:
        return '💬';
      case PostBlockType.listItem:
        return '•';
      case PostBlockType.checklistItem:
        return '☐';
      case PostBlockType.divider:
        return '';
      case PostBlockType.image:
        return '🖼️';
      case PostBlockType.raceResults:
        return '🏆';
    }
  }
}
