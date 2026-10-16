-- TCR Migration 163: Manuel etkinlik satışı üyeyi katılımcı listesine de ekler
-- Admin başka bir kullanıcı için event_participants'a yazamaz (RLS: auth.uid() = user_id).
-- Bu yüzden satış kaydı oluşunca SECURITY DEFINER trigger katılımcıyı going olarak upsert eder.

CREATE OR REPLACE FUNCTION public.sync_participant_from_event_sale()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.source <> 'manual' OR NEW.status = 'cancelled' THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.event_participants (event_id, user_id, status, responded_at)
    VALUES (NEW.event_id, NEW.user_id, 'going', NOW())
    ON CONFLICT (event_id, user_id) DO UPDATE SET
        status = 'going',
        responded_at = NOW();

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.sync_participant_from_event_sale() IS
    'Manuel satışa bağlı üyeyi etkinlik katılımcısı (going) olarak ekler veya günceller.';

DROP TRIGGER IF EXISTS trg_sync_participant_from_event_sale ON public.event_sales;
CREATE TRIGGER trg_sync_participant_from_event_sale
    AFTER INSERT ON public.event_sales
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_participant_from_event_sale();
