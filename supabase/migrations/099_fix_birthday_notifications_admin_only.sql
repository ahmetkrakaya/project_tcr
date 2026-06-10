-- ============================================================
-- Fix: Birthday notifications should trigger only for admins
-- İstek: Sadece admin (super_admin) kullanıcıların doğum günü yaklaşınca,
--        bildirim sadece adminlere gitsin.
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

  -- Doğum günü tam 2 gün sonra olan *admin (super_admin)* ve aktif kullanıcıları bul
  -- (Ay ve gün eşleştirmesi, yıl dikkate alınmaz)
  FOR birthday_user IN
    SELECT u.id, u.first_name, u.last_name, u.birth_date
    FROM public.users u
    WHERE u.is_active = true
      AND u.birth_date IS NOT NULL
      AND EXTRACT(MONTH FROM u.birth_date) = EXTRACT(MONTH FROM target_date)
      AND EXTRACT(DAY FROM u.birth_date) = EXTRACT(DAY FROM target_date)
      AND EXISTS (
        SELECT 1
        FROM public.user_roles ur
        WHERE ur.user_id = u.id
          AND ur.role = 'super_admin'
      )
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

