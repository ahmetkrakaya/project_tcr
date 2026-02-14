# Bildirim Başlık ve İçerik Nerede Tutuluyor?

Bildirimlerin **başlık** ve **içerik (body)** metinleri **Supabase tarafında** üretilir. Uygulama (Flutter) sadece veritabanından gelen `title` ve `body` alanlarını gösterir; metinleri kendisi üretmez.

---

## 1. Veritabanı (Supabase)

- **Tablo:** `public.notifications`
- **Alanlar:** `title` (TEXT), `body` (TEXT), `type`, `data`, vb.
- Tablo şeması: `supabase/migrations/051_notifications.sql`

Kayıtlar bu tabloya **trigger’lar** ile yazılır. Her bildirim türü için hangi tetikleyicinin çalıştığı ve başlık/içeriğin nasıl set edildiği aşağıda.

---

## 2. Başlık ve İçeriğin Yazıldığı Yer: Trigger’lar

Tüm bildirim metinleri **tek bir SQL dosyasında** tanımlı:

**Dosya:** `supabase/migrations/052_notification_triggers.sql`

Bu dosyada her bildirim türü için `insert_notifications(..., p_title, p_body, ...)` çağrılır. Başlık ve body’yi değiştirmek için ilgili trigger fonksiyonundaki `v_title` / body parametresini düzenlemeniz yeterli.

Aşağıda tür bazında **mevcut başlık ve içerik** özeti var.

---

### Etkinlik (oluşturuldu / güncellendi)

| Alan   | Değer |
|--------|--------|
| Başlık | Etkinlik adı |
| İçerik | Etkinlik tarihi (DD.MM.YYYY HH24:MI) + "· Katılımını bekliyoruz." |

- **Fonksiyon:** `notify_on_event_change()`
- **Trigger:** `on_event_notify` (events tablosu, INSERT/UPDATE)

---

### Duyuru (post – yeni / güncelleme)

| Alan   | Değer |
|--------|--------|
| Başlık | Post adı |
| İçerik | Yeni: `Yeni post yayınlandı.` — Güncelleme: `Duyuru güncellendi.` (sabit metin, bloklardan özet alınmıyor) |

- **Fonksiyon:** `notify_on_post_change()`
- **Trigger:** `on_post_notify` (posts tablosu, INSERT/UPDATE)

---

### Yeni ürün (marketplace)

| Alan   | Değer |
|--------|--------|
| Başlık | `Yeni Ürün: ` + ürün adı |
| İçerik | `Yeni ürünü kaçırma! Listede seni bekliyor.` |

- **Fonksiyon:** `notify_on_listing_created()`
- **Trigger:** `on_listing_created_notify` (marketplace_listings, INSERT)

---

### Yeni sipariş (admin/coach’a)

| Alan   | Değer |
|--------|--------|
| Başlık | `Yeni Sipariş Alındı` |
| İçerik | Ürün adı + ` için sipariş verildi.` |

- **Fonksiyon:** `notify_on_order_created()`
- **Trigger:** `on_order_created_notify` (marketplace_orders, INSERT)

---

### Sipariş durumu (alıcıya)

| Alan   | Değer |
|--------|--------|
| Başlık | `Siparişinizin durumu güncellendi` |
| İçerik | Ürün adı + `. Siparişiniz onaylandı/iptal edildi/tamamlandı.` |

- **Fonksiyon:** `notify_on_order_status_changed()`
- **Trigger:** `on_order_status_notify` (marketplace_orders, UPDATE)

---

### Ortak araç başvurusu (sürücüye)

| Alan   | Değer |
|--------|--------|
| Başlık | Etkinlik adı |
| İçerik | Başvuran ismi + ` ortak yolculuk başvurusu yaptı.` |

- **Fonksiyon:** `notify_on_carpool_request_insert()`
- **Trigger:** `on_carpool_request_insert_notify` (carpool_requests, INSERT)

---

### Ortak araç başvuru yanıtı (yolcuya)

| Alan   | Değer |
|--------|--------|
| Başlık | Etkinlik adı |
| İçerik | `Ortak yolculuk başvurunuz kabul edildi.` / `Ortak yolculuk başvurunuz reddedildi.` |

- **Fonksiyon:** `notify_on_carpool_request_status()`
- **Trigger:** `on_carpool_request_status_notify` (carpool_requests, UPDATE)

---

### Etkinlik sohbeti (mesaj)

| Alan   | Değer |
|--------|--------|
| Başlık | Etkinlik adı |
| İçerik | Gönderen adı + `: ` + mesajın ilk 80 karakteri (gönderen yoksa "Bir katılımcı") |

- **Fonksiyon:** `notify_on_event_chat_message()`
- **Trigger:** `on_event_chat_message_notify` (chat_messages, INSERT)

---

## 3. Başlık / İçeriği Nasıl Değiştirirsiniz?

1. **Supabase’te kalıcı değişiklik (önerilen)**  
   - `supabase/migrations/052_notification_triggers.sql` dosyasında ilgili fonksiyonu bulun.  
   - `v_title` ve/veya `insert_notifications(..., v_title, body_ifade, ...)` satırlarındaki metinleri düzenleyin.  
   - Yeni bir migration oluşturup sadece değiştirdiğiniz `CREATE OR REPLACE FUNCTION ...` blok(lar)ını ekleyebilirsiniz; böylece mevcut migration geçmişi bozulmaz.

2. **Push bildirimler**  
   - Edge Function `send-push-on-notification`, veritabanına yazılan kaydın `title` ve `body` alanını olduğu gibi FCM’e gönderir.  
   - Trigger’da `title`/`body`’yi değiştirdiğinizde push metinleri de otomatik güncellenir.

3. **Uygulama tarafı (Flutter)**  
   - `lib/features/notifications/` altında sadece **gösterim** var; bildirim metinleri burada **üretilmez**.  
   - Liste ekranı `NotificationModel.title` ve `NotificationModel.body` ile API’den gelen değerleri aynen kullanır.

---

## 4. Kısa Özet

| Nerede? | Ne var? |
|--------|---------|
| **Supabase** | Bildirim kayıtları (`notifications` tablosu) ve başlık/içeriği üreten **trigger’lar** (`052_notification_triggers.sql`). |
| **Flutter** | Sadece bu kayıtları çekip liste/detayda gösterme; başlık/body metni üretilmez. |
| **Push** | `send-push-on-notification` fonksiyonu, aynı `title`/`body`’yi FCM’e iletir. |

Başlık ve içerik metinlerini değiştirmek için **Supabase** tarafında `052_notification_triggers.sql` (veya bu fonksiyonları güncelleyen yeni migration) içindeki ilgili trigger fonksiyonlarını düzenlemeniz yeterli.
