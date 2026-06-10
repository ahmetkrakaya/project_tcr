-- ============================================================
-- 107: RSVP hatırlatma pencereleri
--
-- Sorun: Geç oluşturulan etkinliklerde 48h/24h/12h hatırlatmaları
-- aynı cron turunda üst üste gidiyordu.
--
-- Çözüm:
-- 1. 48 saatlik RSVP hatırlatması kaldırıldı
-- 2. 24h hatırlatma yalnızca [T-24h, T-12h) penceresinde
-- 3. 12h hatırlatma yalnızca [T-12h, T-start) penceresinde
-- 4. Oluşturulduğunda başlangıca <24h kaldıysa 24h gitmez
-- 5. Oluşturulduğunda başlangıca <12h kaldıysa 12h gitmez
-- Alıcı mantığı değişmedi (get_event_created_recipients, tüm türler).
-- ============================================================

CREATE OR REPLACE FUNCTION public.send_scheduled_event_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
BEGIN
    -- event_created hatırlatması (1 gün önce)
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND start_time > NOW()
          AND (start_time - INTERVAL '1 day') <= NOW()
          AND event_reminder_sent_at IS NULL
    LOOP
        PERFORM public.send_event_reminder(v_event.id);
    END LOOP;

    -- RSVP hatırlatması: 24 saat önce ([T-24h, T-12h) penceresi)
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND start_time > NOW()
          AND (start_time - INTERVAL '24 hours') <= NOW()
          AND (start_time - INTERVAL '12 hours') > NOW()
          AND created_at <= (start_time - INTERVAL '24 hours')
          AND rsvp_reminder_24h_sent_at IS NULL
    LOOP
        PERFORM public.send_rsvp_reminder(v_event.id, 24, 'rsvp_reminder_24h_sent_at');
    END LOOP;

    -- RSVP hatırlatması: 12 saat önce ([T-12h, T-start) penceresi)
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND start_time > NOW()
          AND (start_time - INTERVAL '12 hours') <= NOW()
          AND created_at <= (start_time - INTERVAL '12 hours')
          AND rsvp_reminder_12h_sent_at IS NULL
    LOOP
        PERFORM public.send_rsvp_reminder(v_event.id, 12, 'rsvp_reminder_12h_sent_at');
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.send_scheduled_event_reminders() IS
  'Zamanlanmış etkinlik bildirimleri: event_created (T-1 gün), RSVP hatırlatmaları (T-24h ve T-12h, pencereli).';
