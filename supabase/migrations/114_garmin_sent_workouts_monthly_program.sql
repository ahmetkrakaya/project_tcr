-- Garmin sent workouts: etkinlik yerine haftalık plan (monthly_program_entries) desteği

ALTER TABLE public.garmin_sent_workouts
  DROP CONSTRAINT IF EXISTS garmin_sent_workouts_event_id_fkey;

ALTER TABLE public.garmin_sent_workouts
  ALTER COLUMN event_id DROP NOT NULL;

ALTER TABLE public.garmin_sent_workouts
  DROP CONSTRAINT IF EXISTS garmin_sent_workouts_user_id_event_id_program_id_key;

ALTER TABLE public.garmin_sent_workouts
  ADD CONSTRAINT garmin_sent_workouts_user_id_program_id_key
  UNIQUE (user_id, program_id);

COMMENT ON COLUMN public.garmin_sent_workouts.program_id IS
  'monthly_program_entries.id (haftalık/aylık plan satırı)';

COMMENT ON COLUMN public.garmin_sent_workouts.event_id IS
  'Eski kayıtlar için; yeni senkron etkinlik gerektirmez.';
