import 'package:quick_actions/quick_actions.dart';

/// App icon quick action shortcut type'ları (quick_actions ShortcutItem type ile aynı).
class AppShortcutTypes {
  AppShortcutTypes._();

  static const String createEvent = 'shortcut_create_event';
  static const String createPost = 'shortcut_create_post';
  static const String events = 'shortcut_events';
  static const String marketplace = 'shortcut_marketplace';
}

QuickActions? _quickActionsInstance;

/// Main'de çağrılır: QuickActions instance'ını kaydeder ve kısayol tıklanınca
/// type'ı pending olarak set eder.
void initAppShortcuts(QuickActions quickActions) {
  _quickActionsInstance = quickActions;
  quickActions.initialize((String shortcutType) {
    setPendingShortcutType(shortcutType);
  });
}

/// Rol bazlı kısayol listesini platforma set eder. Mobil değilse no-op.
void setAppShortcutItems(List<ShortcutItem> items) {
  _quickActionsInstance?.setShortcutItems(items);
}

/// Cold start veya login sonrası yönlendirilecek kısayol type'ı.
String? _pendingShortcutType;

void setPendingShortcutType(String type) {
  _pendingShortcutType = type;
}

/// Bekleyen kısayol type'ını döndürür ve temizler. Splash / Login'de tüketilir.
String? takePendingShortcutType() {
  final type = _pendingShortcutType;
  _pendingShortcutType = null;
  return type;
}

/// Kısayol type'ını GoRouter path'ine çevirir. Bilinmeyen type için null döner.
String? shortcutTypeToPath(String? type) {
  if (type == null) return null;
  switch (type) {
    case AppShortcutTypes.createEvent:
      return '/events/create';
    case AppShortcutTypes.createPost:
      return '/home/create-post';
    case AppShortcutTypes.events:
      return '/events';
    case AppShortcutTypes.marketplace:
      return '/marketplace';
    default:
      return null;
  }
}
