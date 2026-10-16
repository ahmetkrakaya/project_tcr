-- TCR Migration 171: Etkinliğe özel menü seçimi
-- Etkinlikte menü listesi varsa katılım (RSVP) ve manuel kayıt bir menü seçmek zorundadır.
-- Menü yoksa davranış değişmez.

ALTER TABLE public.events
    ADD COLUMN IF NOT EXISTS menu_options JSONB;

ALTER TABLE public.events
    DROP CONSTRAINT IF EXISTS events_menu_options_check;

ALTER TABLE public.events
    ADD CONSTRAINT events_menu_options_check
    CHECK (
        menu_options IS NULL
        OR (
            jsonb_typeof(menu_options) = 'array'
            AND jsonb_array_length(menu_options) >= 2
            AND jsonb_array_length(menu_options) <= 12
        )
    );

COMMENT ON COLUMN public.events.menu_options IS
    'Katılımcının seçmesi gereken menü adları. Null ise bu etkinlikte menü seçimi yok.';

-- Tekrarlayan seride sonraki etkinlik, bir önceki etkinliğin menü listesini devralır.
CREATE OR REPLACE FUNCTION public.copy_spawned_event_menu_options()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.parent_event_id IS NOT NULL AND NEW.menu_options IS NULL THEN
        SELECT e.menu_options
        INTO NEW.menu_options
        FROM public.events e
        WHERE (e.id = NEW.parent_event_id OR e.parent_event_id = NEW.parent_event_id)
          AND e.start_time < NEW.start_time
        ORDER BY e.start_time DESC
        LIMIT 1;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_copy_spawned_event_menu_options ON public.events;
CREATE TRIGGER trg_copy_spawned_event_menu_options
    BEFORE INSERT ON public.events
    FOR EACH ROW
    EXECUTE FUNCTION public.copy_spawned_event_menu_options();

ALTER TABLE public.event_participants
    ADD COLUMN IF NOT EXISTS menu_choice TEXT;

COMMENT ON COLUMN public.event_participants.menu_choice IS
    'Katılımcının seçtiği menü. events.menu_options doluysa going kaydında zorunlu.';

ALTER TABLE public.event_sales
    ADD COLUMN IF NOT EXISTS menu_choice TEXT;

COMMENT ON COLUMN public.event_sales.menu_choice IS
    'Satış kaydındaki menü seçimi. Katılımcı kaydıyla senkron tutulur.';

