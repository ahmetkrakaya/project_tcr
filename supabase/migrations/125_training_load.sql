-- ============================================================
-- 125: Training Load (CTL / ATL / TSB) - Koc Antrenman Yuku Paneli
-- ============================================================
-- Sadece kosu (running) aktiviteleri dikkate alinir.
-- TSS hesabi:
--   1) rTSS  : VDOT esik tempo tabanli  (birincil)
--   2) hrTSS : kalp atisi tabanli       (yedek, VDOT yoksa)
--   3) NULL  : ikisi de yoksa yuk disi
-- CTL (fitness, tau=42), ATL (yorgunluk, tau=7), TSB = CTL_dun - ATL_dun
-- ============================================================

-- ------------------------------------------------------------
-- 1) users.threshold_pace_seconds + VDOT'tan turetme
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS threshold_pace_seconds INTEGER;

COMMENT ON COLUMN public.users.threshold_pace_seconds IS
    'VDOT''tan turetilen esik (threshold) tempo (saniye/km). %88 VO2max yogunlugu.';

-- VDOT -> esik tempo (sn/km). Jack Daniels ters formulu (vdot_calculator.dart ile ayni).
CREATE OR REPLACE FUNCTION public.compute_threshold_pace(p_vdot NUMERIC)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_vo2        NUMERIC;
    v_a          NUMERIC := 0.000104;
    v_b          NUMERIC := 0.182258;
    v_c          NUMERIC;
    v_disc       NUMERIC;
    v_velocity   NUMERIC; -- m/min
BEGIN
    IF p_vdot IS NULL OR p_vdot <= 0 THEN
        RETURN NULL;
    END IF;

    v_vo2 := p_vdot * 0.88;
    v_c := -4.60 - v_vo2;
    v_disc := v_b * v_b - 4 * v_a * v_c;
    IF v_disc < 0 THEN
        RETURN NULL;
    END IF;

    v_velocity := (-v_b + sqrt(v_disc)) / (2 * v_a);
    IF v_velocity <= 0 THEN
        RETURN NULL;
    END IF;

    -- pace (sn/km) = (1000 / velocity) * 60
    RETURN round((1000.0 / v_velocity) * 60.0)::INTEGER;
END;
$$;

-- VDOT degisince esik tempoyu otomatik guncelle
CREATE OR REPLACE FUNCTION public.sync_threshold_pace()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.threshold_pace_seconds := public.compute_threshold_pace(NEW.vdot);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_threshold_pace ON public.users;
CREATE TRIGGER trg_sync_threshold_pace
    BEFORE INSERT OR UPDATE OF vdot ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.sync_threshold_pace();

-- Mevcut VDOT'lu kullanicilar icin backfill
UPDATE public.users
SET threshold_pace_seconds = public.compute_threshold_pace(vdot)
WHERE vdot IS NOT NULL AND vdot > 0;

-- ------------------------------------------------------------
-- 2) run_tss(): tek aktivitenin antrenman yuku (TSS)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.run_tss(
    p_duration_seconds   INTEGER,
    p_avg_pace_seconds   INTEGER,
    p_threshold_pace_seconds INTEGER,
    p_avg_heart_rate     INTEGER,
    p_birth_date         DATE
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_hours  NUMERIC;
    v_if     NUMERIC;
    v_age    NUMERIC;
    v_max_hr NUMERIC;
    v_lthr   NUMERIC;
BEGIN
    IF p_duration_seconds IS NULL OR p_duration_seconds <= 0 THEN
        RETURN NULL;
    END IF;
    v_hours := p_duration_seconds / 3600.0;

    -- 1) rTSS (VDOT esik tempo tabanli)
    IF p_threshold_pace_seconds IS NOT NULL AND p_threshold_pace_seconds > 0
       AND p_avg_pace_seconds IS NOT NULL AND p_avg_pace_seconds > 0 THEN
        -- pace dusukse (saniye) daha hizli -> IF = esik / ortalama
        v_if := p_threshold_pace_seconds::NUMERIC / p_avg_pace_seconds::NUMERIC;
        v_if := least(v_if, 1.5); -- absurt degerleri kirp
        RETURN round((v_if * v_if) * v_hours * 100.0, 1);
    END IF;

    -- 2) hrTSS (kalp atisi tabanli yedek)
    IF p_avg_heart_rate IS NOT NULL AND p_avg_heart_rate > 0
       AND p_birth_date IS NOT NULL THEN
        v_age := EXTRACT(YEAR FROM age(p_birth_date));
        IF v_age <= 0 OR v_age > 100 THEN
            RETURN NULL;
        END IF;
        v_max_hr := 208 - 0.7 * v_age;          -- Tanaka
        v_lthr   := 0.88 * v_max_hr;            -- laktat esigi HR yaklasik
        IF v_lthr <= 0 THEN
            RETURN NULL;
        END IF;
        v_if := p_avg_heart_rate::NUMERIC / v_lthr;
        v_if := least(v_if, 1.3);
        RETURN round((v_if * v_if) * v_hours * 100.0, 1);
    END IF;

    RETURN NULL;
