-- =====================================================
-- 109: Birleşik grup talep sistemi
-- Katılım ve grup değişim talepleri; self-join/self-leave kapatılır
-- =====================================================

ALTER TABLE public.group_join_requests
    ADD COLUMN IF NOT EXISTS request_type TEXT NOT NULL DEFAULT 'join'
        CHECK (request_type IN ('join', 'transfer')),
    ADD COLUMN IF NOT EXISTS from_group_id UUID
        REFERENCES public.training_groups(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_group_join_requests_from_group
    ON public.group_join_requests(from_group_id);

-- Mevcut bekleyen talepleri katılım olarak işaretle
UPDATE public.group_join_requests
SET request_type = 'join'
WHERE request_type IS NULL;

-- Grup üyeliğini yalnızca admin ekleyebilir (RPC onay hariç)
DROP POLICY IF EXISTS "Admins can manage group members" ON public.group_members;
CREATE POLICY "Admins can manage group members"
    ON public.group_members FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- Kullanıcı kendini gruptan çıkaramaz
DROP POLICY IF EXISTS "Users can leave groups" ON public.group_members;
CREATE POLICY "Admins can remove group members"
    ON public.group_members FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- Onay RPC: transfer taleplerinde from_group_id doğrulaması
CREATE OR REPLACE FUNCTION public.approve_group_join_request(
    request_id UUID,
    admin_user_id UUID
)
RETURNS VOID AS $$
DECLARE
    v_user_id UUID;
    v_group_id UUID;
    v_request_type TEXT;
    v_from_group_id UUID;
    v_current_group_id UUID;
BEGIN
    SELECT user_id, group_id, request_type, from_group_id
    INTO v_user_id, v_group_id, v_request_type, v_from_group_id
    FROM public.group_join_requests
    WHERE id = request_id AND status = 'pending';

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Talep bulunamadi veya zaten islendi';
    END IF;

    SELECT group_id INTO v_current_group_id
    FROM public.group_members
    WHERE user_id = v_user_id;

    IF v_request_type = 'transfer' THEN
        IF v_current_group_id IS NULL THEN
            RAISE EXCEPTION 'Grup degisim talebi icin kullanici mevcut bir grupta olmali';
        END IF;
        IF v_from_group_id IS NOT NULL AND v_from_group_id != v_current_group_id THEN
            RAISE EXCEPTION 'Talep edilen kaynak grup kullanicinin mevcut grubuyla uyusmuyor';
        END IF;
    ELSIF v_request_type = 'join' AND v_current_group_id IS NOT NULL THEN
        RAISE EXCEPTION 'Katilim talebi icin kullanici zaten bir grupta';
    END IF;

    IF v_current_group_id IS NOT NULL THEN
        DELETE FROM public.group_members
        WHERE user_id = v_user_id AND group_id = v_current_group_id;
    END IF;

    INSERT INTO public.group_members (group_id, user_id)
    VALUES (v_group_id, v_user_id)
    ON CONFLICT (user_id) DO UPDATE SET group_id = v_group_id;

    UPDATE public.group_join_requests
    SET status = 'approved',
        responded_at = NOW(),
        responded_by = admin_user_id
    WHERE id = request_id;

    -- Aynı kullanıcının diğer bekleyen taleplerini iptal et
    UPDATE public.group_join_requests
    SET status = 'rejected',
        responded_at = NOW(),
        responded_by = admin_user_id
    WHERE user_id = v_user_id
      AND status = 'pending'
      AND id != request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
