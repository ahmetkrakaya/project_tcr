-- ============================================================
-- Birthday Notification System
-- Doğum günü 3 gün sonra olan kullanıcılar için
-- sadece super_admin rolüne sahip kullanıcılara bildirim oluşturur.
-- Her gün 05:00 UTC (Türkiye 08:00) cron ile çalışır.
-- ============================================================

-- pg_cron extension'ı etkinleştir (Supabase'de genelde zaten aktif)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ============================================================
-- Doğum günü kontrolü ve bildirim oluşturma fonksiyonu
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_upcoming_birthdays()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  birthday_user RECORD;
  admin_user RECORD;
  target_date DATE;
  user_full_name TEXT;
BEGIN
  -- 2 gün sonraki tarih
  target_date := CURRENT_DATE + INTERVAL '2 days';

  -- Doğum günü tam 2 gün sonra olan aktif kullanıcıları bul
  -- (Ay ve gün eşleştirmesi, yıl dikkate alınmaz)
  FOR birthday_user IN
    SELECT id, first_name, last_name, birth_date
    FROM public.users
    WHERE is_active = true
      AND birth_date IS NOT NULL
      AND EXTRACT(MONTH FROM birth_date) = EXTRACT(MONTH FROM target_date)
      AND EXTRACT(DAY FROM birth_date) = EXTRACT(DAY FROM target_date)
  LOOP
    -- Kullanıcı adını oluştur
    user_full_name := TRIM(COALESCE(birthday_user.first_name, '') || ' ' || COALESCE(birthday_user.last_name, ''));
    IF user_full_name = '' THEN
      user_full_name := 'Bir üye';
    END IF;

    -- Sadece super_admin rolüne sahip aktif kullanıcılara bildirim gönder
    FOR admin_user IN
      SELECT DISTINCT ur.user_id
      FROM public.user_roles ur
      JOIN public.users u ON u.id = ur.user_id
      WHERE ur.role = 'super_admin'
        AND u.is_active = true
    LOOP
      -- Aynı gün için aynı kullanıcıya daha önce bildirim gönderilmediyse ekle
      -- (Duplicate önleme)
      IF NOT EXISTS (
        SELECT 1
        FROM public.notifications
        WHERE user_id = admin_user.user_id
          AND type = 'birthday_reminder'
          AND data->>'user_id' = birthday_user.id::text
          AND created_at::date = CURRENT_DATE
      ) THEN
        INSERT INTO public.notifications (user_id, type, title, body, data)
        VALUES (
          admin_user.user_id,
          'birthday_reminder',
          'Doğum Günü Yaklaşıyor 🎂',
          user_full_name || '''nın doğum günü 2 gün içinde!',
          jsonb_build_object(
            'user_id', birthday_user.id,
            'user_name', user_full_name,
            'birth_date', birthday_user.birth_date::text
          )
        );
      END IF;
    END LOOP;
  END LOOP;
END;
$$;

-- ============================================================
-- Cron job: Her gün 16:00 UTC'de çalıştır (Türkiye saati 19:00)
-- ============================================================
SELECT cron.schedule(
  'check-upcoming-birthdays',
  '0 16 * * *',
  'SELECT public.check_upcoming_birthdays()'
);
