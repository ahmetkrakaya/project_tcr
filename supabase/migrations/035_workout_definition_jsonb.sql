-- =====================================================
-- 035: Workout Definition (Segment tabanlı antrenman) JSONB
-- =====================================================
-- event_group_programs ve event_template_group_programs tablolarına
-- yapılandırılmış antrenman (segment, hedef, yineleme) için workout_definition eklenir.
-- program_content geriye dönük uyumluluk için kalır.

-- event_group_programs
ALTER TABLE public.event_group_programs
ADD COLUMN IF NOT EXISTS workout_definition JSONB DEFAULT NULL;

COMMENT ON COLUMN public.event_group_programs.workout_definition IS
  'Yapılandırılmış antrenman: steps (segment/repeat), hedef türü, süre/mesafe, pace/HR/kadans/güç. FIT/TCX export için kullanılır.';

-- event_template_group_programs
ALTER TABLE public.event_template_group_programs
ADD COLUMN IF NOT EXISTS workout_definition JSONB DEFAULT NULL;

COMMENT ON COLUMN public.event_template_group_programs.workout_definition IS
  'Yapılandırılmış antrenman: steps (segment/repeat), hedef türü, süre/mesafe, pace/HR/kadans/güç. Şablon kopyalanırken taşınır.';
