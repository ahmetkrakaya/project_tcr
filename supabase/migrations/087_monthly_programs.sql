-- =====================================================
-- 087: Monthly XLSX Programs
-- Admin'in aylık antrenman planını normalize saklama
-- =====================================================

CREATE TABLE IF NOT EXISTS public.monthly_program_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    month_key TEXT NOT NULL, -- YYYY-MM
    title TEXT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'archived')),
    source_file_name TEXT,
    row_count INTEGER NOT NULL DEFAULT 0,
    error_count INTEGER NOT NULL DEFAULT 0,
    uploaded_by UUID NOT NULL REFERENCES public.users(id),
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT monthly_program_batches_month_key_format_chk
      CHECK (month_key ~ '^[0-9]{4}-(0[1-9]|1[0-2])$')
);

CREATE INDEX IF NOT EXISTS idx_monthly_program_batches_month_key
  ON public.monthly_program_batches(month_key);

CREATE INDEX IF NOT EXISTS idx_monthly_program_batches_status
  ON public.monthly_program_batches(status);

CREATE TABLE IF NOT EXISTS public.monthly_program_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id UUID NOT NULL REFERENCES public.monthly_program_batches(id) ON DELETE CASCADE,
    plan_date DATE NOT NULL,
    scope_type TEXT NOT NULL CHECK (scope_type IN ('group', 'member')),
    training_group_id UUID REFERENCES public.training_groups(id) ON DELETE SET NULL,
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    training_type_id UUID REFERENCES public.training_types(id) ON DELETE SET NULL,
    route_id UUID REFERENCES public.routes(id) ON DELETE SET NULL,
    start_time TIME,
    duration_minutes INTEGER CHECK (duration_minutes IS NULL OR duration_minutes >= 0),
    program_content TEXT NOT NULL,
    workout_definition JSONB,
    location_name TEXT,
    location_address TEXT,
    coach_notes TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT monthly_program_entries_scope_consistency_chk CHECK (
      (scope_type = 'group' AND training_group_id IS NOT NULL AND user_id IS NULL)
      OR
      (scope_type = 'member' AND user_id IS NOT NULL)
    ),
    CONSTRAINT monthly_program_entries_one_row_per_day_uk UNIQUE(plan_date)
);

CREATE INDEX IF NOT EXISTS idx_monthly_program_entries_batch_id
  ON public.monthly_program_entries(batch_id);

CREATE INDEX IF NOT EXISTS idx_monthly_program_entries_plan_date
  ON public.monthly_program_entries(plan_date);

ALTER TABLE public.monthly_program_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monthly_program_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can select monthly_program_batches"
  ON public.monthly_program_batches FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'super_admin'
    )
  );

CREATE POLICY "Admins can insert monthly_program_batches"
  ON public.monthly_program_batches FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'super_admin'
    )
  );

CREATE POLICY "Admins can update monthly_program_batches"
  ON public.monthly_program_batches FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'super_admin'
    )
  );

CREATE POLICY "Admins can delete monthly_program_batches"
  ON public.monthly_program_batches FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'super_admin'
    )
  );

CREATE POLICY "Admins can select monthly_program_entries"
  ON public.monthly_program_entries FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'super_admin'
    )
  );

CREATE POLICY "Admins can insert monthly_program_entries"
  ON public.monthly_program_entries FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'super_admin'
    )
  );

CREATE POLICY "Admins can update monthly_program_entries"
  ON public.monthly_program_entries FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'super_admin'
    )
  );

CREATE POLICY "Admins can delete monthly_program_entries"
  ON public.monthly_program_entries FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'super_admin'
    )
  );

DROP TRIGGER IF EXISTS monthly_program_batches_set_updated_at ON public.monthly_program_batches;
CREATE TRIGGER monthly_program_batches_set_updated_at
  BEFORE UPDATE ON public.monthly_program_batches
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS monthly_program_entries_set_updated_at ON public.monthly_program_entries;
CREATE TRIGGER monthly_program_entries_set_updated_at
  BEFORE UPDATE ON public.monthly_program_entries
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
