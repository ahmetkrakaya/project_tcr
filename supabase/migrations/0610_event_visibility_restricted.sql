-- 061: Event visibility & per-user access

-- Yeni sütun: etkinlik görünürlüğü
-- public  : herkes (mevcut davranış)
-- restricted : sadece event_visible_users tablosundaki kullanıcılar
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'public'
  CHECK (visibility IN ('public', 'restricted'));

-- Özel görünürlük tablosu
CREATE TABLE IF NOT EXISTS public.event_visible_users (
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (event_id, user_id)
);

ALTER TABLE public.event_visible_users ENABLE ROW LEVEL SECURITY;

-- Kullanıcı kendi kayıtlarını görebilsin (debug / yardımcı sorgular için)
DROP POLICY IF EXISTS "Users can view own event_visible_users"
  ON public.event_visible_users;

CREATE POLICY "Users can view own event_visible_users"
  ON public.event_visible_users
  FOR SELECT
  USING (auth.uid() = user_id);

-- Etkinliği oluşturan kullanıcı görünürlük listesini yönetebilsin
DROP POLICY IF EXISTS "Event creator can manage event_visible_users"
  ON public.event_visible_users;

CREATE POLICY "Event creator can manage event_visible_users"
  ON public.event_visible_users
  FOR ALL
  USING (
    EXISTS (
      SELECT 1
      FROM public.events e
      WHERE e.id = event_id
        AND e.created_by = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.events e
      WHERE e.id = event_id
        AND e.created_by = auth.uid()
    )
  );

-- notify_on_event_change fonksiyonunu visibility alanını dikkate alacak şekilde güncelle
CREATE OR REPLACE FUNCTION public.notify_on_event_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recipient_ids UUID[];
    v_notification_type TEXT;
    v_title TEXT;
    v_body TEXT;
    v_data JSONB;
BEGIN
    -- Sadece yayınlanmış etkinlikler için
    IF NEW.status != 'published' THEN
        RETURN NEW;
    END IF;

    v_data := jsonb_build_object('event_id', NEW.id);
    v_title := trim(NEW.title);
    -- İçerik: etkinlik tarihi + kısa metin (örn. "15.02.2026 09:00 · Katılımını bekliyoruz.")
    v_body := to_char(NEW.start_time AT TIME ZONE 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') || ' · Katılımını bekliyoruz.';

    IF TG_OP = 'INSERT' THEN
        v_notification_type := 'event_created';
    ELSE
        v_notification_type := 'event_updated';
    END IF;

    -- Bireysel antrenman: bildirim yok
    IF NEW.event_type = 'training' AND NEW.participation_type = 'individual' THEN
        RETURN NEW;
    END IF;

    -- Özel (restricted) etkinlikler: sadece event_visible_users içindeki kullanıcılara gönder
    IF NEW.visibility = 'restricted' THEN
        SELECT ARRAY_AGG(evu.user_id)
        INTO v_recipient_ids
        FROM public.event_visible_users evu
        WHERE evu.event_id = NEW.id;

        IF v_recipient_ids IS NULL
           OR array_length(v_recipient_ids, 1) IS NULL
           OR array_length(v_recipient_ids, 1) = 0 THEN
          RETURN NEW;
        END IF;

        PERFORM public.insert_notifications(
            v_notification_type,
            v_title,
            v_body,
            v_data,
            v_recipient_ids
        );
        RETURN NEW;
    END IF;

    -- Ekip antrenmanı (training + team): event_group_programs'taki grupların üyeleri
    IF NEW.event_type = 'training' AND NEW.participation_type = 'team' THEN
        SELECT ARRAY_AGG(DISTINCT gm.user_id)
        INTO v_recipient_ids
        FROM public.event_group_programs egp
        JOIN public.group_members gm ON gm.group_id = egp.training_group_id
        WHERE egp.event_id = NEW.id;
        IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
            PERFORM public.insert_notifications(
                v_notification_type,
                v_title,
                v_body,
                v_data,
                v_recipient_ids
            );
        END IF;
        RETURN NEW;
    END IF;

    -- Diğer etkinlik türleri (race, social, workshop, other): tüm aktif kullanıcılar
    SELECT ARRAY_AGG(id) INTO v_recipient_ids
    FROM public.users
    WHERE is_active = true;
    IF v_recipient_ids IS NOT NULL AND array_length(v_recipient_ids, 1) > 0 THEN
        PERFORM public.insert_notifications(
            v_notification_type,
            v_title,
            v_body,
            v_data,
            v_recipient_ids
        );
    END IF;
    RETURN NEW;
END;
$$;

-- notify_on_event_group_program_insert fonksiyonunu visibility restricted için event_visible_users'a göre filtrele
CREATE OR REPLACE FUNCTION public.notify_on_event_group_program_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event RECORD;
    v_recipient_ids UUID[];
    v_title TEXT;
    v_body TEXT;
    v_data JSONB;
BEGIN
    -- Etkinlik bilgisi: yayınlanmış, antrenman, ekip olmalı
    SELECT id, title, start_time, status, event_type, participation_type, visibility
    INTO v_event
    FROM public.events
    WHERE id = NEW.event_id;

    IF v_event.id IS NULL THEN
        RETURN NEW;
    END IF;
    IF v_event.status != 'published' THEN
        RETURN NEW;
    END IF;
    IF v_event.event_type != 'training' OR v_event.participation_type != 'team' THEN
        RETURN NEW;
    END IF;

    v_data := jsonb_build_object('event_id', v_event.id);
    v_title := trim(v_event.title);
    v_body := to_char(v_event.start_time AT TIME ZONE 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') || ' · Katılımını bekliyoruz.';

    -- Özel (restricted) etkinlikler: sadece event_visible_users
    IF v_event.visibility = 'restricted' THEN
        SELECT ARRAY_AGG(evu.user_id)
        INTO v_recipient_ids
        FROM public.event_visible_users evu
        WHERE evu.event_id = v_event.id;
    ELSE
        -- Bu grubun üyeleri (group_members.group_id = training_group_id)
        SELECT ARRAY_AGG(gm.user_id)
        INTO v_recipient_ids
        FROM public.group_members gm
        WHERE gm.group_id = NEW.training_group_id;
    END IF;

    IF v_recipient_ids IS NULL
       OR array_length(v_recipient_ids, 1) IS NULL
       OR array_length(v_recipient_ids, 1) = 0 THEN
        RETURN NEW;
    END IF;

    PERFORM public.insert_notifications(
        'event_created',
        v_title,
        v_body,
        v_data,
        v_recipient_ids
    );

    RETURN NEW;
END;
$$;

