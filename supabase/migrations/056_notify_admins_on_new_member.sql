-- =====================================================
-- 056: Yeni üye başvurusu – Admin bildirimi
-- =====================================================
-- public.users'a onay bekleyen (is_active = false) yeni kayıt eklendiğinde
-- tüm super_admin'lere uygulama içi bildirim + push (webhook ile) gider.

CREATE OR REPLACE FUNCTION public.notify_admins_on_new_member()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recipient_ids UUID[];
    v_title TEXT := 'Yeni üye başvurusu';
    v_body TEXT;
    v_data JSONB;
BEGIN
    -- Sadece onay bekleyen (pasif) yeni üye için bildirim
    IF NEW.is_active = true THEN
        RETURN NEW;
    END IF;

    -- Tüm super_admin kullanıcı ID'leri
    SELECT ARRAY_AGG(user_id)
    INTO v_recipient_ids
    FROM public.user_roles
    WHERE role = 'super_admin';

    IF v_recipient_ids IS NULL OR array_length(v_recipient_ids, 1) IS NULL OR array_length(v_recipient_ids, 1) = 0 THEN
        RETURN NEW;
    END IF;

    -- Body: isteğe bağlı olarak yeni üye adı/email bilgisi
    v_body := 'Onay bekleyen bir üye var. Üyeler sayfasından onaylayabilirsiniz.';
    IF trim(COALESCE(NEW.first_name, '') || ' ' || COALESCE(NEW.last_name, '')) IS NOT NULL AND trim(COALESCE(NEW.first_name, '') || ' ' || COALESCE(NEW.last_name, '')) != '' THEN
        v_body := trim(COALESCE(NEW.first_name, '') || ' ' || COALESCE(NEW.last_name, '')) || ' üyelik başvurusu yaptı. Üyeler sayfasından onaylayabilirsiniz.';
    ELSIF NEW.email IS NOT NULL AND NEW.email != '' THEN
        v_body := NEW.email || ' üyelik başvurusu yaptı. Üyeler sayfasından onaylayabilirsiniz.';
    END IF;

    v_data := jsonb_build_object('pending_user_id', NEW.id);

    PERFORM public.insert_notifications(
        'new_member_pending',
        v_title,
        v_body,
        v_data,
        v_recipient_ids
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_insert_user_notify_admins ON public.users;
CREATE TRIGGER after_insert_user_notify_admins
    AFTER INSERT ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.notify_admins_on_new_member();

COMMENT ON FUNCTION public.notify_admins_on_new_member() IS 'Yeni üye (is_active=false) eklendiğinde super_admin''lere new_member_pending bildirimi gönderir; push mevcut webhook ile gider.';