END;
$$;

-- ------------------------------------------------------------
-- 3) Yetki yardimcisi: admin VEYA coach
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_admin_or_coach()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ok BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM public.user_roles ur
        WHERE ur.user_id = auth.uid()
          AND ur.role IN ('super_admin', 'coach')
    ) INTO v_ok;

    IF NOT v_ok THEN
        RAISE EXCEPTION 'Bu islem sadece admin veya koclar icindir';
    END IF;
END;
$$;

-- ------------------------------------------------------------
-- 4) get_athlete_training_load(): gunluk TSS + CTL/ATL/TSB serisi
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_athlete_training_load(
    p_user_id UUID,
    p_days    INTEGER DEFAULT 90
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_self    BOOLEAN;
    v_is_coach   BOOLEAN;
    v_warmup     INTEGER := 42;           -- CTL'nin oturmasi icin on isinma penceresi
    v_start      DATE;
    v_window     DATE;
    v_thr        INTEGER;
    v_birth      DATE;
    v_ctl        NUMERIC := 0;
    v_atl        NUMERIC := 0;
    v_tsb        NUMERIC := 0;
    v_result     JSONB := '[]'::jsonb;
    rec          RECORD;
BEGIN
    v_is_self := (auth.uid() = p_user_id);
    SELECT EXISTS (
        SELECT 1 FROM public.user_roles ur
        WHERE ur.user_id = auth.uid()
          AND ur.role IN ('super_admin', 'coach')
    ) INTO v_is_coach;

    IF NOT (v_is_self OR v_is_coach) THEN
        RAISE EXCEPTION 'Bu veriye erisim yetkiniz yok';
    END IF;

    IF p_days IS NULL OR p_days <= 0 THEN
        p_days := 90;
    END IF;

    v_window := CURRENT_DATE - (p_days - 1);
    v_start  := v_window - v_warmup;

    SELECT threshold_pace_seconds, birth_date
    INTO v_thr, v_birth
    FROM public.users WHERE id = p_user_id;

    FOR rec IN
        SELECT
            gs::date AS d,
            COALESCE(t.tss, 0)::NUMERIC AS day_tss
        FROM generate_series(v_start, CURRENT_DATE, INTERVAL '1 day') gs
        LEFT JOIN (
            SELECT
                (a.start_time AT TIME ZONE 'UTC')::date AS d,
                SUM(public.run_tss(
                    a.duration_seconds,
                    a.average_pace_seconds,
                    v_thr,
                    a.average_heart_rate,
                    v_birth
                )) AS tss
            FROM public.activities a
            WHERE a.user_id = p_user_id
              AND a.activity_type = 'running'
              AND (a.start_time AT TIME ZONE 'UTC')::date >= v_start
            GROUP BY 1
        ) t ON t.d = gs::date
        ORDER BY gs
    LOOP
        -- TSB dunku CTL/ATL farki
        v_tsb := v_ctl - v_atl;
        v_ctl := v_ctl + (rec.day_tss - v_ctl) / 42.0;
        v_atl := v_atl + (rec.day_tss - v_atl) / 7.0;

        IF rec.d >= v_window THEN
            v_result := v_result || jsonb_build_object(
                'date', to_char(rec.d, 'YYYY-MM-DD'),
                'tss',  round(rec.day_tss, 1),
                'ctl',  round(v_ctl, 1),
                'atl',  round(v_atl, 1),
                'tsb',  round(v_tsb, 1)
            );
        END IF;
    END LOOP;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_athlete_training_load(UUID, INTEGER) TO authenticated;

-- ------------------------------------------------------------
-- 5) get_coach_training_load_overview(): sporcu basi guncel durum
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_coach_training_load_overview(
    p_group_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_warmup  INTEGER := 90;
    v_start   DATE := CURRENT_DATE - v_warmup;
    v_result  JSONB := '[]'::jsonb;
    u         RECORD;
    rec       RECORD;
    v_ctl     NUMERIC;
    v_atl     NUMERIC;
    v_acute   NUMERIC;   -- son 7 gun toplam TSS
    v_prev    NUMERIC;   -- onceki 7 gun (8-14 gun once) toplam TSS
    v_chronic NUMERIC;   -- son 28 gun toplam TSS
    v_acwr    NUMERIC;
    v_ramp    NUMERIC;
    v_status  TEXT;
    v_km7     NUMERIC;   -- son 7 gun mesafe (km)
BEGIN
    PERFORM public.assert_admin_or_coach();

    FOR u IN
        SELECT
            usr.id,
            TRIM(CONCAT(COALESCE(usr.first_name, ''), ' ', COALESCE(usr.last_name, ''))) AS full_name,
            usr.avatar_url,
            usr.threshold_pace_seconds,
            usr.birth_date
        FROM public.users usr
        WHERE usr.user_status = 'active'
          AND (
              p_group_id IS NULL
              OR EXISTS (
                  SELECT 1 FROM public.group_members gm
                  WHERE gm.user_id = usr.id AND gm.group_id = p_group_id
              )
          )
          AND EXISTS (
              SELECT 1 FROM public.activities a
              WHERE a.user_id = usr.id
                AND a.activity_type = 'running'
                AND (a.start_time AT TIME ZONE 'UTC')::date >= v_start
          )
    LOOP
        v_ctl := 0;
        v_atl := 0;

        -- Gunluk EWMA (CTL/ATL) son 90 gun
        FOR rec IN
            SELECT
                gs::date AS d,
                COALESCE(t.tss, 0)::NUMERIC AS day_tss
            FROM generate_series(v_start, CURRENT_DATE, INTERVAL '1 day') gs
            LEFT JOIN (
                SELECT
                    (a.start_time AT TIME ZONE 'UTC')::date AS d,
                    SUM(public.run_tss(
                        a.duration_seconds,
                        a.average_pace_seconds,
                        u.threshold_pace_seconds,
                        a.average_heart_rate,
                        u.birth_date
                    )) AS tss
                FROM public.activities a
                WHERE a.user_id = u.id
                  AND a.activity_type = 'running'
                  AND (a.start_time AT TIME ZONE 'UTC')::date >= v_start
                GROUP BY 1
            ) t ON t.d = gs::date
            ORDER BY gs
        LOOP
            v_ctl := v_ctl + (rec.day_tss - v_ctl) / 42.0;
            v_atl := v_atl + (rec.day_tss - v_atl) / 7.0;
        END LOOP;

        -- Akut / kronik yukler ve mesafe
        SELECT
            COALESCE(SUM(public.run_tss(a.duration_seconds, a.average_pace_seconds,
                        u.threshold_pace_seconds, a.average_heart_rate, u.birth_date))
                     FILTER (WHERE (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 7), 0),
            COALESCE(SUM(public.run_tss(a.duration_seconds, a.average_pace_seconds,
                        u.threshold_pace_seconds, a.average_heart_rate, u.birth_date))
                     FILTER (WHERE (a.start_time AT TIME ZONE 'UTC')::date <= CURRENT_DATE - 7
                             AND (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 14), 0),
            COALESCE(SUM(public.run_tss(a.duration_seconds, a.average_pace_seconds,
                        u.threshold_pace_seconds, a.average_heart_rate, u.birth_date))
                     FILTER (WHERE (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 28), 0),
            COALESCE(SUM(a.distance_meters)
                     FILTER (WHERE (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 7), 0) / 1000.0
        INTO v_acute, v_prev, v_chronic, v_km7
        FROM public.activities a
        WHERE a.user_id = u.id
          AND a.activity_type = 'running'
          AND (a.start_time AT TIME ZONE 'UTC')::date > CURRENT_DATE - 28;

        -- ACWR = akut(7g) / kronik(28g haftalik ortalama)
        IF v_chronic > 0 THEN
            v_acwr := round(v_acute / (v_chronic / 4.0), 2);
        ELSE
            v_acwr := NULL;
        END IF;

        -- Haftalik ramp %
        IF v_prev > 0 THEN
            v_ramp := round((v_acute - v_prev) / v_prev * 100.0, 0);
        ELSE
            v_ramp := NULL;
        END IF;

        -- Durum bayragi (ACWR oncelikli, sonra TSB)
        IF v_acwr IS NULL THEN
            v_status := 'unknown';
        ELSIF v_acwr > 1.5 OR v_acwr < 0.5 THEN
            v_status := 'risk';
        ELSIF v_acwr > 1.3 OR v_acwr < 0.8 THEN
            v_status := 'warning';
        ELSE
            v_status := 'ok';
        END IF;

        v_result := v_result || jsonb_build_object(
            'user_id',    u.id,
            'full_name',  CASE WHEN length(u.full_name) > 0 THEN u.full_name ELSE 'Isimsiz' END,
            'avatar_url', u.avatar_url,
            'ctl',        round(v_ctl, 1),
            'atl',        round(v_atl, 1),
            'tsb',        round(v_ctl - v_atl, 1),
            'acute_7d',   round(v_acute, 0),
            'chronic_28d',round(v_chronic, 0),
            'acwr',       v_acwr,
            'ramp_pct',   v_ramp,
            'distance_7d_km', round(v_km7, 1),
            'status',     v_status
        );
    END LOOP;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_coach_training_load_overview(UUID) TO authenticated;
