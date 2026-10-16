-- Satış geçmişinden katılım (check-in) işaretleme.
-- Üyeye bağlı satışlarda event_participants.checked_in esas alınır; katılımcı kaydı
-- olmayan manuel satışlarda durum event_sales.checked_in üzerinde tutulur.

ALTER TABLE public.event_sales
    ADD COLUMN IF NOT EXISTS checked_in BOOLEAN NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.set_event_sale_attendance(
    p_sale_id UUID,
    p_checked_in BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sale public.event_sales%ROWTYPE;
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Bu işlem için yetkiniz yok';
    END IF;

    SELECT * INTO v_sale FROM public.event_sales WHERE id = p_sale_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Satış kaydı bulunamadı';
    END IF;

    UPDATE public.event_sales
    SET checked_in = p_checked_in
    WHERE id = p_sale_id;

    IF v_sale.user_id IS NOT NULL THEN
        UPDATE public.event_participants
        SET checked_in = p_checked_in,
            checked_in_at = CASE WHEN p_checked_in THEN COALESCE(checked_in_at, NOW()) ELSE NULL END
        WHERE event_id = v_sale.event_id
          AND user_id = v_sale.user_id;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_event_sale_attendance(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_event_sale_attendance(UUID, BOOLEAN) TO authenticated;

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
                'checked_in', CASE
                    WHEN ep.event_id IS NOT NULL THEN COALESCE(ep.checked_in, false)
                    ELSE es.checked_in
                END
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
