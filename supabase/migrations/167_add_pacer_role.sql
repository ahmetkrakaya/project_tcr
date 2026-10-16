-- TCR Migration 167: Pacer rolü
-- Yeni enum değeri aynı transaction içinde kullanılamadığı için ayrı migration.

ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'pacer';
