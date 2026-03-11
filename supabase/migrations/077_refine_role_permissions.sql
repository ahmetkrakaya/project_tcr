-- =====================================================
-- 077: Yetki sistemi düzenlemesi
-- Coach rolünün erişimlerini daralt, bazı işlemleri sadece admin'e kısıtla
-- =====================================================

-- ==========================================
-- 1) POSTS: Silme sadece admin
-- ==========================================

DROP POLICY IF EXISTS "Post owners and admins can delete posts" ON public.posts;
CREATE POLICY "Only admins can delete posts"
    ON public.posts FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- ==========================================
-- 2) EVENTS: Oluşturma/düzenleme/silme sadece admin
-- ==========================================

DROP POLICY IF EXISTS "Admin/Coach can manage events" ON public.events;
CREATE POLICY "Admins can manage events"
    ON public.events FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- ==========================================
-- 3) EVENT RESULTS: Yönetim sadece admin
-- ==========================================

DROP POLICY IF EXISTS "Admins and coaches can manage event results" ON public.event_results;
CREATE POLICY "Admins can manage event results"
    ON public.event_results FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- ==========================================
-- 4) EVENT GROUP PROGRAMS: Yönetim sadece admin
-- ==========================================

DROP POLICY IF EXISTS "Admins and coaches can create group programs" ON public.event_group_programs;
CREATE POLICY "Admins can create group programs"
    ON public.event_group_programs FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

DROP POLICY IF EXISTS "Admins and coaches can update group programs" ON public.event_group_programs;
CREATE POLICY "Admins can update group programs"
    ON public.event_group_programs FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

DROP POLICY IF EXISTS "Admins and coaches can delete group programs" ON public.event_group_programs;
CREATE POLICY "Admins can delete group programs"
    ON public.event_group_programs FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- ==========================================
-- 5) EVENT MEMBER PROGRAMS: Yönetim sadece admin
-- (Zaten admin-only idi, doğrulama amaçlı yeniden tanımlama)
-- ==========================================

DROP POLICY IF EXISTS "Admins can create member programs" ON public.event_member_programs;
CREATE POLICY "Admins can create member programs"
    ON public.event_member_programs FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

DROP POLICY IF EXISTS "Admins can update member programs" ON public.event_member_programs;
CREATE POLICY "Admins can update member programs"
    ON public.event_member_programs FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

DROP POLICY IF EXISTS "Admins can delete member programs" ON public.event_member_programs;
CREATE POLICY "Admins can delete member programs"
    ON public.event_member_programs FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- ==========================================
-- 6) TRAINING GROUPS: Yönetim sadece admin
-- ==========================================

DROP POLICY IF EXISTS "Admin/Coach can manage training groups" ON public.training_groups;
DROP POLICY IF EXISTS "Admins can create training groups" ON public.training_groups;
DROP POLICY IF EXISTS "Admins can update training groups" ON public.training_groups;
DROP POLICY IF EXISTS "Admins can delete training groups" ON public.training_groups;

CREATE POLICY "Admins can create training groups"
    ON public.training_groups FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

CREATE POLICY "Admins can update training groups"
    ON public.training_groups FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

CREATE POLICY "Admins can delete training groups"
    ON public.training_groups FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- ==========================================
-- 7) GROUP MEMBERS: Yönetim sadece admin (kullanıcı kendini ekleme hariç)
-- ==========================================

DROP POLICY IF EXISTS "Admins can manage group members" ON public.group_members;
CREATE POLICY "Admins can manage group members"
    ON public.group_members FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
        OR user_id = auth.uid()
    );

DROP POLICY IF EXISTS "Users can leave groups" ON public.group_members;
CREATE POLICY "Users can leave groups"
    ON public.group_members FOR DELETE
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- ==========================================
-- 8) GROUP JOIN REQUESTS: Onaylama sadece admin
-- ==========================================

DROP POLICY IF EXISTS "Admins can update join requests" ON public.group_join_requests;
CREATE POLICY "Admins can update join requests"
    ON public.group_join_requests FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- ==========================================
-- 9) ROUTES: Silme sadece admin, oluşturma/düzenleme admin+coach
-- ==========================================

DROP POLICY IF EXISTS "Admin/Coach can manage routes" ON public.routes;
DROP POLICY IF EXISTS "Admins and coaches can create routes" ON public.routes;
DROP POLICY IF EXISTS "Admins and coaches can update routes" ON public.routes;
DROP POLICY IF EXISTS "Admins and coaches can delete routes" ON public.routes;

CREATE POLICY "Admins and coaches can create routes"
    ON public.routes FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

CREATE POLICY "Admins and coaches can update routes"
    ON public.routes FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

CREATE POLICY "Only admins can delete routes"
    ON public.routes FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );
