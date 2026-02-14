-- 044: Event Results - Yarış Sonuçları
-- Etkinlik bazlı yarış sonuçlarını tutan tablo ve yardımcı fonksiyon

CREATE TABLE IF NOT EXISTS public.event_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    participant_id UUID REFERENCES public.event_participants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    gender TEXT,
    finish_time_seconds INTEGER,
    rank_overall INTEGER,
    rank_gender INTEGER,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- Indexler
CREATE INDEX IF NOT EXISTS idx_event_results_event_id
    ON public.event_results(event_id);

CREATE INDEX IF NOT EXISTS idx_event_results_event_id_gender
    ON public.event_results(event_id, gender);

-- updated_at trigger
CREATE OR REPLACE FUNCTION update_event_results_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER event_results_updated_at
    BEFORE UPDATE ON public.event_results
    FOR EACH ROW EXECUTE FUNCTION update_event_results_updated_at();

-- RLS aktif et
ALTER TABLE public.event_results ENABLE ROW LEVEL SECURITY;

-- Politika: Herkes yayınlanmış/completed etkinliklerin sonuçlarını görebilir
CREATE POLICY "Anyone can view event results for completed events"
    ON public.event_results
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.events e
            WHERE e.id = event_results.event_id
              AND e.status = 'completed'
        )
    );

-- Politika: Sadece ilgili etkinliğin admin/koçları sonuç ekleyebilir/güncelleyebilir/silebilir
-- Not: Burada user_roles üzerinden super_admin/coach rollerini kontrol ediyoruz.
CREATE POLICY "Admins and coaches can manage event results"
    ON public.event_results
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles ur
            WHERE ur.user_id = auth.uid()
              AND ur.role IN ('super_admin', 'coach')
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles ur
            WHERE ur.user_id = auth.uid()
              AND ur.role IN ('super_admin', 'coach')
        )
    );

-- Yardımcı fonksiyon: Bir etkinlik için sonuçları UI dostu formatta döndür
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
        COALESCE(u.first_name || ' ' || u.last_name, u.email) AS full_name,
        u.avatar_url,
        COALESCE(er.gender, u.gender) AS gender,
        er.finish_time_seconds,
        er.rank_overall,
        er.rank_gender,
        er.notes
    FROM public.event_results er
    JOIN public.users u ON u.id = er.user_id
    WHERE er.event_id = event_uuid
    ORDER BY 
        er.finish_time_seconds NULLS LAST,
        er.rank_overall NULLS LAST;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

