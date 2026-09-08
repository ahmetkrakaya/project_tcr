-- ============================================================
-- Kişisel doğum günü kutlaması
-- Her rol için: doğum günü olan kullanıcıya aynı gün
-- TCR'dan kişisel kutlama bildirimi gider.
--
-- Mevcut admin hatırlatması (check_upcoming_birthdays) aynen kalır:
-- yalnızca super_admin doğum günleri → yalnızca adminlere, 2 gün önce.
-- ============================================================

CREATE OR REPLACE FUNCTION public.send_personal_birthday_wishes()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  birthday_user RECORD;
  first_name_clean TEXT;
  title_text TEXT;
  body_text TEXT;
  today_date DATE;
BEGIN
  -- Supabase CURRENT_DATE (UTC); mevcut birthday cron ile aynı referans
  today_date := CURRENT_DATE;

  FOR birthday_user IN
    SELECT u.id, u.first_name, u.birth_date
    FROM public.users u
    WHERE u.is_active = true
      AND COALESCE(u.user_status, 'active') = 'active'
      AND u.birth_date IS NOT NULL
      AND EXTRACT(MONTH FROM u.birth_date) = EXTRACT(MONTH FROM today_date)
      AND EXTRACT(DAY FROM u.birth_date) = EXTRACT(DAY FROM today_date)
  LOOP
    -- Aynı gün tekrar göndermeyi önle
    IF EXISTS (
      SELECT 1
      FROM public.notifications
      WHERE user_id = birthday_user.id
        AND type = 'birthday_wish'
        AND created_at::date = today_date
    ) THEN
      CONTINUE;
    END IF;

    first_name_clean := TRIM(COALESCE(birthday_user.first_name, ''));
    title_text := 'Doğum Günün Kutlu Olsun 🎂';

    IF first_name_clean <> '' THEN
      body_text :=
        'Sevgili ' || first_name_clean ||
        ', TCR ailesi olarak doğum gününü en içten dileklerle kutluyoruz. İyi ki varsın!';
    ELSE
      body_text :=
        'TCR ailesi olarak doğum gününü en içten dileklerle kutluyoruz. İyi ki varsın!';
    END IF;

    INSERT INTO public.notifications (user_id, type, title, body, data)
    VALUES (
      birthday_user.id,
      'birthday_wish',
      title_text,
      body_text,
      jsonb_build_object(
        'birth_date', birthday_user.birth_date::text,
        'kind', 'personal_wish'
      )
    );
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.send_personal_birthday_wishes() IS
  'Doğum günü bugün olan aktif kullanıcılara kişisel TCR kutlama bildirimi gönderir.';

-- Aynı saatte (16:00 UTC / TR 19:00) kişisel kutlamaları da çalıştır
DO $$
BEGIN
  PERFORM cron.unschedule('send-personal-birthday-wishes');
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

SELECT cron.schedule(
  'send-personal-birthday-wishes',
  '0 16 * * *',
  'SELECT public.send_personal_birthday_wishes()'
);
