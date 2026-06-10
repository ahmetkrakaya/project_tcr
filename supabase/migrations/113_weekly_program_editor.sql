-- =====================================================
-- 113: Weekly program editor support
-- coach_notes, source tracking, user read RLS
-- =====================================================

ALTER TABLE public.monthly_program_entries
ADD COLUMN IF NOT EXISTS coach_notes TEXT;

ALTER TABLE public.monthly_program_entries
ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'import'
  CHECK (source IN ('import', 'weekly_editor'));

ALTER TABLE public.monthly_program_batches
ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'import'
  CHECK (source IN ('import', 'weekly_editor'));

COMMENT ON COLUMN public.monthly_program_entries.coach_notes IS
  'Koç notu; parse edilmez, sporcu görünümünde gösterilir.';

COMMENT ON COLUMN public.monthly_program_entries.source IS
  'Kaynak: import (Excel) veya weekly_editor.';

-- Authenticated users can read programs for their group or personal scope
DROP POLICY IF EXISTS "Users can select own monthly_program_entries"
  ON public.monthly_program_entries;

CREATE POLICY "Users can select own monthly_program_entries"
  ON public.monthly_program_entries FOR SELECT
  USING (
    (
      scope_type = 'group'
      AND training_group_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.group_id = monthly_program_entries.training_group_id
          AND gm.user_id = auth.uid()
      )
    )
    OR
    (
      scope_type = 'member'
      AND user_id = auth.uid()
    )
  );
