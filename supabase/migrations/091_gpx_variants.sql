-- TCR Migration 091: GPX variants (race distance variants)
-- Adds optional multi-variant GPX storage on a single route.

ALTER TABLE public.routes
ADD COLUMN IF NOT EXISTS gpx_variants JSONB;

