-- 046: Guest (misafir) katılımcılar için destek ekle
-- Uygulamada üyeliği olmayan veya etkinliğe kayıt olmamış kişilerin sonuçlarını da ekleyebilmek için

-- Guest kayıtları için alanlar ekle
ALTER TABLE public.event_results
ADD COLUMN IF NOT EXISTS guest_name TEXT,
ADD COLUMN IF NOT EXISTS guest_gender TEXT;

-- Guest kayıtları için index (sıralama için)
CREATE INDEX IF NOT EXISTS idx_event_results_guest_name
    ON public.event_results(event_id, guest_name)
    WHERE guest_name IS NOT NULL;

-- get_event_results fonksiyonunu güncelle - guest_name varsa onu göster
CREATE OR REPLACE FUNCTION public.get_event_results(event_uuid UUID)
RETURNS TABLE (
    result_id UUID,
    event_id UUID,
    user_id UUID,
    full_name TEXT,
    avatar_url TEXT,
    gender TEXT,
    finish_time_seconds INTEGER,
    rank_overall INTEGER,
    rank_gender INTEGER,
    notes TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        er.id AS result_id,
        er.event_id,
        er.user_id,
        -- Guest kaydıysa guest_name'i göster, değilse kullanıcı adını
        COALESCE(er.guest_name, COALESCE(u.first_name || ' ' || u.last_name, u.email)) AS full_name,
        -- Guest kaydıysa avatar yok
        CASE WHEN er.guest_name IS NOT NULL THEN NULL ELSE u.avatar_url END AS avatar_url,
        -- Guest kaydıysa guest_gender'i göster, değilse er.gender veya u.gender
        COALESCE(er.guest_gender, er.gender, u.gender) AS gender,
        er.finish_time_seconds,
        er.rank_overall,
        er.rank_gender,
        er.notes
    FROM public.event_results er
    LEFT JOIN public.users u ON u.id = er.user_id
    WHERE er.event_id = event_uuid
    ORDER BY 
        er.finish_time_seconds NULLS LAST,
        er.rank_overall NULLS LAST;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
