-- ============================================================
-- 134: RSVP hatırlatması yalnızca etkinlikten 2 saat önce
--
-- - 24h / 12h (ve kullanılmayan 48h) kademeli hatırlatmalar kaldırıldı
-- - Zamanlama start_time (timestamptz) − 2 saat ile NOW() karşılaştırması;
--   sunucu saat diliminden bağımsız, etkinliğin gerçek başlangıcına göre
-- - Yayınlandığında başlangıca 2 saatten az kaldıysa hatırlatma gitmez
-- ============================================================

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS rsvp_reminder_2h_sent_at TIMESTAMPTZ;

COMMENT ON COLUMN public.events.rsvp_reminder_2h_sent_at IS
  'RSVP hatırlatması (etkinlik başlangıcından 2 saat önce) gönderildiğinde set edilir';

CREATE OR REPLACE FUNCTION public.send_rsvp_reminder(
    p_event_id UUID,
    p_hours_before INT,
    p_sent_column TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
    v_all_recipients UUID[];
    v_responded_users UUID[];
    v_pending_users UUID[];
    v_reminder_at TIMESTAMPTZ;
    v_title TEXT;
    v_body TEXT;
    v_data JSONB;
BEGIN
    SELECT id, title, start_time, status
    INTO v_event
    FROM public.events
    WHERE id = p_event_id;

    IF v_event.id IS NULL OR v_event.status != 'published' THEN
        RETURN;
    END IF;

    v_reminder_at := v_event.start_time - make_interval(hours => p_hours_before);

    -- Etkinlik başlangıcına göre pencere: [T-N saat, T-start)
    IF NOW() >= v_event.start_time OR NOW() < v_reminder_at THEN
        RETURN;
    END IF;

    v_all_recipients := public.get_event_created_recipients(p_event_id);
    IF v_all_recipients IS NULL OR array_length(v_all_recipients, 1) IS NULL THEN
        RETURN;
    END IF;

    SELECT ARRAY_AGG(ep.user_id)
    INTO v_responded_users
    FROM public.event_participants ep
    WHERE ep.event_id = p_event_id
      AND ep.status IN ('going', 'not_going');

    IF v_responded_users IS NOT NULL THEN
        SELECT ARRAY_AGG(uid)
        INTO v_pending_users
        FROM unnest(v_all_recipients) AS uid
        WHERE uid != ALL(v_responded_users);
    ELSE
        v_pending_users := v_all_recipients;
    END IF;

    IF v_pending_users IS NULL OR array_length(v_pending_users, 1) IS NULL THEN
        RETURN;
    END IF;

    v_data := jsonb_build_object('event_id', v_event.id);
    v_title := trim(v_event.title);
    v_body := to_char(
        v_event.start_time AT TIME ZONE 'Europe/Istanbul',
        'DD.MM.YYYY HH24:MI'
    ) || ' · Katılımını henüz bildirmedin.';

    PERFORM public.insert_notifications(
        'event_rsvp_reminder',
        v_title,
        v_body,
        v_data,
        v_pending_users
    );

    EXECUTE format('UPDATE public.events SET %I = NOW() WHERE id = $1', p_sent_column)
    USING p_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.send_scheduled_event_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
BEGIN
    -- RSVP hatırlatması: start_time'dan tam 2 saat önce ([T-2h, T-start) penceresi)
    FOR v_event IN
        SELECT id
        FROM public.events
        WHERE status = 'published'
          AND start_time > NOW()
          AND (start_time - INTERVAL '2 hours') <= NOW()
          AND created_at <= (start_time - INTERVAL '2 hours')
          AND rsvp_reminder_2h_sent_at IS NULL
    LOOP
        PERFORM public.send_rsvp_reminder(v_event.id, 2, 'rsvp_reminder_2h_sent_at');
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.send_scheduled_event_reminders() IS
  'RSVP hatırlatması: etkinlik start_time değerine göre 2 saat önce (timestamptz).';

-- Daha sık cron: 2 saatlik hedefe yaklaşmak için (en fazla ~4 dk gecikme)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('send-event-reminders');
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;

    PERFORM cron.schedule(
      'send-event-reminders',
      '*/4 * * * *',
      'SELECT public.send_scheduled_event_reminders()'
    );
  END IF;
END
$$;
