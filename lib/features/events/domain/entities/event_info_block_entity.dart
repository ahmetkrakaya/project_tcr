/// Event Info Block Entity - Notion benzeri dinamik içerik blokları
class EventInfoBlockEntity {
  final String id;
  final String eventId;
  final EventInfoBlockType type;
  final String content;
  final String? subContent;
  final String? color;
  final String? icon;
  final int orderIndex;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const EventInfoBlockEntity({
    required this.id,
    required this.eventId,
    required this.type,
    required this.content,
    this.subContent,
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
enum EventInfoBlockType {
  /// Ana başlık (Tarih başlığı gibi: "CUMARTESİ 04.04.2026")
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
  divider;

  static EventInfoBlockType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'header':
        return EventInfoBlockType.header;
      case 'subheader':
        return EventInfoBlockType.subheader;
      case 'schedule_item':
        return EventInfoBlockType.scheduleItem;
      case 'warning':
        return EventInfoBlockType.warning;
      case 'info':
        return EventInfoBlockType.info;
      case 'tip':
        return EventInfoBlockType.tip;
      case 'text':
        return EventInfoBlockType.text;
      case 'quote':
        return EventInfoBlockType.quote;
      case 'list_item':
        return EventInfoBlockType.listItem;
      case 'checklist_item':
        return EventInfoBlockType.checklistItem;
      case 'divider':
        return EventInfoBlockType.divider;
      default:
        return EventInfoBlockType.text;
    }
  }

  String toDbString() {
    switch (this) {
      case EventInfoBlockType.header:
        return 'header';
      case EventInfoBlockType.subheader:
        return 'subheader';
      case EventInfoBlockType.scheduleItem:
        return 'schedule_item';
      case EventInfoBlockType.warning:
        return 'warning';
      case EventInfoBlockType.info:
        return 'info';
      case EventInfoBlockType.tip:
        return 'tip';
      case EventInfoBlockType.text:
        return 'text';
      case EventInfoBlockType.quote:
        return 'quote';
      case EventInfoBlockType.listItem:
        return 'list_item';
      case EventInfoBlockType.checklistItem:
        return 'checklist_item';
      case EventInfoBlockType.divider:
        return 'divider';
    }
  }

  String get displayName {
    switch (this) {
      case EventInfoBlockType.header:
        return 'Başlık';
      case EventInfoBlockType.subheader:
        return 'Alt Başlık';
      case EventInfoBlockType.scheduleItem:
        return 'Program Öğesi';
      case EventInfoBlockType.warning:
        return 'Uyarı';
      case EventInfoBlockType.info:
        return 'Bilgi';
      case EventInfoBlockType.tip:
        return 'İpucu';
      case EventInfoBlockType.text:
        return 'Metin';
      case EventInfoBlockType.quote:
        return 'Alıntı';
      case EventInfoBlockType.listItem:
        return 'Liste Öğesi';
      case EventInfoBlockType.checklistItem:
        return 'Kontrol Öğesi';
      case EventInfoBlockType.divider:
        return 'Ayırıcı';
    }
  }

  String get defaultColor {
    switch (this) {
      case EventInfoBlockType.header:
        return '#1E3A5F'; // Primary
      case EventInfoBlockType.subheader:
        return '#3D5A80'; // Primary Light
      case EventInfoBlockType.scheduleItem:
        return '#2E7D32'; // Secondary (Yeşil)
      case EventInfoBlockType.warning:
        return '#D32F2F'; // Error (Kırmızı)
      case EventInfoBlockType.info:
        return '#1976D2'; // Info (Mavi)
      case EventInfoBlockType.tip:
        return '#388E3C'; // Success (Yeşil)
      case EventInfoBlockType.text:
        return '#424242'; // Neutral
      case EventInfoBlockType.quote:
        return '#7B1FA2'; // Purple
      case EventInfoBlockType.listItem:
        return '#FF5722'; // Tertiary (Turuncu)
      case EventInfoBlockType.checklistItem:
        return '#2E7D32'; // Secondary
      case EventInfoBlockType.divider:
        return '#BDBDBD'; // Neutral 400
    }
  }

  String get defaultIcon {
    switch (this) {
      case EventInfoBlockType.header:
        return '📅';
      case EventInfoBlockType.subheader:
        return '📌';
      case EventInfoBlockType.scheduleItem:
        return '⏰';
      case EventInfoBlockType.warning:
        return '⚠️';
      case EventInfoBlockType.info:
        return 'ℹ️';
      case EventInfoBlockType.tip:
        return '💡';
      case EventInfoBlockType.text:
        return '';
      case EventInfoBlockType.quote:
        return '💬';
      case EventInfoBlockType.listItem:
        return '•';
      case EventInfoBlockType.checklistItem:
        return '☐';
      case EventInfoBlockType.divider:
        return '';
    }
  }
}
