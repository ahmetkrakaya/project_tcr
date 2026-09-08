-- ============================================================
-- 150: Genel kullanıcı puan sistemi
--
-- Kurallar:
--   - Yarış (race): km başına 1 puan (ör. 21 km → 21 puan)
--   - Antrenman (training): katılım başına 1 puan
--   - Diğer etkinlik türleri: katılım başına 2 puan
--   - Market siparişi: ürün tutarının %5'i (yuvarlanmış)
--
-- Eski Strava bant puanları (5K→5000 vb.) kaldırılır; geçmiş
-- katılımlar ve siparişler yeni kurallarla backfill edilir.
-- Bundan sonraki katılımlar/siparişler trigger ile otomatik puanlanır.
-- ============================================================

-- pg_cron (eski job'u kaldırmak için)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ============================================================
-- 1) user_points ledger
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_points (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    points INTEGER NOT NULL CHECK (points >= 0),
    source_type TEXT NOT NULL CHECK (
        source_type IN ('event_participation', 'marketplace_order')
    ),
    event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
    order_id UUID REFERENCES public.marketplace_orders(id) ON DELETE CASCADE,
    distance_km DECIMAL(10, 2),
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT user_points_source_refs CHECK (
        (
            source_type = 'event_participation'
            AND event_id IS NOT NULL
            AND order_id IS NULL
        )
        OR (
            source_type = 'marketplace_order'
            AND order_id IS NOT NULL
            AND event_id IS NULL
        )
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_points_user_event
    ON public.user_points (user_id, event_id)
    WHERE event_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_points_order
    ON public.user_points (order_id)
    WHERE order_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_user_points_user_id
    ON public.user_points (user_id);

CREATE INDEX IF NOT EXISTS idx_user_points_source_type
    ON public.user_points (source_type);

ALTER TABLE public.user_points ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view user points" ON public.user_points;
CREATE POLICY "Anyone can view user points"
    ON public.user_points
    FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Only backend can manage user points" ON public.user_points;
CREATE POLICY "Only backend can manage user points"
    ON public.user_points
    FOR ALL
    USING (current_user NOT IN ('anon', 'authenticated'))
    WITH CHECK (current_user NOT IN ('anon', 'authenticated'));

-- ============================================================
-- 2) Yardımcı hesaplama fonksiyonları
-- ============================================================

-- "21K", "5k", "42.2 km" gibi etiketlerden km çıkar
CREATE OR REPLACE FUNCTION public.parse_distance_km_from_label(label TEXT)
RETURNS DECIMAL
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    cleaned TEXT;
    parsed DECIMAL;
BEGIN
    IF label IS NULL OR btrim(label) = '' THEN
        RETURN NULL;
    END IF;

    cleaned := regexp_replace(label, '[^0-9.,]', '', 'g');
    cleaned := replace(cleaned, ',', '.');

    IF cleaned IS NULL OR cleaned = '' OR cleaned = '.' THEN
        RETURN NULL;
    END IF;

    BEGIN
        parsed := cleaned::DECIMAL;
    EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
    END;

    IF parsed <= 0 OR parsed > 500 THEN
        RETURN NULL;
    END IF;

    RETURN parsed;
END;
$$;

-- Yarış mesafesini çöz: variant → seçili rota → etkinlik rotası → Strava (aynı gün)
CREATE OR REPLACE FUNCTION public.resolve_race_distance_km(
    p_user_id UUID,
    p_event_id UUID,
    p_race_variant_label TEXT DEFAULT NULL,
    p_selected_route_id UUID DEFAULT NULL
)
RETURNS DECIMAL
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_km DECIMAL;
    v_event_date DATE;
    v_route_id UUID;
BEGIN
    v_km := public.parse_distance_km_from_label(p_race_variant_label);
    IF v_km IS NOT NULL THEN
        RETURN v_km;
    END IF;

    IF p_selected_route_id IS NOT NULL THEN
        SELECT r.total_distance INTO v_km
        FROM public.routes r
        WHERE r.id = p_selected_route_id;

        IF v_km IS NOT NULL AND v_km > 0 THEN
            RETURN v_km;
        END IF;
    END IF;

    SELECT e.route_id, (e.start_time AT TIME ZONE 'Europe/Istanbul')::date
    INTO v_route_id, v_event_date
    FROM public.events e
    WHERE e.id = p_event_id;

    IF v_route_id IS NOT NULL THEN
        SELECT r.total_distance INTO v_km
        FROM public.routes r
        WHERE r.id = v_route_id;

        IF v_km IS NOT NULL AND v_km > 0 THEN
            RETURN v_km;
        END IF;
    END IF;

    -- Fallback: etkinlik günündeki en uzun Strava koşusu
    IF v_event_date IS NOT NULL THEN
        SELECT ROUND((a.distance_meters / 1000.0)::numeric, 2)
        INTO v_km
        FROM public.activities a
        WHERE a.user_id = p_user_id
          AND a.source = 'strava'
          AND a.activity_type = 'running'
          AND a.distance_meters IS NOT NULL
          AND (a.start_time AT TIME ZONE 'Europe/Istanbul')::date = v_event_date
        ORDER BY a.distance_meters DESC
        LIMIT 1;

        IF v_km IS NOT NULL AND v_km > 0 THEN
            RETURN v_km;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

-- Etkinlik türüne göre puan
CREATE OR REPLACE FUNCTION public.calculate_event_participation_points(
    p_event_type public.event_type,
    p_distance_km DECIMAL DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_event_type = 'race' THEN
        IF p_distance_km IS NULL OR p_distance_km <= 0 THEN
            RETURN 0;
        END IF;
        RETURN GREATEST(ROUND(p_distance_km)::INTEGER, 0);
    ELSIF p_event_type = 'training' THEN
        RETURN 1;
    ELSE
        -- social, workshop, other
        RETURN 2;
    END IF;
END;
$$;

-- Sipariş tutarının %5'i
CREATE OR REPLACE FUNCTION public.calculate_order_points(p_total_price DECIMAL)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_total_price IS NULL OR p_total_price <= 0 THEN
        RETURN 0;
    END IF;
    RETURN GREATEST(ROUND(p_total_price * 0.05)::INTEGER, 0);
END;
$$;

-- ============================================================
-- 3) Puan yazma / silme
-- ============================================================
CREATE OR REPLACE FUNCTION public.upsert_event_participation_points(
    p_user_id UUID,
    p_event_id UUID,
    p_race_variant_label TEXT DEFAULT NULL,
    p_selected_route_id UUID DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event_type public.event_type;
    v_distance_km DECIMAL;
    v_points INTEGER;
    v_note TEXT;
BEGIN
    SELECT e.event_type INTO v_event_type
    FROM public.events e
    WHERE e.id = p_event_id;

    IF v_event_type IS NULL THEN
        RETURN;
    END IF;

    IF v_event_type = 'race' THEN
        v_distance_km := public.resolve_race_distance_km(
            p_user_id,
            p_event_id,
            p_race_variant_label,
            p_selected_route_id
        );
        v_points := public.calculate_event_participation_points(v_event_type, v_distance_km);
        v_note := CASE
            WHEN v_distance_km IS NOT NULL THEN format('Yarış: %s km', v_distance_km)
            ELSE 'Yarış: mesafe bulunamadı'
        END;
    ELSIF v_event_type = 'training' THEN
        v_points := 1;
        v_note := 'Antrenman katılımı';
        v_distance_km := NULL;
    ELSE
        v_points := 2;
        v_note := format('Etkinlik katılımı (%s)', v_event_type::text);
        v_distance_km := NULL;
    END IF;

    IF v_points <= 0 THEN
        DELETE FROM public.user_points
        WHERE user_id = p_user_id
          AND event_id = p_event_id
          AND source_type = 'event_participation';
        RETURN;
    END IF;

    UPDATE public.user_points
    SET
        points = v_points,
        distance_km = v_distance_km,
        note = v_note,
        updated_at = NOW()
    WHERE user_id = p_user_id
      AND event_id = p_event_id
      AND source_type = 'event_participation';

    IF NOT FOUND THEN
        INSERT INTO public.user_points (
            user_id, points, source_type, event_id, distance_km, note
        )
        VALUES (
            p_user_id, v_points, 'event_participation', p_event_id, v_distance_km, v_note
        );
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_event_participation_points(
    p_user_id UUID,
    p_event_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM public.user_points
    WHERE user_id = p_user_id
      AND event_id = p_event_id
      AND source_type = 'event_participation';
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_order_points(
    p_order_id UUID,
    p_buyer_id UUID,
    p_total_price DECIMAL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_points INTEGER;
BEGIN
    v_points := public.calculate_order_points(p_total_price);

    IF v_points <= 0 THEN
        DELETE FROM public.user_points
        WHERE order_id = p_order_id
          AND source_type = 'marketplace_order';
        RETURN;
    END IF;

    UPDATE public.user_points
    SET
        user_id = p_buyer_id,
        points = v_points,
        note = format('Market siparişi: yüzde 5 (%s TL)', p_total_price),
        updated_at = NOW()
    WHERE order_id = p_order_id
      AND source_type = 'marketplace_order';

    IF NOT FOUND THEN
        INSERT INTO public.user_points (
            user_id, points, source_type, order_id, note
        )
        VALUES (
            p_buyer_id,
            v_points,
            'marketplace_order',
            p_order_id,
            format('Market siparişi: yüzde 5 (%s TL)', p_total_price)
        );
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_order_points(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM public.user_points
    WHERE order_id = p_order_id
      AND source_type = 'marketplace_order';
END;
$$;

-- ============================================================
-- 4) Trigger'lar (otomatik puan)
-- ============================================================
CREATE OR REPLACE FUNCTION public.trg_award_event_participation_points()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.remove_event_participation_points(OLD.user_id, OLD.event_id);
        RETURN OLD;
    END IF;

    IF NEW.status = 'going' THEN
        PERFORM public.upsert_event_participation_points(
            NEW.user_id,
            NEW.event_id,
            NEW.race_variant_label,
            NEW.selected_route_id
        );
    ELSE
        PERFORM public.remove_event_participation_points(NEW.user_id, NEW.event_id);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_event_participant_points ON public.event_participants;
CREATE TRIGGER on_event_participant_points
    AFTER INSERT OR DELETE OR UPDATE OF status, race_variant_label, selected_route_id
    ON public.event_participants
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_award_event_participation_points();

CREATE OR REPLACE FUNCTION public.trg_award_order_points()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.remove_order_points(OLD.id);
        RETURN OLD;
    END IF;

    IF NEW.status = 'cancelled' THEN
        PERFORM public.remove_order_points(NEW.id);
    ELSE
        PERFORM public.upsert_order_points(NEW.id, NEW.buyer_id, NEW.total_price);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_marketplace_order_points ON public.marketplace_orders;
CREATE TRIGGER on_marketplace_order_points
    AFTER INSERT OR DELETE OR UPDATE OF status, total_price, buyer_id
    ON public.marketplace_orders
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_award_order_points();

-- ============================================================
-- 5) Toplam puan RPC
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_user_total_points(target_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    total INTEGER;
BEGIN
    SELECT COALESCE(SUM(points), 0)
    INTO total
    FROM public.user_points
    WHERE user_id = target_user_id;

    RETURN total;
END;
$$;

-- ============================================================
-- 6) get_person_360: yeni tablodan oku
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_person_360(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile     JSONB;
    v_stats       JSONB;
    v_points      INTEGER;
    v_strava      BOOLEAN;
    v_group_name  TEXT;
    v_last_open   TIMESTAMPTZ;
    v_recent      JSONB;
    v_load        JSONB;
BEGIN
    IF p_user_id IS DISTINCT FROM auth.uid() THEN
        PERFORM public.assert_admin_or_coach();
    END IF;

    SELECT jsonb_build_object(
        'user_id', u.id,
        'full_name', TRIM(CONCAT(COALESCE(u.first_name, ''), ' ', COALESCE(u.last_name, ''))),
        'avatar_url', u.avatar_url,
        'vdot', u.vdot,
        'threshold_pace_seconds', u.threshold_pace_seconds
    ), u.last_app_open_at
    INTO v_profile, v_last_open
    FROM public.users u WHERE u.id = p_user_id;

    IF v_profile IS NULL THEN
        RAISE EXCEPTION 'Kullanici bulunamadi';
    END IF;

    SELECT jsonb_build_object(
        'total_distance_km', round(COALESCE(total_distance_meters, 0) / 1000.0, 1),
        'total_activities', COALESCE(total_activities, 0),
        'total_duration_seconds', COALESCE(total_duration_seconds, 0),
        'longest_run_km', round(COALESCE(longest_run_meters, 0) / 1000.0, 1),
        'this_week_km', (
            SELECT round(COALESCE(SUM(a.distance_meters), 0) / 1000.0, 1)
            FROM public.activities a
            WHERE a.user_id = p_user_id
              AND a.activity_type = 'running'
              AND a.start_time >= date_trunc('week', now())
        ),
        'this_month_km', (
            SELECT round(COALESCE(SUM(a.distance_meters), 0) / 1000.0, 1)
            FROM public.activities a
            WHERE a.user_id = p_user_id
              AND a.activity_type = 'running'
              AND a.start_time >= date_trunc('month', now())
        ),
        'last_activity_at', last_activity_at
    )
    INTO v_stats
    FROM public.user_statistics WHERE user_id = p_user_id;

    IF v_stats IS NULL THEN
        v_stats := jsonb_build_object(
            'total_distance_km', 0,
            'total_activities', 0,
            'total_duration_seconds', 0,
            'longest_run_km', 0,
            'this_week_km', (
                SELECT round(COALESCE(SUM(a.distance_meters), 0) / 1000.0, 1)
                FROM public.activities a
                WHERE a.user_id = p_user_id
                  AND a.activity_type = 'running'
                  AND a.start_time >= date_trunc('week', now())
            ),
            'this_month_km', (
                SELECT round(COALESCE(SUM(a.distance_meters), 0) / 1000.0, 1)
                FROM public.activities a
                WHERE a.user_id = p_user_id
                  AND a.activity_type = 'running'
                  AND a.start_time >= date_trunc('month', now())
            ),
            'last_activity_at', NULL
        );
    END IF;

    SELECT COALESCE(SUM(points), 0)::int INTO v_points
    FROM public.user_points WHERE user_id = p_user_id;

    SELECT EXISTS (
        SELECT 1 FROM public.user_integrations
        WHERE user_id = p_user_id AND provider = 'strava'
    ) INTO v_strava;

    SELECT g.name INTO v_group_name
    FROM public.group_members gm
    JOIN public.training_groups g ON g.id = gm.group_id
    WHERE gm.user_id = p_user_id
    LIMIT 1;

    SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.start_time DESC), '[]'::jsonb)
    INTO v_recent
    FROM (
        SELECT a.id,
               a.title,
               a.start_time,
               round(COALESCE(a.distance_meters, 0) / 1000.0, 2) AS distance_km,
               a.duration_seconds,
               a.average_pace_seconds
        FROM public.activities a
        WHERE a.user_id = p_user_id
          AND a.activity_type = 'running'
        ORDER BY a.start_time DESC
        LIMIT 5
    ) r;

    v_load := public.athlete_load_snapshot(p_user_id);

    RETURN jsonb_build_object(
        'profile', v_profile,
        'group_name', v_group_name,
        'last_app_open_at', v_last_open,
        'total_points', v_points,
        'strava_connected', v_strava,
        'statistics', COALESCE(v_stats, '{}'::jsonb),
        'training_load', v_load,
        'recent_activities', v_recent
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_person_360(UUID) TO authenticated;

-- ============================================================
-- 7) Eski Strava bant puan cron'unu kapat
-- ============================================================
DO $$
BEGIN
    PERFORM cron.unschedule('process-race-points');
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'process-race-points cron job yok veya kaldırılamadı: %', SQLERRM;
END;
$$;

-- Eski fonksiyonu no-op yap (manuel çağrı olursa zarar vermesin)
CREATE OR REPLACE FUNCTION public.process_race_points()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Eski bant puan sistemi devre dışı. Yeni sistem trigger + user_points.
    RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION public.calculate_race_points(distance_m DECIMAL)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    -- Geriye dönük uyumluluk: metre → km başına 1 puan
    IF distance_m IS NULL OR distance_m <= 0 THEN
        RETURN 0;
    END IF;
    RETURN GREATEST(ROUND(distance_m / 1000.0)::INTEGER, 0);
END;
$$;

-- ============================================================
-- 8) Geçmiş backfill
-- ============================================================
CREATE OR REPLACE FUNCTION public.backfill_user_points()
RETURNS TABLE (
    event_rows INTEGER,
    order_rows INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event_rows INTEGER := 0;
    v_order_rows INTEGER := 0;
    r RECORD;
BEGIN
    -- Eski ölçekteki puanları temizle
    DELETE FROM public.user_race_points;
    DELETE FROM public.user_points;

    FOR r IN
        SELECT
            ep.user_id,
            ep.event_id,
            ep.race_variant_label,
            ep.selected_route_id
        FROM public.event_participants ep
        WHERE ep.status = 'going'
    LOOP
        PERFORM public.upsert_event_participation_points(
            r.user_id,
            r.event_id,
            r.race_variant_label,
            r.selected_route_id
        );
        v_event_rows := v_event_rows + 1;
    END LOOP;

    FOR r IN
        SELECT o.id, o.buyer_id, o.total_price
        FROM public.marketplace_orders o
        WHERE o.status IS DISTINCT FROM 'cancelled'
    LOOP
        PERFORM public.upsert_order_points(r.id, r.buyer_id, r.total_price);
        v_order_rows := v_order_rows + 1;
    END LOOP;

    event_rows := v_event_rows;
    order_rows := v_order_rows;
    RETURN NEXT;
END;
$$;

-- Migration sırasında bir kez çalıştır
SELECT * FROM public.backfill_user_points();
