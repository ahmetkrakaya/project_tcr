-- TCR Migration 092: Route race classification

ALTER TABLE public.routes
ADD COLUMN IF NOT EXISTS is_race BOOLEAN NOT NULL DEFAULT false;