CREATE OR REPLACE FUNCTION public.event_menu_option_names(p_event_id UUID)
RETURNS TEXT[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(ARRAY(
        SELECT btrim(item)
        FROM public.events e
        CROSS JOIN LATERAL jsonb_array_elements_text(COALESCE(e.menu_options, '[]'::jsonb)) AS item
        WHERE e.id = p_event_id
          AND btrim(item) <> ''
    ), ARRAY[]::TEXT[]);
$$;

-- Katılım: menü tanımlı etkinlikte yeni "going" kaydı seçim olmadan yazılamaz.
-- Menü eklenmeden önce katılmış kişiler, seçimleri değişmeden güncellenebilir.
CREATE OR REPLACE FUNCTION public.assert_participant_menu_choice()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_options TEXT[];
BEGIN
    IF NEW.status IS DISTINCT FROM 'going' THEN
        RETURN NEW;
    END IF;

    v_options := public.event_menu_option_names(NEW.event_id);
    IF COALESCE(array_length(v_options, 1), 0) = 0 THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE'
       AND OLD.status = 'going'
       AND NEW.menu_choice IS NOT DISTINCT FROM OLD.menu_choice THEN
        RETURN NEW;
    END IF;

    IF NEW.menu_choice IS NULL OR NOT (NEW.menu_choice = ANY (v_options)) THEN
        RAISE EXCEPTION 'Bu etkinlik için bir menü seçmelisiniz';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_event_participants_assert_menu ON public.event_participants;
CREATE TRIGGER trg_event_participants_assert_menu
    BEFORE INSERT OR UPDATE ON public.event_participants
    FOR EACH ROW
    EXECUTE FUNCTION public.assert_participant_menu_choice();

-- Satış: manuel kayıtta menü zorunlu. RSVP satışı katılımcıdan kopyalanır.
CREATE OR REPLACE FUNCTION public.assign_event_sale_menu_choice()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.menu_choice IS NULL AND NEW.user_id IS NOT NULL THEN
        SELECT ep.menu_choice
        INTO NEW.menu_choice
        FROM public.event_participants ep
        WHERE ep.event_id = NEW.event_id
          AND ep.user_id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_event_sale_menu_choice()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_options TEXT[];
BEGIN
    IF NEW.status = 'cancelled' THEN
        RETURN NEW;
    END IF;

    v_options := public.event_menu_option_names(NEW.event_id);
    IF COALESCE(array_length(v_options, 1), 0) = 0 THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE'
       AND NEW.menu_choice IS NOT DISTINCT FROM OLD.menu_choice
       AND OLD.status IS DISTINCT FROM 'cancelled' THEN
        RETURN NEW;
    END IF;

    IF NEW.menu_choice IS NOT NULL AND NOT (NEW.menu_choice = ANY (v_options)) THEN
        RAISE EXCEPTION 'Seçilen menü bu etkinlikte yok';
    END IF;

    IF NEW.source = 'manual'
       AND (NEW.menu_choice IS NULL OR NOT (NEW.menu_choice = ANY (v_options))) THEN
        RAISE EXCEPTION 'Bu etkinlik için bir menü seçmelisiniz';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_event_sales_00_assign_menu ON public.event_sales;
CREATE TRIGGER trg_event_sales_00_assign_menu
    BEFORE INSERT OR UPDATE ON public.event_sales
    FOR EACH ROW
    EXECUTE FUNCTION public.assign_event_sale_menu_choice();

DROP TRIGGER IF EXISTS trg_event_sales_10_assert_menu ON public.event_sales;
CREATE TRIGGER trg_event_sales_10_assert_menu
    BEFORE INSERT OR UPDATE ON public.event_sales
    FOR EACH ROW
    EXECUTE FUNCTION public.assert_event_sale_menu_choice();

-- RSVP -> satış: menü seçimini de taşır
CREATE OR REPLACE FUNCTION public.sync_event_sale_from_participant()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_paid BOOLEAN;
    v_event_id UUID;
    v_user_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_event_id := OLD.event_id;
        v_user_id := OLD.user_id;
    ELSE
        v_event_id := NEW.event_id;
        v_user_id := NEW.user_id;
    END IF;

    SELECT s.is_paid INTO v_is_paid
    FROM public.event_finance_settings s
    WHERE s.event_id = v_event_id;

    IF NOT COALESCE(v_is_paid, false) THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'DELETE' AND NEW.status = 'going' THEN
        INSERT INTO public.event_sales (
            event_id, user_id, buyer_name, source, created_by, menu_choice
        )
        VALUES (v_event_id, v_user_id, '', 'rsvp', v_user_id, NEW.menu_choice)
        ON CONFLICT (event_id, user_id) WHERE user_id IS NOT NULL
        DO UPDATE SET
            menu_choice = EXCLUDED.menu_choice,
            status = CASE
                WHEN public.event_sales.status = 'cancelled' THEN 'pending'
                ELSE public.event_sales.status
            END;
    ELSE
        UPDATE public.event_sales
        SET status = 'cancelled'
        WHERE event_id = v_event_id
          AND user_id = v_user_id
          AND source = 'rsvp'
          AND status <> 'cancelled'
          AND paid_amount = 0;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_event_sale_from_participant ON public.event_participants;
CREATE TRIGGER trg_sync_event_sale_from_participant
    AFTER INSERT OR UPDATE OF status, menu_choice OR DELETE ON public.event_participants
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_event_sale_from_participant();

-- Manuel satış -> katılımcı, menü seçimiyle birlikte
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

    IF TG_OP = 'UPDATE' THEN
        UPDATE public.event_participants
        SET menu_choice = NEW.menu_choice
        WHERE event_id = NEW.event_id
          AND user_id = NEW.user_id
          AND menu_choice IS DISTINCT FROM NEW.menu_choice;
        RETURN NEW;
    END IF;

    IF NEW.source <> 'manual' OR NEW.status = 'cancelled' THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.event_participants (
        event_id, user_id, status, responded_at, menu_choice
    )
    VALUES (NEW.event_id, NEW.user_id, 'going', NOW(), NEW.menu_choice)
    ON CONFLICT (event_id, user_id) DO UPDATE SET
        status = 'going',
        responded_at = NOW(),
        menu_choice = EXCLUDED.menu_choice;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_participant_from_event_sale ON public.event_sales;
CREATE TRIGGER trg_sync_participant_from_event_sale
    AFTER INSERT OR UPDATE OF menu_choice ON public.event_sales
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_participant_from_event_sale();

-- Finans detayı menü listesini ve satıştaki seçimi de döndürür
CREATE OR REPLACE FUNCTION public.get_event_finance_detail(p_event_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event JSONB;
    v_settings JSONB;
    v_costs JSONB;
    v_summary JSONB;
    v_sales JSONB;
    v_event_fixed DECIMAL := 0;
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Bu rapora erişim yetkiniz yok';
    END IF;

    SELECT jsonb_build_object(
        'id', e.id,
        'title', e.title,
        'start_time', e.start_time,
        'status', e.status,
        'ticket_price', e.ticket_price,
        'location_name', e.location_name,
        'menu_options', e.menu_options
    )
    INTO v_event
    FROM public.events e
    WHERE e.id = p_event_id;

    IF v_event IS NULL THEN
        RAISE EXCEPTION 'Etkinlik bulunamadı';
    END IF;

    SELECT to_jsonb(s) - 'created_by' - 'created_at'
    INTO v_settings
    FROM public.event_finance_settings s
    WHERE s.event_id = p_event_id;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', c.id,
            'event_id', c.event_id,
            'name', c.name,
            'scope', c.scope,
            'share_type', c.share_type,
            'share_value', c.share_value,
            'sort_order', c.sort_order
        )
        ORDER BY c.sort_order, c.created_at
    ), '[]'::jsonb)
    INTO v_costs
    FROM public.event_finance_costs c
    WHERE c.event_id = p_event_id;

    IF v_settings IS NOT NULL THEN
        v_settings := v_settings || jsonb_build_object('costs', v_costs);
    END IF;

    v_event_fixed := public.compute_event_fixed_costs(p_event_id);

    SELECT jsonb_build_object(
        'participant_count', COALESCE(SUM(es.quantity), 0),
        'regular_count', COALESCE(SUM(es.quantity) FILTER (WHERE es.sale_type = 'regular'), 0),
        'discounted_count', COALESCE(SUM(es.quantity) FILTER (WHERE es.sale_type = 'discounted'), 0),
        'gift_count', COALESCE(SUM(es.quantity) FILTER (WHERE es.sale_type = 'gift'), 0),
        'total_sales', COALESCE(SUM(es.total_price), 0),
        'total_partner_share', COALESCE(SUM(es.quantity * es.partner_share_amount), 0) + v_event_fixed,
        'per_person_cost', COALESCE(SUM(es.quantity * es.partner_share_amount), 0),
        'event_fixed_cost', v_event_fixed,
        'net_profit', COALESCE(SUM(es.total_price), 0)
            - COALESCE(SUM(es.quantity * es.partner_share_amount), 0)
            - v_event_fixed,
        'total_paid', COALESCE(SUM(es.paid_amount), 0),
        'outstanding', COALESCE(SUM(es.total_price), 0) - COALESCE(SUM(es.paid_amount), 0)
    )
    INTO v_summary
    FROM public.event_sales es
    WHERE es.event_id = p_event_id
      AND es.status <> 'cancelled';

    IF v_summary IS NULL THEN
        v_summary := jsonb_build_object(
            'participant_count', 0,
            'regular_count', 0,
            'discounted_count', 0,
            'gift_count', 0,
            'total_sales', 0,
            'total_partner_share', v_event_fixed,
            'per_person_cost', 0,
            'event_fixed_cost', v_event_fixed,
            'net_profit', -v_event_fixed,
            'total_paid', 0,
            'outstanding', 0
        );
    END IF;

    SELECT COALESCE(jsonb_agg(row_data ORDER BY sort_cancelled, sort_name), '[]'::jsonb)
    INTO v_sales
    FROM (
        SELECT
            (es.status = 'cancelled') AS sort_cancelled,
            lower(COALESCE(
                NULLIF(btrim(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')), ''),
                es.buyer_name
            )) AS sort_name,
            jsonb_build_object(
                'id', es.id,
                'event_id', es.event_id,
                'user_id', es.user_id,
                'buyer_name', COALESCE(
                    NULLIF(btrim(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')), ''),
                    es.buyer_name
                ),
                'avatar_url', u.avatar_url,
                'source', es.source,
                'quantity', es.quantity,
                'unit_price', es.unit_price,
                'partner_share_amount', es.partner_share_amount,
                'total_price', es.total_price,
                'total_partner_share', es.quantity * es.partner_share_amount,
                'net', es.total_price - es.quantity * es.partner_share_amount,
                'sale_type', es.sale_type,
                'status', es.status,
                'paid_amount', es.paid_amount,
                'outstanding', es.total_price - es.paid_amount,
                'payment_method', es.payment_method,
                'payment_date', es.payment_date,
                'notes', es.notes,
                'menu_choice', es.menu_choice,
                'created_at', es.created_at,
                'rsvp_status', ep.status,
                'checked_in', COALESCE(ep.checked_in, false)
            ) AS row_data
        FROM public.event_sales es
        LEFT JOIN public.users u ON u.id = es.user_id
        LEFT JOIN public.event_participants ep
            ON ep.event_id = es.event_id AND ep.user_id = es.user_id
        WHERE es.event_id = p_event_id
    ) t;

    RETURN jsonb_build_object(
        'event', v_event,
        'settings', v_settings,
        'costs', v_costs,
        'summary', v_summary,
        'sales', v_sales
    );
END;
$$;
