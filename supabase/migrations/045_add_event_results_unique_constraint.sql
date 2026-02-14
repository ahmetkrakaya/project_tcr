-- 045: Add unique constraint to event_results for upsert support
-- event_id ve participant_id kombinasyonu unique olmalı (bir katılımcının bir etkinlikte sadece bir sonucu olabilir)

-- Önce mevcut duplicate kayıtları temizle (eğer varsa)
-- Her event_id + participant_id için en yeni kaydı tut
DELETE FROM public.event_results er1
WHERE er1.participant_id IS NOT NULL
  AND er1.id NOT IN (
    SELECT DISTINCT ON (er2.event_id, er2.participant_id) er2.id
    FROM public.event_results er2
    WHERE er2.participant_id IS NOT NULL
    ORDER BY er2.event_id, er2.participant_id, er2.created_at DESC
  );

-- Unique constraint ekle (participant_id NULL olmayanlar için)
-- Supabase'de onConflict için unique constraint veya unique index gerekli
CREATE UNIQUE INDEX IF NOT EXISTS idx_event_results_event_participant_unique
    ON public.event_results(event_id, participant_id)
    WHERE participant_id IS NOT NULL;

-- Alternatif: Eğer yukarıdaki index yeterli değilse, constraint ekle
-- Ama önce index'i deneyelim
