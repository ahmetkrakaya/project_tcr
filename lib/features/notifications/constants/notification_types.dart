import 'package:flutter/material.dart';

/// Bildirim türü sabitleri (veritabanı type ile uyumlu)
class NotificationTypes {
  NotificationTypes._();

  static const String eventCreated = 'event_created';
  static const String eventUpdated = 'event_updated';
  static const String carpoolApplication = 'carpool_application';
  static const String carpoolApplicationResponse = 'carpool_application_response';
  static const String eventChatMessage = 'event_chat_message';
  static const String postCreated = 'post_created';
  static const String postUpdated = 'post_updated';
  static const String listingCreated = 'listing_created';
  static const String orderCreated = 'order_created';
  static const String orderStatusChanged = 'order_status_changed';
  static const String newMemberPending = 'new_member_pending';

  static const List<String> all = [
    eventCreated,
    eventUpdated,
    carpoolApplication,
    carpoolApplicationResponse,
    eventChatMessage,
    postCreated,
    postUpdated,
    listingCreated,
    orderCreated,
    orderStatusChanged,
    newMemberPending,
  ];

  static String label(String type) {
    switch (type) {
      case eventCreated:
        return 'Etkinlik oluşturuldu';
      case eventUpdated:
        return 'Etkinlik güncellendi';
      case carpoolApplication:
        return 'Ortak araç başvurusu';
      case carpoolApplicationResponse:
        return 'Ortak araç başvuru yanıtı';
      case eventChatMessage:
        return 'Etkinlik sohbeti';
      case postCreated:
        return 'Yeni duyuru';
      case postUpdated:
        return 'Duyuru güncellendi';
      case listingCreated:
        return 'Yeni ürün';
      case orderCreated:
        return 'Yeni sipariş';
      case orderStatusChanged:
        return 'Sipariş durumu';
      case newMemberPending:
        return 'Yeni üye başvurusu';
      default:
        return type;
    }
  }
}

/// Ayarlar sayfasında tek switch ile kontrol edilen bildirim kategorileri.
/// Her kategori kapalıyken o gruba ait tüm bildirim türleri kapatılır.
class NotificationCategories {
  NotificationCategories._();

  static const String event = 'event';
  static const String carpool = 'carpool';
  static const String chat = 'chat';
  static const String post = 'post';
  static const String market = 'market';

  static const List<String> all = [event, carpool, chat, post, market];

  static List<String> typesForCategory(String categoryId) {
    switch (categoryId) {
      case event:
        return [NotificationTypes.eventCreated, NotificationTypes.eventUpdated];
      case carpool:
        return [
          NotificationTypes.carpoolApplication,
          NotificationTypes.carpoolApplicationResponse,
        ];
      case chat:
        return [NotificationTypes.eventChatMessage];
      case post:
        return [NotificationTypes.postCreated, NotificationTypes.postUpdated];
      case market:
        return [
          NotificationTypes.listingCreated,
          NotificationTypes.orderCreated,
          NotificationTypes.orderStatusChanged,
        ];
      default:
        return [];
    }
  }

  static String label(String categoryId) {
    switch (categoryId) {
      case event:
        return 'Etkinlik';
      case carpool:
        return 'Ortak Yolculuk';
      case chat:
        return 'Sohbet';
      case post:
        return 'Duyuru (Post)';
      case market:
        return 'Market';
      default:
        return categoryId;
    }
  }

  static IconData icon(String categoryId) {
    switch (categoryId) {
      case event:
        return Icons.event;
      case carpool:
        return Icons.directions_car;
      case chat:
        return Icons.chat_bubble_outline;
      case post:
        return Icons.article_outlined;
      case market:
        return Icons.shopping_bag_outlined;
      default:
        return Icons.notifications_none;
    }
  }
}
